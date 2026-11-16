"""Geometry template for prop sheets in the camera of the arena (ADR-014 section 1, ADR-015 section 9).

The floor is a 2:1 isometric projection: a square base on the ground stands corner-on to the viewer,
its top is a diamond twice as wide as it is tall, both visible side faces are equally wide and every
horizontal edge rises 1 px per 2 px sideways. Image generation drifts towards a front view of a
base, which does not lie on the map, so a sheet is painted over this template: grey stacked blocks
on the chroma key at the place, size and angle of each prop. The left face is lit (light from the
upper left).

    python tools/art/iso_template.py courtyard_guardians out.png
"""
from __future__ import annotations

import argparse
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
}


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


def render(name: str):
    """The template as a PIL image (Pillow is needed only here)."""
    from PIL import Image, ImageDraw

    image = Image.new("RGB", SIZE, KEY)
    draw = ImageDraw.Draw(image)
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
    parser.add_argument("sheet", choices=sorted(LAYOUTS))
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    render(args.sheet).save(args.out)
    print(args.out)


if __name__ == "__main__":
    main()
