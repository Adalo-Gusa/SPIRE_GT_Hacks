"""Server-side xAI Grok client: follow-ups, structured memory extraction, and illustrations."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx
from pydantic import BaseModel, Field, ValidationError, field_validator

from env import require

logger = logging.getLogger("heirloom.grok")

DEFAULT_BASE_URL = "https://api.x.ai/v1"
DEFAULT_REASONING_MODEL = "grok-4.6"
DEFAULT_IMAGE_MODEL = "grok-imagine-image"
# Reasoning models routinely take well over 20 s.
REASONING_TIMEOUT = httpx.Timeout(90.0, connect=10.0)
IMAGE_TIMEOUT = httpx.Timeout(120.0, connect=10.0)
FALLBACK_FOLLOW_UP = "What happened next, and who was there with you?"


class ProviderError(RuntimeError):
    """A provider call failed. The message is safe to return to clients; details are logged."""


class ExtractedMemory(BaseModel):
    extracted_era: str
    location: str | None = None
    entities_mentioned: list[str] = Field(default_factory=list)
    hobbies_identified: list[str] = Field(default_factory=list)
    narrative_summary: str

    @field_validator("extracted_era", mode="before")
    @classmethod
    def _era_as_string(cls, value: Any) -> str:
        if value is None:
            return "Unknown era"
        return str(value).strip() or "Unknown era"

    @field_validator("location", mode="before")
    @classmethod
    def _blank_location_is_none(cls, value: Any) -> Any:
        if isinstance(value, str) and not value.strip():
            return None
        return value


EXTRACTION_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "extracted_era": {"type": "string", "description": "A year or decade, such as 1972 or 1960s"},
        "location": {"type": ["string", "null"]},
        "entities_mentioned": {"type": "array", "items": {"type": "string"}},
        "hobbies_identified": {"type": "array", "items": {"type": "string"}},
        "narrative_summary": {"type": "string", "description": "One sentence"},
    },
    "required": ["extracted_era", "location", "entities_mentioned", "hobbies_identified", "narrative_summary"],
    "additionalProperties": False,
}


def parse_extraction(text: str) -> ExtractedMemory:
    """Parse the model's JSON, tolerating code fences or prose around the object."""
    trimmed = text.strip()
    start, end = trimmed.find("{"), trimmed.rfind("}")
    if start == -1 or end < start:
        raise ProviderError("Grok did not return a JSON object")
    try:
        return ExtractedMemory.model_validate(json.loads(trimmed[start : end + 1]))
    except (json.JSONDecodeError, ValidationError) as error:
        logger.warning("Unparseable extraction: %s", error)
        raise ProviderError("Grok returned malformed memory JSON") from error


class GrokClient:
    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = DEFAULT_BASE_URL,
        reasoning_model: str = DEFAULT_REASONING_MODEL,
        image_model: str = DEFAULT_IMAGE_MODEL,
        http: httpx.AsyncClient | None = None,
    ) -> None:
        self._reasoning_model = reasoning_model
        self._image_model = image_model
        self._http = http or httpx.AsyncClient(
            base_url=base_url.rstrip("/") + "/",
            headers={"Authorization": f"Bearer {api_key}"},
        )

    @classmethod
    def from_env(cls) -> GrokClient:
        return cls(
            require("XAI_API_KEY"),
            base_url=os.environ.get("XAI_BASE_URL", DEFAULT_BASE_URL),
            reasoning_model=os.environ.get("GROK_REASONING_MODEL", DEFAULT_REASONING_MODEL),
            image_model=os.environ.get("GROK_IMAGE_MODEL", DEFAULT_IMAGE_MODEL),
        )

    async def close(self) -> None:
        await self._http.aclose()

    async def chat(self, messages: list[dict[str, str]], *, response_format: dict[str, Any] | None = None) -> str:
        body: dict[str, Any] = {"model": self._reasoning_model, "messages": messages, "stream": False}
        if response_format:
            body["response_format"] = response_format
        payload = await self._post("chat/completions", body, REASONING_TIMEOUT)
        try:
            return payload["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError("Grok returned an unexpected chat response") from error

    async def follow_up(self, transcript: str, prior_context: str) -> str:
        reply = await self.chat(
            [
                {
                    "role": "system",
                    "content": "You are Loom, an empathetic, curious family oral historian. "
                    "Ask one follow-up question that helps the speaker keep talking. "
                    "If they mention a place or person from the prior family context, weave that in naturally. "
                    "Keep the reply under two sentences. No markdown, lists, or emojis.",
                },
                {
                    "role": "user",
                    "content": f"Prior family context:\n{prior_context}\n\nWhat they just said:\n{transcript}",
                },
            ]
        )
        return reply.strip() or FALLBACK_FOLLOW_UP

    async def extract_memory(self, transcript: str) -> ExtractedMemory:
        text = await self.chat(
            [
                {
                    "role": "system",
                    "content": "Parse the family story transcript into the requested JSON. "
                    "extracted_era is a year or decade. narrative_summary is one third-person sentence. "
                    "Only list hobbies and entities the speaker actually mentions.",
                },
                {"role": "user", "content": transcript},
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {"name": "memory_node", "schema": EXTRACTION_SCHEMA, "strict": True},
            },
        )
        return parse_extraction(text)

    async def illustration_prompt(self, summary: str, era: str) -> str:
        reply = await self.chat(
            [
                {
                    "role": "system",
                    "content": "Write one rich image-generation prompt for a family storybook scene. "
                    "Name the era's photographic style, the place, and the action. No preamble. "
                    "Example: Vintage 1970s warm Polaroid style, young student soldering a radio kit in a dorm "
                    "room, nostalgic film grain.",
                },
                {"role": "user", "content": f"Era: {era}\nStory: {summary}"},
            ]
        )
        return reply.strip() or f"Warm family photograph, {era}, {summary}"

    async def generate_image(self, prompt: str) -> str:
        payload = await self._post(
            "images/generations",
            {"model": self._image_model, "prompt": prompt, "n": 1, "response_format": "url"},
            IMAGE_TIMEOUT,
        )
        try:
            url = payload["data"][0]["url"]
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError("Grok Imagine returned no image") from error
        if not url:
            raise ProviderError("Grok Imagine returned no image")
        return url

    async def _post(self, path: str, body: dict[str, Any], timeout: httpx.Timeout) -> dict[str, Any]:
        try:
            response = await self._http.post(path, json=body, timeout=timeout)
        except httpx.TimeoutException as error:
            raise ProviderError("Grok timed out") from error
        except httpx.HTTPError as error:
            logger.warning("Grok transport error on %s: %s", path, error)
            raise ProviderError("Could not reach Grok") from error
        if response.status_code >= 400:
            logger.warning("Grok %s returned %s: %s", path, response.status_code, response.text[:500])
            raise ProviderError(f"Grok returned HTTP {response.status_code}")
        try:
            return response.json()
        except ValueError as error:
            raise ProviderError("Grok returned invalid JSON") from error
