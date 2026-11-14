"""Light acceptance of the run scene (ADR-014 section 7) from a capture_run.gd "grid" run:

    godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- out.json 101 grid
    python tools/art/measure_light.py out.json

Per capture: the median luma of the arena floor away from every point light, the luma of each
lantern spot next to its post and its ratio to that floor, and the share of the frame that is
void. Needs numpy and Pillow (local tool, like build_sprites.py); CI does not render.
"""
from __future__ import annotations

import json
import sys

import numpy as np
from PIL import Image

ARENA = (32 * 48, 20 * 48)
HUD_TOP_PX, HUD_BOTTOM_PX = 60, 90
VOID_MAX_CHANNEL = 16
LIMITS = {"floor": (35.0, 50.0), "spot": (95.0, 120.0), "spot_ratio": 2.2, "void_pct": 20.0}


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

    floor = (world[..., 0] > 0) & (world[..., 0] < ARENA[0]) & (world[..., 1] > 0) & (world[..., 1] < ARENA[1])
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
            # A ring next to the post, below its base on screen (the post hides the rest).
            ring = (distance(lantern) > 22) & (distance(lantern) < 42) & (ys > y)
            spots.append(round(float(np.median(lum[ring])), 1))
    void = float(100.0 * (rgb.max(axis=2) < VOID_MAX_CHANNEL).mean())
    return {"floor_l": floor_l and round(floor_l, 1), "spots": spots, "void_pct": round(void, 1)}


def main() -> int:
    shots = json.load(open(sys.argv[1], encoding="utf-8"))
    results = [measure(shot) for shot in shots]
    floors = [r["floor_l"] for r in results if r["floor_l"] is not None]
    spots = [s for r in results for s in r["spots"]]
    floor = float(np.median(floors))
    summary = {
        "floor_l": round(floor, 1),
        "spot_l": [min(spots), max(spots)] if spots else None,
        "spot_ratio_min": round(min(spots) / floor, 2) if spots else None,
        "void_pct_max": max(r["void_pct"] for r in results),
        "shots": results,
    }
    ok = (LIMITS["floor"][0] <= floor <= LIMITS["floor"][1] and spots
          and LIMITS["spot"][0] <= min(spots) and max(spots) <= LIMITS["spot"][1]
          and min(spots) / floor >= LIMITS["spot_ratio"] and summary["void_pct_max"] <= LIMITS["void_pct"])
    print(json.dumps(summary, indent=2))
    print("OK" if ok else f"FAIL: limits {LIMITS}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
