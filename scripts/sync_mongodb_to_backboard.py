#!/usr/bin/env python3
"""Batch Migration Script: Synchronize MongoDB Atlas archive to Backboard.io.

Populates Backboard memories with:
1. All Family Members (names, generation tiers, birth years, bios, passions, kinship)
2. All Family Cookbook Recipes & Archive Items (ingredients, instructions, heirloom stories)
3. All Oral History Stories (transcripts, summaries, era, locations, people)
4. All Social / Shared Feed Posts (Instagram captions, locations, crafts)
5. All Cross-Generational Sparks

Usage:
    python scripts/sync_mongodb_to_backboard.py [--dry-run] [--all]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Ensure heirloom-api is in Python path
ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR / "heirloom-api"))

try:
    import certifi
    import pymongo
    from backboard_sync import (
        format_member_memory,
        format_item_memory,
        format_story_memory,
        format_post_memory,
        format_spark_memory,
        commit_memory_sync,
        fetch_existing_backboard_memories,
        get_api_key,
        get_assistant_id,
        get_base_url,
        load_env_vars,
    )
except ImportError as err:
    print(f"Error importing dependencies: {err}")
    sys.exit(1)


def parse_args():
    parser = argparse.ArgumentParser(description="Sync MongoDB Atlas to Backboard.io memories.")
    parser.add_argument("--dry-run", action="store_true", help="Print memories without committing to Backboard.")
    parser.add_argument("--force", action="store_true", help="Commit even if similar memory exists in Backboard.")
    return parser.parse_args()


def main():
    args = parse_args()
    env = load_env_vars()

    api_key = get_api_key()
    assistant_id = get_assistant_id()
    base_url = get_base_url()

    print("=" * 65)
    print("       HEIRLOOM -> BACKBOARD.IO MEMORY SYNCHRONIZER")
    print("=" * 65)
    print(f"Backboard API Host : {base_url}")
    print(f"Assistant ID       : {assistant_id}")
    print(f"Backboard API Key  : {'Configured (' + api_key[:8] + '...)' if api_key else 'MISSING!'}")
    print(f"Mode               : {'DRY RUN (No changes)' if args.dry_run else 'LIVE COMMIT'}")
    print("-" * 65)

    if not api_key and not args.dry_run:
        print("ERROR: BACKBOARD_API_KEY is required to sync memories.")
        sys.exit(1)

    # Connect to MongoDB
    mongo_uri = env.get("MONGODB_URI")
    db_name = env.get("MONGODB_DATABASE") or env.get("DB_NAME", "heirloom_db")
    if not mongo_uri:
        print("ERROR: MONGODB_URI is required.")
        sys.exit(1)

    try:
        client = pymongo.MongoClient(mongo_uri, tlsCAFile=certifi.where() if hasattr(certifi, "where") else None)
        db = client[db_name]
        db.command("ping")
        print(f"Connected to MongoDB Atlas database: '{db_name}'\n")
    except Exception as exc:
        print(f"Failed to connect to MongoDB Atlas: {exc}")
        sys.exit(1)

    # Fetch existing memories from Backboard to avoid duplicate spamming
    existing_memories = [] if args.force or args.dry_run else fetch_existing_backboard_memories()
    existing_texts = [
        str(m.get("content", "")).strip().lower()
        for m in existing_memories
        if isinstance(m, dict) and m.get("content")
    ]
    print(f"Existing Backboard Memories on file: {len(existing_texts)}")

    stats = {
        "members": 0,
        "recipes": 0,
        "items": 0,
        "stories": 0,
        "posts": 0,
        "sparks": 0,
        "skipped": 0,
    }

    # 1. MEMBERS
    if "members" in db.list_collection_names():
        members = list(db["members"].find())
        print(f"\nProcessing {len(members)} Member Document(s)...")
        for m in members:
            name = m.get("name", "")
            fact = format_member_memory(m)
            if not args.force and name and any(name.lower() in t for t in existing_texts):
                print(f"  [SKIP] Member '{name}' already recalled in Backboard.")
                stats["skipped"] += 1
                continue

            print(f"  [SYNC] Member '{name}': {fact[:80]}...")
            if not args.dry_run:
                res = commit_memory_sync(
                    fact,
                    "member_profile",
                    str(m["_id"]),
                    m.get("family_id", "fam_clarke_001"),
                )
                if res:
                    stats["members"] += 1
            else:
                stats["members"] += 1

    # 2. ITEMS (Cookbook Recipes & Keepsakes)
    items_col = os.getenv("COLLECTION_NAME", "items")
    if items_col in db.list_collection_names():
        items = list(db[items_col].find())
        print(f"\nProcessing {len(items)} Archive Item Document(s)...")
        for item in items:
            title = (item.get("title") or "").strip()
            fact = format_item_memory(item)
            is_recipe = "recipe" in fact.lower()
            kind_label = "Recipe" if is_recipe else "Keepsake"

            if not args.force and title and any(title.lower() in t for t in existing_texts):
                print(f"  [SKIP] {kind_label} '{title}' already recalled in Backboard.")
                stats["skipped"] += 1
                continue

            print(f"  [SYNC] {kind_label} '{title}': {fact[:80]}...")
            if not args.dry_run:
                res = commit_memory_sync(
                    fact,
                    "cookbook_recipe" if is_recipe else "archive_item",
                    str(item["_id"]),
                    item.get("family_id", "fam_clarke_001"),
                )
                if res:
                    if is_recipe:
                        stats["recipes"] += 1
                    else:
                        stats["items"] += 1
            else:
                if is_recipe:
                    stats["recipes"] += 1
                else:
                    stats["items"] += 1

    # 3. STORIES
    if "stories" in db.list_collection_names():
        stories = list(db["stories"].find())
        print(f"\nProcessing {len(stories)} Story Document(s)...")
        for s in stories:
            title = (s.get("title") or "").strip()
            fact = format_story_memory(s)

            if not args.force and title and any(title.lower() in t for t in existing_texts):
                print(f"  [SKIP] Story '{title}' already recalled in Backboard.")
                stats["skipped"] += 1
                continue

            print(f"  [SYNC] Story '{title}': {fact[:80]}...")
            if not args.dry_run:
                res = commit_memory_sync(
                    fact,
                    "story",
                    str(s["_id"]),
                    s.get("family_id", "fam_clarke_001"),
                )
                if res:
                    stats["stories"] += 1
            else:
                stats["stories"] += 1

    # 4. POSTS
    if "posts" in db.list_collection_names():
        posts = list(db["posts"].find())
        print(f"\nProcessing {len(posts)} Post Document(s)...")
        for p in posts:
            author = p.get("author_name", "Author")
            fact = format_post_memory(p)
            content_snippet = (p.get("content") or "")[:35].lower().strip()

            if not args.force and content_snippet and any(content_snippet in t for t in existing_texts):
                print(f"  [SKIP] Post by {author} already recalled in Backboard.")
                stats["skipped"] += 1
                continue

            print(f"  [SYNC] Post by {author}: {fact[:80]}...")
            if not args.dry_run:
                res = commit_memory_sync(
                    fact,
                    "feed_post",
                    str(p["_id"]),
                    p.get("family_id", "fam_clarke_001"),
                )
                if res:
                    stats["posts"] += 1
            else:
                stats["posts"] += 1

    # 5. SPARKS
    if "sparks" in db.list_collection_names():
        sparks = list(db["sparks"].find())
        print(f"\nProcessing {len(sparks)} Spark Document(s)...")
        for sp in sparks:
            passion = sp.get("matched_passion", "")
            fact = format_spark_memory(sp)

            if not args.force and passion and any(f"connection spark on '{passion.lower()}'" in t for t in existing_texts):
                print(f"  [SKIP] Spark on '{passion}' already recalled in Backboard.")
                stats["skipped"] += 1
                continue

            print(f"  [SYNC] Spark '{passion}': {fact[:80]}...")
            if not args.dry_run:
                res = commit_memory_sync(
                    fact,
                    "spark",
                    str(sp["_id"]),
                    sp.get("family_id", "fam_clarke_001"),
                )
                if res:
                    stats["sparks"] += 1
            else:
                stats["sparks"] += 1

    print("\n" + "=" * 65)
    print("                    SYNCHRONIZATION SUMMARY")
    print("=" * 65)
    print(f"  Members Synced        : {stats['members']}")
    print(f"  Recipes Synced        : {stats['recipes']}")
    print(f"  Archive Items Synced  : {stats['items']}")
    print(f"  Stories Synced        : {stats['stories']}")
    print(f"  Feed Posts Synced     : {stats['posts']}")
    print(f"  Sparks Synced         : {stats['sparks']}")
    print(f"  Already Known (Skip)  : {stats['skipped']}")
    print("=" * 65)
    print("Done! Loomie now has knowledge of all synchronized records.\n")


if __name__ == "__main__":
    main()
