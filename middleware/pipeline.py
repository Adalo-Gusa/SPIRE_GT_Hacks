"""The oral-story pipeline. Ingest returns as soon as the memory, bridges, and sparks are saved;
Backboard persistence and the storybook illustration finish in the background.
"""

from __future__ import annotations

import logging
from typing import Protocol
from uuid import UUID

from grok import FALLBACK_FOLLOW_UP, ExtractedMemory, ProviderError
from interest_bridge import shared_interest
from models import (
    FamilyGraph,
    FamilyMember,
    HobbyConnection,
    LoomSpark,
    MemoryIngestionResult,
    MemoryNode,
    SparkActionType,
    StoryChapter,
)
from store import FamilyStoreProtocol

logger = logging.getLogger("heirloom.pipeline")


class UnknownMemberError(LookupError):
    pass


class GrokProtocol(Protocol):
    async def follow_up(self, transcript: str, prior_context: str) -> str: ...
    async def extract_memory(self, transcript: str) -> ExtractedMemory: ...
    async def illustration_prompt(self, summary: str, era: str) -> str: ...
    async def generate_image(self, prompt: str) -> str: ...


class MemoryProtocol(Protocol):
    async def context(self, family_id: str, query: str, limit: int = 8) -> str: ...
    async def remember(self, family_id: str, speaker_id: str, summary: str) -> None: ...


class LoomPipeline:
    def __init__(self, store: FamilyStoreProtocol, grok: GrokProtocol, memory: MemoryProtocol, family_id: str) -> None:
        self.store = store
        self.grok = grok
        self.memory = memory
        self.family_id = family_id

    async def ingest(self, transcript: str, author_id: UUID) -> tuple[MemoryIngestionResult, FamilyMember]:
        """Extract, bridge, and save a story. Provider failures raise; nothing is ever invented."""
        graph = await self.store.graph(self.family_id)
        author = graph.member(author_id)
        if author is None:
            raise UnknownMemberError(f"No family member {author_id}")

        extracted = await self.grok.extract_memory(transcript)
        memory = MemoryNode(
            author_id=author.id,
            raw_transcript=transcript,
            narrative_summary=extracted.narrative_summary,
            extracted_era=extracted.extracted_era,
            location=extracted.location,
            entities_mentioned=extracted.entities_mentioned,
            hobbies_identified=extracted.hobbies_identified,
            tags=extracted.hobbies_identified,
        )
        connections, sparks = bridges(memory, author, graph)

        await self.store.insert_memory(self.family_id, memory)
        await self.store.insert_connections(self.family_id, connections)
        await self.store.insert_sparks(self.family_id, sparks)
        passions = sorted(set(author.passion_tags) | set(memory.hobbies_identified))
        if passions != sorted(author.passion_tags):
            await self.store.update_member_passions(self.family_id, author.id, passions)

        return MemoryIngestionResult(memory=memory, new_connections=connections, sparks=sparks), author

    async def finish_in_background(self, memory: MemoryNode, author_name: str) -> None:
        """Best-effort follow-through. Each step logs and continues so one outage doesn't block the rest."""
        try:
            await self.memory.remember(self.family_id, str(memory.author_id), memory.narrative_summary)
        except Exception:
            logger.exception("Backboard persist failed for memory %s", memory.id)

        illustration_url: str | None = None
        try:
            prompt = await self.grok.illustration_prompt(memory.narrative_summary, memory.extracted_era)
            illustration_url = await self.grok.generate_image(prompt)
        except Exception:
            logger.exception("Illustration failed for memory %s", memory.id)

        try:
            await self.store.insert_chapter(
                self.family_id,
                StoryChapter(
                    title=f"{author_name}, {memory.extracted_era}",
                    narrative_text=memory.narrative_summary,
                    illustration_url=illustration_url,
                    source_memory_ids=[memory.id],
                ),
            )
        except Exception:
            logger.exception("Chapter insert failed for memory %s", memory.id)

    async def follow_ups(self, memory: MemoryNode) -> list[str]:
        context = await self.family_context(memory.raw_transcript)
        try:
            return [await self.grok.follow_up(memory.raw_transcript, context)]
        except ProviderError:
            logger.exception("Follow-up generation failed")
            return [FALLBACK_FOLLOW_UP]

    async def family_context(self, query: str) -> str:
        try:
            return await self.memory.context(self.family_id, query)
        except Exception:
            logger.exception("Backboard context failed; using recent Atlas memories")
            graph = await self.store.graph(self.family_id)
            recent = sorted(graph.memories, key=lambda m: m.timestamp, reverse=True)[:4]
            lines = [f"{m.extracted_era}: {m.narrative_summary}" for m in recent]
            return "\n".join(lines) if lines else "No saved family context yet."

    async def storybook(self, memory_ids: list[UUID]) -> list[StoryChapter]:
        """Stored chapters, plus a text-only chapter for any selected memory that has none yet."""
        graph = await self.store.graph(self.family_id)
        chapters = await self.store.chapters(self.family_id, memory_ids)
        by_memory = {memory_id: chapter for chapter in chapters for memory_id in chapter.source_memory_ids}
        wanted = set(memory_ids)
        selected = [m for m in graph.memories if not wanted or m.id in wanted]
        result: list[StoryChapter] = []
        for memory in sorted(selected, key=lambda m: m.timestamp):
            chapter = by_memory.get(memory.id)
            if chapter is None:
                author = graph.member(memory.author_id)
                chapter = StoryChapter(
                    id=memory.id,
                    title=f"{author.name if author else 'A family member'}, {memory.extracted_era}",
                    narrative_text=memory.narrative_summary,
                    source_memory_ids=[memory.id],
                )
            if chapter not in result:
                result.append(chapter)
        return result


def bridges(memory: MemoryNode, author: FamilyMember, graph: FamilyGraph) -> tuple[list[HobbyConnection], list[LoomSpark]]:
    """Connect the storyteller to younger relatives who share an interest (anyone, if nobody is younger)."""
    others = [m for m in graph.members if m.id != author.id]
    younger = [m for m in others if m.generation_tier > author.generation_tier]
    connections: list[HobbyConnection] = []
    sparks: list[LoomSpark] = []
    for member in younger or others:
        shared = shared_interest(memory.hobbies_identified, member.passion_tags)
        if shared is None:
            continue
        connections.append(
            HobbyConnection(
                from_member_id=author.id,
                to_member_id=member.id,
                shared_interest=shared,
                match_rationale=f"{author.first_name} talked about {', '.join(memory.hobbies_identified)}, "
                f"which lines up with {member.first_name}'s {', '.join(member.passion_tags)}.",
                source_memory_id=memory.id,
            )
        )
        sparks.append(
            LoomSpark(
                target_member_id=member.id,
                elder_id=author.id,
                prompt_text=f"{author.first_name} just shared a story about {shared}. Give them a call and ask about it.",
                action_type=SparkActionType.CALL_PHONE,
                related_memory_id=memory.id,
            )
        )
    return connections, sparks
