import os
import asyncio
from bson import ObjectId
import certifi
from motor.motor_asyncio import AsyncIOMotorClient
from dotenv import load_dotenv

import urllib.parse
from pathlib import Path

load_dotenv()
if not os.getenv("MONGODB_URI"):
    middleware_env = Path(__file__).resolve().parent.parent / "middleware" / ".env"
    if middleware_env.is_file():
        load_dotenv(dotenv_path=middleware_env)

def sanitize_mongodb_uri(raw_uri: str) -> str:
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

async def run_verification():
    raw_uri = os.getenv("MONGODB_URI") or ""
    uri = sanitize_mongodb_uri(raw_uri)
    db_name = os.getenv("DB_NAME") or os.getenv("MONGODB_DATABASE") or "heirloom_db"
    col_name = os.getenv("COLLECTION_NAME", "items")
    
    print("=" * 60)
    print("HEIRLOOM BACKEND - FULL DATABASE & CRUD VERIFICATION")
    print("=" * 60)
    print(f"Connecting to MongoDB Atlas [{db_name}.{col_name}]...")
    
    client = AsyncIOMotorClient(
        uri,
        tlsCAFile=certifi.where(),
        serverSelectionTimeoutMS=5000,
        connectTimeoutMS=5000
    )
    db = client[db_name]
    col = db[col_name]
    
    # -------------------------------------------------------------
    # 1. PING / HEALTH CHECK
    # -------------------------------------------------------------
    print("\n--- 1. PING / HEALTH CHECK ---")
    try:
        ping_res = await db.command("ping")
        print(f"Ping response: {ping_res} -> SUCCESS")
    except Exception as e:
        print(f"[!] Ping failed: {e}")
        print("Note: Ensure your IP is whitelisted in MongoDB Atlas Network Access (0.0.0.0/0).")
        client.close()
        return

    
    # -------------------------------------------------------------
    # 2. INSERT / POST DOCUMENTS
    # -------------------------------------------------------------
    print("\n--- 2. INSERT / POST DOCUMENTS (Persisting Real Data) ---")
    stories = [
        {
            "title": "Grandpa Joe's 1968 Ham Radio Story",
            "description": "First time transmitting across the Atlantic from his Brooklyn garage.",
            "tags": ["audio", "1960s", "radio", "brooklyn"],
            "author": "Grandpa Joe",
            "user_id": "usr_101",
            "year": 1968
        },
        {
            "title": "Nana Maria's Sunday Gravy Recipe",
            "description": "Slow cooked short ribs, sweet sausages, San Marzano tomatoes, and fresh basil.",
            "tags": ["recipe", "italian", "tradition", "food"],
            "author": "Nana Maria",
            "user_id": "usr_102",
            "year": 1974
        },
        {
            "title": "1945 Golden Heirloom Pocket Watch",
            "description": "Passed down through four generations on each child's 21st birthday.",
            "tags": ["jewelry", "watch", "heirloom", "1940s"],
            "author": "Eleanor Vance",
            "user_id": "usr_103",
            "year": 1945
        }
    ]
    
    inserted_ids = []
    for item in stories:
        # Check if already exists to avoid duplicates on repeat runs
        existing = await col.find_one({"title": item["title"]})
        if existing:
            inserted_ids.append(existing["_id"])
            print(f"  [Found Existing] ID: {existing['_id']} | '{item['title']}'")
        else:
            res = await col.insert_one(item)
            inserted_ids.append(res.inserted_id)
            print(f"  [Inserted New]   ID: {res.inserted_id} | '{item['title']}'")
            
    # Verify directly in MongoDB Atlas
    for doc_id in inserted_ids:
        doc = await col.find_one({"_id": doc_id})
        assert doc is not None, f"Document {doc_id} was not found in Atlas!"
    print("  -> Verified all documents exist in MongoDB Atlas!")

    # -------------------------------------------------------------
    # 3. GET / QUERY ALL ITEMS
    # -------------------------------------------------------------
    print("\n--- 3. GET / QUERY ALL ITEMS ---")
    cursor = col.find({})
    all_docs = await cursor.to_list(length=50)
    print(f"Total documents retrieved: {len(all_docs)}")
    assert len(all_docs) >= 3, "Expected at least 3 documents!"
    
    # -------------------------------------------------------------
    # 4. PAGINATION (skip & limit)
    # -------------------------------------------------------------
    print("\n--- 4. PAGINATION (skip & limit) ---")
    p1 = await col.find({}).skip(0).limit(2).to_list(length=2)
    print(f"Page 1 (skip=0, limit=2): Retrieved {len(p1)} docs")
    assert len(p1) == 2, "Pagination limit failed"
    
    p2 = await col.find({}).skip(2).limit(2).to_list(length=2)
    print(f"Page 2 (skip=2, limit=2): Retrieved {len(p2)} docs")

    # -------------------------------------------------------------
    # 5. FILTER BY TAG (e.g. tag='recipe')
    # -------------------------------------------------------------
    print("\n--- 5. FILTER BY TAG (tag='recipe') ---")
    recipe_docs = await col.find({"tags": "recipe"}).to_list(length=10)
    print(f"Found {len(recipe_docs)} matching 'recipe':")
    for r in recipe_docs:
        print(f"  - '{r['title']}' (tags: {r['tags']})")
    assert len(recipe_docs) >= 1, "Expected recipe document"

    # -------------------------------------------------------------
    # 6. GET SINGLE ITEM BY ID
    # -------------------------------------------------------------
    print("\n--- 6. GET SINGLE ITEM BY ID ---")
    sample_id = inserted_ids[0]
    single_doc = await col.find_one({"_id": sample_id})
    print(f"Retrieved by ID {sample_id}: '{single_doc['title']}' by {single_doc.get('author')}")
    assert single_doc["_id"] == sample_id

    # -------------------------------------------------------------
    # 7. UPDATE ITEM (PUT / PATCH)
    # -------------------------------------------------------------
    print("\n--- 7. UPDATE ITEM (PUT / PATCH) ---")
    update_data = {
        "title": "Grandpa Joe's 1968 Ham Radio Story (Remastered Audio)",
        "audio_url": "https://storage.heirloom.app/audio/radio_1968.mp3",
        "verified": True
    }
    await col.update_one({"_id": sample_id}, {"$set": update_data})
    updated_doc = await col.find_one({"_id": sample_id})
    print(f"Updated title:     '{updated_doc['title']}'")
    print(f"Added audio URL:   '{updated_doc.get('audio_url')}'")
    print(f"Verified flag:     {updated_doc.get('verified')}")
    assert updated_doc["title"] == update_data["title"]
    assert updated_doc["audio_url"] == update_data["audio_url"]

    # -------------------------------------------------------------
    # 8. DELETE ITEM (DELETE)
    # -------------------------------------------------------------
    print("\n--- 8. DELETE ITEM (DELETE) ---")
    temp = await col.insert_one({"title": "Temp Item to Delete", "tags": ["test_delete"]})
    temp_id = temp.inserted_id
    print(f"Created temp doc:  {temp_id}")
    
    del_res = await col.delete_one({"_id": temp_id})
    print(f"Deleted count:     {del_res.deleted_count}")
    assert del_res.deleted_count == 1
    
    del_check = await col.find_one({"_id": temp_id})
    print(f"Verified deleted:  {del_check is None}")
    assert del_check is None

    # -------------------------------------------------------------
    # FINAL AUDIT: PERMANENT DATA READY FOR USERS & SWIFT
    # -------------------------------------------------------------
    print("\n" + "=" * 60)
    print("MONGODB ATLAS - CURRENT STORED DOCUMENTS READY FOR SWIFT")
    print("=" * 60)
    all_final = await col.find({}).to_list(length=100)
    for i, d in enumerate(all_final, 1):
        print(f"[{i}] ID: {d['_id']}")
        print(f"    Title:       {d.get('title')}")
        print(f"    Description: {d.get('description')}")
        print(f"    Tags:        {d.get('tags')}")
        if "author" in d:
            print(f"    Author:      {d.get('author')}")
        if "user_id" in d:
            print(f"    User ID:     {d.get('user_id')}")
        if "audio_url" in d:
            print(f"    Audio URL:   {d.get('audio_url')}")
        print()

    client.close()
    print("=" * 60)
    print("ALL REQUEST TYPES & ATLAS PERSISTENCE VERIFIED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(run_verification())
