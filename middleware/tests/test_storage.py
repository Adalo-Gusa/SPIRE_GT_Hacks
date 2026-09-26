from __future__ import annotations

import asyncio
from datetime import datetime
from types import SimpleNamespace

from family_memory import NO_CONTEXT, FamilyMemory
from models import KinshipEdge, KinshipRelation, MemoryNode
from seed import ALEX, JOSEPH
from store import to_document


def test_to_document_uses_uuid_strings_and_keeps_datetimes() -> None:
    memory = MemoryNode(author_id=JOSEPH, raw_transcript="t", narrative_summary="s", extracted_era="1960s")
    document = to_document(memory, "fam_x")
    assert document["id"] == str(memory.id)
    assert document["author_id"] == str(JOSEPH)
    assert isinstance(document["timestamp"], datetime)
    assert document["family_id"] == "fam_x"
    assert "_id" not in document

    edge = to_document(KinshipEdge(from_id=JOSEPH, to_id=ALEX, relation_type=KinshipRelation.PARENT), "fam_x")
    assert edge["relation_type"] == "parent"


class FakeBackboard:
    def __init__(self) -> None:
        self.created = 0
        self.added: list[tuple[str, str, dict]] = []
        self.searched: list[tuple[str, str, int]] = []

    async def create_assistant(self, name: str, description: str, system_prompt: str):
        self.created += 1
        await asyncio.sleep(0)
        return SimpleNamespace(assistant_id=f"asst_{self.created}")

    async def search_memories(self, assistant_id: str, query: str, limit: int = 5) -> dict:
        self.searched.append((assistant_id, query, limit))
        return {"memories": [{"content": "Joseph fixes radios"}, {"content": ""}], "total_count": 2}

    async def add_memory(self, assistant_id: str, content: str, metadata: dict) -> dict:
        self.added.append((assistant_id, content, metadata))
        return {}


async def test_one_assistant_per_family_created_once(store) -> None:
    backboard = FakeBackboard()
    memory = FamilyMemory(backboard, store)

    first, second = await asyncio.gather(memory.assistant_for("fam_a"), memory.assistant_for("fam_a"))
    other = await memory.assistant_for("fam_b")

    assert first == second == "asst_1"
    assert other == "asst_2"
    assert backboard.created == 2
    assert store.assistants == {"fam_a": "asst_1", "fam_b": "asst_2"}


async def test_context_and_remember_are_scoped_to_family_assistant(store) -> None:
    backboard = FakeBackboard()
    memory = FamilyMemory(backboard, store)
    store.assistants["fam_a"] = "asst_existing"

    assert await memory.context("fam_a", "radio") == "Joseph fixes radios"
    await memory.remember("fam_a", str(JOSEPH), "summary")

    assert backboard.created == 0
    assert backboard.searched[0][0] == "asst_existing"
    assert backboard.added == [("asst_existing", "summary", {"family_id": "fam_a", "speaker_id": str(JOSEPH), "source": "heirloom"})]


async def test_empty_context(store) -> None:
    backboard = FakeBackboard()

    async def nothing(assistant_id: str, query: str, limit: int = 5) -> dict:
        return {"memories": []}

    backboard.search_memories = nothing
    assert await FamilyMemory(backboard, store).context("fam_a", "q") == NO_CONTEXT
