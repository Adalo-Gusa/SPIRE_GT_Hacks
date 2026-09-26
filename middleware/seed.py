"""Seed the Clarke demo family into Atlas. Mirrors `MockDataService.seededGraph()` in the iOS app.

  python seed.py            seed only if the family has no members yet
  python seed.py --reset    delete this family's documents and reseed
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from datetime import UTC, datetime
from uuid import UUID

from env import load_env
from models import (
    FamilyGraph,
    FamilyMember,
    GenerationTier,
    HobbyConnection,
    KinshipEdge,
    KinshipRelation,
    LoomSpark,
    MemoryNode,
    SparkActionType,
)
from store import MongoFamilyStore

JOSEPH = UUID("00000000-0000-0000-0000-000000000101")
ELEANOR = UUID("00000000-0000-0000-0000-000000000102")
MARCUS = UUID("00000000-0000-0000-0000-000000000201")
SARAH = UUID("00000000-0000-0000-0000-000000000202")
ALEX = UUID("00000000-0000-0000-0000-000000000301")

JOSEPH_WORKSHOP_MEMORY = UUID("00000000-0000-0000-0001-000000000001")
ELEANOR_AIRFIELD_MEMORY = UUID("00000000-0000-0000-0001-000000000002")
MARCUS_MUSTANG_MEMORY = UUID("00000000-0000-0000-0001-000000000003")
ALEX_SYNTH_MEMORY = UUID("00000000-0000-0000-0001-000000000004")


def _date(year: int, month: int, day: int) -> datetime:
    return datetime(year, month, day, tzinfo=UTC)


def clarke_graph() -> FamilyGraph:
    members = [
        FamilyMember(
            id=JOSEPH,
            name="Joseph Clarke",
            generation_tier=GenerationTier.GRANDPARENTS,
            relationship_label="Grandfather",
            bio="Retired aircraft mechanic and lifelong tinkerer. Licensed ham radio operator since 1963.",
            passion_tags=["Woodworking", "Ham Radio", "1960s Civil Aviation"],
            phone_number="+15555550101",
        ),
        FamilyMember(
            id=ELEANOR,
            name="Eleanor Clarke",
            generation_tier=GenerationTier.GRANDPARENTS,
            relationship_label="Grandmother",
            bio="Former airline operations clerk at Dayton Municipal Airport. Keeper of the family photo albums.",
            passion_tags=["1960s Civil Aviation", "Quilting", "Big Band Music"],
            phone_number="+15555550102",
        ),
        FamilyMember(
            id=MARCUS,
            name="Marcus Clarke",
            generation_tier=GenerationTier.PARENTS,
            relationship_label="Father",
            bio="High school physics teacher who restores classic cars with anyone who will hold a wrench.",
            passion_tags=["Woodworking", "Classic Cars", "Physics"],
            phone_number="+15555550201",
        ),
        FamilyMember(
            id=SARAH,
            name="Sarah Clarke",
            generation_tier=GenerationTier.PARENTS,
            relationship_label="Mother",
            bio="Nurse and amateur genealogist; started the family's first digital archive.",
            passion_tags=["Genealogy", "Photography", "Baking"],
            phone_number="+15555550202",
        ),
        FamilyMember(
            id=ALEX,
            name="Alex Clarke",
            generation_tier=GenerationTier.GRANDCHILDREN,
            relationship_label="Grandchild",
            bio="Computer engineering student at Georgia Tech who builds modular synths and guitar pedals.",
            passion_tags=["Computer Engineering", "Synthesizer Music", "Guitar Pedals"],
            phone_number="+15555550301",
        ),
    ]
    memories = [
        MemoryNode(
            id=ELEANOR_AIRFIELD_MEMORY,
            author_id=ELEANOR,
            timestamp=_date(2026, 8, 2),
            raw_transcript="I worked the ticket counter when the first jets came through Dayton. We'd go up to the "
            "observation deck on breaks and listen to the tower chatter on Joseph's little receiver.",
            narrative_summary="Eleanor worked the Dayton airport counter as jet service arrived in the 1960s, "
            "spending breaks on the observation deck listening to tower radio.",
            extracted_era="1960s",
            location="Dayton Municipal Airport, Ohio",
            entities_mentioned=["Dayton Municipal Airport", "Joseph Clarke"],
            hobbies_identified=["1960s Civil Aviation", "Ham Radio"],
            tags=["aviation", "career", "1960s"],
        ),
        MemoryNode(
            id=JOSEPH_WORKSHOP_MEMORY,
            author_id=JOSEPH,
            timestamp=_date(2026, 8, 15),
            raw_transcript="Every Saturday Marcus and I were in the garage. I made him cut dovetails by hand "
            "before I'd let him near the table saw.",
            narrative_summary="Joseph taught a young Marcus hand-cut dovetail joinery in the family garage "
            "every Saturday throughout the 1980s.",
            extracted_era="1980s",
            location="Clarke family garage, Dayton, Ohio",
            entities_mentioned=["Marcus Clarke"],
            hobbies_identified=["Woodworking"],
            tags=["workshop", "teaching", "father and son"],
        ),
        MemoryNode(
            id=MARCUS_MUSTANG_MEMORY,
            author_id=MARCUS,
            timestamp=_date(2026, 9, 1),
            raw_transcript="Dad and I spent two summers rebuilding a '66 Mustang. He rewired the whole dash from memory.",
            narrative_summary="Marcus and Joseph rebuilt a 1966 Mustang over two summers in the 1990s, "
            "with Joseph rewiring the dashboard from memory.",
            extracted_era="1990s",
            location="Dayton, Ohio",
            entities_mentioned=["Joseph Clarke", "1966 Ford Mustang"],
            hobbies_identified=["Classic Cars"],
            tags=["cars", "restoration"],
        ),
        MemoryNode(
            id=ALEX_SYNTH_MEMORY,
            author_id=ALEX,
            timestamp=_date(2026, 9, 18),
            raw_transcript="Finished my first Eurorack oscillator module in the dorm. Took three tries to get "
            "the tuning stable.",
            narrative_summary="Alex completed a hand-built Eurorack oscillator module in his Georgia Tech dorm "
            "after three attempts to stabilize its tuning.",
            extracted_era="2020s",
            location="Georgia Tech, Atlanta",
            entities_mentioned=["Eurorack", "Georgia Tech"],
            hobbies_identified=["Synthesizer Music", "Computer Engineering"],
            tags=["synth", "electronics", "college"],
        ),
    ]
    kinship = [
        KinshipEdge(from_id=JOSEPH, to_id=ELEANOR, relation_type=KinshipRelation.SPOUSE),
        KinshipEdge(from_id=MARCUS, to_id=SARAH, relation_type=KinshipRelation.SPOUSE),
        KinshipEdge(from_id=JOSEPH, to_id=MARCUS, relation_type=KinshipRelation.PARENT),
        KinshipEdge(from_id=ELEANOR, to_id=MARCUS, relation_type=KinshipRelation.PARENT),
        KinshipEdge(from_id=MARCUS, to_id=ALEX, relation_type=KinshipRelation.PARENT),
        KinshipEdge(from_id=SARAH, to_id=ALEX, relation_type=KinshipRelation.PARENT),
    ]
    connections = [
        HobbyConnection(
            from_member_id=JOSEPH,
            to_member_id=MARCUS,
            shared_interest="Woodworking",
            match_rationale="Joseph taught Marcus joinery in the garage workshop; Marcus still builds furniture on weekends.",
            source_memory_id=JOSEPH_WORKSHOP_MEMORY,
        )
    ]
    sparks = [
        LoomSpark(
            target_member_id=SARAH,
            elder_id=ELEANOR,
            prompt_text="Eleanor's airfield story is now a storybook chapter. Take a look before Sunday dinner.",
            action_type=SparkActionType.VIEW_STORY,
            timestamp=_date(2026, 9, 20),
            related_memory_id=ELEANOR_AIRFIELD_MEMORY,
        )
    ]
    return FamilyGraph(
        members=members,
        memories=memories,
        kinship_edges=kinship,
        hobby_connections=connections,
        sparks=sparks,
    )


async def seed(reset: bool) -> str:
    family_id = os.environ.get("HEIRLOOM_FAMILY_ID", "fam_clarke_001")
    store = MongoFamilyStore.from_env()
    try:
        await store.ping()
        await store.ensure_indexes()
        if not reset and await store.has_members(family_id):
            return f"Family {family_id} already has members. Pass --reset to reseed."
        await store.replace_family(family_id, clarke_graph())
        return f"Seeded the Clarke family as {family_id}."
    finally:
        await store.close()


def main() -> None:
    load_env()
    parser = argparse.ArgumentParser(description="Seed the Clarke demo family into MongoDB Atlas.")
    parser.add_argument("--reset", action="store_true", help="Delete this family's documents first")
    args = parser.parse_args()
    try:
        print(asyncio.run(seed(args.reset)))
    except Exception as error:
        print(f"Seeding failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
