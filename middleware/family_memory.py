"""Backboard long-term memory, with one assistant per family so families never share context."""

from __future__ import annotations

import asyncio
import logging

from backboard import BackboardClient

from loom_session import LOOM_SYSTEM_PROMPT
from store import FamilyStoreProtocol

logger = logging.getLogger("heirloom.memory")

NO_CONTEXT = "No saved family context yet."


class FamilyMemory:
    def __init__(self, client: BackboardClient, store: FamilyStoreProtocol) -> None:
        self._client = client
        self._store = store
        self._lock = asyncio.Lock()

    async def assistant_for(self, family_id: str) -> str:
        """The family's Backboard assistant, created and recorded in Atlas on first use."""
        existing = await self._store.assistant_id(family_id)
        if existing:
            return existing
        async with self._lock:
            existing = await self._store.assistant_id(family_id)
            if existing:
                return existing
            assistant = await self._client.create_assistant(
                name=f"HeirLoom {family_id}",
                description=f"Oral-history memory for family {family_id}",
                system_prompt=LOOM_SYSTEM_PROMPT,
            )
            assistant_id = str(assistant.assistant_id)
            await self._store.set_assistant_id(family_id, assistant_id)
            logger.info("Created Backboard assistant for %s", family_id)
            return assistant_id

    async def context(self, family_id: str, query: str, limit: int = 8) -> str:
        assistant_id = await self.assistant_for(family_id)
        result = await self._client.search_memories(assistant_id, query=query, limit=limit)
        facts = [item.get("content", "") for item in result.get("memories", []) if item.get("content")]
        return "\n".join(facts) if facts else NO_CONTEXT

    async def remember(self, family_id: str, speaker_id: str, summary: str) -> None:
        assistant_id = await self.assistant_for(family_id)
        await self._client.add_memory(
            assistant_id,
            content=summary,
            metadata={"family_id": family_id, "speaker_id": speaker_id, "source": "heirloom"},
        )
