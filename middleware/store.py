"""MongoDB Atlas persistence for one or more families.

Every document carries `family_id` and its app `id` as a UUID string, so ids never depend on ObjectId.
"""

from __future__ import annotations

import os
from datetime import UTC, datetime
from typing import Any, Protocol
from uuid import UUID

from pydantic import BaseModel
from pymongo import AsyncMongoClient, ReturnDocument

from env import require
from models import (
    FamilyGraph,
    FamilyMember,
    HobbyConnection,
    KinshipEdge,
    LoomSpark,
    MemoryNode,
    StoryChapter,
)

_NO_ID = {"_id": 0, "family_id": 0}


class FamilyStoreProtocol(Protocol):
    async def graph(self, family_id: str) -> FamilyGraph: ...
    async def member(self, family_id: str, member_id: UUID) -> FamilyMember | None: ...
    async def insert_memory(self, family_id: str, memory: MemoryNode) -> None: ...
    async def insert_connections(self, family_id: str, connections: list[HobbyConnection]) -> None: ...
    async def insert_sparks(self, family_id: str, sparks: list[LoomSpark]) -> None: ...
    async def update_member_passions(self, family_id: str, member_id: UUID, passions: list[str]) -> None: ...
    async def pending_sparks(self, family_id: str, member_id: UUID) -> list[LoomSpark]: ...
    async def resolve_spark(self, family_id: str, spark_id: UUID) -> bool: ...
    async def chapters(self, family_id: str, memory_ids: list[UUID]) -> list[StoryChapter]: ...
    async def insert_chapter(self, family_id: str, chapter: StoryChapter) -> None: ...
    async def assistant_id(self, family_id: str) -> str | None: ...
    async def set_assistant_id(self, family_id: str, assistant_id: str) -> None: ...


def to_document(model: BaseModel, family_id: str) -> dict[str, Any]:
    document = _bsonify(model.model_dump(mode="python"))
    document["family_id"] = family_id
    return document


