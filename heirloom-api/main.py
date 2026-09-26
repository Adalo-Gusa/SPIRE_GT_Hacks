import os
import datetime
import urllib.parse
from contextlib import asynccontextmanager
from typing import List, Optional, Annotated, Any

from fastapi import FastAPI, HTTPException, Query, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, Field, ConfigDict
from pydantic.functional_validators import BeforeValidator
from pymongo.errors import PyMongoError
from bson import ObjectId
from bson.errors import InvalidId
from dotenv import load_dotenv

try:
    import certifi
    ca = certifi.where()
except ImportError:
    ca = None

# Load .env from current directory, or fallback to middleware/.env
load_dotenv()
if not os.getenv("MONGODB_URI"):
    from pathlib import Path
    middleware_env = Path(__file__).resolve().parent.parent / "middleware" / ".env"
    if middleware_env.is_file():
        load_dotenv(dotenv_path=middleware_env)


def sanitize_mongodb_uri(raw_uri: str) -> str:
    """Ensures passwords with special characters like '@' are safely URL-encoded."""
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


# --- Connection Pooling & Database Configuration ---
class Database:
    client: Optional[AsyncIOMotorClient] = None
    db: Any = None

db_config = Database()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize the MongoDB client on startup
    raw_uri = os.getenv("MONGODB_URI") or ""
    uri = sanitize_mongodb_uri(raw_uri)
    db_name = os.getenv("DB_NAME") or os.getenv("MONGODB_DATABASE") or "heirloom_db"

    client_kwargs = {
        "maxPoolSize": 10,
        "minPoolSize": 1,
        "serverSelectionTimeoutMS": 5000,
        "connectTimeoutMS": 5000,
    }
    if ca:
        client_kwargs["tlsCAFile"] = ca

    db_config.client = AsyncIOMotorClient(uri, **client_kwargs)
    db_config.db = db_config.client[db_name]
    print(f"[HeirLoom API] Connected to MongoDB Atlas: {db_name}")

    yield

    if db_config.client:
        db_config.client.close()
    print("[HeirLoom API] MongoDB connection closed.")


app = FastAPI(
    title="HeirLoom MongoDB API",
    description="Backend service powering the HeirLoom oral family history corkboard, member management, and sparks.",
    version="1.1.0",
    lifespan=lifespan,
)

# --- Security: CORS Configuration ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(PyMongoError)
async def pymongo_exception_handler(request: Request, exc: PyMongoError):
    return JSONResponse(
        status_code=500,
        content={"error": "Database error", "detail": str(exc)},
    )


# --- Helper: Universal ID Query (Matches both ObjectId and semantic String IDs) ---
def id_query(id_str: str) -> dict:
    try:
        return {"$or": [{"_id": ObjectId(id_str)}, {"_id": id_str}]}
    except (InvalidId, TypeError):
        return {"_id": id_str}


def serialize_doc(doc: Optional[dict]) -> Optional[dict]:
    """Ensures _id is serialized to a string for JSON compliance."""
    if doc is None:
        return None
    doc["_id"] = str(doc["_id"])
    return doc


# --- Health & Diagnostic Endpoints ---

@app.get("/health", tags=["Health"])
async def health_check():
    try:
        await db_config.db.command("ping")
        return {"status": "ok", "database": "connected", "db_name": db_config.db.name}
    except Exception as e:
        return JSONResponse(status_code=503, content={"status": "error", "database": str(e)})


# =====================================================================
# MEMBER / USER DOMAIN MODELS & ENDPOINTS
# =====================================================================

class MemberModel(BaseModel):
    id: Optional[str] = Field(alias="_id", default=None)
    family_id: str = Field(default="fam_clarke_001")
    name: str
    birth_year: Optional[int] = Field(default=None)
    age: Optional[int] = Field(default=None) # Convenience mapping for UI
    generation_tier: int = Field(default=1)
    spouse_id: Optional[str] = None
    parents: List[str] = Field(default_factory=list)
    children: List[str] = Field(default_factory=list)
    passions: List[str] = Field(default_factory=list)
    interests: Optional[List[str]] = None # Convenience alias for passions
    avatar_url: Optional[str] = None
    gender: Optional[str] = None  # "female" or "male"; picks the app's girl or guy placeholder
    bio: Optional[str] = None
    created_at: Optional[datetime.datetime] = None
    updated_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(
        populate_by_name=True,
        extra="allow",
        json_schema_extra={
            "example": {
                "name": "Joseph Clarke",
                "birth_year": 1948,
                "generation_tier": 1,
                "passions": ["Ham Radio", "Woodworking", "Civil Aviation"],
                "bio": "Retired civil aerospace engineer and vintage car tinkerer."
            }
        }
    )


