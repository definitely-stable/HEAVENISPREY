import json
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / ".work" / "config" / "v7"

def load(name):
    return json.loads((BASE / (name + ".json")).read_text(encoding="utf-8"))

class LateProgressionDesignChecks(unittest.TestCase):
    def setUp(self):
        self.diff = {v["id"]: v for v in load("difficulty_profiles")["profiles"]}
        self.rewards = load("reward_contract")
        self.modes = {v["id"]: v for v in load("modes")["profiles"]}
        self.unlocks = {v["id"]: v for v in load("unlock_rules")["rules"]}

    def test_late_currency_locked_to_two_difficulties(self):
        allowed = set(self.rewards["dao_seals_allowed_difficulties"])
        self.assertEqual(allowed, {"difficulty.tribulation", "difficulty.abyss"})
        for id, spec in self.diff.items():
            self.assertEqual(spec["dao_seals_on_clear"] > 0, id in allowed)

    def test_late_unlock_requires_multiple_conditions(self):
        self.assertGreaterEqual(len(self.unlocks["unlock.tribulation"]["all"]), 3)
        self.assertGreaterEqual(len(self.unlocks["unlock.abyss"]["all"]), 2)

    def test_abyss_more_rewarding(self):
        self.assertGreater(self.diff["difficulty.abyss"]["spirit_stones_mult"], self.diff["difficulty.tribulation"]["spirit_stones_mult"])
        self.assertGreater(self.diff["difficulty.abyss"]["dao_seals_on_clear"], self.diff["difficulty.tribulation"]["dao_seals_on_clear"])

    def test_unranked_never_eligible(self):
        for id in ["mode.training", "mode.custom_unranked"]:
            self.assertFalse(self.modes[id]["reward_eligible"])
            self.assertIn(id, self.rewards["prohibited_progress_modes"])

    def test_endless_has_seal_cap(self):
        self.assertEqual(self.rewards["endless_dao_seals"], "first_complete_cycle_only")

if __name__ == "__main__":
    unittest.main()
