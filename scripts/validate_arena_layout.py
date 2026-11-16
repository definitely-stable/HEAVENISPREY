#!/usr/bin/env python3
"""ADR-015: arena 07 "Руины секты Юнхэ" after REF-033 (stage.jade_grove topology).

Checks the drawn grid (tools/content/arena_layout.py) with the GAME-ARCH-02 topology rules (no
isolated pockets, no long 1-wide corridors, a spawn point far enough from any cell, a clear boss
circle) and with the rules of the board: raised wings are climbed only by stairs, six spawn
points on the main loop, two entries, a ring of ruins with gaps around the seal, and a field
at least three times the P0 rectangle. Design-only, stdlib only.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOPOLOGY = ROOT / ".work/proposals/arena-07-sect-ruins/topology.json"
_spec = importlib.util.spec_from_file_location("hip_encounter", ROOT / "scripts/validate_encounter_proposal.py")
encounter = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(encounter)

ContractError = encounter.ContractError
must = encounter.must
WALK = ".HB^SE"
BLOCK = "w# "
P0_FIELD_CELLS = 32 * 20
MIN_FIELD_FACTOR = 3
LOOP_SPAWNS = 6
ENTRIES = 2
SEAL_RING = (9.6, 12.2)
SEAL_RING_BLOCKED = (0.3, 0.7)
STEPS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def load(path: Path = TOPOLOGY) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def terrain(data: dict) -> list[str]:
    """The grid in the GAME-ARCH-02 alphabet: '#' blocks, 'S' spawn lane, '.' walkable."""
    return ["".join("#" if ch in BLOCK else ("S" if ch == "S" else ".") for ch in row) for row in data["rows"]]


def verify(data: dict) -> dict:
    for key in ("schema_version", "kind", "stage_id", "legend", "cell_px", "cells", "centre", "boss_radius_cells",
                "start", "entries", "rows"):
        must(key in data, "E_SCHEMA", f"missing {key}")
    must(data["kind"] == "stage_topology", "E_SCHEMA", "kind is not stage_topology")
    rows = data["rows"]
    w, h = data["cells"]
    must(len(rows) == h and all(len(r) == w for r in rows), "E_TERRAIN", "rows do not match cells")
    must(set("".join(rows)) <= set(data["legend"]), "E_TERRAIN", "unknown terrain symbol")

    def at(x: int, y: int) -> str:
        return rows[y][x] if 0 <= x < w and 0 <= y < h else " "

    # GAME-ARCH-02: pockets, corridors, spawn distance, boss circle.
    fx = encounter.load()
    fx["topology"] = {
        "terrain": terrain(data), "soft_speed_multiplier": fx["topology"]["soft_speed_multiplier"],
        "legend": fx["topology"]["legend"], "player_start": data["start"],
        "boss_arena": {"center": data["centre"], "radius_cells": data["boss_radius_cells"]},
    }
    topo = encounter.check_topology(fx)
    # The board: wings are climbed by their stairs only.
    for y in range(h):
        for x in range(w):
            if rows[y][x] == "H":
                for a, b in STEPS:
                    must(at(x + a, y + b) != ".", "E_HEIGHT", f"raised floor {(x, y)} meets the court without stairs")
    walkable = sum(row.count(ch) for row in rows for ch in WALK)
    must(walkable >= MIN_FIELD_FACTOR * P0_FIELD_CELLS, "E_SIZE",
         f"{walkable} walkable cells, under {MIN_FIELD_FACTOR} x the P0 field")
    spawns = [(x, y) for y in range(h) for x in range(w) if rows[y][x] == "S"]
    loop = [s for s in spawns if any(at(s[0] + a, s[1] + b) == "." for a, b in STEPS)]
    must(len(loop) >= LOOP_SPAWNS, "E_SPAWN_POINTS", f"{len(loop)} spawn points on the main loop")
    entries = [(x, y) for y in range(h) for x in range(w) if rows[y][x] == "E"]
    must(len(entries) == ENTRIES and [list(e) for e in entries] == data["entries"], "E_ENTRIES", "two entries listed")
    must(tuple(data["start"]) in entries, "E_ENTRIES", "the start is not an entry")
    cx, cy = data["centre"]
    ring = [(x, y) for y in range(h) for x in range(w) if SEAL_RING[0] <= math.hypot(x - cx, y - cy) <= SEAL_RING[1]]
    blocked = sum(1 for x, y in ring if rows[y][x] in BLOCK) / max(1, len(ring))
    must(SEAL_RING_BLOCKED[0] <= blocked <= SEAL_RING_BLOCKED[1], "E_SEAL_RING",
         f"ruins cover {blocked:.0%} of the ring around the seal")
    return {"cells": [w, h], "walkable_cells": walkable, "field_factor": round(walkable / P0_FIELD_CELLS, 2),
            "max_corridor": topo["max_corridor"], "spawn_points": len(spawns), "loop_spawns": len(loop),
            "entries": len(entries), "seal_ring_blocked": round(blocked, 2)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ADR-015 arena 07 topology")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = verify(load())
    except ContractError as error:
        print(f"FAIL: {error}")
        return 1
    print(json.dumps(result, ensure_ascii=False) if args.json else f"PASS: arena 07 after REF-033 {json.dumps(result)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