class MemberUpdateModel(BaseModel):
    name: Optional[str] = None
    birth_year: Optional[int] = None
    age: Optional[int] = None
    generation_tier: Optional[int] = None
    spouse_id: Optional[str] = None
    parents: Optional[List[str]] = None
    children: Optional[List[str]] = None
    passions: Optional[List[str]] = None
    interests: Optional[List[str]] = None
    avatar_url: Optional[str] = None
    gender: Optional[str] = None  # "female" or "male"; picks the app's girl or guy placeholder
    bio: Optional[str] = None

    model_config = ConfigDict(populate_by_name=True, extra="allow")


class PassionsAppendModel(BaseModel):
    passions: List[str]


@app.post("/members", response_model=MemberModel, status_code=status.HTTP_201_CREATED, tags=["Members"])
@app.post("/users", response_model=MemberModel, status_code=status.HTTP_201_CREATED, tags=["Users (Alias)"])
async def create_member(member: MemberModel):
    collection = db_config.db["members"]
    data = member.model_dump(by_alias=True)

    # Normalize age -> birth_year if birth_year is missing
    if data.get("birth_year") is None and data.get("age") is not None:
        data["birth_year"] = datetime.datetime.now().year - data["age"]

    # Normalize interests -> passions
    if data.get("interests"):
        existing_passions = set(data.get("passions") or [])
        existing_passions.update(data["interests"])
        data["passions"] = list(existing_passions)

    if not data.get("_id"):
        data.pop("_id", None)
    data["created_at"] = data.get("created_at") or datetime.datetime.now(datetime.timezone.utc)
    data["updated_at"] = datetime.datetime.now(datetime.timezone.utc)

    result = await collection.insert_one(data)
    new_id = str(result.inserted_id)

    # Automatic bidirectional relationship healing
    if data.get("spouse_id"):
        await collection.update_one({"_id": data["spouse_id"]}, {"$set": {"spouse_id": new_id}})
    for parent_id in (data.get("parents") or []):
        await collection.update_one({"_id": parent_id}, {"$addToSet": {"children": new_id}})
    for child_id in (data.get("children") or []):
        await collection.update_one({"_id": child_id}, {"$addToSet": {"parents": new_id}})

    created = await collection.find_one({"_id": result.inserted_id})
    return serialize_doc(created)


@app.get("/members", response_model=List[MemberModel], tags=["Members"])
@app.get("/users", response_model=List[MemberModel], tags=["Users (Alias)"])
async def list_members(
    family_id: Optional[str] = Query(None, description="Filter by family ID"),
    generation_tier: Optional[int] = Query(None, description="Filter by generation tier")
):
    collection = db_config.db["members"]
    query = {}
    if family_id:
        query["family_id"] = family_id
    if generation_tier is not None:
        query["generation_tier"] = generation_tier

    cursor = collection.find(query).sort("generation_tier", 1)
    docs = await cursor.to_list(length=100)
    return [serialize_doc(doc) for doc in docs]


@app.get("/members/{id}", response_model=MemberModel, tags=["Members"])
@app.get("/users/{id}", response_model=MemberModel, tags=["Users (Alias)"])
async def get_member(id: str):
    collection = db_config.db["members"]
    doc = await collection.find_one(id_query(id))
    if not doc:
        raise HTTPException(status_code=404, detail=f"Member '{id}' not found")
    return serialize_doc(doc)


