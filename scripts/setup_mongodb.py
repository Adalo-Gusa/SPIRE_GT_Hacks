#!/usr/bin/env python3
"""MongoDB Atlas Database Setup and Seeding Script for HeirLoom.

Configures database 'heirloom_db' with:
1. Collections: 'members', 'stories', 'sparks'
2. Standard B-Tree Indexes on kinship, authors, and generations
3. Pre-seeded 3-Generation Clarke Family for the corkboard canvas
4. Historical Story: 'Tinkering at 2 AM: The Dorm Radio' (Grandpa Joe, 1970)
5. Intergenerational Spark: Grandpa Joe & Alex Clarke on 'Electronics'
6. Atlas Vector Search & Search Index configurations
"""

from __future__ import annotations

import datetime
import json
import os
import sys
import urllib.parse
from pathlib import Path

try:
    import certifi
    import pymongo
    from pymongo.errors import ConnectionFailure, ServerSelectionTimeoutError
except ImportError:
    print("Error: pymongo, certifi, and dnspython are required.")
    print("Run: pip install pymongo certifi dnspython")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
DB_NAME = "heirloom_db"
FAMILY_ID = "fam_clarke_001"

# Default connection credentials
DEFAULT_URI = (
    "mongodb+srv://adalo-gusaDB:n%40dG8gDkUiaa.tW@testcluster.s7u10u.mongodb.net/?appName=TestCluster"
)


def load_mongodb_uri() -> str:
    """Resolves MongoDB URI from sys.argv, os.environ, middleware/.env, or default."""
    if len(sys.argv) > 1 and sys.argv[1].startswith("mongodb"):
        raw_uri = sys.argv[1]
    elif os.environ.get("MONGODB_URI"):
        raw_uri = os.environ["MONGODB_URI"]
    else:
        env_file = ROOT / "middleware" / ".env"
        found = None
        if env_file.is_file():
            for line in env_file.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("MONGODB_URI="):
                    found = line.split("=", 1)[1].strip().strip("\"'")
                    break
        raw_uri = found or DEFAULT_URI

    # Clean markdown artifacts if pasted from UI (e.g. mailto or [link])
    raw_uri = raw_uri.replace("[", "").replace("]", "")
    if "mailto:" in raw_uri:
        raw_uri = raw_uri.replace("mailto:", "")

    # Ensure password special characters are URL-encoded
    if "@" in raw_uri:
        prefix, rest = raw_uri.split("://", 1) if "://" in raw_uri else ("", raw_uri)
        if "@" in rest:
            userinfo, hostinfo = rest.rsplit("@", 1)
            if ":" in userinfo:
                username, password = userinfo.split(":", 1)
                encoded_password = urllib.parse.quote_plus(urllib.parse.unquote_plus(password))
                raw_uri = f"{prefix}://{username}:{encoded_password}@{hostinfo}"

    return raw_uri


