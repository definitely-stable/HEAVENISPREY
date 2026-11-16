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

from PIL import Image, ImageDraw

SIZE = (1536, 1024)
KEY = (0, 255, 0)
TOP, LEFT, RIGHT, EDGE = (150, 146, 160), (110, 104, 122), (62, 58, 72), (40, 36, 48)

# Per sheet: blocks [centre x, lowest point y, [[width, height], ...] bottom to top] and guide
# ellipses [centre x, centre y offset from the top face of the block, half width, half height].
LAYOUTS: dict[str, list[dict]] = {
    "courtyard_guardians": [
        {"x": 384, "y": 485, "blocks": [[300, 22], [250, 84], [280, 20]], "seat": [80, 27]},
        {"x": 1152, "y": 485, "blocks": [[300, 22], [250, 84], [280, 20]], "seat": [80, 27]},
        {"x": 384, "y": 1004, "blocks": [[170, 34], [130, 290], [165, 26]]},
        {"x": 1152, "y": 1004, "blocks": [[170, 34], [130, 140]]},
    ],
}


def block(draw: ImageDraw.ImageDraw, cx: float, by: float, width: float, height: float) -> float:
    """A square block with its front corner at (cx, by); returns the y of its top face centre."""
    a, b = width / 2, width / 4
    draw.polygon([(cx - a, by - b), (cx, by), (cx, by - height), (cx - a, by - b - height)], fill=LEFT, outline=EDGE)
    draw.polygon([(cx, by), (cx + a, by - b), (cx + a, by - b - height), (cx, by - height)], fill=RIGHT, outline=EDGE)
    draw.polygon([(cx, by - height), (cx - a, by - b - height), (cx, by - 2 * b - height), (cx + a, by - b - height)],
                 fill=TOP, outline=EDGE)
    return by - b - height


def render(name: str) -> Image.Image:
    image = Image.new("RGB", SIZE, KEY)
    draw = ImageDraw.Draw(image)
    for prop in LAYOUTS[name]:
        cx, by = prop["x"], prop["y"]
        centre = None
        for width, height in prop["blocks"]:
            if centre is not None:
                by = centre + width / 4  # coaxial: the next block stands on the centre of this one
            centre = block(draw, cx, by, width, height)
        if "seat" in prop:
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