@app.put("/members/{id}", response_model=MemberModel, tags=["Members"])
@app.patch("/members/{id}", response_model=MemberModel, tags=["Members"])
@app.put("/users/{id}", response_model=MemberModel, tags=["Users (Alias)"])
@app.patch("/users/{id}", response_model=MemberModel, tags=["Users (Alias)"])
async def update_member(id: str, update: MemberUpdateModel):
    collection = db_config.db["members"]
    update_data = {k: v for k, v in update.model_dump().items() if v is not None}

    # Normalize age -> birth_year
    if "age" in update_data and "birth_year" not in update_data:
        update_data["birth_year"] = datetime.datetime.now().year - update_data["age"]

    # Normalize interests -> passions
    if "interests" in update_data:
        interests = update_data.pop("interests")
        existing_doc = await collection.find_one(id_query(id))
        cur_passions = set((existing_doc or {}).get("passions") or [])
        cur_passions.update(interests)
        update_data["passions"] = list(cur_passions)

    update_data["updated_at"] = datetime.datetime.now(datetime.timezone.utc)

    if update_data:
        await collection.update_one(id_query(id), {"$set": update_data})

    updated = await collection.find_one(id_query(id))
    if not updated:
        raise HTTPException(status_code=404, detail=f"Member '{id}' not found")
    return serialize_doc(updated)


@app.post("/members/{id}/passions", response_model=MemberModel, tags=["Members"])
async def append_member_passions(id: str, body: PassionsAppendModel):
    collection = db_config.db["members"]
    if body.passions:
        await collection.update_one(
            id_query(id),
            {
                "$addToSet": {"passions": {"$each": body.passions}},
                "$set": {"updated_at": datetime.datetime.now(datetime.timezone.utc)},
            },
        )
    doc = await collection.find_one(id_query(id))
    if not doc:
        raise HTTPException(status_code=404, detail=f"Member '{id}' not found")
    return serialize_doc(doc)


@app.delete("/members/{id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Members"])
@app.delete("/users/{id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Users (Alias)"])
async def delete_member(id: str):
    collection = db_config.db["members"]
    res = await collection.delete_one(id_query(id))
    if res.deleted_count == 0:
        raise HTTPException(status_code=404, detail=f"Member '{id}' not found")
    return


# =====================================================================
# STORIES DOMAIN MODELS & ENDPOINTS
# =====================================================================

class StoryModel(BaseModel):
    id: Optional[str] = Field(alias="_id", default=None)
    family_id: str = Field(default="fam_clarke_001")
    author_id: str
    title: str
    narrative_summary: str
    extracted_era: Optional[str] = None
    location: Optional[str] = None
    passions: List[str] = Field(default_factory=list)
    people_mentioned: List[str] = Field(default_factory=list)
    grok_imagine_prompt: Optional[str] = None
    raw_transcript: Optional[str] = None
    image_url: Optional[str] = None
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(populate_by_name=True, extra="allow")


@app.post("/stories", response_model=StoryModel, status_code=status.HTTP_201_CREATED, tags=["Stories"])
async def create_story(story: StoryModel):
    collection = db_config.db["stories"]
    data = story.model_dump(by_alias=True)
    if not data.get("_id"):
        data.pop("_id", None)
    data["created_at"] = data.get("created_at") or datetime.datetime.now(datetime.timezone.utc)
    res = await collection.insert_one(data)
    created = await collection.find_one({"_id": res.inserted_id})
    return serialize_doc(created)


@app.get("/stories", response_model=List[StoryModel], tags=["Stories"])
async def list_stories(
    family_id: Optional[str] = Query(None, description="Filter by family ID"),
    author_id: Optional[str] = Query(None, description="Filter by author member ID"),
):
    collection = db_config.db["stories"]
    query = {}
    if family_id:
        query["family_id"] = family_id
    if author_id:
        query["author_id"] = author_id

    cursor = collection.find(query).sort("created_at", -1)
    docs = await cursor.to_list(length=100)
    return [serialize_doc(doc) for doc in docs]


# =====================================================================
# SPARKS DOMAIN MODELS & ENDPOINTS
# =====================================================================

class SparkModel(BaseModel):
    id: Optional[str] = Field(alias="_id", default=None)
    family_id: str = Field(default="fam_clarke_001")
    elder_id: str
    target_member_id: str
    matched_passion: str
    spark_message: str
    cta_action: str
    is_read: bool = False
    status: str = "active"
    created_at: Optional[datetime.datetime] = None

    model_config = ConfigDict(populate_by_name=True, extra="allow")


