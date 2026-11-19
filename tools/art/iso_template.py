"""Geometry template for prop sheets in the camera of the arena (ADR-014 section 1, ADR-015 section 9).

The floor is a 2:1 isometric projection: a square base on the ground stands corner-on to the viewer,
its top is a diamond twice as wide as it is tall, both visible side faces are equally wide and every
horizontal edge rises 1 px per 2 px sideways. Image generation drifts towards a front view of a
base, which does not lie on the map, so a sheet is painted over this template: grey stacked blocks
on the chroma key at the place, size and angle of each prop. The left face is lit (light from the
upper left).

    python tools/art/iso_template.py courtyard_guardians out.png

The fragments of the ruin ring around the seal (ADR-015 section 11) are drawn from the arena file
itself, two per sheet (seal_ruins_1 .. seal_ruins_3): the footprint of each fragment's cells flat
on the ground, the broken wall along the middle of the ring and the pillar stumps on its solid
cells, all at one scale, so the painted fragment fits its cells exactly.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SIZE = (1536, 1024)
KEY = (0, 255, 0)
TOP, LEFT, RIGHT, EDGE = (150, 146, 160), (110, 104, 122), (62, 58, 72), (40, 36, 48)

# Per sheet: blocks [centre x, lowest point y, [[width, height], ...] bottom to top], guide
# ellipses [centre x, centre y offset from the top face of the block, half width, half height] and
# flat front elevations ("flat": [width, height] standing on (x, y)).
LAYOUTS: dict[str, list[dict]] = {
    "courtyard_guardians": [
        {"x": 384, "y": 485, "blocks": [[300, 22], [250, 84], [280, 20]], "seat": [80, 27]},
        {"x": 1152, "y": 485, "blocks": [[300, 22], [250, 84], [280, 20]], "seat": [80, 27]},
        {"x": 384, "y": 1004, "blocks": [[170, 34], [130, 290], [165, 26]]},
        {"x": 1152, "y": 1004, "blocks": [[170, 34], [130, 140]]},
    ],
    # ADR-015 section 10: a balustrade post, the post broken, a heap of ruin on one cell and the
    # flat front elevation of one rail bay (it is drawn on a vertical plane between two posts).
    "courtyard_balustrade": [
        {"x": 384, "y": 480, "blocks": [[150, 26], [112, 230], [146, 22], [90, 40]]},
        {"x": 1152, "y": 480, "blocks": [[150, 26], [112, 120]]},
        {"x": 384, "y": 1000, "blocks": [[380, 30], [230, 40]]},
        {"x": 1152, "y": 980, "flat": [600, 375]},
    ],
    # Stone posts sit on the run corners and terminals. The two elevations are sampled on planes.
    "jade_grove_masonry": [
        {"x": 384, "y": 435, "blocks": [[228, 43], [180, 112], [214, 32]]},
        {"x": 1152, "y": 435, "blocks": [[183, 36], [146, 88], [178, 26]]},
        {"x": 384, "y": 886, "flat": [582, 170]},
        {"x": 1152, "y": 886, "flat": [582, 188]},
    ],
    "jade_grove_rail_details": [
        {"x": 384, "y": 435, "blocks": [[335, 59], [306, 24]]},
        {"x": 1152, "y": 435, "blocks": [[236, 42], [189, 102], [218, 27]]},
        {"x": 384, "y": 886, "flat": [582, 170]},
        {"x": 1152, "y": 886, "flat": [582, 152]},
    ],
    "jade_grove_rail_finishes": [
        {"x": 384, "y": 435, "blocks": [[214, 34], [152, 124], [196, 33]]},
        {"x": 1152, "y": 465, "blocks": [[202, 32], [132, 87], [166, 103], [205, 42]]},
        {"x": 384, "y": 886, "flat": [582, 176]},
        {"x": 1152, "y": 886, "flat": [582, 164]},
    ],
    # ADR-015 section 12, REF-068: the seal ring and the parapet, at 3.73 sheet px per screen px
    # (1.6 times the guardians: small props need the room for detail). A brazier on one cell
    # (pedestal to the hero's waist, the bowl on the ellipse), a stone pagoda lantern on one cell
    # (stepped base, shaft, platform, light box; the roof is painted above it) and a broken pillar
    # on two by two cells (1.3 hero heights).
    "courtyard_ring": [
        {"x": 256, "y": 990, "blocks": [[227, 22], [186, 118], [211, 19]], "seat": [99, 32]},
        {"x": 768, "y": 990, "blocks": [[227, 22], [179, 29], [86, 179], [179, 19], [134, 106]]},
        {"x": 1280, "y": 990, "blocks": [[374, 45], [285, 314]]},
    ],
}

# Columns and rows of the sheet grid (build_sprites `sheet.grid`) when not 2 x 2.
GRIDS: dict[str, tuple[int, int]] = {"courtyard_ring": (3, 1)}


Point = tuple[float, float]


def faces(cx: float, by: float, width: float, height: float) -> dict[str, list[Point]]:
    """The visible faces of a square block with its front corner at (cx, by)."""
    a, b = width / 2, width / 4
    return {
        "left": [(cx - a, by - b), (cx, by), (cx, by - height), (cx - a, by - b - height)],
        "right": [(cx, by), (cx + a, by - b), (cx + a, by - b - height), (cx, by - height)],
        "top": [(cx, by - height), (cx - a, by - b - height), (cx, by - 2 * b - height), (cx + a, by - b - height)],
    }


def blocks(prop: dict) -> list[dict[str, list[Point]]]:
    """The faces of the stacked blocks of a prop, bottom to top; each next block stands coaxially on
    the centre of the top face of the one below. A flat prop has none."""
    out = []
    cx, by = prop["x"], prop["y"]
    for width, height in prop.get("blocks", []):
        if out:
            top = out[-1]["top"]
            by = (top[0][1] + top[2][1]) / 2 + width / 4
        out.append(faces(cx, by, width, height))
    return out


def flat_rect(prop: dict) -> tuple[float, float, float, float] | None:
    """The front elevation (x0, y0, x1, y1) of a flat prop, bottom centre at (x, y); None for a
    prop of blocks."""
    if "flat" not in prop:
        return None
    width, height = prop["flat"]
    return (prop["x"] - width / 2, prop["y"] - height, prop["x"] + width / 2, prop["y"])


# --- ADR-015 section 11: the six fragments of the ruin ring around the seal ---

# The arena grid the ruin sheets were painted for: the ring of jade_grove.json before ADR-015
# section 12 opened the court (the fragments now wait in reserve for ruins at the edge). GUT
# checks the atlas against the same file.
ARENA = Path(__file__).resolve().parents[2] / "game" / "tests" / "fixtures" / "seal_ring_layout.json"
RUIN_PROP = "seal_ruin"
CELL_PX = 48
ISO_K = math.sqrt(2.0) / 2.0
## The ring of arena_layout.py (step 5): fragment i spans RING_START + RING_STEP * i degrees and
## RING_SPAN more; its ends (RING_END degrees) are pillars.
RING_START, RING_STEP, RING_SPAN, RING_END = 15.0, 60.0, 26.0, 4.0
## The broken wall: along the middle of the ring (cells from the seal), its thickness (cells) and
## height (screen px, 0.48 hero heights: it blocks movement, not sight). On each group of solid
## cells a broken pillar (1.3 hero heights, it blocks shots) on the cell nearest the middle of the
## ring, inset from the cell edge (cells), standing in the fallen masonry of its base that covers
## the rest of the group (0.4 hero heights).
WALL_RADIUS, WALL_THICK, WALL_PX = 10.9, 0.8, 40.0
PILLAR_PX, PILLAR_INSET, PILLAR_BASE_PX = 110.0, 0.1, 32.0
RUIN_SHEETS = 3
FLOOR = (178, 174, 188)
## Share of a half sheet (one fragment) the largest fragment fills.
RUIN_FILL = 0.84


def iso_screen(wx: float, wy: float) -> Point:
    """Screen px of a world point given in cells (IsoProjection.to_screen of the game)."""
    return ((wx - wy) * CELL_PX * ISO_K, (wx + wy) * CELL_PX * ISO_K / 2.0)


def load_arena(path: Path = ARENA) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def ruin_index(at: list[float], centre: list[int]) -> int:
    """Which fragment of the ring a seal_ruin prop at `at` (cells) is: its turn from RING_START."""
    angle = math.degrees(math.atan2(at[1] - centre[1] - 0.5, at[0] - centre[0] - 0.5))
    return int(((angle - RING_START) % 360.0) // RING_STEP)


def ruin_cells(rows: list[str], at: list[float]) -> list[tuple[int, int]]:
    """The wall cells ('w' and '#', eight neighbours) of the fragment nearest to `at` (cells)."""
    walls = {(x, y) for y, row in enumerate(rows) for x, ch in enumerate(row) if ch in "w#"}
    start = min(walls, key=lambda c: ((c[0] + 0.5 - at[0]) ** 2 + (c[1] + 0.5 - at[1]) ** 2, c[1], c[0]))
    seen, todo = {start}, [start]
    while todo:
        x, y = todo.pop()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (x + dx, y + dy)
                if n in walls and n not in seen:
                    seen.add(n)
                    todo.append(n)
    return sorted(seen, key=lambda c: (c[1], c[0]))


def ruins(data: dict | None = None) -> list[dict]:
    """The fragments in ring order: {index, at (cells), cells, solid (the '#' cells)}."""
    data = data or load_arena()
    rows, centre = data["rows"], data["centre"]
    out = []
    for item in data["props"]:
        if item["prop"] == RUIN_PROP:
            cells = ruin_cells(rows, item["at"])
            out.append({"index": ruin_index(item["at"], centre), "at": item["at"], "cells": cells,
                        "solid": [c for c in cells if rows[c[1]][c[0]] == "#"]})
    return sorted(out, key=lambda r: r["index"])


def _wall_band(centre: list[int], index: int) -> list[Point]:
    """The broken wall as a polygon in cells: an arc band from the middle of one end pillar to the
    middle of the other."""
    cx, cy = centre[0] + 0.5, centre[1] + 0.5
    a0 = RING_START + RING_STEP * index + RING_END / 2.0
    a1 = RING_START + RING_STEP * index + RING_SPAN - RING_END / 2.0
    steps = 24
    outer, inner = [], []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        outer.append((cx + (WALL_RADIUS + WALL_THICK / 2) * math.cos(a), cy + (WALL_RADIUS + WALL_THICK / 2) * math.sin(a)))
        inner.append((cx + (WALL_RADIUS - WALL_THICK / 2) * math.cos(a), cy + (WALL_RADIUS - WALL_THICK / 2) * math.sin(a)))
    return outer + inner[::-1]


def _prism(base: list[Point], height: float) -> list[tuple[float, list[tuple[Point, float]], str | tuple]]:
    """Visible faces of an upright prism on `base` (cells): [(depth, [(world point, lift px)],
    fill)], sides far to near, then the top. A side faces the viewer when its outward normal
    points down the screen; it is lit as it turns to the screen left (light from the upper left)."""
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(base, base[1:] + base[:1]))
    faces = []
    for a, b in zip(base, base[1:] + base[:1]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        nx, ny = (dy, -dx) if area > 0 else (-dy, dx)
        if nx + ny <= 1e-9:
            continue
        length = math.hypot(nx, ny)
        t = (1.0 - (nx - ny) / (length * math.sqrt(2.0))) / 2.0
        fill = tuple(round(r + (l - r) * t) for l, r in zip(LEFT, RIGHT))
        faces.append((a[0] + a[1] + b[0] + b[1], [(a, 0.0), (b, 0.0), (b, height), (a, height)], fill))
    faces.sort(key=lambda f: f[0])
    top = (math.inf, [(p, height) for p in base], TOP)
    return faces + [top]


FENCE_SCALE = 2.5
FENCE_ANCHORS = ((151, 285), (862, 328), (374, 697), (1152, 790))


def fence_sheet():
    """Whole modules at one screen scale, including the actual turn beside the gate lion."""
    from PIL import Image, ImageDraw

    image = Image.new("RGB", SIZE, KEY)
    draw = ImageDraw.Draw(image)

    def prism(slot, a, b, half_width, lift, height, wood=False):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy * half_width / length, dx * half_width / length
        base = [(a[0] - nx, a[1] - ny), (b[0] - nx, b[1] - ny),
                (b[0] + nx, b[1] + ny), (a[0] + nx, a[1] + ny)]
        x, y = FENCE_ANCHORS[slot]
        for _, face, tone in _prism(base, height):
            points = [(x + u * FENCE_SCALE, y + (v - z - lift) * FENCE_SCALE)
                      for world, z in face for u, v in [iso_screen(*world)]]
            fill = tuple(round(c * s) for c, s in zip(tone, (1.24, 0.72, 0.63))) if wood else tone
            draw.polygon(points, fill=fill, outline=EDGE)

    def pier(slot, at, height):
        x, y = at
        for radius, lift, rise in ((0.34, 0, 5), (0.25, 5, height - 11), (0.33, height - 6, 6)):
            prism(slot, (x - radius, y), (x + radius, y), radius, lift, rise)

    left, turn, near, end = (-1.59, -2.0), (0.0, 0.0), (3.205, -0.085), (4.0, -1.0)
    pier(0, left, 30)
    prism(0, left, turn, 0.29, 0, 14)
    prism(0, left, turn, 0.34, 14, 5)
    for a, b in ((turn, near), (near, end)):
        prism(0, a, b, 0.30, 0, 6)
        for lift, height, width in ((8, 4, 0.08), (19, 4, 0.08), (31, 5, 0.13)):
            prism(0, a, b, width, lift, height, wood=True)
    for at, height in ((turn, 44), (near, 44), (end, 40)):
        pier(0, at, height)

    start, finish = (0.0, 0.0), (2.0, -2.0)
    prism(1, start, finish, 0.28, 0, 6)
    prism(1, start, finish, 0.19, 30, 5)
    for t in (0.5, 0.94):
        x, y = 2 * t, -2 * t
        prism(1, (x - 0.105, y + 0.105), (x + 0.105, y - 0.105), 0.16, 6, 24)
    pier(1, start, 39)

    for i in range(2):
        a, b = (float(i), float(i)), (i + 1.0, i + 1.0)
        prism(2, a, b, 0.34, 0, 5)
        prism(2, a, b, 0.25, 5, 12)
        prism(2, (i + 0.025, i + 0.025), (i + 0.975, i + 0.975), 0.32, 17, 5)
        if i == 0:
            prism(2, (0.86, 0.62), (1.10, 0.86), 0.24, 0, 16)
            prism(2, (0.82, 0.58), (1.14, 0.90), 0.28, 16, 4)

    prism(3, (-0.50, -0.50), (0.50, 0.50), 0.32, 0, 4)
    prism(3, (-0.41, -0.41), (0.41, 0.41), 0.24, 4, 3)
    return image


def cell_groups(cells: list[tuple[int, int]]) -> list[list[tuple[int, int]]]:
    """Groups of cells joined by a side, each in row order, groups in order of their first cell."""
    left, out = set(cells), []
    for start in sorted(cells, key=lambda c: (c[1], c[0])):
        if start not in left:
            continue
        group, todo = [], [start]
        left.discard(start)
        while todo:
            x, y = todo.pop()
            group.append((x, y))
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in left:
                    left.discard(n)
                    todo.append(n)
        out.append(sorted(group, key=lambda c: (c[1], c[0])))
    return out


def pillar_cell(group: list[tuple[int, int]], centre: list[int]) -> tuple[int, int]:
    """The cell of a group of solid cells whose centre lies nearest the middle of the ring."""
    return min(group, key=lambda c: (abs(math.hypot(c[0] - centre[0], c[1] - centre[1]) - WALL_RADIUS), c[1], c[0]))


def outline(cells: list[tuple[int, int]]) -> list[Point]:
    """The outline of a group of cells joined by sides: one loop of cell corners, corners on
    straight runs dropped."""
    edges: dict[tuple[int, int], tuple[int, int]] = {}
    own = set(cells)
    for x, y in cells:
        for (dx, dy), a, b in (((0, -1), (x, y), (x + 1, y)), ((1, 0), (x + 1, y), (x + 1, y + 1)),
                               ((0, 1), (x + 1, y + 1), (x, y + 1)), ((-1, 0), (x, y + 1), (x, y))):
            if (x + dx, y + dy) not in own:
                if a in edges:
                    raise ValueError("cells that touch only at a corner have no single outline")
                edges[a] = b
    start = min(edges, key=lambda p: (p[1], p[0]))
    loop, at = [start], edges[start]
    while at != start:
        loop.append(at)
        at = edges[at]
    keep = [p for i, p in enumerate(loop)
            if (loop[i - 1][0] - p[0]) * (loop[(i + 1) % len(loop)][1] - p[1])
            != (loop[i - 1][1] - p[1]) * (loop[(i + 1) % len(loop)][0] - p[0])]
    return [(float(x), float(y)) for x, y in keep]


def ruin_shapes(ruin: dict, centre: list[int]) -> list[list[tuple[float, list[tuple[Point, float]], tuple]]]:
    """The wall, the pillar bases and the pillars of a fragment as prisms, far to near (a pillar
    right after its own base)."""
    units = [[_prism(_wall_band(centre, ruin["index"]), WALL_PX)]]
    for group in cell_groups(ruin["solid"]):
        x, y = pillar_cell(group, centre)
        i = PILLAR_INSET
        pillar = _prism([(x + i, y + i), (x + 1 - i, y + i), (x + 1 - i, y + 1 - i), (x + i, y + 1 - i)], PILLAR_PX)
        units.append(([_prism(outline(group), PILLAR_BASE_PX)] if len(group) > 1 else []) + [pillar])
    depth = [sum(p[0] + p[1] for p, _ in u[0][-1][1]) / len(u[0][-1][1]) for u in units]
    return [shape for _, unit in sorted(zip(depth, units), key=lambda z: z[0]) for shape in unit]


def _extent(ruin: dict) -> tuple[float, float, float, float]:
    """Screen box (px, unscaled, origin at the world origin) of the footprint and the stumps."""
    us, vs = [], []
    for x, y in ruin["cells"]:
        for wx, wy in ((x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)):
            u, v = iso_screen(wx, wy)
            us.append(u)
            vs.append(v)
            if (x, y) in ruin["solid"]:
                vs.append(v - PILLAR_PX)
    return min(us), min(vs), max(us), max(vs)


def ruin_layout(data: dict | None = None) -> dict:
    """{scale (sheet px per screen px), fragments: [{index, sheet (1..), slot (0 left, 1 right),
    origin (sheet px of the world origin), anchor (sheet px of the prop's `at`)}]}: one scale
    for all six, each fragment centred in its half sheet."""
    data = data or load_arena()
    items = ruins(data)
    boxes = [_extent(r) for r in items]
    half = SIZE[0] / 2
    scale = min(min(half / (b[2] - b[0]), SIZE[1] / (b[3] - b[1])) for b in boxes) * RUIN_FILL
    scale = math.floor(scale * 20) / 20
    out = []
    for n, (ruin, box) in enumerate(zip(items, boxes)):
        slot = n % 2
        ox = half * slot + half / 2 - scale * (box[0] + box[2]) / 2
        oy = SIZE[1] / 2 - scale * (box[1] + box[3]) / 2
        u, v = iso_screen(*ruin["at"])
        out.append({"index": ruin["index"], "sheet": n // 2 + 1, "slot": slot, "origin": (ox, oy),
                    "anchor": (round(ox + scale * u, 2), round(oy + scale * v, 2))})
    return {"scale": scale, "fragments": out, "ruins": items}


def ruin_polygons(sheet: int, data: dict | None = None) -> list[tuple[list[Point], tuple, bool]]:
    """Every polygon of a ruin sheet in draw order: (sheet px points, fill, outlined)."""
    data = data or load_arena()
    layout = ruin_layout(data)
    scale = layout["scale"]
    out = []
    for frag, ruin in zip(layout["fragments"], layout["ruins"]):
        if frag["sheet"] != sheet:
            continue
        ox, oy = frag["origin"]

        def at(p: Point, lift: float = 0.0) -> Point:
            u, v = iso_screen(*p)
            return (ox + scale * u, oy + scale * (v - lift))

        cells = set(ruin["cells"])
        for x, y in ruin["cells"]:
            out.append(([at((x, y)), at((x + 1, y)), at((x + 1, y + 1)), at((x, y + 1))], FLOOR, False))
        for x, y in ruin["cells"]:
            # The outline of the footprint: the cell edges no other cell of it shares.
            for (dx, dy), edge in (((0, -1), ((x, y), (x + 1, y))), ((1, 0), ((x + 1, y), (x + 1, y + 1))),
                                   ((0, 1), ((x + 1, y + 1), (x, y + 1))), ((-1, 0), ((x, y + 1), (x, y)))):
                if (x + dx, y + dy) not in cells:
                    out.append(([at(edge[0]), at(edge[1])], EDGE, True))
        for shape in ruin_shapes(ruin, data["centre"]):
            for _, face, fill in shape:
                out.append(([at(p, lift) for p, lift in face], fill, False))
    return out


def render(name: str):
    """The template as a PIL image (Pillow is needed only here)."""
    from PIL import Image, ImageDraw

    if name == "jade_grove_fence_modules":
        return fence_sheet()

    image = Image.new("RGB", SIZE, KEY)
    draw = ImageDraw.Draw(image)
    if name.startswith("seal_ruins_"):
        for points, fill, line in ruin_polygons(int(name.rsplit("_", 1)[1])):
            if line:
                draw.line(points, fill=fill, width=2)
            else:
                draw.polygon(points, fill=fill, outline=EDGE if fill != FLOOR else None)
        return image
    for prop in LAYOUTS[name]:
        rect = flat_rect(prop)
        if rect:
            draw.rectangle(rect, fill=LEFT, outline=EDGE, width=2)
        stack = blocks(prop)
        for block in stack:
            for face, fill in (("left", LEFT), ("right", RIGHT), ("top", TOP)):
                draw.polygon(block[face], fill=fill, outline=EDGE)
        if "seat" in prop:
            top = stack[-1]["top"]
            cx, centre = prop["x"], (top[0][1] + top[2][1]) / 2
            rx, ry = prop["seat"]
            draw.ellipse([cx - rx, centre - ry - 5, cx + rx, centre + ry - 5], outline=EDGE, width=2)
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sheets = sorted(LAYOUTS) + ["jade_grove_fence_modules"] + [f"seal_ruins_{n}" for n in range(1, RUIN_SHEETS + 1)]
    parser.add_argument("sheet", choices=sheets)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    render(args.sheet).save(args.out)
    print(args.out)


if __name__ == "__main__":
    main()
