"""Backboard.io Memory Synchronization Module for HeirLoom.

Ensures all entities in MongoDB Atlas (members, stories, cookbook recipes,
keepsakes, feed posts, and sparks) are seamlessly synchronized into Backboard.io
as semantic memories for Loomie.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Optional
import httpx

logger = logging.getLogger("heirloom.backboard_sync")

DEFAULT_ASSISTANT_ID = "3de074d9-d6b6-4139-9d31-e12d9a5bebf2"
DEFAULT_BASE_URL = "https://app.backboard.io/api"


def load_env_vars() -> dict[str, str]:
    """Finds and loads configuration variables from all candidate .env locations."""
    values: dict[str, str] = {}
    current = Path(__file__).resolve().parent
    repo_root = current.parent
    candidates = [
        repo_root / ".env",
        repo_root / "middleware" / ".env",
        repo_root / "heirloom-api" / ".env",
        current / ".env",
    ]
    for candidate in candidates:
        if candidate.is_file():
            try:
                for line in candidate.read_text(encoding="utf-8", errors="ignore").splitlines():
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        values[k.strip()] = v.strip().strip("\"'")
            except Exception:
                pass

    for key in ("BACKBOARD_API_KEY", "BACKBOARD_ASSISTANT_ID", "BACKBOARD_BASE_URL", "MONGODB_URI", "DB_NAME", "MONGODB_DATABASE"):
        env_val = os.environ.get(key)
        if env_val:
            values[key] = env_val
        elif key in values:
            os.environ[key] = values[key]
    return values


CONFIG = load_env_vars()


def get_api_key() -> str:
    return os.environ.get("BACKBOARD_API_KEY") or CONFIG.get("BACKBOARD_API_KEY", "")


def get_assistant_id() -> str:
    return os.environ.get("BACKBOARD_ASSISTANT_ID") or CONFIG.get("BACKBOARD_ASSISTANT_ID", DEFAULT_ASSISTANT_ID)


def get_base_url() -> str:
    return os.environ.get("BACKBOARD_BASE_URL") or CONFIG.get("BACKBOARD_BASE_URL", DEFAULT_BASE_URL)


def get_headers() -> dict[str, str]:
    return {
        "X-API-Key": get_api_key(),
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


# =====================================================================
# SEMANTIC MEMORY FORMATTERS
# =====================================================================

def format_member_memory(member: dict) -> str:
    name = member.get("name") or "Unknown Family Member"
    tier = member.get("generation_tier", 1)
    birth_year = member.get("birth_year")
    bio = member.get("bio") or ""
    passions = member.get("passions") or member.get("interests") or []
    passions_str = ", ".join(passions) if passions else ""

    tier_label = {
        1: "Elder / Grandparent generation",
        2: "Parent / Adult generation",
        3: "Youth / Grandchild generation"
    }.get(tier, f"Generation tier {tier}")
    born_str = f", born {birth_year}" if birth_year else ""

    parts = [f"Family Member Profile: {name} ({tier_label}{born_str})."]
    if bio:
        parts.append(f"Bio: {bio}")
    if passions_str:
        parts.append(f"Passions & Interests: {passions_str}.")

    # Kinship relationships
    parents = member.get("parents") or []
    children = member.get("children") or []
    spouse_id = member.get("spouse_id")
    kinship = []
    if spouse_id:
        kinship.append("Spouse recorded")
    if parents:
        kinship.append(f"{len(parents)} parent(s) connected")
    if children:
        kinship.append(f"{len(children)} child(ren) connected")
    if kinship:
        parts.append(f"Kinship: {'; '.join(kinship)}.")

    return " ".join(parts)


def format_item_memory(item: dict) -> str:
    title = item.get("title") or "Untitled Archive Item"
    author = item.get("author") or item.get("author_name") or "Family Archives"
    year = item.get("year")
    tags = item.get("tags") or []
    desc = item.get("description") or item.get("content") or ""
    ingredients = item.get("ingredients") or []
    instructions = item.get("instructions") or item.get("steps") or ""
    notes = item.get("notes") or item.get("origin_story") or ""

    lower_tags = [str(t).lower() for t in tags]
    is_recipe = (
        "recipe" in lower_tags
        or "food" in lower_tags
        or "cooking" in lower_tags
        or "recipe" in title.lower()
        or "cookbook" in title.lower()
        or bool(ingredients)
    )

    year_str = f" ({year})" if year else ""
    if is_recipe:
        prefix = f"Family Cookbook Recipe: '{title}' by {author}{year_str}."
    else:
        prefix = f"Family Archive Keepsake: '{title}' by {author}{year_str}."

    parts = [prefix]
    if tags:
        parts.append(f"Tags: {', '.join(tags)}.")
    if desc:
        parts.append(f"Description: {desc}")
    if ingredients:
        if isinstance(ingredients, list):
            parts.append(f"Ingredients: {', '.join(str(i) for i in ingredients)}.")
        else:
            parts.append(f"Ingredients: {ingredients}")
    if instructions:
        if isinstance(instructions, list):
            parts.append(f"Instructions: {' '.join(str(s) for s in instructions)}")
        else:
            parts.append(f"Instructions: {instructions}")
    if notes:
        parts.append(f"Heritage Note: {notes}")

    return " ".join(parts)


def format_story_memory(story: dict) -> str:
    title = story.get("title") or "Untitled Family Story"
    era = story.get("extracted_era")
    location = story.get("location")
    summary = story.get("narrative_summary") or story.get("raw_transcript") or ""
    passions = story.get("passions") or []
    people = story.get("people_mentioned") or []

    meta_parts = []
    if era:
        meta_parts.append(f"Era: {era}")
    if location:
        meta_parts.append(f"Location: {location}")
    era_loc = f" ({', '.join(meta_parts)})" if meta_parts else ""

    parts = [f"Biographical memory. {title}{era_loc}."]
    if summary:
        parts.append(summary)
    if people:
        names = []
        for p in people:
            if isinstance(p, dict):
                names.append(p.get("name", ""))
            elif isinstance(p, str):
                names.append(p)
        clean_names = [n for n in names if n]
        if clean_names:
            parts.append(f"People: {', '.join(clean_names)}.")
    if passions:
        parts.append(f"Passions and hobbies: {', '.join(passions)}.")

    return " ".join(parts)


def format_post_memory(post: dict) -> str:
    author = post.get("author_name") or "Family Member"
    content = post.get("content") or ""
    location = post.get("location")
    passions = post.get("passions") or []
    source = post.get("source") or "Family Feed"

    loc_str = f" in {location}" if location else ""
    parts = [f"Recent family post by {author}{loc_str} (via {source}): \"{content}\"."]
    if passions:
        parts.append(f"Passions: {', '.join(passions)}.")
    return " ".join(parts)


def format_spark_memory(spark: dict) -> str:
    passion = spark.get("matched_passion") or "Shared Interest"
    message = spark.get("spark_message") or ""
    cta = spark.get("cta_action") or ""
    parts = [f"Intergenerational Connection Spark on '{passion}': {message}"]
    if cta:
        parts.append(f"Conversation starter: {cta}")
    return " ".join(parts)


# =====================================================================
# COMMITTING MEMORIES TO BACKBOARD
# =====================================================================

async def commit_memory_async(
    fact_text: str,
    kind: str,
    entity_id: str,
    family_id: str = "fam_clarke_001",
) -> Optional[dict]:
    """Posts a semantic fact memory to the Backboard assistant asynchronously."""
    api_key = get_api_key()
    if not api_key:
        logger.warning("[BackboardSync] BACKBOARD_API_KEY is not set. Skipping sync.")
        return None

    assistant_id = get_assistant_id()
    url = f"{get_base_url()}/assistants/{assistant_id}/memories"
    payload = {
        "content": fact_text.strip(),
        "metadata": {
            "source": "mongodb_sync",
            "kind": kind,
            "entity_id": str(entity_id),
            "family_id": family_id,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload, headers=get_headers())
            if 200 <= response.status_code < 300:
                logger.info(f"[BackboardSync] Synced {kind} '{entity_id}' to Backboard.")
                return response.json()
            else:
                logger.error(
                    f"[BackboardSync] HTTP {response.status_code} committing {kind} '{entity_id}': {response.text}"
                )
                return None
    except Exception as exc:
        logger.error(f"[BackboardSync] Failed to commit {kind} '{entity_id}' to Backboard: {exc}")
        return None


def commit_memory_sync(
    fact_text: str,
    kind: str,
    entity_id: str,
    family_id: str = "fam_clarke_001",
) -> Optional[dict]:
    """Posts a semantic fact memory to Backboard synchronously (for scripts or background threads)."""
    api_key = get_api_key()
    if not api_key:
        logger.warning("[BackboardSync] BACKBOARD_API_KEY is not set. Skipping sync.")
        return None

    assistant_id = get_assistant_id()
    url = f"{get_base_url()}/assistants/{assistant_id}/memories"
    payload = {
        "content": fact_text.strip(),
        "metadata": {
            "source": "mongodb_sync",
            "kind": kind,
            "entity_id": str(entity_id),
            "family_id": family_id,
        },
    }

    try:
        with httpx.Client(timeout=10.0) as client:
            response = client.post(url, json=payload, headers=get_headers())
            if 200 <= response.status_code < 300:
                logger.info(f"[BackboardSync] Synced {kind} '{entity_id}' to Backboard.")
                return response.json()
            else:
                logger.error(
                    f"[BackboardSync] HTTP {response.status_code} committing {kind} '{entity_id}': {response.text}"
                )
                return None
    except Exception as exc:
        logger.error(f"[BackboardSync] Failed to commit {kind} '{entity_id}' to Backboard: {exc}")
        return None


# =====================================================================
# INDIVIDUAL ENTITY SYNC HANDLERS (Used in FastAPI background tasks)
# =====================================================================

async def sync_member_to_backboard(member_doc: dict):
    if not member_doc:
        return
    fact = format_member_memory(member_doc)
    entity_id = str(member_doc.get("_id") or member_doc.get("id"))
    family_id = member_doc.get("family_id", "fam_clarke_001")
    await commit_memory_async(fact, "member_profile", entity_id, family_id)


async def sync_item_to_backboard(item_doc: dict):
    if not item_doc:
        return
    fact = format_item_memory(item_doc)
    entity_id = str(item_doc.get("_id") or item_doc.get("id"))
    family_id = item_doc.get("family_id", "fam_clarke_001")
    is_recipe = "recipe" in fact.lower()
    kind = "cookbook_recipe" if is_recipe else "archive_item"
    await commit_memory_async(fact, kind, entity_id, family_id)


async def sync_story_to_backboard(story_doc: dict):
    if not story_doc:
        return
    fact = format_story_memory(story_doc)
    entity_id = str(story_doc.get("_id") or story_doc.get("id"))
    family_id = story_doc.get("family_id", "fam_clarke_001")
    await commit_memory_async(fact, "story", entity_id, family_id)


async def sync_post_to_backboard(post_doc: dict):
    if not post_doc:
        return
    fact = format_post_memory(post_doc)
    entity_id = str(post_doc.get("_id") or post_doc.get("id"))
    family_id = post_doc.get("family_id", "fam_clarke_001")
    await commit_memory_async(fact, "feed_post", entity_id, family_id)


async def sync_spark_to_backboard(spark_doc: dict):
    if not spark_doc:
        return
    fact = format_spark_memory(spark_doc)
    entity_id = str(spark_doc.get("_id") or spark_doc.get("id"))
    family_id = spark_doc.get("family_id", "fam_clarke_001")
    await commit_memory_async(fact, "spark", entity_id, family_id)


# =====================================================================
# BATCH CATCH-UP / BULK SYNC FROM MONGODB
# =====================================================================

def fetch_existing_backboard_memories() -> list[dict]:
    """Retrieves all current memories in the assistant to check existing items."""
    api_key = get_api_key()
    if not api_key:
        return []
    assistant_id = get_assistant_id()
    url = f"{get_base_url()}/assistants/{assistant_id}/memories"
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.get(url, headers=get_headers())
            if 200 <= resp.status_code < 300:
                data = resp.json()
                if isinstance(data, dict):
                    return data.get("memories") or data.get("data") or []
                elif isinstance(data, list):
                    return data
    except Exception as exc:
        logger.warning(f"[BackboardSync] Failed to fetch existing memories: {exc}")
    return []


def sync_all_from_mongodb_sync(db, skip_existing_titles: bool = True) -> dict[str, int]:
    """Iterates through all MongoDB collections and pushes them to Backboard.

    Can be called synchronously by CLI migration scripts or in thread pools.
    """
    existing_memories = fetch_existing_backboard_memories()
    existing_texts = {
        m.get("content", "").strip().lower()
        for m in existing_memories
        if isinstance(m, dict) and m.get("content")
    }

    stats = {
        "members": 0,
        "items": 0,
        "recipes": 0,
        "stories": 0,
        "posts": 0,
        "sparks": 0,
        "skipped": 0,
    }

    # 1. Members
    if "members" in db.list_collection_names():
        for member in db["members"].find():
            fact = format_member_memory(member)
            if skip_existing_titles and any(member.get("name", "").lower() in t for t in existing_texts if member.get("name")):
                stats["skipped"] += 1
                continue
            res = commit_memory_sync(
                fact,
                "member_profile",
                str(member["_id"]),
                member.get("family_id", "fam_clarke_001")
            )
            if res:
                stats["members"] += 1

    # 2. Items (Recipes, Keepsakes, Documents)
    items_col_name = os.getenv("COLLECTION_NAME", "items")
    if items_col_name in db.list_collection_names():
        for item in db[items_col_name].find():
            fact = format_item_memory(item)
            title = (item.get("title") or "").strip().lower()
            if skip_existing_titles and title and any(title in t for t in existing_texts):
                stats["skipped"] += 1
                continue
            is_recipe = "recipe" in fact.lower()
            kind = "cookbook_recipe" if is_recipe else "archive_item"
            res = commit_memory_sync(
                fact,
                kind,
                str(item["_id"]),
                item.get("family_id", "fam_clarke_001")
            )
            if res:
                if is_recipe:
                    stats["recipes"] += 1
                else:
                    stats["items"] += 1

    # 3. Stories
    if "stories" in db.list_collection_names():
        for story in db["stories"].find():
            fact = format_story_memory(story)
            title = (story.get("title") or "").strip().lower()
            if skip_existing_titles and title and any(title in t for t in existing_texts):
                stats["skipped"] += 1
                continue
            res = commit_memory_sync(
                fact,
                "story",
                str(story["_id"]),
                story.get("family_id", "fam_clarke_001")
            )
            if res:
                stats["stories"] += 1

    # 4. Posts
    if "posts" in db.list_collection_names():
        for post in db["posts"].find():
            fact = format_post_memory(post)
            content_snippet = (post.get("content") or "")[:30].strip().lower()
            if skip_existing_titles and content_snippet and any(content_snippet in t for t in existing_texts):
                stats["skipped"] += 1
                continue
            res = commit_memory_sync(
                fact,
                "feed_post",
                str(post["_id"]),
                post.get("family_id", "fam_clarke_001")
            )
            if res:
                stats["posts"] += 1

    # 5. Sparks
    if "sparks" in db.list_collection_names():
        for spark in db["sparks"].find():
            fact = format_spark_memory(spark)
            passion = (spark.get("matched_passion") or "").strip().lower()
            if skip_existing_titles and passion and any(passion in t for t in existing_texts):
                stats["skipped"] += 1
                continue
            res = commit_memory_sync(
                fact,
                "spark",
                str(spark["_id"]),
                spark.get("family_id", "fam_clarke_001")
            )
            if res:
                stats["sparks"] += 1

    return stats
