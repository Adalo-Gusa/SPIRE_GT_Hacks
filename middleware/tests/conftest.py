from __future__ import annotations

import sys
from pathlib import Path
from uuid import UUID

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from grok import ExtractedMemory, ProviderError  # noqa: E402
from models import (  # noqa: E402
    FamilyGraph,
    FamilyMember,
    HobbyConnection,
    LoomSpark,
    MemoryNode,
    StoryChapter,
)
from pipeline import LoomPipeline  # noqa: E402
from seed import clarke_graph  # noqa: E402

FAMILY = "fam_test"


class FakeStore:
    def __init__(self, graph: FamilyGraph) -> None:
        self.data = graph.model_copy(deep=True)
        self.stored_chapters: list[StoryChapter] = []
        self.assistants: dict[str, str] = {}

    async def graph(self, family_id: str) -> FamilyGraph:
        return self.data.model_copy(deep=True)

    async def member(self, family_id: str, member_id: UUID) -> FamilyMember | None:
        return self.data.member(member_id)

    async def insert_memory(self, family_id: str, memory: MemoryNode) -> None:
        self.data.memories.append(memory)

    async def insert_connections(self, family_id: str, connections: list[HobbyConnection]) -> None:
        self.data.hobby_connections.extend(connections)

    async def insert_sparks(self, family_id: str, sparks: list[LoomSpark]) -> None:
        self.data.sparks.extend(sparks)

    async def update_member_passions(self, family_id: str, member_id: UUID, passions: list[str]) -> None:
        member = self.data.member(member_id)
        assert member is not None
        member.passion_tags = passions

    async def pending_sparks(self, family_id: str, member_id: UUID) -> list[LoomSpark]:
        return [s for s in self.data.sparks if s.target_member_id == member_id and not s.is_resolved]

    async def resolve_spark(self, family_id: str, spark_id: UUID) -> bool:
        for spark in self.data.sparks:
            if spark.id == spark_id:
                spark.is_resolved = True
                return True
        return False

    async def chapters(self, family_id: str, memory_ids: list[UUID]) -> list[StoryChapter]:
        wanted = set(memory_ids)
        return [c for c in self.stored_chapters if not wanted or wanted & set(c.source_memory_ids)]

    async def insert_chapter(self, family_id: str, chapter: StoryChapter) -> None:
        self.stored_chapters.append(chapter)

    async def assistant_id(self, family_id: str) -> str | None:
        return self.assistants.get(family_id)

    async def set_assistant_id(self, family_id: str, assistant_id: str) -> None:
        self.assistants[family_id] = assistant_id


class FakeGrok:
    def __init__(self) -> None:
        self.extraction = ExtractedMemory(
            extracted_era="1962",
            location="Dayton, Ohio",
            entities_mentioned=["Heathkit", "Nova Scotia"],
            hobbies_identified=["Ham Radio", "Soldering"],
            narrative_summary="Joseph built a Heathkit shortwave radio in 1962.",
        )
        self.fail_extraction = False
        self.fail_image = False
        self.fail_follow_up = False
        self.image_prompts: list[str] = []

    async def follow_up(self, transcript: str, prior_context: str) -> str:
        if self.fail_follow_up:
            raise ProviderError("Grok timed out")
        return f"Who taught you? (context: {prior_context})"

    async def extract_memory(self, transcript: str) -> ExtractedMemory:
        if self.fail_extraction:
            raise ProviderError("Grok timed out")
        return self.extraction

    async def illustration_prompt(self, summary: str, era: str) -> str:
        return f"Vintage {era} photo: {summary}"

    async def generate_image(self, prompt: str) -> str:
        self.image_prompts.append(prompt)
        if self.fail_image:
            raise ProviderError("Grok Imagine returned no image")
        return "https://images.example/radio.png"


class FakeMemory:
    def __init__(self) -> None:
        self.remembered: list[tuple[str, str, str]] = []
        self.fail = False

    async def context(self, family_id: str, query: str, limit: int = 8) -> str:
        if self.fail:
            raise RuntimeError("Backboard down")
        return "Joseph is a ham radio operator."

    async def remember(self, family_id: str, speaker_id: str, summary: str) -> None:
        if self.fail:
            raise RuntimeError("Backboard down")
        self.remembered.append((family_id, speaker_id, summary))


@pytest.fixture
def store() -> FakeStore:
    return FakeStore(clarke_graph())


@pytest.fixture
def grok() -> FakeGrok:
    return FakeGrok()


@pytest.fixture
def memory() -> FakeMemory:
    return FakeMemory()


@pytest.fixture
def pipeline(store: FakeStore, grok: FakeGrok, memory: FakeMemory) -> LoomPipeline:
    return LoomPipeline(store, grok, memory, FAMILY)
