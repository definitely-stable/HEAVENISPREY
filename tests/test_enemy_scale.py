"""ADR-014 section 19: the horde at the size and tone of its reference boards (REF-044, REF-034).

Measured on the built atlases, as the game draws them (one density for every character): the
Yin Corpse stands nearly as tall as the hero, the wolf at the shoulder height of REF-034, and both
are graded to the palette taken from their boards.
"""
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_build_sprites", ROOT / "tools/art/build_sprites.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def entry(asset_id: str) -> dict:
    manifest = json.loads((ROOT / "game/assets/manifest.json").read_text(encoding="utf-8"))
    return next(e for e in manifest["assets"] if e["asset_id"] == asset_id)


def clip_height(asset_id: str, clip: str) -> float:
    """Median body height (atlas px) of a clip over every frame and direction."""
    item = entry(asset_id)
    layout = item["layout"]
    frame = layout["frame_size"]
    info = layout["clips"][clip]
    atlas = Image.open(ROOT / item["path"])
    heights = []
    for offset in range(len(info["directions"])):
        y = (info["row"] + offset) * frame
        for index in range(info["frames"]):
            cell = atlas.crop((index * frame, y, (index + 1) * frame, y + frame))
            heights.append(build.body_height(np.asarray(cell.getchannel("A"))))
    return float(np.median(heights))


def is_pointer(path: Path) -> bool:
    return path.read_bytes()[:40].startswith(b"version https://git-lfs")


@unittest.skipIf(is_pointer(ROOT / entry("asset.enemy.yin_corpse")["path"]), "LFS files not checked out")
class EnemyScaleTests(unittest.TestCase):
    def test_yin_corpse_stands_nearly_as_tall_as_the_hero(self):
        ratio = clip_height("asset.enemy.yin_corpse", "walk") / clip_height("asset.char.hero_sword", "idle")
        self.assertGreaterEqual(ratio, 0.9)
        self.assertLessEqual(ratio, 1.0)

    def test_wolf_reaches_the_hero_chest(self):
        ratio = clip_height("asset.enemy.blood_wolf", "walk") / clip_height("asset.char.hero_sword", "idle")
        self.assertGreaterEqual(ratio, 0.6)
        self.assertLessEqual(ratio, 0.75)

    def test_horde_uses_the_palette_of_its_boards(self):
        for asset_id in ("asset.enemy.yin_corpse", "asset.enemy.blood_wolf"):
            item = entry(asset_id)
            self.assertEqual(item["qa"]["palette_group"], "enemies", asset_id)
            self.assertGreaterEqual(item["qa"]["median_l"], 80.0, f"{asset_id} is not darker than the floor")
            self.assertEqual(item["qa"]["threat_colour_pct"], 0.0, asset_id)

    def test_grade_lifts_mid_tones_and_keeps_black(self):
        piece = Image.new("RGBA", (3, 1))
        piece.putdata([(0, 0, 0, 255), (64, 64, 64, 255), (255, 255, 255, 128)])
        graded = list(build.grade(piece, [1.0, 1.0, 1.05], 0.74).getdata())
        self.assertEqual(graded[0], (0, 0, 0, 255), "the outline stays black")
        self.assertGreater(graded[1][0], 64, "mid tones rise")
        self.assertGreater(graded[1][2], graded[1][0], "the tint cools")
        self.assertEqual(graded[2][3], 128, "alpha unchanged")


if __name__ == "__main__":
    unittest.main()
