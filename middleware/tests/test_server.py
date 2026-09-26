from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import server
from seed import ALEX, JOSEPH

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


class FakeChat:
    def __init__(self) -> None:
        self.fail = False
        self.calls: list[tuple[str, str]] = []

    async def reply(self, message: str, session_id: str) -> str:
        if self.fail:
            raise RuntimeError("backboard exploded with secret details")
        self.calls.append((message, session_id))
        return "That sounds wonderful.\nWho taught you?"


@pytest.fixture
def chat() -> FakeChat:
    return FakeChat()


@pytest.fixture
def client(pipeline, chat):
    server.app.state.services = server.Services(pipeline=pipeline, chat=chat, api_token=TOKEN)
    yield TestClient(server.app)
    server.app.state.services = None


def test_health_is_public(client) -> None:
    assert client.get("/health").json() == {"status": "ok"}


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer wrong"}, {"Authorization": "Basic x"}])
def test_routes_require_token(client, headers) -> None:
    assert client.get("/graph", headers=headers).status_code == 401


def test_graph_shape(client) -> None:
    response = client.get("/graph", headers=AUTH)
    assert response.status_code == 200
    graph = response.json()
    assert set(graph) == {"members", "memories", "kinship_edges", "hobby_connections", "sparks"}
    member = graph["members"][0]
    assert member["profile_image_url"] is None  # present as null, which Swift's Optional decoding accepts
    assert graph["memories"][0]["timestamp"].endswith("Z")


def test_ingest_returns_result_and_runs_background(client, store) -> None:
    response = client.post(
        "/memories/ingest",
        headers=AUTH,
        json={"transcript": "  I built a radio.  ", "author_id": str(JOSEPH).upper()},
    )
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"memory", "new_connections", "sparks"}
    assert body["memory"]["raw_transcript"] == "I built a radio."
    assert body["sparks"][0]["target_member_id"] == str(ALEX)
    # TestClient runs background tasks before returning.
    assert len(store.stored_chapters) == 1


def test_ingest_rejects_blank_transcript_and_unknown_author(client) -> None:
    blank = client.post("/memories/ingest", headers=AUTH, json={"transcript": "   ", "author_id": str(JOSEPH)})
    assert blank.status_code == 422
    unknown = client.post("/memories/ingest", headers=AUTH, json={"transcript": "hi", "author_id": str(uuid4())})
    assert unknown.status_code == 404


def test_ingest_provider_failure_is_502_with_short_detail(client, grok) -> None:
    grok.fail_extraction = True
    response = client.post("/memories/ingest", headers=AUTH, json={"transcript": "hi", "author_id": str(JOSEPH)})
    assert response.status_code == 502
    assert response.json() == {"detail": "Grok timed out"}


def test_sparks_list_and_resolve(client) -> None:
    ingest = client.post("/memories/ingest", headers=AUTH, json={"transcript": "radio", "author_id": str(JOSEPH)})
    spark_id = ingest.json()["sparks"][0]["id"]

    pending = client.get(f"/sparks/{ALEX}", headers=AUTH).json()
    assert [s["id"] for s in pending] == [spark_id]

    assert client.post(f"/sparks/{spark_id}/resolve", headers=AUTH).status_code == 204
    assert client.get(f"/sparks/{ALEX}", headers=AUTH).json() == []
    assert client.post(f"/sparks/{uuid4()}/resolve", headers=AUTH).status_code == 404


def test_add_memory_accepts_swift_encoding(client, store) -> None:
    swift_body = {
        "id": str(uuid4()).upper(),
        "author_id": str(JOSEPH).upper(),
        "timestamp": "2026-09-26T07:05:03Z",
        "raw_transcript": "t",
        "narrative_summary": "s",
        "extracted_era": "1960s",
        "entities_mentioned": [],
        "hobbies_identified": [],
        "tags": [],
        "media_urls": [],
    }
    before = len(store.data.memories)
    assert client.post("/memories", headers=AUTH, json=swift_body).status_code == 204
    assert len(store.data.memories) == before + 1


def test_followups(client, store) -> None:
    memory = store.data.memories[0].model_dump(mode="json")
    response = client.post("/agent/followups", headers=AUTH, json={"memory": memory, "session_id": "s1"})
    assert response.status_code == 200
    assert len(response.json()["questions"]) == 1


def test_chat_streams_single_line(client, chat) -> None:
    response = client.post("/agent/chat", headers=AUTH, json={"message": "hello", "session_id": "s1"})
    assert response.status_code == 200
    assert response.text == "That sounds wonderful. Who taught you?\n"
    assert chat.calls == [("hello", "s1")]


def test_chat_failure_hides_details(client, chat) -> None:
    chat.fail = True
    response = client.post("/agent/chat", headers=AUTH, json={"message": "hello", "session_id": "s1"})
    assert response.status_code == 502
    assert "secret" not in response.text


def test_database_outage_is_503_without_details(client, store) -> None:
    from pymongo.errors import ServerSelectionTimeoutError

    async def down(family_id: str):
        raise ServerSelectionTimeoutError("testcluster-shard-00-00 internal topology details")

    store.graph = down
    response = client.get("/graph", headers=AUTH)
    assert response.status_code == 503
    assert response.json() == {"detail": "The family database is unavailable."}


def test_storybook_and_illustration(client) -> None:
    chapters = client.post("/storybook", headers=AUTH, json={"memory_ids": []}).json()
    assert chapters and set(chapters[0]) == {
        "id", "title", "narrative_text", "illustration_url", "audio_snippet_url", "source_memory_ids",
    }
    art = client.post("/storybook/illustration", headers=AUTH, json={"prompt": "a radio"}).json()
    assert art == {"url": "https://images.example/radio.png"}
