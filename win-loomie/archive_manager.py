"""HeirLoom Archive Manager Agent powered by the official Grok SDK (xai-sdk).

This lightweight agent manages the oral history archives and family knowledge base:
1. Analyzes conversational story transcripts using Grok LLM structured parsing.
2. Identifies the teller/author. If the teller is NOT in MongoDB Atlas, automatically creates
   a rich new member profile (inferring generation tier, birth year estimate, bio, and passions).
3. Persists structured stories into MongoDB Atlas (stories collection).
4. Enriches author profiles with newly captured passions.
5. Intelligently discovers authentic cross-generational connection "Sparks" between the new
   story and other family members across generations (sparks collection).
6. Explores and searches connections across the entire family archive.
"""

from __future__ import annotations

import datetime
import os
import re
import uuid
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field
import pymongo

# Ensure environment variables are loaded
FILE_DIR = Path(__file__).resolve().parent
REPO_DIR = FILE_DIR if (FILE_DIR / "middleware").exists() else FILE_DIR.parent


def load_env_vars() -> dict[str, str]:
    values: dict[str, str] = {}
    candidates = [
        REPO_DIR / ".env",
        REPO_DIR / "middleware" / ".env",
        REPO_DIR / "heirloom-api" / ".env",
        FILE_DIR / ".env",
        FILE_DIR.parent / "middleware" / ".env",
    ]
    for candidate in candidates:
        if candidate.is_file():
            for line in candidate.read_text(encoding="utf-8", errors="ignore").splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    values[k.strip()] = v.strip().strip("\"'")
    for key in ("XAI_API_KEY", "BACKBOARD_API_KEY", "MONGODB_URI", "MONGODB_DATABASE", "DB_NAME"):
        env_val = os.environ.get(key)
        if env_val:
            values[key] = env_val
        elif key in values:
            os.environ[key] = values[key]
    return values


ENV_VARS = load_env_vars()

# Import xai-sdk
try:
    import xai_sdk
    from xai_sdk.chat import system, user
    HAS_XAI_SDK = True
except ImportError:
    HAS_XAI_SDK = False

try:
    import certifi
    CA_FILE = certifi.where()
except ImportError:
    CA_FILE = None


# --- Pydantic Structured Schemas for Grok SDK ---

class InferredPerson(BaseModel):
    name: str = Field(description="Name of the person mentioned in the story")
    relation_to_teller: Optional[str] = Field(None, description="Relation to the teller (e.g. brother, daughter, friend)")
    passions_or_hobbies: List[str] = Field(default_factory=list, description="Passions, hobbies, or skills mentioned for this person")
    estimated_generation_tier: int = Field(1, description="1 for elders/grandparents, 2 for parents/aunts/uncles, 3 for youth/grandchildren")
    bio_summary: Optional[str] = Field(None, description="Brief bio or role context")


class StoryAnalysis(BaseModel):
    teller_name: Optional[str] = Field(
        None,
        description="The name or honorific of the person telling the story (e.g., 'Joseph Clarke', 'Aunt Beatrice', 'Grandpa Joe'). If not stated, null."
    )
    teller_generation_tier: int = Field(
        1,
        description="Estimated generation tier of teller: 1 for elder/grandparent (born ~1930-1955), 2 for parent/adult (born ~1965-1985), 3 for teen/young adult (born ~2000+)"
    )
    teller_bio_summary: Optional[str] = Field(
        None,
        description="A concise 1-2 sentence biographical summary of the teller based on their story."
    )
    teller_estimated_birth_year: Optional[int] = Field(
        None,
        description="Estimated 4-digit birth year of the teller based on the era of their story (e.g., in 1968 they were ~20 -> born ~1948)."
    )
    title: str = Field(
        description="Evocative, poetic 3-6 word title for this family memory."
    )
    narrative_summary: str = Field(
        description="Heartfelt, polished 2-3 sentence summary of the oral history memory."
    )
    extracted_era: Optional[str] = Field(
        None,
        description="Era or approximate year(s) of the story (e.g., '1974', 'Late 1960s', 'WWII era')."
    )
    location: Optional[str] = Field(
        None,
        description="Geographic location or setting (e.g., 'Detroit, Michigan', 'Ann Arbor', 'Chicago print shop')."
    )
    passions_or_hobbies: List[str] = Field(
        default_factory=list,
        description="Specific passions, hobbies, technical crafts, or arts exhibited in the story (e.g., 'analog synthesizers', 'guitar pedals', 'watercolor painting')."
    )
    people_mentioned: List[InferredPerson] = Field(
        default_factory=list,
        description="List of other people mentioned in the story and their relationship to the teller."
    )
    emotional_tone: Optional[str] = Field(
        None,
        description="Emotional tone of the memory (e.g., 'nostalgic and triumphant', 'warm and reflective', 'humorous')."
    )
    grok_imagine_prompt: str = Field(
        description="Prompt engineered for Grok image generation: vintage Polaroid or 35mm film aesthetic, warm cinematic lighting, authentic historical details."
    )


