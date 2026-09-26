"""Matches story hobbies to family members' passions through shared interest families."""

from __future__ import annotations

import re

_SYNONYMS: dict[str, str] = {
    "radio": "electronics",
    "ham": "electronics",
    "circuit": "electronics",
    "circuits": "electronics",
    "solder": "electronics",
    "soldering": "electronics",
    "electronics": "electronics",
    "electronic": "electronics",
    "analog": "electronics",
    "pedal": "electronics",
    "pedals": "electronics",
    "synth": "electronics",
    "synthesizer": "electronics",
    "wood": "woodworking",
    "woodworking": "woodworking",
    "joinery": "woodworking",
    "aviation": "aviation",
    "aircraft": "aviation",
    "photo": "photography",
    "photography": "photography",
    "darkroom": "photography",
}

_LABELS: dict[str, str] = {
    "electronics": "electronics and circuits",
    "woodworking": "woodworking",
    "aviation": "aviation",
    "photography": "photography",
}


def _keys(raw: str) -> set[str]:
    return {_SYNONYMS[word] for word in re.split(r"[^a-z]+", raw.lower()) if word in _SYNONYMS}


def shared_interest(hobbies: list[str], passions: list[str]) -> str | None:
    """Human-readable label for the first interest family both lists share, or None."""
    hobby_keys = set().union(*map(_keys, hobbies)) if hobbies else set()
    passion_keys = set().union(*map(_keys, passions)) if passions else set()
    common = sorted(hobby_keys & passion_keys)
    if not common:
        return None
    return _LABELS.get(common[0], common[0])
