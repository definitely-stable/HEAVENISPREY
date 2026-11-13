"""hip-run-eligibility-v1 reference (IC-02 start gate): vectors current, links fail closed."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("run_eligibility", ROOT / "tools/content/run_eligibility.py")
elig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elig)


class RunEligibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = json.loads(elig.REGISTRY_PATH.read_bytes())
        cls.catalog = elig.Catalog(cls.registry)

    def test_committed_vectors_are_current(self):
        self.assertEqual(elig.VECTORS_PATH.read_bytes(), elig.vectors_bytes())

    def test_every_gated_definition_points_to_a_known_unlock_rule(self):
        unlocks = self.catalog.ids("unlock_rules")
        for stem in ("classes", "difficulty_profiles", "modes"):
            for def_id, definition in self.catalog.ids(stem).items():
                unlock_id = definition.get("unlock_id")
                self.assertTrue(unlock_id is None or unlock_id in unlocks, def_id)

    def test_starting_content_needs_no_unlock(self):
        self.assertEqual(elig.check(self.catalog, [], "class.sword", "difficulty.apprentice",
                                    ["mode.normal"]), elig.OK)

    def test_unknown_unlock_link_in_content_fails_closed(self):
        broken = copy.deepcopy(self.registry)
        broken["catalogs"]["classes"]["classes"][0]["unlock_id"] = "unlock.missing"
        sword = broken["catalogs"]["classes"]["classes"][0]["id"]
        self.assertEqual(elig.check(elig.Catalog(broken), [], sword, "difficulty.standard", []),
                         elig.CONTENT_UNLOCK_UNKNOWN)

    def test_profile_fixture_unlocks_are_derived_from_unlock_ids(self):
        profiles = {p["id"]: p for p in
                    json.loads(elig.PROFILES_PATH.read_bytes())["profiles"]}
        self.assertEqual(elig.profile_unlocks(self.catalog, profiles["profile.clean"]), [])
        self.assertEqual(elig.profile_unlocks(self.catalog, profiles["profile.hard_unlocked"]),
                         ["unlock.hard", "unlock.thunder"])

    def test_mode_order_does_not_change_the_reason(self):
        a = elig.check(self.catalog, ["unlock.hurry"], "class.sword", "difficulty.standard",
                       ["mode.hyper", "mode.hurry"])
        b = elig.check(self.catalog, ["unlock.hurry"], "class.sword", "difficulty.standard",
                       ["mode.hurry", "mode.hyper"])
        self.assertEqual((a, b), (elig.MODE_LOCKED, elig.MODE_LOCKED))


if __name__ == "__main__":
    unittest.main()
