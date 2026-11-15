"""Light acceptance of the run scene (ADR-014 section 7) from a capture_run.gd "grid" run:

    godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- out.json 101 grid
    python tools/art/measure_light.py out.json

Per capture: the median luma of the arena floor away from every point light, the luma of each
lantern spot on the arena floor in front of its prop and its ratio to that floor, and the share of the frame that is
void. Over all captures: how much the paving repeats (ADR-014 section 7, slice A3): the floor is
resampled onto the world grid, its slow light is removed, and the luma at a point is correlated
with the luma one tile period further along each world axis, for the period of every floor
layer. Needs numpy and Pillow (local tool, like build_sprites.py); CI does not render.
"""
from __future__ import annotations

import json
import sys

import numpy as np
from PIL import Image

ARENA = (32 * 48, 20 * 48)
HUD_TOP_PX, HUD_BOTTOM_PX = 60, 90
VOID_MAX_CHANNEL = 16
# A3: the dusk courtyard of REF-023 / REF-033 (floor L 80-90, mauve), warm pools by the lanterns.
LIMITS = {"floor": (78.0, 92.0), "spot": (120.0, 190.0), "spot_ratio": 1.4, "void_pct": 20.0, "tile_corr": 0.15}
# Repeat periods of the floor layers, world px: the clean paving (8 cells), its second layer
# (9 cells) and the worn paving (10 cells).
TILE_PERIODS = (384, 432, 480)
REPEAT_STEP = 2
# The seal is not paving: world px around the arena centre left out of the repeat measure.
SEAL_RADIUS = 360.0
# Pairs of points below which a period is not reported.
MIN_PAIRS = 5000


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def measure(shot: dict) -> dict:
    rgb = np.asarray(Image.open(shot["path"]).convert("RGB"), dtype=np.float64)
    lum = luma(rgb)
    height, width = lum.shape
    corners = np.array(shot["corners"], dtype=np.float64)
    origin = corners[0]
    to_world = np.linalg.inv(np.column_stack([(corners[1] - origin) / ARENA[0], (corners[3] - origin) / ARENA[1]]))
    ys, xs = np.mgrid[0:height, 0:width]
    world = np.stack([xs - origin[0], ys - origin[1]], axis=-1) @ to_world.T

    def distance(point: np.ndarray) -> np.ndarray:
        return np.hypot(world[..., 0] - point[0], world[..., 1] - point[1])

    inside = (world[..., 0] > 0) & (world[..., 0] < ARENA[0]) & (world[..., 1] > 0) & (world[..., 1] < ARENA[1])
    floor = inside.copy()
    floor &= distance(to_world @ (np.array(shot["hero"]) - origin)) > shot["aura"] * 1.15
    lanterns = [to_world @ (np.array(p) - origin) for p in shot["lanterns"]]
    for lantern in lanterns:
        floor &= distance(lantern) > shot["radius"] * 1.1
    floor[:HUD_TOP_PX] = False
    floor[height - HUD_BOTTOM_PX:] = False
    floor_l = float(np.median(lum[floor])) if floor.sum() > 2000 else None
    spots = []
    for lantern, (x, y) in zip(lanterns, shot["lanterns"]):
        if 180 < x < width - 180 and 110 < y < height - 110:
            # The arena floor the light reaches past the balustrade, nearer the viewer than the
            # prop (the prop hides the floor behind it).
            ring = (distance(lantern) > 50) & (distance(lantern) < 80) & inside & (ys > y)
            if ring.sum() > 200:
                spots.append(round(float(np.median(lum[ring])), 1))
    void = float(100.0 * (rgb.max(axis=2) < VOID_MAX_CHANNEL).mean())
    return {"floor_l": floor_l and round(floor_l, 1), "spots": spots, "void_pct": round(void, 1)}


def box_sum(values: np.ndarray, half: int) -> np.ndarray:
    """Sum over a (2 * half + 1) square window, clipped at the borders."""
    total = np.cumsum(np.cumsum(np.pad(values, ((1, 0), (1, 0))), axis=0), axis=1)
    height, width = values.shape
    y0, y1 = np.clip(np.arange(height) - half, 0, height), np.clip(np.arange(height) + half + 1, 0, height)
    x0, x1 = np.clip(np.arange(width) - half, 0, width), np.clip(np.arange(width) + half + 1, 0, width)
    return total[y1][:, x1] - total[y0][:, x1] - total[y1][:, x0] + total[y0][:, x0]


