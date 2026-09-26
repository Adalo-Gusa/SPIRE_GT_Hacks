from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest

from env import _parse_value, load_env
from grok import GrokClient, ProviderError, parse_extraction
from interest_bridge import shared_interest
from loom_session import _load_state, _save_state
from models import FamilyGraph, LoomSpark, MemoryNode, SparkActionType
from seed import ALEX, JOSEPH, clarke_graph


class TestEnv:
    def test_values(self) -> None:
        assert _parse_value('"quoted # kept"') == "quoted # kept"
        assert _parse_value("plain # comment") == "plain"
        assert _parse_value("a#b") == "a#b"
        assert _parse_value("mongodb+srv://u:p%40ss@host/?appName=X") == "mongodb+srv://u:p%40ss@host/?appName=X"

    def test_load_env_does_not_override(self, tmp_path, monkeypatch) -> None:
        env_file = tmp_path / ".env"
        env_file.write_text("# c\nHEIRLOOM_T1=from_file\nexport HEIRLOOM_T2='x y'\nbad line\n", encoding="utf-8")
        monkeypatch.setenv("HEIRLOOM_T1", "preset")
        monkeypatch.delenv("HEIRLOOM_T2", raising=False)
        load_env(env_file)
        assert os.environ["HEIRLOOM_T1"] == "preset"
        assert os.environ["HEIRLOOM_T2"] == "x y"
        monkeypatch.delenv("HEIRLOOM_T2")


class TestInterestBridge:
    def test_radio_story_matches_alex_through_pedals_and_synths(self) -> None:
        passions = ["Computer Engineering", "Synthesizer Music", "Guitar Pedals"]
        assert shared_interest(["Ham Radio", "Soldering"], passions) == "electronics and circuits"

    def test_engineering_alone_is_not_electronics(self) -> None:
        assert shared_interest(["Ham Radio"], ["Civil Engineering", "Computer Science"]) is None

    def test_no_overlap_or_empty(self) -> None:
        assert shared_interest(["Quilting"], ["Woodworking"]) is None
        assert shared_interest([], ["Woodworking"]) is None

    def test_woodworking(self) -> None:
        assert shared_interest(["Wood joinery"], ["Woodworking"]) == "woodworking"


class TestExtractionParsing:
    def test_fenced_json_and_numeric_era(self) -> None:
        text = '```json\n{"extracted_era": 1972, "location": "", "entities_mentioned": [], ' \
            '"hobbies_identified": ["Radio"], "narrative_summary": "A story."}\n```'
        parsed = parse_extraction(text)
        assert parsed.extracted_era == "1972"
        assert parsed.location is None
        assert parsed.hobbies_identified == ["Radio"]

    def test_null_era_becomes_unknown(self) -> None:
        parsed = parse_extraction('{"extracted_era": null, "narrative_summary": "x"}')
        assert parsed.extracted_era == "Unknown era"

    @pytest.mark.parametrize("text", ["no json here", '{"extracted_era": "1960s"}', "{not json}"])
    def test_malformed(self, text: str) -> None:
        with pytest.raises(ProviderError):
            parse_extraction(text)


class TestGrokClient:
    async def test_extraction_request_uses_schema_and_model(self) -> None:
        seen: dict = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["path"] = request.url.path
            seen["auth"] = request.headers["authorization"]
            seen["body"] = json.loads(request.content)
            content = json.dumps(
                {
                    "extracted_era": "1960s",
                    "location": None,
                    "entities_mentioned": [],
                    "hobbies_identified": ["Ham Radio"],
                    "narrative_summary": "A radio story.",
                }
            )
            return httpx.Response(200, json={"choices": [{"message": {"role": "assistant", "content": content}}]})

        http = httpx.AsyncClient(
            base_url="https://api.x.ai/v1/",
            headers={"Authorization": "Bearer k"},
            transport=httpx.MockTransport(handler),
        )
        client = GrokClient("k", reasoning_model="grok-test", http=http)
        memory = await client.extract_memory("I built a radio.")
        await client.close()

        assert memory.hobbies_identified == ["Ham Radio"]
        assert seen["path"] == "/v1/chat/completions"
        assert seen["auth"] == "Bearer k"
        assert seen["body"]["model"] == "grok-test"
        assert seen["body"]["response_format"]["type"] == "json_schema"

    async def test_http_error_hides_body(self) -> None:
        http = httpx.AsyncClient(
            base_url="https://api.x.ai/v1/",
            transport=httpx.MockTransport(lambda r: httpx.Response(500, text="secret internals")),
        )
        client = GrokClient("k", http=http)
        with pytest.raises(ProviderError) as info:
            await client.follow_up("t", "c")
        assert "secret" not in str(info.value)
        assert "500" in str(info.value)

    async def test_timeout(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("slow", request=request)

        client = GrokClient("k", http=httpx.AsyncClient(base_url="https://x/", transport=httpx.MockTransport(handler)))
        with pytest.raises(ProviderError, match="timed out"):
            await client.generate_image("prompt")


class TestWireFormat:
    def test_memory_json_matches_swift_keys_and_dates(self) -> None:
        memory = MemoryNode(
            author_id=JOSEPH,
            timestamp=datetime(2026, 9, 26, 7, 5, 3, 123456, tzinfo=UTC),
            raw_transcript="t",
            narrative_summary="s",
            extracted_era="1960s",
        )
        payload = json.loads(memory.model_dump_json())
        assert set(payload) == {
            "id", "author_id", "timestamp", "raw_transcript", "narrative_summary", "extracted_era",
            "location", "entities_mentioned", "hobbies_identified", "tags", "media_urls",
        }
        assert payload["timestamp"] == "2026-09-26T07:05:03.123Z"
        assert payload["location"] is None

    def test_naive_datetimes_are_treated_as_utc(self) -> None:
        spark = LoomSpark(
            target_member_id=ALEX,
            elder_id=JOSEPH,
            prompt_text="p",
            action_type=SparkActionType.CALL_PHONE,
            timestamp=datetime(2026, 1, 1, 12, 0, 0),
        )
        assert json.loads(spark.model_dump_json())["timestamp"] == "2026-01-01T12:00:00.000Z"

    def test_graph_round_trip_accepts_uppercase_swift_uuids(self) -> None:
        graph = clarke_graph()
        payload = json.loads(graph.model_dump_json())
        assert set(payload) == {"members", "memories", "kinship_edges", "hobby_connections", "sparks"}
        assert payload["members"][0]["generation_tier"] == 1
        payload["members"][0]["id"] = payload["members"][0]["id"].upper()
        restored = FamilyGraph.model_validate(payload)
        assert restored.members[0].id == UUID("00000000-0000-0000-0000-000000000101")


class TestSessionState:
    def test_atomic_save_round_trip(self, tmp_path) -> None:
        path = tmp_path / "state.json"
        _save_state(path, {"assistant_id": "a", "threads": {"default": "t"}})
        assert _load_state(path) == {"assistant_id": "a", "threads": {"default": "t"}}
        assert [p.name for p in tmp_path.iterdir()] == ["state.json"]
