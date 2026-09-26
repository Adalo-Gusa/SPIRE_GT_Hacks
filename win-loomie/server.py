"""Local Windows preview of Loomie.

Serves the browser client and holds the API keys. The page never sees them.
Reads XAI_API_KEY and BACKBOARD_API_KEY from the environment, then from
middleware/.env.

Run: py -3 server.py
"""

from __future__ import annotations

import datetime
import json
import os
import re
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
HOST = "127.0.0.1"
PORT = 8765

BACKBOARD_BASE = "https://app.backboard.io/api"
GROK_BASE = "https://api.x.ai/v1"
ASSISTANT_ID = "3de074d9-d6b6-4139-9d31-e12d9a5bebf2"
GROK_MODEL = "grok-4.3"

LOOMIE_SYSTEM_PROMPT = """You are Loomie, a warm family oral historian in a back-and-forth conversation.

Greetings and small talk: greet them like a person. Do not start an interview yet. Invite them to share a memory whenever they are ready.

Stories and facts: remember people, places, years, jobs, and feelings from this conversation. Acknowledge a specific detail. You may ask one gentle follow-up.

Recall: if they ask what they told you, who they mentioned, or where something happened, answer from this conversation and the known family memories. Never say you forgot.

Keep replies to 1–3 spoken sentences. Sound like a conversation, not a questionnaire.
"""

SMALL_TALK = {
    "hi", "hello", "hey", "yo", "howdy", "hiya", "hi there",
    "hi loomie", "hello loomie", "hey loomie", "hey there",
    "good morning", "good afternoon", "good evening",
    "how are you", "how are you doing", "how's it going", "how is it going",
    "what's up", "whats up", "sup", "how are ya",
    "thanks", "thank you", "thanks loomie", "thank you loomie",
    "ok", "okay", "k", "sure", "yes", "yeah", "yep", "no", "nope",
    "bye", "goodbye", "see you", "good night", "goodnight",
    "i'm good", "im good", "i am good", "i'm fine", "im fine",
}

FACT_NEEDLES = (
    "my ", "i was", "i am", "i'm ", "im ", "i worked", "i lived", "i grew",
    "brother", "sister", "mother", "father", "mom", "dad", "grandma", "grandpa",
    "uncle", "aunt", "cousin", "husband", "wife", "son", "daughter", "niece", "nephew",
    "in 19", "in 20", "years ago", "born", "school", "college", "university",
    "worked at", "lived in", "named", "family", "print shop", "restor", "mustang",
    "chicago", "fixing cars", "summer of", "married", "wedding", "job", "career",
    "retired", "hometown", "neighborhood", "military", "army", "navy", "air force",
)

STATIC = {
    "/": "index.html",
    "/index.html": "index.html",
    "/app.js": "app.js",
    "/audio-worklet.js": "audio-worklet.js",
    "/styles.css": "styles.css",
}

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
}

conversations: dict[str, list[dict[str, str]]] = {}


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def load_secrets() -> dict[str, str]:
    values: dict[str, str] = {}
    values.update(parse_env_file(REPO / "middleware" / ".env"))
    values.update(parse_env_file(REPO / "heirloom-api" / ".env"))
    for name in ("XAI_API_KEY", "BACKBOARD_API_KEY", "MONGODB_URI", "MONGODB_DATABASE"):
        env = os.environ.get(name)
        if env:
            values[name] = env
    return values


SECRETS = load_secrets()


def get_mongo_db():
    raw_uri = SECRETS.get("MONGODB_URI") or ""
    if not raw_uri:
        return None
    try:
        import certifi
        import pymongo
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
                    uri = f"{prefix}://{username}:{encoded_password}@{hostinfo}"
        client = pymongo.MongoClient(uri, tlsCAFile=certifi.where(), serverSelectionTimeoutMS=4000)
        db_name = SECRETS.get("MONGODB_DATABASE") or "heirloom_db"
        return client[db_name]
    except Exception as err:
        print(f"[Loomie] MongoDB connection error: {err}")
        return None


def should_store(text: str) -> bool:
    collapsed = text.lower().strip()
    stripped = collapsed.strip(" \t\r\n.,!?;:\"'()[]{}")
    if not stripped or stripped in SMALL_TALK:
        return False
    # Never store questions as biographical memories
    if "?" in text or any(collapsed.startswith(q) for q in (
        "what ", "whats ", "what's ", "where ", "where's ", "who ", "who's ",
        "when ", "why ", "how ", "do you ", "did you ", "can you ", "could you ",
        "tell me ", "remember ", "do you remember", "did i tell you"
    )):
        return False
    # Filter meta-talk and conversational filler
    if any(m in collapsed for m in (
        "text bubble", "can you hear", "can you hear me", "microphone", "sound check",
        "four hours of sleep", "you got that", "i guess", "i think so", "wait a minute", "hold on"
    )):
        return False
    return any(needle in collapsed for needle in FACT_NEEDLES)


