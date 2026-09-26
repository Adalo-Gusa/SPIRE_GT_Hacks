"""HeirLoom Corkboard Family Tree Engine.

Automatically computes 2D coordinates, pushpin locations, rotation angles,
and connecting red twine strings for family members in a conspiracy-theory /
evidence corkboard aesthetic.

Hierarchical rules:
- Generation 1 placed at the top tier, propagating downwards (Gen 2, Gen 3, etc.).
- Spouses placed adjacent with spouse tension strings.
- Children centered beneath their parents with hanging twine strings.
- Organic card tilts (-3° to +3°) and pushpin offsets for authentic corkboard feel.
- Automatic relationship healing (bidirectional parents <-> children, spouse <-> spouse).
"""

from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional, Set, Tuple
from pydantic import BaseModel, Field

CARD_WIDTH = 160.0
CARD_HEIGHT = 190.0
HORIZONTAL_GAP = 50.0
SPOUSE_GAP = 28.0
TIER_HEIGHT = 270.0
TOP_PADDING = 100.0
LEFT_PADDING = 120.0


class CorkboardNode(BaseModel):
    id: str
    name: str
    generation_tier: int
    birth_year: Optional[int] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    passions: List[str] = Field(default_factory=list)
    spouse_id: Optional[str] = None
    parents: List[str] = Field(default_factory=list)
    children: List[str] = Field(default_factory=list)
    x: float
    y: float
    width: float = CARD_WIDTH
    height: float = CARD_HEIGHT
    pin_x: float
    pin_y: float
    rotation_deg: float
    pin_color: str = "red"


class CorkboardString(BaseModel):
    id: str
    type: str  # "spouse" | "parent-child" | "connection"
    from_member_id: str
    to_member_id: str
    from_x: float
    from_y: float
    to_x: float
    to_y: float
    color: str = "#d63031"  # Classic conspiracy corkboard crimson string
    sag_pixels: float = 16.0
    label: Optional[str] = None


class CorkboardTree(BaseModel):
    family_id: str
    canvas_width: float
    canvas_height: float
    nodes: List[CorkboardNode]
    strings: List[CorkboardString]
    generation_tiers: List[Dict[str, Any]] = Field(default_factory=list)


def deterministic_tilt(member_id: str) -> float:
    """Computes a subtle organic rotation between -3.2 and +3.2 degrees."""
    h = int(hashlib.md5(member_id.encode("utf-8")).hexdigest()[:6], 16)
    angle = ((h % 65) - 32) * 0.1
    return round(angle, 1)


def pick_pin_color(tier: int, member_id: str) -> str:
    """Elder pins get brass/gold, middle get red, youth get silver/cyan."""
    if tier == 1:
        return "#e1b12c"  # Brass gold pushpin
    elif tier == 2:
        return "#e84118"  # Classic red pushpin
    return "#00a8ff"  # Modern cyan/silver pushpin


