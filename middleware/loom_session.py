"""Backboard-backed conversation state for the Loom agent.

Memories live on one assistant. Each named session is one thread.
The first send creates both; later sends reuse the saved ids:

    response = await client.send_message(text, memory="Auto")
    response = await client.send_message(text, thread_id=response.thread_id, memory="Auto")
"""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

from backboard import BackboardClient

from env import load_env, require

STATE_PATH = Path(__file__).with_name(".session_state.json")

LOOM_SYSTEM_PROMPT = (
    "You are Loom, the oral-history interviewer for HeirLoom. "
    "Help family members tell stories. Remember the people, places, eras, and hobbies they mention, "
    "and ask one gentle follow-up question at a time."
)


@dataclass(frozen=True)
class LoomReply:
    content: str
    thread_id: str
    assistant_id: str
    session: str


class LoomSession:
    """Persists assistant_id and per-session thread_id across process restarts."""

    def __init__(self, client: BackboardClient, state_path: Path = STATE_PATH) -> None:
        self._client = client
        self._state_path = state_path
        self._state = _load_state(state_path)
        self.llm_provider = os.environ.get("BACKBOARD_LLM_PROVIDER", "").strip() or None
        self.model_name = os.environ.get("BACKBOARD_MODEL", "").strip() or None

    @classmethod
    def from_env(cls, state_path: Path = STATE_PATH) -> LoomSession:
        load_env()
        return cls(BackboardClient(api_key=require("BACKBOARD_API_KEY")), state_path)

    async def send(
        self,
        content: str,
        *,
        session: str = "default",
        new_thread: bool = False,
        system_prompt: str | None = None,
        assistant_id: str | None = None,
    ) -> LoomReply:
        """Send one turn. `assistant_id` pins the assistant (and its memory) instead of the saved one."""
        kwargs: dict = {"memory": "Auto"}
        if system_prompt:
            kwargs["system_prompt"] = system_prompt
        if self.llm_provider:
            kwargs["llm_provider"] = self.llm_provider
        if self.model_name:
            kwargs["model_name"] = self.model_name

        assistant_id = assistant_id or self._state.get("assistant_id")
        if assistant_id:
            kwargs["assistant_id"] = assistant_id
        thread_id = None if new_thread else self._state["threads"].get(session)
        if thread_id:
            kwargs["thread_id"] = thread_id

        response = await self._client.send_message(content, **kwargs)

        saved_assistant = str(response.assistant_id)
        saved_thread = str(response.thread_id)
        self._state["assistant_id"] = saved_assistant
        self._state["threads"][session] = saved_thread
        _save_state(self._state_path, self._state)

        return LoomReply(
            content=response.content or "",
            thread_id=saved_thread,
            assistant_id=saved_assistant,
            session=session,
        )

    async def connect_voice(
        self,
        *,
        session: str = "default",
        new_thread: bool = False,
        voice: str = "eve",
        model: str = "grok-voice-latest",
        system_prompt: str | None = None,
    ):
        """Open a Grok Voice session on this assistant's saved thread.

        Passing the stored thread continues the text conversation. A new thread
        still reuses the assistant, so memory carries over. The ids returned by
        Backboard are written back to the same state file.
        """
        assistant_id = self._state.get("assistant_id")
        thread_id = None if new_thread else self._state["threads"].get(session)
        kwargs: dict = {
            "provider": "xai",
            "model": model,
            "provider_options": {
                "voice": voice,
                "turn_detection": {"type": "server_vad", "silence_duration_ms": 600},
            },
            "memory": "Auto",
            "timeout": 45,
        }
        if system_prompt:
            kwargs["system_prompt"] = system_prompt
        if thread_id:
            kwargs["thread_id"] = thread_id
        elif assistant_id:
            kwargs["assistant_id"] = assistant_id

        realtime = await self._client.connect_realtime(**kwargs)
        self.remember(str(realtime.assistant_id), str(realtime.thread_id), session)
        return realtime

    def remember(self, assistant_id: str, thread_id: str, session: str) -> None:
        self._state["assistant_id"] = assistant_id
        self._state["threads"][session] = thread_id
        _save_state(self._state_path, self._state)

    def reset(self, session: str | None = None) -> None:
        """Drop one thread, or the assistant and every thread when session is omitted."""
        if session is None:
            self._state = {"assistant_id": None, "threads": {}}
        else:
            self._state["threads"].pop(session, None)
        _save_state(self._state_path, self._state)


def _load_state(path: Path) -> dict:
    if not path.exists():
        return {"assistant_id": None, "threads": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("assistant_id", None)
    data.setdefault("threads", {})
    return data


def _save_state(path: Path, state: dict) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