def http_json(url: str, method: str, headers: dict[str, str], body: dict | None = None) -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
            status = response.status
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        status = error.code
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return 502, {"error": f"Network connection failed: {error}"}
    if not raw:
        return status, None
    try:
        return status, json.loads(raw)
    except json.JSONDecodeError:
        return status, raw


def grok_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {SECRETS.get('XAI_API_KEY', '')}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def backboard_headers() -> dict[str, str]:
    return {
        "X-API-Key": SECRETS.get("BACKBOARD_API_KEY", ""),
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def memory_items(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        nested = payload.get("memories") or payload.get("data") or []
        if isinstance(nested, list):
            return [item for item in nested if isinstance(item, dict)]
    return []


def memory_text(item: dict) -> str:
    for key in ("content", "memory", "text"):
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def fetch_memories(query: str) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()

    def append_items(items: list[dict]) -> None:
        for item in items:
            text = memory_text(item)
            if not text:
                continue
            key = str(item.get("id") or item.get("memory_id") or text)
            if key not in seen:
                seen.add(key)
                ordered.append(text)

    trimmed = query.strip()
    if trimmed:
        search_url = f"{BACKBOARD_BASE}/assistants/{ASSISTANT_ID}/memories/search"
        status, payload = http_json(search_url, "POST", backboard_headers(), {"query": trimmed, "limit": 10})
        if 200 <= status < 300:
            append_items(memory_items(payload))

    list_url = f"{BACKBOARD_BASE}/assistants/{ASSISTANT_ID}/memories"
    status, payload = http_json(list_url, "GET", backboard_headers())
    if 200 <= status < 300:
        append_items(memory_items(payload))

    return ordered


def add_memory(text: str, thread_id: str) -> None:
    url = f"{BACKBOARD_BASE}/assistants/{ASSISTANT_ID}/memories"
    status, payload = http_json(url, "POST", backboard_headers(), {
        "content": text,
        "metadata": {"source": "loomie", "thread_id": thread_id, "kind": "user_story"},
    })
    if not (200 <= status < 300):
        raise RuntimeError(f"HTTP {status}: {payload}")
    auto_url = f"{BACKBOARD_BASE}/threads/messages"
    http_json(auto_url, "POST", backboard_headers(), {
        "content": text,
        "assistant_id": ASSISTANT_ID,
        "memory": "Auto",
        "send_to_llm": "false",
        "stream": False,
        "metadata": {"source": "loomie", "session_thread_id": thread_id},
    })


def remember(text: str, thread_id: str) -> bool:
    utterance = text.strip()
    if not should_store(utterance):
        return False
    try:
        add_memory(utterance, thread_id)
    except Exception as error:
        print(f"[Loomie] memory persist failed: {error}")
        return False
    return True


def complete_grok(user_text: str, memories: list[str], history: list[dict[str, str]]) -> str:
    if memories:
        memory_block = "Known family memories. Use these when the speaker asks you to recall something:\n" + "\n".join(
            f"- {item}" for item in memories
        )
    else:
        memory_block = "No prior family memories are on file for this speaker yet."
    messages = [
        {"role": "system", "content": LOOMIE_SYSTEM_PROMPT},
        {"role": "system", "content": memory_block},
        *history,
        {"role": "user", "content": user_text},
    ]
    status, payload = http_json(f"{GROK_BASE}/chat/completions", "POST", grok_headers(), {
        "model": GROK_MODEL,
        "messages": messages,
        "temperature": 0.8,
        "max_tokens": 220,
        "reasoning_effort": "none",
    })
    if not (200 <= status < 300) or not isinstance(payload, dict):
        raise RuntimeError(f"HTTP {status}: {payload}")
    choices = payload.get("choices") or []
    content = ""
    if choices and isinstance(choices[0], dict):
        message = choices[0].get("message") or {}
        content = (message.get("content") or "").strip()
    if not content:
        raise RuntimeError("Grok returned an empty reply.")
    return content


def send_message(text: str, thread_id: str) -> str:
    utterance = text.strip()
    memories = fetch_memories(utterance)
    history = conversations.get(thread_id, [])
    reply = complete_grok(utterance, memories, history)
    history = [*history, {"role": "user", "content": utterance}, {"role": "assistant", "content": reply}]
    conversations[thread_id] = history[-16:]
    if should_store(utterance):
        try:
            add_memory(utterance, thread_id)
        except Exception as error:
            print(f"[Loomie] memory persist failed: {error}")
    return reply


ARCHIVIST_PROMPT = """You are a biographical archivist. Analyze the following conversation between Loomie and an elder. Extract the key historical and biographical facts. Return ONLY a valid JSON object matching this schema:
{
"title": "Short catchy title (e.g., Rebuilding the '65 Mustang)",
"narrativeSummary": "1-2 sentence core biographical summary",
"extractedEra": "Year, decade, or life stage if mentioned, or null",
"location": "City, region, or landmark if mentioned, or null",
"peopleMentioned": ["List of family/friends mentioned"],
"passionsOrHobbies": ["Specific skills, trades, sports, or hobbies identified"],
"grokImaginePrompt": "A vivid, warm 1970s Polaroid or watercolor style prompt capturing the central scene without text or modern elements"
}
"""


def extract_json_object(raw: str) -> dict:
    text = raw.strip()
    if text.startswith("```"):
        text = text.replace("```json", "").replace("```", "").strip()
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end >= start:
        text = text[start:end + 1]
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise RuntimeError("Story JSON was not an object.")
    return parsed


def field_text(obj: dict, *keys: str) -> str | None:
    for key in keys:
        value = obj.get(key)
        if isinstance(value, str):
            trimmed = value.strip()
            if trimmed and trimmed.lower() != "null":
                return trimmed
    return None


def field_list(obj: dict, *keys: str) -> list[str]:
    for key in keys:
        value = obj.get(key)
        if isinstance(value, list):
            return [item.strip() for item in value if isinstance(item, str) and item.strip()]
    return []


def extract_story_artifact(transcript: str) -> dict:
    status, payload = http_json(f"{GROK_BASE}/chat/completions", "POST", grok_headers(), {
        "model": GROK_MODEL,
        "messages": [
            {"role": "system", "content": ARCHIVIST_PROMPT},
            {"role": "user", "content": transcript},
        ],
        "temperature": 0.2,
        "max_tokens": 900,
        "reasoning_effort": "none",
        "response_format": {"type": "json_object"},
    })
    if not (200 <= status < 300) or not isinstance(payload, dict):
        raise RuntimeError(f"HTTP {status}: {payload}")
    choices = payload.get("choices") or []
    raw = ""
    if choices and isinstance(choices[0], dict):
        raw = ((choices[0].get("message") or {}).get("content") or "").strip()
    if not raw:
        raise RuntimeError("Grok returned an empty story extraction.")
    parsed = extract_json_object(raw)
    title = field_text(parsed, "title")
    summary = field_text(parsed, "narrativeSummary", "narrative_summary")
    imagine = field_text(parsed, "grokImaginePrompt", "grok_imagine_prompt")
    if not title or not summary or not imagine:
        raise RuntimeError(f"Story JSON was missing required fields: {raw[:500]}")
    return {
        "title": title,
        "narrativeSummary": summary,
        "extractedEra": field_text(parsed, "extractedEra", "extracted_era"),
        "location": field_text(parsed, "location"),
        "peopleMentioned": field_list(parsed, "peopleMentioned", "people_mentioned"),
        "passionsOrHobbies": field_list(parsed, "passionsOrHobbies", "passions_or_hobbies"),
        "grokImaginePrompt": imagine,
        "rawTranscript": transcript,
    }


def permanent_fact_summary(artifact: dict) -> str:
    era = artifact.get("extractedEra") or "unspecified"
    place = artifact.get("location") or "unspecified"
    people = ", ".join(artifact.get("peopleMentioned") or []) or "none named"
    passions = ", ".join(artifact.get("passionsOrHobbies") or []) or "none named"
    return (
        f"Biographical memory. {artifact['title']}. {artifact['narrativeSummary']} "
        f"Era: {era}. Location: {place}. People: {people}. Passions and hobbies: {passions}."
    )


def commit_permanent_memory(assistant_id: str, fact_summary: str) -> None:
    url = f"{BACKBOARD_BASE}/assistants/{assistant_id}/memories"
    status, payload = http_json(url, "POST", backboard_headers(), {
        "content": fact_summary,
        "metadata": {"source": "loomie", "kind": "story_artifact", "scope": "assistant"},
    })
    if not (200 <= status < 300):
        raise RuntimeError(f"HTTP {status}: {payload}")


def run_cross_session_story_test() -> dict:
    story = "In 1968 I spent the summer fixing cars with Uncle Bob. We restored a Mustang in his garage."
    probe = "Do you remember what car project I worked on in my youth?"
    first = str(uuid.uuid4())
    reply1 = send_message(story, first)
    artifact = extract_story_artifact(f"Elder: {story}\nLoomie: {reply1}")
    commit_permanent_memory(ASSISTANT_ID, permanent_fact_summary(artifact))
    time.sleep(1.5)
    second = str(uuid.uuid4())
    reply2 = send_message(probe, second)
    haystack = reply2.lower()
    recalled_year = "1968" in haystack
    recalled_person = "bob" in haystack
    recalled_project = "mustang" in haystack or "car" in haystack or "restor" in haystack
    return {
        "ok": recalled_year and recalled_person and recalled_project,
        "year": recalled_year,
        "person": recalled_person,
        "project": recalled_project,
        "title": artifact["title"],
        "reply": reply2,
    }


def mint_token() -> tuple[int, dict]:
    started = time.time()
    if not SECRETS.get("XAI_API_KEY"):
        return 500, {"error": "XAI_API_KEY is not set. Add it to middleware/.env, then restart the preview."}
    status, payload = http_json(
        f"{GROK_BASE}/realtime/client_secrets",
        "POST",
        grok_headers(),
        {"expires_after": {"seconds": 300}},
    )
    ms = int((time.time() - started) * 1000)
    ok = 200 <= status < 300 and isinstance(payload, dict) and bool(payload.get("value"))
    print(f"[Loomie] server.token ok={ok} status={status} ms={ms}")
    if not ok:
        detail = payload if isinstance(payload, str) else json.dumps(payload)[:500]
        return status if status else 502, {"error": f"HTTP {status}: {detail}"}
    return 200, {"value": payload["value"]}


def append_voice_log(session_id: str, entries: list) -> None:
    if not session_id.isalnum() or not (4 <= len(session_id) <= 64):
        raise ValueError("bad session id")
    folder = ROOT / ".voice-logs"
    folder.mkdir(exist_ok=True)
    path = folder / f"{session_id}.ndjson"
    with path.open("a", encoding="utf-8") as handle:
        for entry in entries[:500]:
            if not isinstance(entry, dict):
                continue
            line = json.dumps(entry, ensure_ascii=False)
            if len(line) < 16000:
                handle.write(line + "\n")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/api/health":
            self._json(200, {
                "ok": True,
                "hasXai": bool(SECRETS.get("XAI_API_KEY")),
                "hasBackboard": bool(SECRETS.get("BACKBOARD_API_KEY")),
                "hasMongo": bool(SECRETS.get("MONGODB_URI")),
            })
            return
        name = STATIC.get(path)
        if not name:
            self.send_error(404)
            return
        file_path = ROOT / name
        body = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(file_path.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "Expected JSON."})
            return
        if not isinstance(payload, dict):
            self._json(400, {"error": "Expected a JSON object."})
            return
        try:
            if path == "/api/token":
                status, body = mint_token()
                self._json(status, body)
            elif path == "/api/memories/recall":
                memories = fetch_memories(str(payload.get("query") or ""))
                self._json(200, {"memories": memories})
            elif path == "/api/memories/remember":
                stored = remember(str(payload.get("text") or ""), str(payload.get("threadId") or ""))
                self._json(200, {"stored": stored})
            elif path == "/api/chat":
                reply = send_message(str(payload.get("text") or ""), str(payload.get("threadId") or ""))
                self._json(200, {"reply": reply})
            elif path == "/api/story/cross-session-test":
                self._json(200, run_cross_session_story_test())
            elif path == "/api/story/wrap-up":
                transcript = str(payload.get("transcript") or "")
                artifact = extract_story_artifact(transcript)
                try:
                    commit_permanent_memory(ASSISTANT_ID, permanent_fact_summary(artifact))
                except Exception as e:
                    print(f"[Loomie] warning: permanent memory sync failed: {e}")

                mongo_saved = False
                story_id = f"story_{uuid.uuid4().hex[:12]}"
                spark_created = None
                try:
                    db = get_mongo_db()
                    if db is not None:
                        story_doc = {
                            "_id": story_id,
                            "family_id": "fam_clarke_001",
                            "author_id": "member_grandpa_joe",
                            "title": artifact["title"],
                            "narrative_summary": artifact["narrativeSummary"],
                            "extracted_era": artifact.get("extractedEra"),
                            "location": artifact.get("location"),
                            "passions": artifact.get("passionsOrHobbies", []),
                            "people_mentioned": artifact.get("peopleMentioned", []),
                            "grok_imagine_prompt": artifact.get("grokImaginePrompt"),
                            "raw_transcript": artifact.get("rawTranscript") or transcript,
                            "created_at": datetime.datetime.now(datetime.timezone.utc),
                        }
                        db.stories.insert_one(story_doc)
                        mongo_saved = True
                        print(f"[Loomie] Successfully stored story '{artifact['title']}' in MongoDB Atlas: {story_id}")

                        # Update Grandpa Joe's passions in members
                        passions = artifact.get("passionsOrHobbies", [])
                        if passions:
                            db.members.update_one(
                                {"_id": "member_grandpa_joe"},
                                {"$addToSet": {"passions": {"$each": passions}}}
                            )

                        # Check for sparks with other family members
                        other_members = list(db.members.find({"_id": {"$ne": "member_grandpa_joe"}}))
                        for target in other_members:
                            for target_passion in target.get("passions", []):
                                tp_lower = target_passion.lower()
                                matched = False
                                for passion in passions:
                                    p_lower = passion.lower()
                                    if (tp_lower in p_lower or p_lower in tp_lower or
                                        any(len(w) > 3 and w in p_lower for w in tp_lower.split())):
                                        matched = True
                                        break
                                if matched:
                                    spark_id = f"spark_{target_passion.lower().replace(' ', '_')}_{story_id[:8]}"
                                    spark_doc = {
                                        "_id": spark_id,
                                        "family_id": "fam_clarke_001",
                                        "elder_id": "member_grandpa_joe",
                                        "target_member_id": target["_id"],
                                        "matched_passion": target_passion,
                                        "spark_message": f"Grandpa Joe shared a memory about '{artifact['title']}' connecting with {target['name']}'s passion for {target_passion}!",
                                        "cta_action": f"Ask Grandpa Joe about {artifact['title']}",
                                        "is_read": False,
                                        "status": "active",
                                        "created_at": datetime.datetime.now(datetime.timezone.utc),
                                    }
                                    db.sparks.update_one({"_id": spark_id}, {"$set": spark_doc}, upsert=True)
                                    spark_created = spark_id
                                    print(f"[Loomie] Created intergenerational spark: {spark_id} ({target_passion} -> {target['name']})")
                except Exception as e:
                    print(f"[Loomie] warning: MongoDB sync failed: {e}")

                self._json(200, {
                    "artifact": artifact,
                    "mongo_saved": mongo_saved,
                    "story_id": story_id if mongo_saved else None,
                    "spark_id": spark_created
                })
            elif path == "/api/story/test-mongo":
                db = get_mongo_db()
                if db is None:
                    self._json(500, {"error": "MongoDB Atlas connection not available"})
                    return
                test_story_id = f"story_win_test_{uuid.uuid4().hex[:8]}"
                test_story = {
                    "_id": test_story_id,
                    "family_id": "fam_clarke_001",
                    "author_id": "member_grandpa_joe",
                    "title": "Windows Preview Test: Grandpa Joe at Lake Michigan",
                    "narrative_summary": "In the summer of 1965, Grandpa Joe sailed a wooden sloop across Lake Michigan with Arthur.",
                    "extracted_era": "1965",
                    "location": "Lake Michigan",
                    "passions": ["Sailing", "Woodworking"],
                    "people_mentioned": ["Arthur Clarke"],
                    "grok_imagine_prompt": "A warm 1960s Polaroid of a young man sailing a wooden boat on Lake Michigan, sun flare, film grain",
                    "raw_transcript": "Grandpa Joe: In 1965, my brother Arthur and I sailed a wooden sloop across Lake Michigan.",
                    "created_at": datetime.datetime.now(datetime.timezone.utc),
                }
                db.stories.insert_one(test_story)
                queried = db.stories.find_one({"_id": test_story_id})
                total_stories = db.stories.count_documents({"family_id": "fam_clarke_001"})
                self._json(200, {
                    "ok": True,
                    "saved": queried is not None,
                    "story_id": test_story_id,
                    "title": queried["title"] if queried else None,
                    "total_stories": total_stories
                })
            elif path == "/api/voice/log":
                append_voice_log(str(payload.get("sessionId") or ""), payload.get("entries") or [])
                self._json(200, {"ok": True})
            else:
                self.send_error(404)
        except Exception as error:
            self._json(500, {"error": str(error)})

    def _json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args) -> None:
        print(f"[Loomie] {self.address_string()} {fmt % args}")


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Loomie Windows preview: http://{HOST}:{PORT}")
    print(f"XAI key loaded: {bool(SECRETS.get('XAI_API_KEY'))}")
    print(f"Backboard key loaded: {bool(SECRETS.get('BACKBOARD_API_KEY'))}")
    print("Use headphones. Ctrl+C stops the server.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
