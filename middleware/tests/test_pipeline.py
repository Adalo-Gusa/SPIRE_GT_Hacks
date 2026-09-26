from __future__ import annotations

from uuid import uuid4

import pytest

from grok import FALLBACK_FOLLOW_UP, ProviderError
from pipeline import UnknownMemberError
from seed import ALEX, ELEANOR_AIRFIELD_MEMORY, JOSEPH, MARCUS

TRANSCRIPT = "In '62 I built a Heathkit shortwave radio on the kitchen table."


async def test_ingest_saves_memory_bridges_and_sparks(pipeline, store) -> None:
    before = len(store.data.memories)
    result, author = await pipeline.ingest(TRANSCRIPT, JOSEPH)

    assert author.id == JOSEPH
    assert result.memory.raw_transcript == TRANSCRIPT
    assert result.memory.author_id == JOSEPH
    assert len(store.data.memories) == before + 1
    # Only Alex shares electronics; Marcus (woodworking, cars) does not.
    assert [c.to_member_id for c in result.new_connections] == [ALEX]
    assert [s.target_member_id for s in result.sparks] == [ALEX]
    assert result.sparks[0].related_memory_id == result.memory.id
    joseph = store.data.member(JOSEPH)
    assert "Soldering" in joseph.passion_tags


async def test_ingest_unknown_author(pipeline) -> None:
    with pytest.raises(UnknownMemberError):
        await pipeline.ingest(TRANSCRIPT, uuid4())


async def test_extraction_failure_saves_nothing(pipeline, store, grok) -> None:
    grok.fail_extraction = True
    before = store.data.model_copy(deep=True)
    with pytest.raises(ProviderError):
        await pipeline.ingest(TRANSCRIPT, JOSEPH)
    assert store.data == before


async def test_background_persists_memory_and_illustrated_chapter(pipeline, store, memory) -> None:
    result, author = await pipeline.ingest(TRANSCRIPT, JOSEPH)
    await pipeline.finish_in_background(result.memory, author.name)

    assert memory.remembered == [("fam_test", str(JOSEPH), result.memory.narrative_summary)]
    [chapter] = store.stored_chapters
    assert chapter.illustration_url == "https://images.example/radio.png"
    assert chapter.source_memory_ids == [result.memory.id]
    assert chapter.title == "Joseph Clarke, 1962"


async def test_background_keeps_going_when_providers_fail(pipeline, store, grok, memory) -> None:
    grok.fail_image = True
    memory.fail = True
    result, author = await pipeline.ingest(TRANSCRIPT, JOSEPH)
    await pipeline.finish_in_background(result.memory, author.name)

    [chapter] = store.stored_chapters
    assert chapter.illustration_url is None


async def test_follow_ups_use_backboard_context(pipeline, store) -> None:
    [question] = await pipeline.follow_ups(store.data.memories[0])
    assert "ham radio operator" in question


async def test_follow_ups_fall_back_to_atlas_context_then_generic_question(pipeline, store, grok, memory) -> None:
    memory.fail = True
    [question] = await pipeline.follow_ups(store.data.memories[0])
    assert "1960s" in question  # recent Atlas memories replaced the Backboard context

    grok.fail_follow_up = True
    assert await pipeline.follow_ups(store.data.memories[0]) == [FALLBACK_FOLLOW_UP]


async def test_storybook_merges_stored_and_text_only_chapters(pipeline, store) -> None:
    result, author = await pipeline.ingest(TRANSCRIPT, JOSEPH)
    await pipeline.finish_in_background(result.memory, author.name)

    chapters = await pipeline.storybook([])
    assert len(chapters) == len(store.data.memories)
    illustrated = [c for c in chapters if c.illustration_url]
    assert [c.source_memory_ids for c in illustrated] == [[result.memory.id]]
    seeded = next(c for c in chapters if c.source_memory_ids == [ELEANOR_AIRFIELD_MEMORY])
    assert seeded.id == ELEANOR_AIRFIELD_MEMORY  # stable identity for SwiftUI lists
    assert seeded.title == "Eleanor Clarke, 1960s"

    only = await pipeline.storybook([ELEANOR_AIRFIELD_MEMORY])
    assert [c.id for c in only] == [ELEANOR_AIRFIELD_MEMORY]


async def test_bridges_go_to_elders_when_nobody_is_younger(pipeline, store, grok) -> None:
    grok.extraction.hobbies_identified = ["Woodworking"]
    result, _ = await pipeline.ingest("Alex made a birdhouse with dovetail joinery.", ALEX)
    targets = {s.target_member_id for s in result.sparks}
    assert targets == {JOSEPH, MARCUS}
