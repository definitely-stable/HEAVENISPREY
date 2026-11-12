"""ARCH-02: recipe reachability — witnesses, explainable unreachability, flexible policies."""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_recipe_graph", ROOT / "scripts/validate_recipe_graph_proposal.py")
rg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rg)

STD, MINI = "sample.profile.standard", "sample.profile.minimalist"


class RecipeGraphTests(unittest.TestCase):
    def setUp(self):
        self.fx = rg.load()

    def tables(self, fx=None):
        return rg.validate_structure(self.fx if fx is None else fx)

    def verdict(self, rid, pid=STD, fx=None):
        fx = self.fx if fx is None else fx
        t = rg.validate_structure(fx)
        return rg.classify(fx, t, t["profiles"][pid], rid)

    @staticmethod
    def find(items, ident):
        return next(x for x in items if x["id"] == ident)

    # -- golden and witness replay
    def test_golden_expectations_and_witness_replay(self):
        summary = rg.verify(self.fx)
        self.assertEqual(summary["expectations"], 26)
        self.assertEqual(summary["cycles"], 1)

    def test_multi_tier_witness_base_evolved_union_gift(self):
        row = self.verdict("sample.recipe.sky_tribute")
        applied = [i for k, i in row["path"] if k == "recipe"]
        self.assertEqual(applied, ["sample.recipe.sword_rain", "sample.recipe.storm_sword",
                                   "sample.recipe.heaven_prison", "sample.recipe.sky_tribute"])
        self.assertEqual((row["picks"], row["second"]), (11, 270))

    def test_tampered_witness_fails_replay(self):
        t = self.tables()
        path = self.verdict("sample.recipe.sword_rain")["path"]
        broken = [a for a in path if a != ["rank", "sample.skill.flying_sword"]]
        with self.assertRaisesRegex(rg.ContractError, "not applicable"):
            rg.replay(self.fx, t, t["profiles"][STD], broken)

    # -- capacity is a profile lever, not a type limit
    def test_open_slot_lever_makes_capacity_recipe_reachable(self):
        self.assertEqual(self.verdict("sample.recipe.trinity_array", MINI)["result"], "CAPACITY")
        fx = copy.deepcopy(self.fx)
        self.find(fx["profiles"], MINI)["active_capacity"] = 3
        self.assertEqual(self.verdict("sample.recipe.trinity_array", MINI, fx)["result"], "REACHABLE")

    def test_meridian_capacity_grant_is_used_by_minimalist_witness(self):
        row = self.verdict("sample.recipe.storm_sword", MINI)
        self.assertIn(["recipe", "sample.meridian.open_palm"], row["path"])

    def test_n_to_m_grant_counts_every_output_slot(self):
        self.assertEqual(self.verdict("sample.recipe.heaven_prison", MINI)["result"], "CAPACITY")
        fx = copy.deepcopy(self.fx)
        self.find(fx["profiles"], MINI)["passive_capacity"] = 2
        self.assertEqual(self.verdict("sample.recipe.heaven_prison", MINI, fx)["result"], "REACHABLE")

    # -- post-max growth
    def test_limit_break_makes_rank_eight_reachable(self):
        self.assertEqual(self.verdict("sample.recipe.sword_saint")["picks"], 7)
        fx = copy.deepcopy(self.fx)
        self.find(fx["skills"], "sample.skill.flying_sword")["growth"] = {"kind": "none"}
        self.assertEqual(self.verdict("sample.recipe.sword_saint", fx=fx)["result"], "RANK_UNREACHABLE")

    def test_repeatable_growth_without_cap_is_rejected(self):
        fx = copy.deepcopy(self.fx)
        self.find(fx["skills"], "sample.skill.iron_body")["growth"] = {"kind": "repeatable", "per_step": 5}
        with self.assertRaisesRegex(rg.ContractError, "value_cap"):
            self.tables(fx)

    # -- run budgets
    def test_more_rituals_make_fourth_transformation_reachable(self):
        fx = copy.deepcopy(self.fx)
        fx["event_gates"]["RITUAL"]["max_per_run"] = 4
        self.assertEqual(self.verdict("sample.recipe.prison_ascension", fx=fx)["result"], "REACHABLE")

    def test_longer_pick_schedule_lifts_pick_budget(self):
        self.assertEqual(self.verdict("sample.recipe.grand_array")["picks"], 19)
        fx = copy.deepcopy(self.fx)
        fx["run"]["pick_schedule"][-1] = [300, 19]
        self.assertEqual(self.verdict("sample.recipe.grand_array", fx=fx)["result"], "REACHABLE")

    def test_class_lock_opens_for_matching_class(self):
        fx = copy.deepcopy(self.fx)
        self.find(fx["profiles"], STD)["class_id"] = "class.body"
        self.assertEqual(self.verdict("sample.recipe.iron_storm", fx=fx)["result"], "REACHABLE")

    # -- structural negatives
    def test_implicit_conflict_between_consumers_is_rejected(self):
        fx = copy.deepcopy(self.fx)
        self.find(fx["recipes"], "sample.recipe.trinity_array")["exclusive_group"] = "sample.group.other"
        with self.assertRaisesRegex(rg.ContractError, "implicit conflict"):
            self.tables(fx)

    def test_conflicting_recipes_are_offered_together_never_auto_resolved(self):
        t = self.tables()
        prof = t["profiles"][STD]
        state = rg.replay(self.fx, t, prof, self.verdict("sample.recipe.sword_rain")["path"][:-1])
        for action in (("acquire", "sample.skill.thunder_chain"), ("rank", "sample.skill.thunder_chain"),
                       ("acquire", "sample.skill.talisman_ward"), ("rank", "sample.skill.talisman_ward")):
            state = rg.step(self.fx, t, prof, state, action)
        both = [r for r in ("sample.recipe.sword_rain", "sample.recipe.trinity_array")
                if rg.recipe_applicable(self.fx, t, prof, state, r)]
        self.assertEqual(len(both), 2)
        self.assertEqual({t["recipes"][r]["exclusive_group"] for r in both}, {"sample.group.sword_thunder"})

    def test_cycle_without_allow_cycle_is_rejected(self):
        fx = copy.deepcopy(self.fx)
        del self.find(fx["recipes"], "sample.recipe.yang_to_yin")["allow_cycle"]
        with self.assertRaisesRegex(rg.ContractError, "cycle without allow_cycle"):
            self.tables(fx)

    def test_kind_contracts(self):
        cases = [
            ("sample.recipe.sky_tribute", {"consumes": [{"id": "sample.skill.thunder_chain", "min_rank": 1}],
                                           "exclusive_group": "sample.group.sword_thunder"}, "input count"),
            ("sample.meridian.open_palm", {"grants": [{"kind": "active", "id": "sample.skill.void_lance"}]}, "MERIDIAN"),
            ("sample.recipe.sword_rain", {"kind": "FUSION"}, "unknown recipe kind"),
            ("sample.recipe.sword_rain", {"gate": "LEVEL_UP_ANY"}, "unknown event gate"),
        ]
        for rid, patch, pattern in cases:
            fx = copy.deepcopy(self.fx)
            self.find(fx["recipes"], rid).update(patch)
            with self.subTest(rid=rid, pattern=pattern), self.assertRaisesRegex(rg.ContractError, pattern):
                self.tables(fx)

    def test_evolution_result_must_not_be_draftable(self):
        fx = copy.deepcopy(self.fx)
        self.find(fx["skills"], "sample.skill.sword_rain")["sources"] = ["draft"]
        with self.assertRaisesRegex(rg.ContractError, "must not be draftable"):
            self.tables(fx)

    def test_unknown_canonical_class_is_rejected(self):
        fx = copy.deepcopy(self.fx)
        self.find(fx["profiles"], STD)["class_id"] = "class.archer"
        with self.assertRaisesRegex(rg.ContractError, "unknown canonical class"):
            self.tables(fx)


if __name__ == "__main__":
    unittest.main()