@app.post("/sparks", response_model=SparkModel, status_code=status.HTTP_201_CREATED, tags=["Sparks"])
async def create_spark(spark: SparkModel):
    collection = db_config.db["sparks"]
    data = spark.model_dump(by_alias=True)
    if not data.get("_id"):
        data.pop("_id", None)
    data["created_at"] = data.get("created_at") or datetime.datetime.now(datetime.timezone.utc)
    res = await collection.insert_one(data)
    created = await collection.find_one({"_id": res.inserted_id})
    return serialize_doc(created)


@app.get("/sparks", response_model=List[SparkModel], tags=["Sparks"])
async def list_sparks(family_id: Optional[str] = Query(None)):
    collection = db_config.db["sparks"]
    query = {"family_id": family_id} if family_id else {}
    cursor = collection.find(query).sort("created_at", -1)
    docs = await cursor.to_list(length=50)
    return [serialize_doc(doc) for doc in docs]



# =====================================================================
# FAMILY FEED POSTS DOMAIN MODELS & ENDPOINTS
# =====================================================================

class FeedPostModel(BaseModel):
    id: Optional[str] = Field(alias="_id", default=None)
    family_id: str = Field(default="fam_clarke_001")
    author_id: str
    author_name: str
    author_avatar_url: Optional[str] = None
    content: str
    image_url: Optional[str] = None
    post_url: Optional[str] = None
    source: str = "in_app"  # "instagram" or "in_app"
    passions: List[str] = Field(default_factory=list)
    location: Optional[str] = None
    created_at: Optional[datetime.datetime] = None
    is_unread: bool = True

    model_config = ConfigDict(populate_by_name=True, extra="allow")


@app.post("/posts", response_model=FeedPostModel, status_code=status.HTTP_201_CREATED, tags=["Feed Posts"])
async def create_feed_post(post: FeedPostModel):
    collection = db_config.db["posts"]
    data = post.model_dump(by_alias=True)
    if not data.get("_id"):
        import uuid
        data["_id"] = f"post_{uuid.uuid4().hex[:12]}"
    if not data.get("created_at"):
        data["created_at"] = datetime.datetime.now(datetime.timezone.utc)
    await collection.insert_one(data)
    created = await collection.find_one({"_id": data["_id"]})
    return serialize_doc(created)


@app.get("/posts", response_model=List[FeedPostModel], tags=["Feed Posts"])
async def list_feed_posts(
    family_id: Optional[str] = Query(None),
    author_id: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=100)
):
    collection = db_config.db["posts"]
    query = {}
    if family_id:
        query["family_id"] = family_id
    if author_id:
        query["author_id"] = author_id
    cursor = collection.find(query).sort("created_at", -1).limit(limit)
    docs = await cursor.to_list(length=limit)
    return [serialize_doc(doc) for doc in docs]


# =====================================================================
# BACKWARD COMPATIBLE /items ENDPOINTS (Used by test_db.py)
# =====================================================================

PyObjectId = Annotated[str, BeforeValidator(str)]

class ItemModel(BaseModel):
    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    title: str
    description: Optional[str] = None
    tags: List[str] = []

    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
        extra="allow",
    )