class GeneratedSpark(BaseModel):
    target_member_id: str = Field(description="The _id of the matching family member from the database")
    target_member_name: str = Field(description="The full name of the matching family member")
    matched_passion: str = Field(description="The specific passion or shared interest that links them")
    spark_message: str = Field(description="A warm, emotionally resonant 1-2 sentence message connecting the story to the target member.")
    cta_action: str = Field(description="A gentle, actionable prompt encouraging them to reach out (e.g. 'Ask Grandpa Joe about the 1974 garage pedals')")
    generation_bridge_rationale: str = Field(description="Why this connection is meaningful across generations.")
    relevance_score: float = Field(default=0.9, ge=0.0, le=1.0, description="Relevance confidence score")


class SparkBatch(BaseModel):
    sparks: List[GeneratedSpark] = Field(
        default_factory=list,
        description="List of meaningful intergenerational sparks generated from the story."
    )


class ConnectionInsight(BaseModel):
    headline: str = Field(description="Catchy, meaningful title for this connection")
    deep_connection: str = Field(description="In-depth analysis of how stories and family members interlock around this theme")
    connected_members: List[str] = Field(description="Names of family members who share this connection")
    relevant_story_ids: List[str] = Field(default_factory=list, description="IDs or titles of stories involved")
    suggested_conversation_prompts: List[str] = Field(description="2-3 specific questions for the family corkboard or dinner table")


class ArchiveResult(BaseModel):
    ok: bool = True
    story_id: str
    title: str
    narrative_summary: str
    author_id: str
    author_name: str
    is_new_member_created: bool
    created_member_details: Optional[Dict[str, Any]] = None
    passions_added: List[str] = Field(default_factory=list)
    sparks_generated: List[Dict[str, Any]] = Field(default_factory=list)
    grok_imagine_prompt: str
    extracted_era: Optional[str] = None
    location: Optional[str] = None


# --- Helper Functions ---

def slugify(text: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower())
    return cleaned.strip("_") or "unknown"


def sanitize_mongo_uri(raw_uri: str) -> str:
    if not raw_uri:
        return ""
    uri = raw_uri.strip().strip("\"'").replace("[", "").replace("]", "")
    if "mailto:" in uri:
        uri = uri.replace("mailto:", "")
    if "://" in uri and "@" in uri:
        prefix, rest = uri.split("://", 1)
        if "@" in rest:
            userinfo, hostinfo = rest.rsplit("@", 1)
            if ":" in userinfo:
                username, password = userinfo.split(":", 1)
                encoded_password = urllib.parse.quote_plus(urllib.parse.unquote_plus(password))
                return f"{prefix}://{username}:{encoded_password}@{hostinfo}"
    return uri


AVATAR_POOL = {
    1: [
        "https://images.unsplash.com/photo-1544005313-94ddf0286df2",
        "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d",
    ],
    2: [
        "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d",
        "https://images.unsplash.com/photo-1534528741775-53994a69daeb",
    ],
    3: [
        "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6",
        "https://images.unsplash.com/photo-1494790108377-be9c29b29330",
    ],
}


# --- Core Archive Manager Agent ---

