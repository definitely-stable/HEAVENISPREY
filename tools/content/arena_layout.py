#!/usr/bin/env python3
"""Arena 07 "Руины секты Юнхэ" (REF-033): the walkable grid of stage.jade_grove, drawn after the
collision, loop and spawn panels of the board (ADR-015).

Writes game/content/arena/jade_grove.json, the arena the simulation and the scene load (ADR-015
A1); `--check` fails when the file differs from what this script draws. Stdlib only.

Legend: '.' floor, 'H' raised floor, '^' stairs, 'B' bridge, 'S' spawn point, 'E' entry / start,
'w' low wall, balustrade or ruin (blocks movement, not sight), '#' solid (pillar, statue, brazier
column, building: blocks movement and shots), ' ' void (cliff, mist).

Features are placed in the screen axes of the 2:1 projection (IsoProjection), relative to the
seal at the centre: u = dx - dy runs to the screen right, v = dx + dy down the screen; the back
with the gate is v < 0. Cell (0, 0) is the top of the screen.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/content/arena/jade_grove.json"
CELL_PX = 48
BOSS_RADIUS_CELLS = 7
SIDE = 76
WALK = ".HB^SE"
STEPS = ((1, 0), (-1, 0), (0, 1), (0, -1))
LEGEND = {
    ".": "floor", "H": "raised floor", "^": "stairs", "B": "bridge", "S": "spawn point (floor)",
    "E": "entry / start (floor)", "w": "low wall, balustrade, ruin: blocks movement, not sight",
    "#": "solid: blocks movement and shots", " ": "void",
}


class Canvas:
    """A square grid of SIDE cells with the seal at its centre."""

    def __init__(self) -> None:
        self.c = SIDE // 2
        self.g = [[" "] * SIDE for _ in range(SIDE)]
        self.props: list[tuple[str, float, float]] = []

    def uv(self, x: int, y: int) -> tuple[int, int]:
        dx, dy = x - self.c, y - self.c
        return dx - dy, dx + dy

    def cells(self):
        return ((x, y) for y in range(SIDE) for x in range(SIDE))

    def fill(self, pred, ch: str) -> None:
        for x, y in self.cells():
            if pred(*self.uv(x, y)):
                self.g[y][x] = ch

    def block(self, u: int, v: int, ch: str, size: int = 2, prop: str = "") -> None:
        """size x size cells whose top cell sits at screen (u, v); a named prop stands on it."""
        x0, y0 = self.c + (u + v) // 2, self.c + (v - u) // 2
        for a in range(size):
            for b in range(size):
                self.g[y0 + b][x0 + a] = ch
        if prop:
            self.props.append((prop, x0 + size / 2, y0 + size / 2))

    def region_prop(self, pred, prop: str) -> None:
        """A prop at the centre of the cells where pred(u, v) holds."""
        cells = [(x, y) for x, y in self.cells() if pred(*self.uv(x, y))]
        self.props.append((prop, sum(x for x, _ in cells) / len(cells) + 0.5,
                           sum(y for _, y in cells) / len(cells) + 0.5))

    def touches(self, x: int, y: int, chars: str) -> bool:
        for a, b in STEPS:
            xx, yy = x + a, y + b
            inside = 0 <= xx < SIDE and 0 <= yy < SIDE
            if (self.g[yy][xx] if inside else " ") in chars:
                return True
        return False

    def mark(self, where, ch: str) -> None:
        for x, y in [cell for cell in self.cells() if where(*cell)]:
            self.g[y][x] = ch


def draw() -> dict:
    """The grid of arena 07 with its metadata."""
    k = Canvas()
    g, c = k.g, k.c
    # 1. Courtyard: a wide octagon on screen, flat back and front, cut corners. Wings as raised
    #    floor: the gate terrace at the back, the west platform of the old maple, the west landing
    #    behind the bridge, the east and south landings.
    k.fill(lambda u, v: abs(u) <= 34 and abs(v) <= 30 and abs(u) * 0.62 + abs(v) <= 42, ".")
    k.fill(lambda u, v: -42 <= v <= -30 and -8 <= u <= 22, "H")
    k.fill(lambda u, v: -26 <= v <= -14 and -48 <= u <= -32, "H")
    k.fill(lambda u, v: -2 <= v <= 3 and -54 <= u <= -32, "B")
    k.fill(lambda u, v: -8 <= v <= 9 and -64 <= u <= -54, "H")
    k.fill(lambda u, v: 10 <= v <= 24 and 33 <= u <= 48, "H")
    k.fill(lambda u, v: 30 <= v <= 42 and -20 <= u <= 2, "H")
    # 2. Parapet against the void; retaining walls where a wing meets the court.
    k.mark(lambda x, y: g[y][x] in ".HB" and k.touches(x, y, " "), "w")
    k.mark(lambda x, y: g[y][x] == "H" and k.touches(x, y, "."), "w")
    # 3. Joins: stairs and the bridge mouth through the walls.
    k.fill(lambda u, v: -32 <= v <= -27 and 2 <= u <= 12, "^")
    k.fill(lambda u, v: -24 <= v <= -17 and -37 <= u <= -30, "^")
    k.fill(lambda u, v: -1 <= v <= 2 and -36 <= u <= -30, "B")
    k.fill(lambda u, v: 13 <= v <= 20 and 30 <= u <= 37, "^")
    k.fill(lambda u, v: 27 <= v <= 33 and -14 <= u <= -4, "^")
    # 4. The gate hall, statues and columns of the wings.
    gate = (lambda u, v: -42 <= v <= -37 and 0 <= u <= 14)
    k.fill(gate, "#")
    k.region_prop(gate, "gate")
    for u, v, prop in [(-1, -30, "lion"), (15, -30, "lion"), (-6, -40, "pillar"), (20, -40, "pillar"),
                       (-17, 28, "lion"), (-1, 28, "lion"), (31, 11, "lion"), (31, 22, "lion")]:
        k.block(u, v, "#", prop=prop)
    maple = (lambda u, v: -26 <= v <= -21 and -48 <= u <= -43)
    k.fill(maple, "#")
    k.region_prop(maple, "maple_large")
    # 5. Seal ring: six ruin fragments at grid radius 9.6-12.2 with wide gaps (the inner loop runs
    #    through them), pillar ends; brazier columns between them at radius 14.5.
    for x, y in k.cells():
        dx, dy = x - c, y - c
        r = math.hypot(dx, dy)
        if 9.6 <= r <= 12.2 and g[y][x] == ".":
            a = (math.degrees(math.atan2(dy, dx)) - 15) % 60
            if a <= 26:
                g[y][x] = "#" if a <= 4 or a >= 22 else "w"
    for i in range(6):
        a = math.radians(i * 60 + 50)
        x, y = round(c + 14.5 * math.cos(a)), round(c + 14.5 * math.sin(a))
        for b in range(2):
            for d in range(2):
                g[y + b][x + d] = "#"
        k.props.append(("brazier", x + 1.0, y + 1.0))
    # 6. Pillars and obelisks along the parapet, the main loop stays at least 6 cells wide.
    for u, v in [(-26, -20), (26, -22), (-30, 12), (28, 16), (-14, -28), (18, -26), (8, 28), (-24, 22)]:
        k.block(u, v, "#", prop="pillar")
    # 7. Spawn points: six on the main loop (the red rings of REF-033), one on the south landing
    #    and one on the west platform; entries on the west and east landings.
    for degrees in (100, 160, 220, 280, 340, 40):
        x, y = round(c + 19.0 * math.cos(math.radians(degrees))), round(c + 19.0 * math.sin(math.radians(degrees)))
        if g[y][x] == ".":
            g[y][x] = "S"
    k.block(-60, 0, "E", 1)
    k.block(44, 16, "E", 1)
    k.block(-8, 38, "S", 1)
    k.block(-42, -16, "S", 1)
    # 8. Cells cut off behind statues and corners become wall: no pockets (E_ISOLATED_POCKET).
    seed = next((x, y) for x, y in k.cells() if g[y][x] == "E")
    seen, todo = {seed}, [seed]
    while todo:
        x, y = todo.pop()
        for a, b in STEPS:
            n = (x + a, y + b)
            if n not in seen and g[n[1]][n[0]] in WALK:
                seen.add(n)
                todo.append(n)
    k.mark(lambda x, y: g[y][x] in WALK and (x, y) not in seen, "w")
    # Trim to the used box.
    used = [(x, y) for x, y in k.cells() if g[y][x] != " "]
    x0, x1 = min(x for x, _ in used) - 1, max(x for x, _ in used) + 1
    y0, y1 = min(y for _, y in used) - 1, max(y for _, y in used) + 1
    rows = ["".join(g[y][x0:x1 + 1]) for y in range(y0, y1 + 1)]
    entries = [[x, y] for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "E"]
    props = [{"prop": name, "at": [round(x - x0, 2), round(y - y0, 2)]} for name, x, y in k.props]
    return {
        "schema_version": 1, "kind": "stage_topology", "status": "ADR-015",
        "stage_id": "stage.jade_grove", "reference": "REF-033", "legend": LEGEND, "cell_px": CELL_PX,
        "cells": [len(rows[0]), len(rows)], "centre": [c - x0, c - y0], "boss_radius_cells": BOSS_RADIUS_CELLS,
        "start": min(entries, key=lambda e: e[0] - e[1]), "entries": entries, "props": props, "rows": rows,
    }


def render(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Arena 07 topology after REF-033 (ADR-015)")
    parser.add_argument("--check", action="store_true", help="fail when the file differs from the drawing")
    args = parser.parse_args(argv)
    text = render(draw())
    name = OUT.relative_to(ROOT).as_posix()
    if args.check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print(f"FAIL: {name} differs from tools/content/arena_layout.py")
            return 1
        print(f"OK: {name} matches the drawing")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"written {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
