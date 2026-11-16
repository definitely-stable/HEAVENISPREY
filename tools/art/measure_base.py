"""Does each prop of a chroma-key sheet stand on the 2:1 floor (ADR-015 section 9)?

For every grid cell: the lower contour of the shape (the lowest opaque pixel per column), the median
slope of that contour on each side of its lowest point (a 2:1 base gives +0.5 left and -0.5 right;
a leaf or a chip does not move a median), and the width of the base over the lowest 15 % of the
rows, as the sprite builder anchors it. Run it on a fresh master before building; exit 1 when a
cell listed in --check is off by more than --tolerance.

    python tools/art/measure_base.py master.png --grid 2 2 --check 0 1 2
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SLOPE = 0.5
TOLERANCE = 0.06
INLIER_PX = 2.5


def median(values: list[float]) -> float:
    ordered = sorted(values)
    return ordered[len(ordered) // 2] if ordered else 0.0


def median_slope(bottom: list[int], start: int, stop: int) -> float:
    """Slope of the lower contour over [start, stop), robust and finer than a pixel step.

    A median of local slopes (step a quarter of the range) ignores leaves and chips but is
    quantised to 1 / step, which on a small base (a 16 px step) is coarser than the tolerance.
    So it only seeds a line; the columns within INLIER_PX of that line are refitted by least
    squares twice, and a leaf or a chip off the edge never enters the fit."""
    step = max(4, (stop - start) // 4)
    xs = [x for x in range(start, stop) if bottom[x] >= 0]
    slope = median([(bottom[x + step] - bottom[x]) / step for x in range(start, stop - step)
                    if bottom[x] >= 0 and bottom[x + step] >= 0])
    for _ in range(2):
        offset = median([bottom[x] - slope * x for x in xs])
        inliers = [x for x in xs if abs(bottom[x] - slope * x - offset) <= INLIER_PX]
        if len(inliers) < 8:
            break
        mean_x = sum(inliers) / len(inliers)
        mean_y = sum(bottom[x] for x in inliers) / len(inliers)
        spread = sum((x - mean_x) ** 2 for x in inliers)
        if spread == 0:
            break
        slope = sum((x - mean_x) * (bottom[x] - mean_y) for x in inliers) / spread
    return slope


def measure(bottom: list[int], top: int) -> dict:
    """Slopes left and right of the lowest point (inner 80 % of each side) and the base width.
    bottom[x] is the lowest opaque row of column x or -1; top is the highest opaque row."""
    columns = [x for x, y in enumerate(bottom) if y >= 0]
    first, last = columns[0], columns[-1]
    lowest = max(columns, key=lambda x: (bottom[x], -x))
    left, right = lowest - first, last - lowest
    band = max(2, round((bottom[lowest] + 1 - top) * 0.15))
    base = [x for x in columns if bottom[x] > bottom[lowest] - band]
    return {
        "left": median_slope(bottom, first + left // 10, lowest - left // 10),
        "right": median_slope(bottom, lowest + right // 10, last - right // 10),
        "base_px": base[-1] - base[0] + 1,
        "height_px": bottom[lowest] + 1 - top,
    }


def on_floor(result: dict, tolerance: float = TOLERANCE) -> bool:
    return abs(result["left"] - SLOPE) <= tolerance and abs(result["right"] + SLOPE) <= tolerance


def cells(path: Path, grid: tuple[int, int]) -> list[dict]:
    from PIL import Image  # only the image reading needs Pillow

    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    cols, rows = grid
    out = []
    for row in range(rows):
        for col in range(cols):
            x0, x1 = col * width // cols, (col + 1) * width // cols
            y0, y1 = row * height // rows, (row + 1) * height // rows
            bottom, top = [], y1
            for x in range(x0, x1):
                low = -1
                for y in range(y0, y1):
                    r, g, b = pixels[x, y]
                    if not (g > 150 and r < 140 and b < 140):  # not the #00FF00 key
                        low = y - y0
                        top = min(top, y - y0)
                bottom.append(low)
            out.append(measure(bottom, top) if max(bottom) >= 0 else {})
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("sheet", type=Path)
    parser.add_argument("--grid", type=int, nargs=2, default=(2, 2), metavar=("COLS", "ROWS"))
    parser.add_argument("--check", type=int, nargs="*", default=[], help="cells whose base must lie on the floor")
    parser.add_argument("--tolerance", type=float, default=TOLERANCE)
    args = parser.parse_args()
    failed = []
    for index, result in enumerate(cells(args.sheet, tuple(args.grid))):
        if not result:
            print(f"cell {index}: empty")
            continue
        ok = on_floor(result, args.tolerance)
        print(f"cell {index}: slope left {result['left']:+.3f} right {result['right']:+.3f}, "
              f"base {result['base_px']} px, height {result['height_px']} px"
              + ("" if index not in args.check else (" OK" if ok else " OFF THE FLOOR")))
        if index in args.check and not ok:
            failed.append(index)
    if failed:
        print(f"cells off the 2:1 floor: {failed}; regenerate over the template (tools/art/iso_template.py)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
