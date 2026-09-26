"""Minimal .env loader shared by the middleware and the sandbox scripts."""

from __future__ import annotations

import os
from pathlib import Path

MIDDLEWARE_ENV_PATH = Path(__file__).with_name(".env")


def load_env(path: Path = MIDDLEWARE_ENV_PATH) -> None:
    """Load KEY=VALUE lines into os.environ without overriding variables that are already set.

    Quoted values are taken literally. Unquoted values drop a trailing ` # comment`.
    """
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("export "):
            line = line[len("export ") :].lstrip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), _parse_value(value.strip()))


def _parse_value(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    comment = value.find(" #")
    if comment != -1:
        value = value[:comment]
    return value.strip()


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value or value == "your-key-here":
        raise RuntimeError(f"Set {name} in middleware/.env")
    return value