class ItemUpdateModel(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None
    model_config = ConfigDict(arbitrary_types_allowed=True, extra="allow")


@app.post("/items", response_model=ItemModel, status_code=status.HTTP_201_CREATED, tags=["Items (Legacy)"])
async def create_item(item: ItemModel):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    data = item.model_dump(by_alias=True)
    if not data.get("_id"):
        data.pop("_id", None)
    new_item = await collection.insert_one(data)
    created_item = await collection.find_one({"_id": new_item.inserted_id})
    return serialize_doc(created_item)


@app.get("/items", response_model=List[ItemModel], tags=["Items (Legacy)"])
async def list_items(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    tag: Optional[str] = Query(None)
):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    query = {}
    if tag:
        query["tags"] = tag
    cursor = collection.find(query).skip(skip).limit(limit)
    items = await cursor.to_list(length=limit)
    return [serialize_doc(item) for item in items]


@app.get("/items/{id}", response_model=ItemModel, tags=["Items (Legacy)"])
async def get_item(id: str):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    item = await collection.find_one(id_query(id))
    if item is not None:
        return serialize_doc(item)
    raise HTTPException(status_code=404, detail=f"Item {id} not found")


@app.put("/items/{id}", response_model=ItemModel, tags=["Items (Legacy)"])
async def update_item(id: str, item_update: ItemUpdateModel):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    query = id_query(id)
    update_data = {k: v for k, v in item_update.model_dump().items() if v is not None}

    if len(update_data) >= 1:
        await collection.update_one(query, {"$set": update_data})
        if (updated_item := await collection.find_one(query)) is not None:
            return serialize_doc(updated_item)

    if (existing_item := await collection.find_one(query)) is not None:
        return serialize_doc(existing_item)

    raise HTTPException(status_code=404, detail=f"Item {id} not found")


@app.patch("/items/{id}", response_model=ItemModel, tags=["Items (Legacy)"])
async def patch_item(id: str, item_update: ItemUpdateModel):
    return await update_item(id, item_update)


@app.delete("/items/{id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Items (Legacy)"])
async def delete_item(id: str):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    delete_result = await collection.delete_one(id_query(id))
    if delete_result.deleted_count == 1:
        return
    raise HTTPException(status_code=404, detail=f"Item {id} not found")


# --- Grok SDK Archive Manager Endpoints ---
try:
    from archive_manager import ArchiveManagerAgent
    archive_agent_instance = ArchiveManagerAgent()
except Exception as e:
    print(f"[HeirLoom API] ArchiveManagerAgent load note: {e}")
    archive_agent_instance = None


class ArchiveProcessRequest(BaseModel):
    transcript: str
    teller_hint: Optional[str] = None
    family_id: str = "fam_clarke_001"


class ConnectionSearchRequest(BaseModel):
    query: str
    family_id: str = "fam_clarke_001"


@app.post("/api/archive/process-story", tags=["Archive Manager (Grok SDK)"])
async def archive_process_story(req: ArchiveProcessRequest):
    """Grok SDK Agent endpoint to analyze story, create new person in Atlas if not found,
    save story document, enrich passions, and generate cross-generational sparks.
    """
    if archive_agent_instance is None:
        raise HTTPException(status_code=503, detail="Archive Manager Agent not initialized. Check XAI_API_KEY.")
    try:
        res = archive_agent_instance.process_story(
            transcript=req.transcript,
            teller_hint=req.teller_hint,
            family_id=req.family_id,
        )
        return res.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Story archival failed: {str(e)}")


@app.post("/api/archive/search-connections", tags=["Archive Manager (Grok SDK)"])
async def archive_search_connections(req: ConnectionSearchRequest):
    """Grok SDK Agent endpoint to explore and synthesize cross-generational connections."""
    if archive_agent_instance is None:
        raise HTTPException(status_code=503, detail="Archive Manager Agent not initialized.")
    try:
        res = archive_agent_instance.search_connections(
            query=req.query,
            family_id=req.family_id,
        )
        return res.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Connection search failed: {str(e)}")


@app.get("/api/archive/digest", tags=["Archive Manager (Grok SDK)"])
async def archive_digest(family_id: str = "fam_clarke_001"):
    """Returns overview statistics of members, stories, and sparks in MongoDB Atlas."""
    if archive_agent_instance is None:
        raise HTTPException(status_code=503, detail="Archive Manager Agent not initialized.")
    return archive_agent_instance.get_archive_digest(family_id=family_id)


# --- Corkboard Tree Auto-Orientation Layout Endpoint ---
from tree_engine import FamilyCorkboardLayoutEngine

@app.get("/api/tree", tags=["Corkboard Tree"])
@app.get("/api/family/corkboard-layout", tags=["Corkboard Tree"])
async def get_corkboard_tree(family_id: str = "fam_clarke_001"):
    """Returns auto-oriented 2D corkboard layout with node coordinates, pushpins,
    rotation angles, and conspiracy red twine strings.
    """
    collection = db_config.db["members"]
    cursor = collection.find({"family_id": family_id})
    members = await cursor.to_list(length=200)
    engine = FamilyCorkboardLayoutEngine(family_id=family_id)
    layout = engine.build_layout(members)
    return layout.model_dump()

