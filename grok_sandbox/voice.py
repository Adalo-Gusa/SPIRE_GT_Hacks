"""Live Grok Voice conversation stored on the Backboard Loom thread.

  pip install -r requirements.txt
  python voice.py

Audio still goes to grok-voice-latest. Backboard keeps the thread and memory,
so a later `python ../middleware/chat.py ask "..."` continues the same session.
Headphones work best, so the microphone does not hear the speakers.
Press Ctrl+C to quit.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import sys
import threading
from pathlib import Path

import sounddevice as sd
from backboard.exceptions import BackboardAPIError

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "middleware"))

from env import load_env  # noqa: E402
from loom_session import LOOM_SYSTEM_PROMPT, LoomSession  # noqa: E402

ENV_PATH = Path(__file__).with_name(".env")
SAMPLE_RATE = 24000
CHUNK_MS = 100

INSTRUCTIONS = (
    LOOM_SYSTEM_PROMPT
    + " Talk the way you would in a casual spoken conversation. "
    "Keep most replies to one or two short sentences, and go longer only when asked. "
    "No markdown, lists, or emojis. If you are unsure, say so briefly."
)
GREETING = "Greet the person in one short sentence and invite them to tell a family story."


class Speaker:
    """Plays PCM16 mono audio and can drop it when the user interrupts."""

    def __init__(self, rate: int) -> None:
        self._buffer = bytearray()
        self._sync = threading.Lock()
        self.stream = sd.RawOutputStream(
            samplerate=rate,
            channels=1,
            dtype="int16",
            callback=self._callback,
            blocksize=rate // 50,
        )

    def _callback(self, outdata, frames, _time, _status) -> None:
        need = frames * 2
        with self._sync:
            chunk = bytes(self._buffer[:need])
            del self._buffer[:need]
        if len(chunk) < need:
            chunk += b"\x00" * (need - len(chunk))
        outdata[:] = chunk

    def start(self) -> None:
        self.stream.start()

    def play(self, pcm: bytes) -> None:
        with self._sync:
            self._buffer.extend(pcm)

    def clear(self) -> None:
        with self._sync:
            self._buffer.clear()

    def close(self) -> None:
        self.stream.stop()
        self.stream.close()


async def send_mic(session, rate: int, stop: asyncio.Event) -> None:
    loop = asyncio.get_running_loop()
    audio_queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=32)
    blocksize = rate * CHUNK_MS // 1000

    def enqueue(pcm: bytes) -> None:
        # Runs on the event loop, so QueueFull is raised here rather than in the audio thread.
        try:
            audio_queue.put_nowait(pcm)
        except asyncio.QueueFull:
            pass

    def on_audio(indata, _frames, _time, status) -> None:
        if status:
            print(f"mic: {status}", file=sys.stderr)
        loop.call_soon_threadsafe(enqueue, bytes(indata))

    stream = sd.RawInputStream(
        samplerate=rate,
        channels=1,
        dtype="int16",
        callback=on_audio,
        blocksize=blocksize,
    )
    with stream:
        while not stop.is_set():
            pcm = await audio_queue.get()
            await session.send_audio(pcm)


def print_user(text: str) -> None:
    text = text.strip()
    if text:
        print(f"\nyou> {text}")


def print_loom(text: str) -> None:
    text = " ".join(text.split())
    if text:
        print(f"loom> {text}\n")


async def receive(session, speaker: Speaker, stop: asyncio.Event, check_only: bool, missing_audio: list[bool]) -> None:
    try:
        await _receive_events(session, speaker, stop, check_only, missing_audio)
    finally:
        # However the event stream ends (including a dropped connection), let the conversation exit.
        stop.set()


async def _receive_events(
    session, speaker: Speaker, stop: asyncio.Event, check_only: bool, missing_audio: list[bool]
) -> None:
    heard_audio = False
    stopping = False
    async for event in session.events():
        kind = event.get("type", "")

        if kind == "error":
            print(f"API error: {event.get('message', event)}", file=sys.stderr)
            stop.set()
            return

        if kind == "interrupted":
            speaker.clear()
            continue

        if kind == "transcript.final":
            text = event.get("text") or ""
            if event.get("role") == "user":
                print_user(text)
            else:
                print_loom(text)
            continue

        if kind == "audio.delta":
            payload = event.get("data")
            if payload:
                speaker.play(base64.b64decode(payload))
                heard_audio = True
            continue

        if kind == "response.done" and check_only and not stopping:
            if not heard_audio:
                print("Connected, but no audio came back.", file=sys.stderr)
                missing_audio.append(True)
                stop.set()
                return
            stopping = True
            await session.send_json({"type": "stop"})
            continue

        if kind == "session.ended":
            stop.set()
            return


async def conversation(model: str, voice: str, session_name: str, new_thread: bool, check_only: bool) -> None:
    loom = LoomSession.from_env()
    realtime = await loom.connect_voice(
        session=session_name,
        new_thread=new_thread,
        voice=voice,
        model=model,
        system_prompt=INSTRUCTIONS,
    )
    input_format = realtime.input_format or {}
    output_format = realtime.output_format or {}
    input_rate = int(input_format.get("sample_rate", SAMPLE_RATE))
    output_rate = int(output_format.get("sample_rate", SAMPLE_RATE))
    stop = asyncio.Event()
    async with realtime:
        # Opening audio inside the session means a missing output device still closes the connection.
        speaker = Speaker(output_rate)
        speaker.start()
        try:
            print(f"Connected to {model} as {voice}.")
            print(f"thread_id={realtime.thread_id}")
            if not check_only:
                print("Use headphones, then just start talking after the greeting. Ctrl+C to quit.")
            await realtime.send_text(GREETING)
            missing_audio: list[bool] = []
            tasks = [asyncio.create_task(receive(realtime, speaker, stop, check_only, missing_audio))]
            if not check_only:
                tasks.append(asyncio.create_task(send_mic(realtime, input_rate, stop)))
            if check_only:
                await asyncio.wait_for(stop.wait(), timeout=60)
            else:
                await stop.wait()
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            if missing_audio:
                raise SystemExit(1)
            if not check_only:
                try:
                    await realtime.send_json({"type": "stop"})
                except Exception:
                    pass  # The connection may already be gone; closing the session below still runs.
        finally:
            speaker.close()


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass
    load_env(ENV_PATH)
    parser = argparse.ArgumentParser(description="Talk to Grok by voice.")
    parser.add_argument("--model", default="grok-voice-latest")
    parser.add_argument("--voice", default="eve")
    parser.add_argument("--session", default="default", help="Backboard thread to continue")
    parser.add_argument("--new", action="store_true", help="Start a new thread on the saved assistant")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Request one spoken greeting and exit, without opening the microphone.",
    )
    args = parser.parse_args()
    try:
        asyncio.run(conversation(args.model, args.voice, args.session, args.new, args.check))
    except KeyboardInterrupt:
        print("\nBye.")
    except (RuntimeError, BackboardAPIError, sd.PortAudioError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