class ArchiveManagerAgent:
    """Intelligent Oral History Archive Manager powered by xAI Grok SDK."""

    def __init__(
        self,
        db: Optional[pymongo.database.Database] = None,
        xai_api_key: Optional[str] = None,
        model: str = "grok-3",
    ):
        self.api_key = xai_api_key or ENV_VARS.get("XAI_API_KEY") or os.environ.get("XAI_API_KEY")
        self.model = model
        self.db = db if db is not None else self._connect_db()

        if not self.api_key:
            print("[ArchiveManager] Warning: XAI_API_KEY not found in environment.")
        if HAS_XAI_SDK and self.api_key:
            self.client = xai_sdk.Client(api_key=self.api_key)
        else:
            self.client = None

    def _connect_db(self) -> Optional[pymongo.database.Database]:
        raw_uri = ENV_VARS.get("MONGODB_URI") or os.environ.get("MONGODB_URI") or ""
        if not raw_uri:
            return None
        try:
            uri = sanitize_mongo_uri(raw_uri)
            client_kwargs = {"serverSelectionTimeoutMS": 5000}
            if CA_FILE:
                client_kwargs["tlsCAFile"] = CA_FILE
            client = pymongo.MongoClient(uri, **client_kwargs)
            db_name = (
                ENV_VARS.get("MONGODB_DATABASE")
                or ENV_VARS.get("DB_NAME")
                or os.environ.get("MONGODB_DATABASE")
                or "heirloom_db"
            )
            return client[db_name]
        except Exception as e:
            print(f"[ArchiveManager] MongoDB connection error: {e}")
            return None

    # --- 1. Story Archival & Dynamic Person Resolution ---

    def process_story(
        self,
        transcript: str,
        teller_hint: Optional[str] = None,
        family_id: str = "fam_clarke_001",
    ) -> ArchiveResult:
        """Processes an oral history transcript, extracts metadata, creates missing persons in Atlas,
        saves the story document, updates passions, and generates intergenerational sparks.
        """
        if not self.client:
            raise RuntimeError("Grok SDK client is not initialized. Check XAI_API_KEY.")
        if self.db is None:
            raise RuntimeError("MongoDB connection not available.")

        # Step 1: Analyze story transcript using Grok structured parsing
        analysis = self._analyze_transcript_with_grok(transcript, teller_hint)

        # Step 2: Resolve or Create Member in MongoDB Atlas
        author_id, author_name, is_new_member, created_member_details = self._resolve_or_create_author(
            analysis, teller_hint, family_id
        )

        # Step 3: Insert Story Document into Atlas
        story_id = f"story_{uuid.uuid4().hex[:12]}"
        now = datetime.datetime.now(datetime.timezone.utc)
        story_doc = {
            "_id": story_id,
            "family_id": family_id,
            "author_id": author_id,
            "author_name": author_name,
            "title": analysis.title,
            "narrative_summary": analysis.narrative_summary,
            "extracted_era": analysis.extracted_era,
            "location": analysis.location,
            "passions": analysis.passions_or_hobbies,
            "people_mentioned": [p.name for p in analysis.people_mentioned],
            "emotional_tone": analysis.emotional_tone,
            "grok_imagine_prompt": analysis.grok_imagine_prompt,
            "raw_transcript": transcript,
            "created_at": now,
        }
        self.db.stories.insert_one(story_doc)
        print(f"[ArchiveManager] Saved story '{analysis.title}' (ID: {story_id}) for author '{author_name}' ({author_id})")

        # Step 4: Update Author Passions in MongoDB Atlas
        passions = analysis.passions_or_hobbies
        if passions:
            self.db.members.update_one(
                {"_id": author_id},
                {
                    "$addToSet": {"passions": {"$each": passions}},
                    "$set": {"updated_at": now},
                },
            )

        # Step 5: AI-Driven Intergenerational Spark Discovery
        sparks_created = self._discover_and_save_sparks(
            story_doc=story_doc,
            author_id=author_id,
            author_name=author_name,
            family_id=family_id,
        )

        return ArchiveResult(
            ok=True,
            story_id=story_id,
            title=analysis.title,
            narrative_summary=analysis.narrative_summary,
            author_id=author_id,
            author_name=author_name,
            is_new_member_created=is_new_member,
            created_member_details=created_member_details,
            passions_added=passions,
            sparks_generated=sparks_created,
            grok_imagine_prompt=analysis.grok_imagine_prompt,
            extracted_era=analysis.extracted_era,
            location=analysis.location,
        )

    def _analyze_transcript_with_grok(
        self, transcript: str, teller_hint: Optional[str]
    ) -> StoryAnalysis:
        """Calls Grok SDK chat.parse to extract structured story analysis from transcript."""
        chat = self.client.chat.create(model=self.model)
        chat.append(
            system(
                "You are the HeirLoom Oral History Archival Agent. "
                "Analyze family oral history conversations, identifying the storyteller, "
                "extracting passions, era, location, and crafting poignant summaries and Grok image prompts."
            )
        )
        hint_text = f"\n\nContext Hint: The user indicated the teller might be '{teller_hint}'." if teller_hint else ""
        prompt = f"Oral History Conversation Transcript:\n{transcript}{hint_text}\n\nExtract the structured story archive data:"
        chat.append(user(prompt))

        response, parsed = chat.parse(StoryAnalysis)
        return parsed

    def _resolve_or_create_author(
        self,
        analysis: StoryAnalysis,
        teller_hint: Optional[str],
        family_id: str,
    ) -> tuple[str, str, bool, Optional[dict]]:
        """Finds matching member in Atlas or dynamically creates a new member profile."""
        now = datetime.datetime.now(datetime.timezone.utc)
        all_members = list(self.db.members.find({"family_id": family_id}))

        candidate_name = teller_hint or analysis.teller_name
        matched_member = None

        if candidate_name:
            cand_lower = candidate_name.lower().strip()
            # 1. Exact or substring match in name or _id
            for m in all_members:
                m_name = m.get("name", "").lower()
                m_id = m.get("_id", "").lower()
                if cand_lower == m_name or cand_lower == m_id or cand_lower in m_name or m_name in cand_lower:
                    matched_member = m
                    break
            # 2. Check common nicknames (e.g. Grandpa Joe -> Joseph Clarke)
            if not matched_member:
                if any(w in cand_lower for w in ["joe", "joseph", "grandpa"]):
                    matched_member = next((m for m in all_members if "joseph" in m.get("name", "").lower() or "joe" in m.get("_id", "")), None)
                elif any(w in cand_lower for w in ["eleanor", "grandma"]):
                    matched_member = next((m for m in all_members if "eleanor" in m.get("name", "").lower()), None)
                elif "alex" in cand_lower:
                    matched_member = next((m for m in all_members if "alex" in m.get("name", "").lower()), None)
                elif "marcus" in cand_lower:
                    matched_member = next((m for m in all_members if "marcus" in m.get("name", "").lower()), None)
                elif "sarah" in cand_lower:
                    matched_member = next((m for m in all_members if "sarah" in m.get("name", "").lower()), None)

        # If existing member found, return their ID
        if matched_member:
            return matched_member["_id"], matched_member.get("name", candidate_name or "Family Member"), False, None

        # If NOT found and candidate name exists, create a new person!
        if candidate_name and candidate_name.lower() not in ["elder", "you", "user"]:
            new_id = f"member_{slugify(candidate_name)}"
            # Deduplicate ID if already exists
            suffix = 1
            base_id = new_id
            while self.db.members.find_one({"_id": new_id}):
                new_id = f"{base_id}_{suffix}"
                suffix += 1

            tier = analysis.teller_generation_tier or 1
            avatars = AVATAR_POOL.get(tier, AVATAR_POOL[1])
            avatar_url = avatars[len(candidate_name) % len(avatars)]

            birth_year = analysis.teller_estimated_birth_year
            if not birth_year:
                birth_year = 1945 if tier == 1 else 1975 if tier == 2 else 2004

            bio = analysis.teller_bio_summary or f"Family member and storyteller. Shared oral history from {analysis.extracted_era or 'the past'}."

            new_member_doc = {
                "_id": new_id,
                "family_id": family_id,
                "name": candidate_name,
                "generation_tier": tier,
                "bio": bio,
                "birth_year": birth_year,
                "passions": analysis.passions_or_hobbies,
                "parents": [],
                "children": [],
                "spouse_id": None,
                "avatar_url": avatar_url,
                "created_at": now,
                "updated_at": now,
            }
            self.db.members.insert_one(new_member_doc)
            print(f"[ArchiveManager] Created NEW family member in MongoDB Atlas: {new_id} ({candidate_name}, Gen {tier})")
            return new_id, candidate_name, True, new_member_doc

        # Default fallback to Grandpa Joe if completely unspecified
        default_author = self.db.members.find_one({"_id": "member_grandpa_joe"})
        if default_author:
            return default_author["_id"], default_author["name"], False, None

        return "member_grandpa_joe", "Joseph Clarke", False, None

    # --- 2. AI Spark Discovery Using Grok Reasoning ---

    def _discover_and_save_sparks(
        self,
        story_doc: dict,
        author_id: str,
        author_name: str,
        family_id: str,
    ) -> List[Dict[str, Any]]:
        """Uses Grok to discover authentic cross-generational sparks with other family members."""
        other_members = list(self.db.members.find({"family_id": family_id, "_id": {"$ne": author_id}}))
        if not other_members:
            return []

        members_context = []
        for m in other_members:
            members_context.append(
                f"- ID: {m['_id']} | Name: {m['name']} | Gen Tier: {m.get('generation_tier', 1)} | "
                f"Bio: {m.get('bio', '')} | Passions: {', '.join(m.get('passions', []))}"
            )
        members_text = "\n".join(members_context)

        prompt = f"""
Newly Archived Story:
Title: {story_doc['title']}
Author: {author_name} ({author_id})
Summary: {story_doc['narrative_summary']}
Era: {story_doc.get('extracted_era') or 'Unknown'}
Passions in story: {', '.join(story_doc.get('passions', []))}

Other Family Members in Archive:
{members_text}

Task:
Identify 1 to 3 authentic, emotionally rich intergenerational connections (Sparks) between this story and other family members.
Highlight how the teller's past experiences connect to younger or distant members' passions or life stages.
Make each spark message heartwarming, conversational, and direct, paired with an engaging Call to Action (CTA).
"""

        try:
            chat = self.client.chat.create(model=self.model)
            chat.append(
                system(
                    "You are the HeirLoom Spark Discovery Agent. You bridge generations by connecting "
                    "elders' historical stories to the passions, curiosities, and crafts of modern family members."
                )
            )
            chat.append(user(prompt))

            response, parsed = chat.parse(SparkBatch)
            created_sparks = []
            now = datetime.datetime.now(datetime.timezone.utc)

            for s in parsed.sparks:
                clean_passion = slugify(s.matched_passion)[:16]
                spark_id = f"spark_{clean_passion}_{story_doc['_id'][:10]}"
                spark_doc = {
                    "_id": spark_id,
                    "family_id": family_id,
                    "story_id": story_doc["_id"],
                    "elder_id": author_id,
                    "elder_name": author_name,
                    "target_member_id": s.target_member_id,
                    "target_member_name": s.target_member_name,
                    "matched_passion": s.matched_passion,
                    "spark_message": s.spark_message,
                    "cta_action": s.cta_action,
                    "generation_bridge_rationale": s.generation_bridge_rationale,
                    "relevance_score": s.relevance_score,
                    "is_read": False,
                    "status": "active",
                    "created_at": now,
                }
                self.db.sparks.update_one({"_id": spark_id}, {"$set": spark_doc}, upsert=True)
                created_sparks.append(spark_doc)
                print(f"[ArchiveManager] Created Grok Spark: {spark_id} ({author_name} -> {s.target_member_name} for '{s.matched_passion}')")

            return created_sparks
        except Exception as e:
            print(f"[ArchiveManager] Spark discovery failed: {e}")
            return []

    # --- 3. Cross-Archive Connection Search ---

    def search_connections(
        self,
        query: str,
        family_id: str = "fam_clarke_001",
    ) -> ConnectionInsight:
        """Finds thematic, emotional, and cross-generational connections across the entire family archive."""
        if not self.client:
            raise RuntimeError("Grok SDK client is not initialized.")
        if self.db is None:
            raise RuntimeError("MongoDB connection not available.")

        members = list(self.db.members.find({"family_id": family_id}))
        stories = list(self.db.stories.find({"family_id": family_id}))

        members_summary = "\n".join(
            [f"- {m['name']} (Gen {m.get('generation_tier', 1)}): {', '.join(m.get('passions', []))} — {m.get('bio', '')}" for m in members]
        )
        stories_summary = "\n".join(
            [f"- [{s.get('_id')}] '{s['title']}' by {s.get('author_name', s.get('author_id'))} ({s.get('extracted_era', '')}): {s['narrative_summary']}" for s in stories]
        )

        prompt = f"""
Search Query: "{query}"

Family Members:
{members_summary}

Family Stories:
{stories_summary}

Task:
Synthesize the connection across family members and stories addressing this query.
Highlight cross-generational synergies, common threads, and provide conversation prompts for the family.
"""

        chat = self.client.chat.create(model=self.model)
        chat.append(
            system(
                "You are the HeirLoom Family Knowledge Graph Agent. You uncover hidden connections, "
                "shared family genetics of passion, and conversational sparks between generations."
            )
        )
        chat.append(user(prompt))

        response, parsed = chat.parse(ConnectionInsight)
        return parsed

    # --- 4. Archive Health & Digest ---

    def get_archive_digest(self, family_id: str = "fam_clarke_001") -> Dict[str, Any]:
        """Returns statistics and overview of the family archive in MongoDB Atlas."""
        if self.db is None:
            return {"error": "Database not connected"}

        total_members = self.db.members.count_documents({"family_id": family_id})
        total_stories = self.db.stories.count_documents({"family_id": family_id})
        total_sparks = self.db.sparks.count_documents({"family_id": family_id})

        members = list(self.db.members.find({"family_id": family_id}, {"name": 1, "generation_tier": 1, "passions": 1}))
        all_passions = set()
        for m in members:
            for p in m.get("passions", []):
                all_passions.add(p)

        return {
            "family_id": family_id,
            "total_members": total_members,
            "total_stories": total_stories,
            "total_sparks": total_sparks,
            "unique_passions_count": len(all_passions),
            "members": members,
        }