# Seed Data: 3-Generation Family Tree
SEED_MEMBERS = [
    # Generation 1 (Grandparents)
    {
        "_id": "member_grandpa_joe",
        "family_id": FAMILY_ID,
        "name": "Joseph Clarke",
        "birth_year": 1948,
        "generation_tier": 1,
        "spouse_id": "member_grandma_eleanor",
        "parents": [],
        "children": ["member_marcus"],
        "passions": ["Ham Radio", "Woodworking", "Civil Aviation", "1960s Cars"],
        "avatar_url": "https://images.unsplash.com/photo-1544005313-94ddf0286df2",
        "bio": "Retired aerospace engineer, lifelong ham radio operator (callsign K4JOC), and vintage car tinkerer.",
        "created_at": datetime.datetime(2026, 1, 1, 12, 0, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    },
    {
        "_id": "member_grandma_eleanor",
        "family_id": FAMILY_ID,
        "name": "Eleanor Clarke",
        "birth_year": 1950,
        "generation_tier": 1,
        "spouse_id": "member_grandpa_joe",
        "parents": [],
        "children": ["member_marcus"],
        "passions": ["Baking", "Watercolor Painting", "Gardening"],
        "avatar_url": "https://images.unsplash.com/photo-1544005313-94ddf0286df2",
        "bio": "Master gardener, botanical watercolor artist, and family holiday pastry anchor.",
        "created_at": datetime.datetime(2026, 1, 1, 12, 0, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    },
    # Generation 2 (Parents)
    {
        "_id": "member_marcus",
        "family_id": FAMILY_ID,
        "name": "Marcus Clarke",
        "birth_year": 1976,
        "generation_tier": 2,
        "spouse_id": "member_sarah",
        "parents": ["member_grandpa_joe", "member_grandma_eleanor"],
        "children": ["member_alex"],
        "passions": ["Cycling", "Photography", "Acoustic Guitar"],
        "avatar_url": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d",
        "bio": "Landscape photographer, gravel cyclist, and acoustic folk guitarist.",
        "created_at": datetime.datetime(2026, 1, 2, 12, 0, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    },
    {
        "_id": "member_sarah",
        "family_id": FAMILY_ID,
        "name": "Sarah Clarke",
        "birth_year": 1978,
        "generation_tier": 2,
        "spouse_id": "member_marcus",
        "parents": [],
        "children": ["member_alex"],
        "passions": ["Pottery", "Trail Running"],
        "avatar_url": "https://images.unsplash.com/photo-1534528741775-53994a69daeb",
        "bio": "Studio ceramic artist and ultrarunner exploring mountain passes.",
        "created_at": datetime.datetime(2026, 1, 2, 12, 0, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    },
    # Generation 3 (Grandchild)
    {
        "_id": "member_alex",
        "family_id": FAMILY_ID,
        "name": "Alex Clarke",
        "birth_year": 2004,
        "generation_tier": 3,
        "spouse_id": None,
        "parents": ["member_marcus", "member_sarah"],
        "children": [],
        "passions": ["Electronics", "Synthesizer Music", "Guitar Pedals", "Computer Engineering"],
        "avatar_url": "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6",
        "bio": "Georgia Tech CE sophomore building analog synthesizer filters, fuzz pedals, and embedded audio DSP.",
        "created_at": datetime.datetime(2026, 1, 3, 12, 0, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    },
]

# Seed Data: Sample Oral History Story
SEED_STORIES = [
    {
        "_id": "story_dorm_radio_1970",
        "family_id": FAMILY_ID,
        "author_id": "member_grandpa_joe",
        "title": "Tinkering at 2 AM: The Dorm Radio",
        "narrative_summary": (
            "In November 1970, while living in a college dorm, Joe stayed up past 2 AM assembling "
            "a custom vacuum-tube shortwave transmitter out of salvaged aircraft parts. Amid the static, "
            "he tuned into a live ham operator in Oslo, Norway, sparking a lifelong romance with electronics and radios."
        ),
        "extracted_era": "1970",
        "location": "Durham, NC",
        "passions": ["Ham Radio", "Electronics"],
        "people_mentioned": ["Eleanor Clarke"],
        "grok_imagine_prompt": (
            "A warm 1970s Kodachrome photograph of a 22-year-old engineering student in a cozy college dorm room late at night, "
            "surrounded by glowing vacuum tubes, copper wiring, and an illuminated ham radio dial, soft warm amber glow, film grain, vintage desktop clutter"
        ),
        "raw_transcript": (
            "User: In November of 1970, I was in my college dorm with parts from an old aircraft radio I'd scavenged. "
            "Around 2 in the morning, while my roommate was dead asleep, I fired up the circuit. The vacuum tubes gave off this "
            "deep warm orange glow. Then through the headphones came a crackle and a callsign from Oslo, Norway. "
            "That was the exact moment I knew electronics was my calling."
        ),
        "image_url": "https://images.unsplash.com/photo-1550751827-4bd374c3f58b",
        "created_at": datetime.datetime(1970, 11, 15, 2, 14, 0),
        "updated_at": datetime.datetime.now(datetime.timezone.utc),
    }
]

# Seed Data: Sample Intergenerational Spark
SEED_SPARKS = [
    {
        "_id": "spark_electronics_joe_alex",
        "family_id": FAMILY_ID,
        "elder_id": "member_grandpa_joe",
        "target_member_id": "member_alex",
        "matched_passion": "Electronics",
        "spark_message": (
            "Grandpa Joe built vacuum-tube shortwave transmitters in his college dorm in 1970—just like "
            "Alex is soldering guitar pedals and modular synth circuits today! Ask him about the 2 AM tube glow."
        ),
        "cta_action": "Ask Grandpa Joe about the 2 AM Dorm Radio",
        "is_read": False,
        "status": "active",
        "created_at": datetime.datetime.now(datetime.timezone.utc),
    }
]

# Atlas Vector Search Definition for 'stories'
ATLAS_VECTOR_SEARCH_INDEX = {
    "name": "story_vector_index",
    "definition": {
        "fields": [
            {
                "type": "vector",
                "path": "embedding",
                "numDimensions": 1536,
                "similarity": "cosine",
            },
            {
                "type": "filter",
                "path": "family_id",
            },
            {
                "type": "filter",
                "path": "passions",
            },
            {
                "type": "filter",
                "path": "author_id",
            },
        ]
    },
}

# Atlas Search (Full-Text) Definition for 'stories'
ATLAS_FULLTEXT_SEARCH_INDEX = {
    "name": "story_text_index",
    "definition": {
        "mappings": {
            "dynamic": False,
            "fields": {
                "title": {"type": "string"},
                "narrative_summary": {"type": "string"},
                "location": {"type": "string"},
                "extracted_era": {"type": "string"},
                "passions": {"type": "string"},
                "people_mentioned": {"type": "string"},
            },
        }
    },
}


def run_setup() -> bool:
    uri = load_mongodb_uri()
    # Mask password for display
    display_uri = uri
    if "@" in display_uri and "://" in display_uri:
        p, rest = display_uri.split("://", 1)
        u, h = rest.rsplit("@", 1)
        display_uri = f"{p}://***:***@{h}"

    print("=" * 70)
    print("HeirLoom — MongoDB Atlas Setup & Seeding")
    print("=" * 70)
    print(f"Target Cluster: {display_uri}")
    print(f"Target Database: {DB_NAME}")
    print(f"Family ID:       {FAMILY_ID}")
    print()

    print("[1/5] Connecting to MongoDB Atlas Cluster...")
    try:
        client = pymongo.MongoClient(
            uri,
            tlsCAFile=certifi.where(),
            serverSelectionTimeoutMS=8000,
            connectTimeoutMS=8000,
            socketTimeoutMS=8000,
        )
        # Verify connection by issuing a ping command
        client.admin.command("ping")
        print("  -> Connection successful! MongoDB Atlas ping acknowledged.")
    except (ServerSelectionTimeoutError, ConnectionFailure) as err:
        print()
        print("  [!] Connection Timed Out:")
        print(f"      {err}")
        print()
        print("  -> CAUSE: MongoDB Atlas Network Access Firewall.")
        print("     Atlas blocks incoming traffic from new IP addresses by default.")
        print()
        print("  -> QUICK RESOLUTION (takes 30 seconds):")
        print("     1. Log in to https://cloud.mongodb.com")
        print("     2. In the left navigation, click 'Network Access' (under Security).")
        print("     3. Click '+ Add IP Address'.")
        print("     4. Click 'Allow Access from Anywhere' (0.0.0.0/0), or add current IP.")
        print("     5. Click 'Confirm' and wait ~15 seconds for Atlas to apply.")
        print("     6. Re-run this script: py -3 scripts/setup_mongodb.py")
        print("=" * 70)
        return False
    except Exception as err:
        print(f"  [!] Unexpected connection error: {err}")
        return False

    db = client[DB_NAME]

    print("\n[2/5] Creating / Verifying Collections...")
    existing = set(db.list_collection_names())
    for col_name in ("members", "stories", "sparks"):
        if col_name not in existing:
            db.create_collection(col_name)
            print(f"  -> Created collection: '{col_name}'")
        else:
            print(f"  -> Collection already exists: '{col_name}'")

    print("\n[3/5] Configuring Standard B-Tree Indexes...")
    # Indexes on 'members'
    db.members.create_index([("family_id", pymongo.ASCENDING)], name="idx_members_family")
    db.members.create_index([("generation_tier", pymongo.ASCENDING)], name="idx_members_generation")
    db.members.create_index(
        [("family_id", pymongo.ASCENDING), ("generation_tier", pymongo.ASCENDING)],
        name="idx_members_fam_gen",
    )
    print("  -> Created indexes on 'members': family_id, generation_tier, (family_id + generation_tier)")

    # Indexes on 'stories'
    db.stories.create_index([("family_id", pymongo.ASCENDING)], name="idx_stories_family")
    db.stories.create_index([("author_id", pymongo.ASCENDING)], name="idx_stories_author")
    db.stories.create_index([("created_at", pymongo.DESCENDING)], name="idx_stories_created_at")
    db.stories.create_index([("passions", pymongo.ASCENDING)], name="idx_stories_passions")
    print("  -> Created indexes on 'stories': family_id, author_id, created_at, passions")

    # Indexes on 'sparks'
    db.sparks.create_index([("family_id", pymongo.ASCENDING)], name="idx_sparks_family")
    db.sparks.create_index([("elder_id", pymongo.ASCENDING)], name="idx_sparks_elder")
    db.sparks.create_index([("target_member_id", pymongo.ASCENDING)], name="idx_sparks_target")
    db.sparks.create_index(
        [("family_id", pymongo.ASCENDING), ("is_read", pymongo.ASCENDING)],
        name="idx_sparks_fam_status",
    )
    print("  -> Created indexes on 'sparks': family_id, elder_id, target_member_id, (family_id + is_read)")

    print("\n[4/5] Upserting Seed Data (Idempotent)...")
    # Upsert Members
    for member in SEED_MEMBERS:
        db.members.update_one({"_id": member["_id"]}, {"$set": member}, upsert=True)
        print(f"  -> Upserted member: {member['name']} (Gen {member['generation_tier']}) [{member['_id']}]")

    # Upsert Stories
    for story in SEED_STORIES:
        db.stories.update_one({"_id": story["_id"]}, {"$set": story}, upsert=True)
        print(f"  -> Upserted story: \"{story['title']}\" [{story['_id']}]")

    # Upsert Sparks
    for spark in SEED_SPARKS:
        db.sparks.update_one({"_id": spark["_id"]}, {"$set": spark}, upsert=True)
        print(f"  -> Upserted spark: {spark['matched_passion']} [{spark['elder_id']} <-> {spark['target_member_id']}]")

    print("\n[5/5] Atlas Vector Search & Full-Text Search Configuration:")
    print("  To enable Vector Search on 'stories' for AI semantic matching:")
    print("  1. In Atlas UI, go to: Atlas Search -> Create Search Index")
    print("  2. Select 'Atlas Vector Search' (JSON Editor)")
    print("  3. Target collection: 'heirloom_db.stories'")
    print(f"  4. Index Name: '{ATLAS_VECTOR_SEARCH_INDEX['name']}'")
    print("  5. Paste the following JSON definition:")
    print(json.dumps(ATLAS_VECTOR_SEARCH_INDEX["definition"], indent=4))
    print()
    print("  Full-Text Search Index definition for keyword / hobby queries:")
    print(f"  Index Name: '{ATLAS_FULLTEXT_SEARCH_INDEX['name']}'")
    print(json.dumps(ATLAS_FULLTEXT_SEARCH_INDEX["definition"], indent=4))

    print("\n" + "=" * 70)
    print("Setup Complete! Database 'heirloom_db' is primed and ready.")
    print("=" * 70)
    return True


if __name__ == "__main__":
    success = run_setup()
    sys.exit(0 if success else 1)
