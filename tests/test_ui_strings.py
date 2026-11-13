"""RU/EN UI strings for the game runtime (tools/content/ui_strings.py, P0-01 slice 5b)."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


strings = _load("ui_strings", "tools/content/ui_strings.py")
sim = _load("sim_core_for_strings", "tools/content/sim_core.py")

HEADER = "keys,en,ru\n"


def stem(upgrade_id: str) -> str:
    """Same rule as UpgradeCard.key_stem in the game."""
    return upgrade_id.replace(".", "_").upper()


class UiStringsTests(unittest.TestCase):
    def setUp(self):
        self.table = strings.load()

    def build_from(self, text: str) -> bytes:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "translations.csv"
            source.write_bytes(text.encode("utf-8"))
            return strings.build(source)

    def test_committed_file_matches_translations(self):
        self.assertEqual(strings.OUT.read_bytes(), strings.build())
        self.assertEqual(strings.main(["--check"]), 0)

    def test_every_upgrade_card_has_name_and_stat_line(self):
        ids = [upgrade_id for upgrade_id, _ in sim.UPGRADES] + [sim.RECOVER_ID]
        for upgrade_id in ids:
            name, desc = stem(upgrade_id) + "_NAME", stem(upgrade_id) + "_DESC"
            self.assertIn(name, self.table, upgrade_id)
            self.assertIn(desc, self.table, upgrade_id)
            for locale in strings.LOCALES:
                self.assertEqual(strings.placeholders(self.table[desc][locale]), ["%s", "%s"],
                                 desc + " " + locale)
                self.assertEqual(strings.placeholders(self.table[name][locale]), [], name)

    def test_menu_keys(self):
        self.assertEqual(strings.placeholders(self.table["UI_UPGRADE_RANK"]["ru"]), ["%d", "%d"])
        self.assertEqual(strings.placeholders(self.table["UI_LEVEL_UP_MORE"]["en"]), ["%d"])
        self.assertIn("UI_LEVEL_UP_TITLE", self.table)

    def test_output_is_presentation_only(self):
        data = json.loads(strings.OUT.read_text(encoding="utf-8"))
        self.assertEqual(data["kind"], "ui_strings")
        self.assertEqual(data["locales"], ["en", "ru"])
        self.assertNotIn("generated", strings.OUT.parts, "outside the ContentRegistry directory")

    def test_rejects_mismatched_placeholders(self):
        with self.assertRaises(strings.StringsError):
            self.build_from(HEADER + "UI_X,Rank %d/%d,Ранг %d\n")
        with self.assertRaises(strings.StringsError):
            self.build_from(HEADER + "UI_X,%s then %d,%d затем %s\n")
        self.build_from(HEADER + "UI_X,100%% sure %d,уверен на 100%% %d\n")

    def test_rejects_bad_rows(self):
        for text in (HEADER + "UI_X,One,\n", HEADER + "ui_x,One,Один\n",
                     HEADER + "UI_X,One,Один\nUI_X,Two,Два\n", "keys,ru,en\nUI_X,Один,One\n"):
            with self.assertRaises(strings.StringsError, msg=text):
                self.build_from(text)


if __name__ == "__main__":
    unittest.main()
