from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.content import run_receipt


ROOT = Path(__file__).resolve().parents[1]


class RewardPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors = json.loads((ROOT / "game/tests/fixtures/run_receipt_vectors.json").read_text(encoding="utf-8"))
        cls.catalogs = {
            name: json.loads((ROOT / f".work/config/v7/{name}.json").read_text(encoding="utf-8"))
            for name in ("difficulty_profiles", "modes", "economy_milestones")
        }

    def test_shared_vectors(self):
        self.assertEqual(self.vectors["policy_id"], run_receipt.POLICY_ID)
        uid = run_receipt.test_run_uid(self.vectors["scenario_id"], self.vectors["seed"])
        self.assertEqual(uid, self.vectors["run_uid"])
        for case in self.vectors["cases"]:
            with self.subTest(case=case["name"]):
                fields = {"run_uid": uid, "difficulty_id": "difficulty.standard", "mode_ids": ["mode.normal"], **case}
                if "error" in case:
                    with self.assertRaisesRegex(ValueError, f"^{case['error']}$"):
                        run_receipt.compute(fields, self.catalogs)
                    continue
                events = []
                if case["event"]:
                    events.append({"source_id": "reward.minute3", "reward_event_id": self.vectors["reward_event_id"], "stones": 8})
                self.assertEqual(run_receipt.compute(fields, self.catalogs), {
                    "reward_events": events, "stones_preview": case["stones_preview"],
                })

    def test_fractional_milli_is_rejected(self):
        catalogs = copy.deepcopy(self.catalogs)
        catalogs["difficulty_profiles"]["profiles"][0]["spirit_stones_mult"] = 0.8505
        fields = {
            "run_uid": self.vectors["run_uid"], "result": "victory", "difficulty_id": "difficulty.apprentice",
            "mode_ids": ["mode.normal"], "survived_ticks": 18000, "kills": 20,
        }
        with self.assertRaisesRegex(ValueError, "^invalid_difficulty_multiplier$"):
            run_receipt.compute(fields, catalogs)