def _bsonify(value: Any) -> Any:
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, dict):
        return {key: _bsonify(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_bsonify(item) for item in value]
    if isinstance(value, datetime) or value is None or isinstance(value, (str, int, float, bool)):
        return value
    # Enums serialize to their value.
    return getattr(value, "value", value)


class MongoFamilyStore:
    def __init__(self, client: AsyncMongoClient, database: str) -> None:
        self._client = client
        db = client[database]
        self._members = db["members"]
        self._memories = db["memories"]
        self._kinship = db["kinship"]
        self._connections = db["connections"]
        self._sparks = db["sparks"]
        self._chapters = db["chapters"]
        self._families = db["families"]

    @classmethod
    def from_env(cls) -> MongoFamilyStore:
        client: AsyncMongoClient = AsyncMongoClient(
            require("MONGODB_URI"),
            tz_aware=True,
            serverSelectionTimeoutMS=10_000,
            appname="heirloom-middleware",
        )
        return cls(client, os.environ.get("MONGODB_DATABASE", "heirloom"))

    async def ensure_indexes(self) -> None:
        for collection in (self._members, self._memories, self._connections, self._sparks, self._chapters):
            await collection.create_index([("family_id", 1), ("id", 1)], unique=True)
        await self._sparks.create_index([("family_id", 1), ("target_member_id", 1), ("is_resolved", 1)])
        await self._families.create_index("family_id", unique=True)

    async def close(self) -> None:
        await self._client.close()

    async def ping(self) -> None:
        await self._client.admin.command("ping")

    # MARK: - Reads

    async def graph(self, family_id: str) -> FamilyGraph:
        scope = {"family_id": family_id}
        members = await self._members.find(scope, _NO_ID).to_list()
        memories = await self._memories.find(scope, _NO_ID).sort("timestamp", 1).to_list()
        kinship = await self._kinship.find(scope, _NO_ID).to_list()
        connections = await self._connections.find(scope, _NO_ID).to_list()
        sparks = await self._sparks.find(scope, _NO_ID).to_list()
        return FamilyGraph(
            members=[FamilyMember.model_validate(doc) for doc in members],
            memories=[MemoryNode.model_validate(doc) for doc in memories],
            kinship_edges=[KinshipEdge.model_validate(doc) for doc in kinship],
            hobby_connections=[HobbyConnection.model_validate(doc) for doc in connections],
            sparks=[LoomSpark.model_validate(doc) for doc in sparks],
        )

    async def member(self, family_id: str, member_id: UUID) -> FamilyMember | None:
        doc = await self._members.find_one({"family_id": family_id, "id": str(member_id)}, _NO_ID)
        return FamilyMember.model_validate(doc) if doc else None

    async def pending_sparks(self, family_id: str, member_id: UUID) -> list[LoomSpark]:
        docs = (
            await self._sparks.find(
                {"family_id": family_id, "target_member_id": str(member_id), "is_resolved": False}, _NO_ID
            )
            .sort("timestamp", -1)
            .to_list()
        )
        return [LoomSpark.model_validate(doc) for doc in docs]

    async def chapters(self, family_id: str, memory_ids: list[UUID]) -> list[StoryChapter]:
        query: dict[str, Any] = {"family_id": family_id}
        if memory_ids:
            query["source_memory_ids"] = {"$in": [str(memory_id) for memory_id in memory_ids]}
        docs = await self._chapters.find(query, _NO_ID).sort("created_at", 1).to_list()
        return [StoryChapter.model_validate(doc) for doc in docs]

    async def assistant_id(self, family_id: str) -> str | None:
        doc = await self._families.find_one({"family_id": family_id})
        return doc.get("backboard_assistant_id") if doc else None

    # MARK: - Writes

    async def insert_memory(self, family_id: str, memory: MemoryNode) -> None:
        await self._memories.insert_one(to_document(memory, family_id))

    async def insert_connections(self, family_id: str, connections: list[HobbyConnection]) -> None:
        if connections:
            await self._connections.insert_many([to_document(item, family_id) for item in connections])

    async def insert_sparks(self, family_id: str, sparks: list[LoomSpark]) -> None:
        if sparks:
            await self._sparks.insert_many([to_document(item, family_id) for item in sparks])

    async def update_member_passions(self, family_id: str, member_id: UUID, passions: list[str]) -> None:
        await self._members.update_one(
            {"family_id": family_id, "id": str(member_id)},
            {"$set": {"passion_tags": passions}},
        )

    async def resolve_spark(self, family_id: str, spark_id: UUID) -> bool:
        doc = await self._sparks.find_one_and_update(
            {"family_id": family_id, "id": str(spark_id)},
            {"$set": {"is_resolved": True}},
            return_document=ReturnDocument.AFTER,
        )
        return doc is not None

    async def insert_chapter(self, family_id: str, chapter: StoryChapter) -> None:
        document = to_document(chapter, family_id)
        document["created_at"] = datetime.now(UTC)
        await self._chapters.insert_one(document)

    async def set_assistant_id(self, family_id: str, assistant_id: str) -> None:
        await self._families.update_one(
            {"family_id": family_id},
            {"$set": {"backboard_assistant_id": assistant_id}},
            upsert=True,
        )

    # MARK: - Seeding

    async def replace_family(self, family_id: str, graph: FamilyGraph) -> None:
        scope = {"family_id": family_id}
        for collection in (self._members, self._memories, self._kinship, self._connections, self._sparks, self._chapters):
            await collection.delete_many(scope)
        if graph.members:
            await self._members.insert_many([to_document(item, family_id) for item in graph.members])
        if graph.memories:
            await self._memories.insert_many([to_document(item, family_id) for item in graph.memories])
        if graph.kinship_edges:
            await self._kinship.insert_many([to_document(item, family_id) for item in graph.kinship_edges])
        await self.insert_connections(family_id, graph.hobby_connections)
        await self.insert_sparks(family_id, graph.sparks)

    async def has_members(self, family_id: str) -> bool:
        return await self._members.count_documents({"family_id": family_id}, limit=1) > 0
