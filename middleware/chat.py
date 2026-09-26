"""Loom chat over Backboard.

The first message creates a thread and assistant. Later messages pass that thread_id
and memory="Auto", matching the Backboard quickstart. Ids are saved in
.session_state.json so the conversation survives restarts.

Usage:
  python chat.py demo                 run the two-message quickstart
  python chat.py                      interactive Loom interview
  python chat.py ask "your prompt"    one turn on the default session
  python chat.py reset                forget the assistant, threads, and memories binding
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from loom_session import LOOM_SYSTEM_PROMPT, LoomSession


async def demo(session: LoomSession) -> None:
    first = await session.send("Hello! I'm excited to get started.", session="demo", new_thread=True)
    print(first.content)
    print(f"\nthread_id={first.thread_id}")

    follow_up = await session.send("What can you help me with?", session="demo")
    print(f"\n{follow_up.content}")


async def one_shot(session: LoomSession, prompt: str, name: str, new_thread: bool) -> None:
    reply = await session.send(prompt, session=name, new_thread=new_thread, system_prompt=LOOM_SYSTEM_PROMPT)
    print(reply.content)


async def repl(session: LoomSession, name: str) -> None:
    print(f"Loom session '{name}'. /quit exits, /new starts a new thread on the same assistant.")
    start_new_thread = False
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
        if prompt == "/new":
            start_new_thread = True
            print("Next message starts a new thread. Shared memory stays on this assistant.")
            continue
        reply = await session.send(
            prompt,
            session=name,
            new_thread=start_new_thread,
            system_prompt=LOOM_SYSTEM_PROMPT,
        )
        start_new_thread = False
        print(f"loom> {reply.content}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Talk to Loom through Backboard memory.")
    parser.add_argument("--session", default="default", help="Named thread to continue")
    parser.add_argument("--new", action="store_true", help="Start a new thread on the saved assistant")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("demo", help="Send the two quickstart messages")
    ask = sub.add_parser("ask", help="Send one prompt and print the reply")
    ask.add_argument("prompt")
    sub.add_parser("reset", help="Clear saved assistant and thread ids")
    args = parser.parse_args()

    try:
        session = LoomSession.from_env()
    except RuntimeError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error

    if args.command == "reset":
        session.reset()
        print("Cleared saved Backboard session.")
        return

    try:
        if args.command == "demo":
            asyncio.run(demo(session))
        elif args.command == "ask":
            asyncio.run(one_shot(session, args.prompt, args.session, args.new))
        else:
            asyncio.run(repl(session, args.session))
    except Exception as error:
        print(f"Backboard request failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
