import os
from contextlib import asynccontextmanager
from typing import List, Optional, Annotated

from fastapi import FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, Field, ConfigDict
from pydantic.functional_validators import BeforeValidator
from bson import ObjectId
from bson.errors import InvalidId
from dotenv import load_dotenv

try:
    import certifi
    ca = certifi.where()
except ImportError:
    ca = None

load_dotenv()

# --- Connection Pooling & Database Configuration ---
class Database:
    client: AsyncIOMotorClient = None
    db = None

db_config = Database()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize the MongoDB client on startup
    uri = os.getenv("MONGODB_URI")
    db_name = os.getenv("DB_NAME", "HeirLoomDb")
    
    client_kwargs = {"maxPoolSize": 10, "minPoolSize": 1}
    if ca:
        client_kwargs["tlsCAFile"] = ca
    
    # maxPoolSize handles concurrency; minPoolSize keeps connections warm
    db_config.client = AsyncIOMotorClient(uri, **client_kwargs)
    db_config.db = db_config.client[db_name]
    print(f"Connected to MongoDB Atlas: {db_name}")
    
    yield
    
    # Close connection gracefully on shutdown
    db_config.client.close()
    print("MongoDB connection closed.")

from pymongo.errors import PyMongoError
from starlette.responses import JSONResponse
from fastapi import Request

app = FastAPI(title="HeirLoom API", lifespan=lifespan)

# --- Security: CORS Configuration ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # In production, replace with your specific frontend domains
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

@app.get("/health", tags=["Health"])
async def health_check():
    try:
        await db_config.db.command("ping")
        return {"status": "ok", "database": "connected"}
    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "database": str(e)})

# --- Pydantic Models & ObjectId Handling ---
# Converts BSON ObjectId to a string for JSON serialization
PyObjectId = Annotated[str, BeforeValidator(str)]

class ItemModel(BaseModel):
    # Field(alias="_id") maps the Python 'id' to the MongoDB '_id'
    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    title: str
    description: Optional[str] = None
    tags: List[str] = []
    
    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
        extra="allow",
        json_schema_extra={
            "example": {
                "title": "Grandpa's Radio Story",
                "description": "Building the first ham radio in 1968.",
                "tags": ["audio", "1960s"]
            }
        }
    )

class ItemUpdateModel(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None
    model_config = ConfigDict(arbitrary_types_allowed=True, extra="allow")

# --- Helper: Validate ObjectId ---
def validate_object_id(id: str) -> ObjectId:
    try:
        return ObjectId(id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid ID format.")

# --- REST Endpoints ---

@app.post("/items", response_model=ItemModel, status_code=status.HTTP_201_CREATED)
async def create_item(item: ItemModel):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    new_item = await collection.insert_one(item.model_dump(by_alias=True, exclude={"id"}))
    created_item = await collection.find_one({"_id": new_item.inserted_id})
    return created_item

@app.get("/items", response_model=List[ItemModel])
async def list_items(
    skip: int = Query(0, ge=0, description="Pagination skip count"),
    limit: int = Query(20, ge=1, le=100, description="Pagination limit"),
    tag: Optional[str] = Query(None, description="Filter by tag")
):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    
    query = {}
    if tag:
        query["tags"] = tag

    cursor = collection.find(query).skip(skip).limit(limit)
    items = await cursor.to_list(length=limit)
    return items

@app.get("/items/{id}", response_model=ItemModel)
async def get_item(id: str):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    obj_id = validate_object_id(id)
    
    if (item := await collection.find_one({"_id": obj_id})) is not None:
        return item
    raise HTTPException(status_code=404, detail=f"Item {id} not found")

@app.put("/items/{id}", response_model=ItemModel)
async def update_item(id: str, item_update: ItemUpdateModel):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    obj_id = validate_object_id(id)
    
    update_data = {k: v for k, v in item_update.model_dump().items() if v is not None}
    
    if len(update_data) >= 1:
        update_result = await collection.update_one({"_id": obj_id}, {"$set": update_data})
        if update_result.modified_count == 1:
            if (updated_item := await collection.find_one({"_id": obj_id})) is not None:
                return updated_item
    
    if (existing_item := await collection.find_one({"_id": obj_id})) is not None:
        return existing_item
        
    raise HTTPException(status_code=404, detail=f"Item {id} not found")

@app.patch("/items/{id}", response_model=ItemModel)
async def patch_item(id: str, item_update: ItemUpdateModel):
    return await update_item(id, item_update)

@app.delete("/items/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(id: str):
    collection = db_config.db[os.getenv("COLLECTION_NAME", "items")]
    obj_id = validate_object_id(id)
    
    delete_result = await collection.delete_one({"_id": obj_id})
    if delete_result.deleted_count == 1:
        return
        
    raise HTTPException(status_code=404, detail=f"Item {id} not found")
