"""ADR-014 section 19: the horde in the tone and palette of its reference boards (REF-044,
REF-034), read from the manifest. The height of the bodies is measured on the atlases by GUT
(game/tests/integration/test_sprite_set.gd)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HORDE = ("asset.enemy.yin_corpse", "asset.enemy.blood_wolf")


def manifest() -> dict:
    return json.loads((ROOT / "game/assets/manifest.json").read_text(encoding="utf-8"))


def source(asset_id: str) -> dict:
    name = asset_id.rsplit(".", 1)[1]
    return json.loads((ROOT / "art_source" / name / "source.json").read_text(encoding="utf-8"))


class EnemyToneTests(unittest.TestCase):
    def test_horde_uses_the_palette_of_its_boards(self):
        passport = json.loads((ROOT / "art_source/style_passport.json").read_text(encoding="utf-8"))
        self.assertIn("enemies", passport["groups"])
        for entry in manifest()["assets"]:
            if entry["asset_id"] in HORDE:
                qa = entry["qa"]
                self.assertEqual(qa["palette_group"], "enemies", entry["asset_id"])
                self.assertGreaterEqual(qa["median_l"], 80.0, f"{entry['asset_id']} is darker than the floor")
                self.assertEqual(qa["threat_colour_pct"], 0.0, entry["asset_id"])

    def test_grade_lifts_and_keeps_the_hue_near(self):
        for asset_id in HORDE:
            grade = source(asset_id)["grade"]
            self.assertLess(grade["gamma"], 1.0, asset_id)
            self.assertGreaterEqual(grade["gamma"], 0.7, f"{asset_id}: a stronger lift washes the ink out")
            for channel in grade["tint"]:
                self.assertAlmostEqual(channel, 1.0, delta=0.1, msg=asset_id)


if __name__ == "__main__":
    unittest.main()
