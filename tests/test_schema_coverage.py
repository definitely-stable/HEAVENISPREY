"""GAP-SCHEMA-COVERAGE: validators for localization_context.json and settings.example.cfg."""
from __future__ import annotations

import csv
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / ".work/config/v7"
spec = importlib.util.spec_from_file_location("hip_content_schema", ROOT / "scripts/validate_content.py")
vc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vc)


class SchemaCoverageTests(unittest.TestCase):
    def setUp(self):
        self.ctx = json.loads((DATA / "localization_context.json").read_text(encoding="utf-8"))
        with (DATA / "translations.csv").open(encoding="utf-8", newline="") as f:
            self.trs = {row["keys"]: row for row in csv.DictReader(f)}
        self.cfg = (DATA / "settings.example.cfg").read_text(encoding="utf-8")

    def test_repository_files_are_valid(self):
        self.assertEqual(vc.check_localization_context(self.ctx, self.trs), [])
        self.assertEqual(vc.check_settings(self.cfg), [])

    def test_context_for_missing_key_or_prefix_fails(self):
        self.ctx["contexts"]["UI_OPEN_SHOP"] = "shop"
        self.ctx["contexts"]["RELIC_"] = "relic tooltip"
        problems = vc.check_localization_context(self.ctx, self.trs)
        self.assertEqual(len(problems), 2)

    def test_empty_hint_fails(self):
        self.ctx["contexts"]["UI_START_RUN"] = " "
        self.assertTrue(vc.check_localization_context(self.ctx, self.trs))

    def test_settings_rejects_unknown_out_of_range_and_missing(self):
        cases = {
            "[graphics]\nbloom=1\n": "unknown key",
            "[audio]\n": "unknown section",
            '[localization]\npreferred_locale="de"\n': "must be one of",
            "[graphics]\nvfx_intensity=1.4\n": "outside 0..1",
            "[accessibility]\nfont_scale=0\n": "must be > 0",
            "[graphics]\nscreenshake=strong\n": "not a number",
        }
        for text, needle in cases.items():
            with self.subTest(text=text):
                self.assertTrue(any(needle in p for p in vc.check_settings(text)))
        self.assertTrue(any("missing graphics.vfx_intensity" in p
                            for p in vc.check_settings(self.cfg.replace("vfx_intensity=0.65\n", ""))))


if __name__ == "__main__":
    unittest.main()