def paving(shot: dict) -> tuple[np.ndarray, np.ndarray]:
    """The arena floor of a capture on a world grid of REPEAT_STEP px: luma with its slow light
    (the mean of a one-cell window) removed, and which grid points show bare paving."""
    lum = luma(np.asarray(Image.open(shot["path"]).convert("RGB"), dtype=np.float64))
    height, width = lum.shape
    corners = np.array(shot["corners"], dtype=np.float64)
    origin = corners[0]
    to_screen = np.column_stack([(corners[1] - origin) / ARENA[0], (corners[3] - origin) / ARENA[1]])
    to_world = np.linalg.inv(to_screen)
    gx, gy = np.meshgrid(np.arange(0, ARENA[0], REPEAT_STEP, dtype=np.float64),
                         np.arange(0, ARENA[1], REPEAT_STEP, dtype=np.float64))
    px = origin[0] + to_screen[0, 0] * gx + to_screen[0, 1] * gy
    py = origin[1] + to_screen[1, 0] * gx + to_screen[1, 1] * gy
    valid = (px >= 1) & (px < width - 2) & (py >= HUD_TOP_PX) & (py < height - HUD_BOTTOM_PX)
    ix, iy = np.clip(px.astype(int), 0, width - 2), np.clip(py.astype(int), 0, height - 2)
    fx, fy = px - ix, py - iy
    sample = (lum[iy, ix] * (1 - fx) * (1 - fy) + lum[iy, ix + 1] * fx * (1 - fy)
              + lum[iy + 1, ix] * (1 - fx) * fy + lum[iy + 1, ix + 1] * fx * fy)
    for point in shot["lanterns"]:
        lantern = to_world @ (np.array(point) - origin)
        valid &= np.hypot(gx - lantern[0], gy - lantern[1]) > shot["radius"] * 1.1
    hero = to_world @ (np.array(shot["hero"]) - origin)
    valid &= np.hypot(gx - hero[0], gy - hero[1]) > shot["aura"] * 1.15
    valid &= np.hypot(gx - ARENA[0] / 2, gy - ARENA[1] / 2) > SEAL_RADIUS
    half = 48 // REPEAT_STEP
    mean = box_sum(np.where(valid, sample, 0.0), half) / np.maximum(box_sum(valid.astype(np.float64), half), 1.0)
    return np.where(valid, sample - mean, 0.0), valid


def tile_correlation(shots: list[dict]) -> dict:
    """Pearson correlation of the paving with itself one period away, pooled over the captures
    and both world axes; None for a period seen in too few pairs."""
    floors = [paving(shot) for shot in shots]
    out = {}
    for period in TILE_PERIODS:
        lag = period // REPEAT_STEP
        near, far = [], []
        for detail, valid in floors:
            for dy, dx in ((0, lag), (lag, 0)):
                rows, cols = detail.shape[0] - dy, detail.shape[1] - dx
                both = valid[:rows, :cols] & valid[dy:, dx:]
                near.append(detail[:rows, :cols][both])
                far.append(detail[dy:, dx:][both])
        a, b = np.concatenate(near), np.concatenate(far)
        out[str(period)] = round(float(np.corrcoef(a, b)[0, 1]), 3) if a.size >= MIN_PAIRS else None
    return out


def main() -> int:
    shots = json.load(open(sys.argv[1], encoding="utf-8"))
    results = [measure(shot) for shot in shots]
    repeats = tile_correlation(shots)
    measured = [value for value in repeats.values() if value is not None]
    floors = [r["floor_l"] for r in results if r["floor_l"] is not None]
    spots = [s for r in results for s in r["spots"]]
    floor = float(np.median(floors))
    summary = {
        "floor_l": round(floor, 1),
        "spot_l": [min(spots), max(spots)] if spots else None,
        "spot_ratio_min": round(min(spots) / floor, 2) if spots else None,
        "void_pct_max": max(r["void_pct"] for r in results),
        "tile_corr": repeats,
        "shots": results,
    }
    ok = (LIMITS["floor"][0] <= floor <= LIMITS["floor"][1] and spots
          and LIMITS["spot"][0] <= min(spots) and max(spots) <= LIMITS["spot"][1]
          and min(spots) / floor >= LIMITS["spot_ratio"] and summary["void_pct_max"] <= LIMITS["void_pct"]
          and measured and max(measured) < LIMITS["tile_corr"])
    print(json.dumps(summary, indent=2))
    print("OK" if ok else f"FAIL: limits {LIMITS}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