def heal_relationships(members: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Ensures bidirectional consistency across spouse, parents, and children lists."""
    id_map = {m["_id"]: dict(m) for m in members}

    for mid, m in id_map.items():
        # Ensure list types
        m["parents"] = list(m.get("parents") or [])
        m["children"] = list(m.get("children") or [])

    for mid, m in id_map.items():
        # Spouse healing: if A lists B as spouse, ensure B lists A
        spouse_id = m.get("spouse_id")
        if spouse_id and spouse_id in id_map:
            if id_map[spouse_id].get("spouse_id") != mid:
                id_map[spouse_id]["spouse_id"] = mid

        # Children healing: if A lists C as child, ensure C lists A as parent
        for child_id in m.get("children", []):
            if child_id in id_map:
                if mid not in id_map[child_id]["parents"]:
                    id_map[child_id]["parents"].append(mid)

        # Parent healing: if A lists P as parent, ensure P lists A as child
        for parent_id in m.get("parents", []):
            if parent_id in id_map:
                if mid not in id_map[parent_id]["children"]:
                    id_map[parent_id]["children"].append(mid)

    # Re-infer generation tiers if missing or inconsistent
    for mid, m in id_map.items():
        if not m.get("generation_tier"):
            if m.get("parents"):
                p_tiers = [id_map[pid].get("generation_tier", 1) for pid in m["parents"] if pid in id_map]
                if p_tiers:
                    m["generation_tier"] = max(p_tiers) + 1
            elif m.get("spouse_id") and id_map.get(m["spouse_id"]):
                m["generation_tier"] = id_map[m["spouse_id"]].get("generation_tier", 1)
            elif m.get("children"):
                c_tiers = [id_map[cid].get("generation_tier", 2) for cid in m["children"] if cid in id_map]
                if c_tiers:
                    m["generation_tier"] = max(1, min(c_tiers) - 1)
            else:
                m["generation_tier"] = 1

    return list(id_map.values())


class FamilyCorkboardLayoutEngine:
    """Computes auto-oriented 2D coordinates for conspiracy corkboard visualization."""

    def __init__(self, family_id: str = "fam_clarke_001"):
        self.family_id = family_id

    def build_layout(self, raw_members: List[Dict[str, Any]]) -> CorkboardTree:
        if not raw_members:
            return CorkboardTree(
                family_id=self.family_id,
                canvas_width=1200,
                canvas_height=800,
                nodes=[],
                strings=[],
            )

        members = heal_relationships(raw_members)
        by_id = {m["_id"]: m for m in members}

        # 1. Group members by generation tier (1, 2, 3...)
        tiers_dict: Dict[int, List[Dict[str, Any]]] = {}
        for m in members:
            tier = m.get("generation_tier", 1)
            tiers_dict.setdefault(tier, []).append(m)

        sorted_tier_keys = sorted(tiers_dict.keys())
        min_tier = sorted_tier_keys[0] if sorted_tier_keys else 1
        max_tier = sorted_tier_keys[-1] if sorted_tier_keys else 1

        # 2. Arrange "Units" in each tier (Couples placed together, Singles placed cleanly)
        positioned_nodes: Dict[str, CorkboardNode] = {}
        tier_widths: Dict[int, float] = {}

        # Calculate preliminary placement
        for tier in sorted_tier_keys:
            tier_members = tiers_dict[tier]
            visited_in_tier: Set[str] = set()
            units: List[List[Dict[str, Any]]] = []

            for m in tier_members:
                mid = m["_id"]
                if mid in visited_in_tier:
                    continue
                spouse_id = m.get("spouse_id")
                if spouse_id and spouse_id in by_id and by_id[spouse_id].get("generation_tier") == tier:
                    units.append([m, by_id[spouse_id]])
                    visited_in_tier.add(mid)
                    visited_in_tier.add(spouse_id)
                else:
                    units.append([m])
                    visited_in_tier.add(mid)

            # Measure tier horizontal width
            current_x = LEFT_PADDING
            y = TOP_PADDING + (tier - min_tier) * TIER_HEIGHT

            for unit in units:
                if len(unit) == 2:
                    m1, m2 = unit
                    # Node 1
                    pos1 = self._create_node(m1, tier, current_x, y)
                    positioned_nodes[m1["_id"]] = pos1
                    current_x += CARD_WIDTH + SPOUSE_GAP

                    # Node 2 (Spouse)
                    pos2 = self._create_node(m2, tier, current_x, y)
                    positioned_nodes[m2["_id"]] = pos2
                    current_x += CARD_WIDTH + HORIZONTAL_GAP
                else:
                    m = unit[0]
                    pos = self._create_node(m, tier, current_x, y)
                    positioned_nodes[m["_id"]] = pos
                    current_x += CARD_WIDTH + HORIZONTAL_GAP

            tier_widths[tier] = current_x

        # 3. Center lower tiers under their parents if possible
        max_width = max(tier_widths.values()) if tier_widths else 1200
        canvas_width = max(max_width + LEFT_PADDING, 1300.0)
        canvas_height = TOP_PADDING + (max_tier - min_tier + 1) * TIER_HEIGHT + 140.0

        # Optional: fine-tune child centering
        for tier in sorted_tier_keys:
            if tier == min_tier:
                continue
            for m in tiers_dict[tier]:
                mid = m["_id"]
                parents = [by_id[pid] for pid in m.get("parents", []) if pid in positioned_nodes]
                if parents:
                    p_pins_x = [positioned_nodes[p["_id"]].pin_x for p in parents]
                    avg_p_x = sum(p_pins_x) / len(p_pins_x)
                    # Gentle pull toward parent center if no collision
                    current_node = positioned_nodes[mid]
                    target_x = avg_p_x - (CARD_WIDTH / 2.0)
                    # Check collision with other nodes on same tier
                    same_tier_nodes = [n for n in positioned_nodes.values() if n.generation_tier == tier and n.id != mid]
                    has_collision = any(abs(n.x - target_x) < (CARD_WIDTH + 20) for n in same_tier_nodes)
                    if not has_collision and target_x >= LEFT_PADDING:
                        current_node.x = target_x
                        current_node.pin_x = target_x + (CARD_WIDTH / 2.0)

        # 4. Generate Connecting Strings (Conspiracy Red Twine)
        strings: List[CorkboardString] = []
        created_string_pairs: Set[str] = set()

        for mid, node in positioned_nodes.items():
            m = by_id[mid]

            # A. Spouse String (Taut Crimson String with Golden Pushpins)
            spouse_id = m.get("spouse_id")
            if spouse_id and spouse_id in positioned_nodes:
                pair_key = tuple(sorted([mid, spouse_id]))
                if pair_key not in created_string_pairs:
                    created_string_pairs.add(pair_key)
                    spouse_node = positioned_nodes[spouse_id]
                    strings.append(
                        CorkboardString(
                            id=f"str_spouse_{pair_key[0]}_{pair_key[1]}",
                            type="spouse",
                            from_member_id=mid,
                            to_member_id=spouse_id,
                            from_x=node.pin_x,
                            from_y=node.pin_y,
                            to_x=spouse_node.pin_x,
                            to_y=spouse_node.pin_y,
                            color="#e74c3c",  # Vivid red cord
                            sag_pixels=8.0,   # Taut connection
                            label="Married",
                        )
                    )

            # B. Parent-Child Strings (Crimson Twine with natural gravity sag)
            for child_id in m.get("children", []):
                if child_id in positioned_nodes:
                    c_pair = (mid, child_id)
                    if c_pair not in created_string_pairs:
                        created_string_pairs.add(c_pair)
                        child_node = positioned_nodes[child_id]
                        strings.append(
                            CorkboardString(
                                id=f"str_parent_{mid}_{child_id}",
                                type="parent-child",
                                from_member_id=mid,
                                to_member_id=child_id,
                                from_x=node.pin_x,
                                from_y=node.pin_y,
                                to_x=child_node.pin_x,
                                to_y=child_node.pin_y,
                                color="#c0392b",  # Dark red detective twine
                                sag_pixels=24.0,  # Natural catenary gravity sag
                                label="Child",
                            )
                        )

        # 5. Label Generation Tiers
        tier_labels = [
            {"tier": 1, "title": "Generation 1 · Elders & Forebears", "y": TOP_PADDING - 40},
            {"tier": 2, "title": "Generation 2 · Parents & Aunts/Uncles", "y": TOP_PADDING + TIER_HEIGHT - 40},
            {"tier": 3, "title": "Generation 3 · Next Gen & Makers", "y": TOP_PADDING + 2 * TIER_HEIGHT - 40},
        ]

        return CorkboardTree(
            family_id=self.family_id,
            canvas_width=canvas_width,
            canvas_height=canvas_height,
            nodes=list(positioned_nodes.values()),
            strings=strings,
            generation_tiers=tier_labels,
        )

    def _create_node(self, member: Dict[str, Any], tier: int, x: float, y: float) -> CorkboardNode:
        mid = member["_id"]
        tilt = deterministic_tilt(mid)
        pin_color = pick_pin_color(tier, mid)
        pin_x = x + (CARD_WIDTH / 2.0)
        pin_y = y + 14.0

        return CorkboardNode(
            id=mid,
            name=member.get("name", "Unknown Member"),
            generation_tier=tier,
            birth_year=member.get("birth_year"),
            avatar_url=member.get("avatar_url"),
            bio=member.get("bio"),
            passions=member.get("passions", []),
            spouse_id=member.get("spouse_id"),
            parents=member.get("parents", []),
            children=member.get("children", []),
            x=round(x, 1),
            y=round(y, 1),
            width=CARD_WIDTH,
            height=CARD_HEIGHT,
            pin_x=round(pin_x, 1),
            pin_y=round(pin_y, 1),
            rotation_deg=tilt,
            pin_color=pin_color,
        )
