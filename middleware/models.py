"""Wire models. Field names are the exact snake_case JSON keys the Swift `Codable` models use.

Every field is always serialized (including nulls) because Swift's synthesized decoders require
non-optional keys to be present.
"""

from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum, IntEnum
from typing import Annotated
from uuid import UUID, uuid4

from pydantic import AfterValidator, BaseModel, Field, PlainSerializer


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _iso_millis(value: datetime) -> str:
    # Millisecond precision with a Z suffix parses with Swift's ISO8601FormatStyle(includingFractionalSeconds:).
    return _as_utc(value).strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"


UTCDateTime = Annotated[
    datetime,
    AfterValidator(_as_utc),
    PlainSerializer(_iso_millis, return_type=str, when_used="json"),
]


def utc_now() -> datetime:
    return datetime.now(UTC)


class GenerationTier(IntEnum):
    GRANDPARENTS = 1
    PARENTS = 2
    GRANDCHILDREN = 3


class KinshipRelation(str, Enum):
    PARENT = "parent"
    CHILD = "child"
    SPOUSE = "spouse"
    SIBLING = "sibling"


class SparkActionType(str, Enum):
    CALL_PHONE = "call_phone"
    SEND_VOICE_NOTE = "send_voice_note"
    VIEW_STORY = "view_story"


class FamilyMember(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str
    generation_tier: GenerationTier
    relationship_label: str | None = None
    bio: str = ""
    profile_image_url: str | None = None
    passion_tags: list[str] = Field(default_factory=list)
    phone_number: str | None = None

    @property
    def first_name(self) -> str:
        return self.name.split(" ", 1)[0] if self.name else self.name


class MemoryNode(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    author_id: UUID
    timestamp: UTCDateTime = Field(default_factory=utc_now)
    raw_transcript: str
    narrative_summary: str
    extracted_era: str
    location: str | None = None
    entities_mentioned: list[str] = Field(default_factory=list)
    hobbies_identified: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    media_urls: list[str] = Field(default_factory=list)


class KinshipEdge(BaseModel):
    from_id: UUID
    to_id: UUID
    relation_type: KinshipRelation


class HobbyConnection(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    from_member_id: UUID
    to_member_id: UUID
    shared_interest: str
    match_rationale: str
    source_memory_id: UUID | None = None


class LoomSpark(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    target_member_id: UUID
    elder_id: UUID
    prompt_text: str
    action_type: SparkActionType
    timestamp: UTCDateTime = Field(default_factory=utc_now)
    related_memory_id: UUID | None = None
    is_resolved: bool = False


class StoryChapter(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    title: str
    narrative_text: str
    illustration_url: str | None = None
    audio_snippet_url: str | None = None
    source_memory_ids: list[UUID] = Field(default_factory=list)


class FamilyGraph(BaseModel):
    members: list[FamilyMember] = Field(default_factory=list)
    memories: list[MemoryNode] = Field(default_factory=list)
    kinship_edges: list[KinshipEdge] = Field(default_factory=list)
    hobby_connections: list[HobbyConnection] = Field(default_factory=list)
    sparks: list[LoomSpark] = Field(default_factory=list)

    def member(self, member_id: UUID) -> FamilyMember | None:
        return next((m for m in self.members if m.id == member_id), None)


class MemoryIngestionResult(BaseModel):
    memory: MemoryNode
    new_connections: list[HobbyConnection] = Field(default_factory=list)
    sparks: list[LoomSpark] = Field(default_factory=list)


# Request and response bodies for the routes VultrMiddlewareClient calls.


class IngestRequest(BaseModel):
    transcript: str = Field(min_length=1, max_length=50_000)
    author_id: UUID


class FollowUpRequest(BaseModel):
    memory: MemoryNode
    session_id: str = Field(min_length=1, max_length=200)


class FollowUpResponse(BaseModel):
    questions: list[str]


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10_000)
    session_id: str = Field(min_length=1, max_length=200)


class StorybookRequest(BaseModel):
    memory_ids: list[UUID] = Field(default_factory=list)


class IllustrationRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=4_000)


class IllustrationResponse(BaseModel):
    url: str
