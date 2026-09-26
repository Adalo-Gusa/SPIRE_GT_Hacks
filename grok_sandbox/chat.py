"""Small CLI for trying the xAI Grok chat API.

Usage:
  python chat.py                     interactive chat
  python chat.py models              list models on this key
  python chat.py ask "your prompt"   one-shot reply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "middleware"))

from env import load_env  # noqa: E402

API_BASE = "https://api.x.ai/v1"
ENV_PATH = Path(__file__).with_name(".env")
# Keep in sync with DEFAULT_REASONING_MODEL in middleware/grok.py.
DEFAULT_MODEL = "grok-4.6"

def api_key() -> str:
    key = os.environ.get("XAI_API_KEY", "").strip()
    if not key or key == "your-key-here":
        print("Set XAI_API_KEY in grok_sandbox/.env", file=sys.stderr)
        raise SystemExit(1)
    return key


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        print(f"API error {error.code}: {detail}", file=sys.stderr)
        raise SystemExit(1) from error
    except urllib.error.URLError as error:
        print(f"Network error: {error.reason}", file=sys.stderr)
        raise SystemExit(1) from error


def list_models() -> None:
    payload = request("GET", "/models")
    models = payload.get("data", payload if isinstance(payload, list) else [])
    if not models:
        print(json.dumps(payload, indent=2))
        return
    for model in models:
        model_id = model.get("id", model) if isinstance(model, dict) else model
        print(model_id)


def complete(model: str, messages: list[dict]) -> str:
    payload = request(
        "POST",
        "/chat/completions",
        {"model": model, "messages": messages, "stream": False},
    )
    try:
        return payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        print(json.dumps(payload, indent=2))
        raise SystemExit(1)


def one_shot(model: str, prompt: str) -> None:
    reply = complete(
        model,
        [
            {"role": "system", "content": "You are Grok, a helpful assistant built by xAI."},
            {"role": "user", "content": prompt},
        ],
    )
    print(reply)


def repl(model: str) -> None:
    messages = [
        {"role": "system", "content": "You are Grok, a helpful assistant built by xAI."}
    ]
    print(f"Chatting with {model}. Type /quit to exit, /reset to clear history.")
    while True:
        try:
            prompt = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not prompt:
            continue
        if prompt in {"/quit", "/exit"}:
            return
        if prompt == "/reset":
            messages = messages[:1]
            print("History cleared.")
            continue
        messages.append({"role": "user", "content": prompt})
        reply = complete(model, messages)
        messages.append({"role": "assistant", "content": reply})
        print(f"grok> {reply}\n")


def main() -> None:
    load_env(ENV_PATH)
    parser = argparse.ArgumentParser(description="Test the xAI Grok chat API.")
    parser.add_argument("--model", default=os.environ.get("XAI_MODEL", DEFAULT_MODEL))
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("models", help="List models available to this API key")
    ask = sub.add_parser("ask", help="Send one prompt and print the reply")
    ask.add_argument("prompt")
    args = parser.parse_args()

    if args.command == "models":
        list_models()
    elif args.command == "ask":
        one_shot(args.model, args.prompt)
    else:
        repl(args.model)


if __name__ == "__main__":
    main()
