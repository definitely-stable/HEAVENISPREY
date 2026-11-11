"""Negative and witness tests for architecture-only build catalog.

The oracle is a design-time contract checker, not a gameplay simulator.
"""
import copy
import importlib.util
import unittest

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_design_validator", ROOT / "scripts/validate_build_proposal.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def source():
    return mod.load_json(mod.SAMPLE)


def witness(catalog, suffix):
    return next(x for x in catalog["witnesses"] if x["id"].endswith(suffix))["build"]


class BuildDesignProposalTests(unittest.TestCase):

    def test_positive_catalog_and_all_witnesses(self):
        result = mod.validate_catalog(source())
        self.assertEqual(result["recipes"], 3)
        self.assertEqual(result["witnesses"], 5)
        self.assertLess(result["proc_bound"], 128)

    def test_conflicting_evolution_and_union_require_choice(self):
        catalog = source()
        build = witness(catalog, ".conflict")
        ids = mod.applicable_recipes(catalog, build, "ritual_reward")
        self.assertEqual(ids, ["sample.evolution.thousand_swords", "sample.union.storm_blades"])
        self.assertEqual(mod.conflicting_choices(catalog, ids),
                         {"sword_primary": ids})

    def test_evolution_preserves_catalyst_and_other_skills(self):
        catalog = source()
        build = witness(catalog, ".conflict")
        result = mod.apply_recipe(catalog, build, "sample.evolution.thousand_swords",
                                  build["revision"], "ritual_reward")
        self.assertEqual({x["id"] for x in result["active"]},
                         {"sample.skill.thousand_swords", "sample.skill.thunder_chain"})
        self.assertEqual(result["passive"], build["passive"])
        self.assertEqual(result["revision"], build["revision"] + 1)
        self.assertEqual(build, witness(catalog, ".conflict"), "original build mutated")

    def test_union_frees_one_slot(self):
        catalog = source()
        build = witness(catalog, ".union")
        result = mod.apply_recipe(catalog, build, "sample.union.storm_blades",
                                  build["revision"], "ritual_reward")
        self.assertEqual(result["active"], [{"id": "sample.skill.storm_blades", "rank": 1}])
        self.assertEqual(len(build["active"]) - len(result["active"]), 1)

    def test_gift_does_not_consume_base(self):
        catalog = source()
        build = witness(catalog, ".gift")
        result = mod.apply_recipe(catalog, build, "sample.gift.sword_echo_reward",
                                  build["revision"], "gift_event")
        self.assertEqual(result["active"], build["active"])
        self.assertEqual(result["gifts"], ["sample.gift.sword_echo"])

    def test_stale_revision_is_rejected_and_input_unchanged(self):
        catalog = source()
        build = witness(catalog, ".union")
        before = copy.deepcopy(build)
        with self.assertRaisesRegex(mod.ContractError, "stale build revision"):
            mod.apply_recipe(catalog, build, "sample.union.storm_blades",
                             build["revision"] - 1, "ritual_reward")
        self.assertEqual(build, before)

    def test_wrong_gate_cannot_trigger(self):
        catalog = source()
        self.assertEqual(mod.applicable_recipes(catalog, witness(catalog, ".evolution"), "gift_event"),
                         ["sample.gift.sword_echo_reward"])
        self.assertNotIn("sample.gift.sword_echo_reward",
                         mod.applicable_recipes(catalog, witness(catalog, ".evolution"), "ritual_reward"))

    def test_draft_pool_is_order_independent(self):
        catalog = source()
        build = witness(catalog, ".not_ready")
        first = mod.eligible_offers(catalog, build)
        catalog["offers"].reverse()
        self.assertEqual(first, mod.eligible_offers(catalog, build))
        self.assertEqual(first, ["sample.offer.echo", "sample.offer.new_thunder",
                                 "sample.offer.sword_rank", "sample.offer.thunder_conduit"])

    def test_offer_no_rank_up_if_at_cap(self):
        catalog = source()
        build = witness(catalog, ".evolution")
        self.assertNotIn("sample.offer.sword_rank", mod.eligible_offers(catalog, build))

    def test_draft_respects_full_active_slots(self):
        catalog = source()
        build = witness(catalog, ".evolution")
        for n in range(5):
            clone = copy.deepcopy(catalog["skills"][1])
            clone["id"] = f"sample.skill.filler_{n}"
            clone["canonical_ref"] = None
            catalog["skills"].append(clone)
            build["active"].append({"id": clone["id"], "rank": 1})
        self.assertEqual(len(build["active"]), 6)
        self.assertNotIn("sample.offer.new_thunder", mod.eligible_offers(catalog, build))
        with self.assertRaisesRegex(mod.ContractError, "slots overflow"):
            clone = copy.deepcopy(catalog["skills"][1])
            clone["id"] = "sample.skill.seventh"
            catalog["skills"].append(clone)
            build["active"].append({"id": clone["id"], "rank": 1})
            mod.eligible_offers(catalog, build)

    def test_bad_reference_rejected(self):
        catalog = source()
        catalog["skills"][0]["status_ids"] = ["status.unknown"]
        with self.assertRaisesRegex(mod.ContractError, "unknown status ref"):
            mod.validate_catalog(catalog)

    def test_impossible_rank_rejected(self):
        catalog = source()
        catalog["transformations"][0]["required_skills"][0]["min_rank"] = 6
        with self.assertRaisesRegex(mod.ContractError, "unreachable rank"):
            mod.validate_catalog(catalog)

    def test_unknown_catalyst_rejected(self):
        catalog = source()
        catalog["transformations"][0]["required_passives"][0]["id"] = "sample.passive.fake"
        with self.assertRaisesRegex(mod.ContractError, "missing catalyst"):
            mod.validate_catalog(catalog)

    def test_duplicate_union_input_rejected(self):
        catalog = source()
        catalog["transformations"][1]["consumes_skill_ids"].append("sample.skill.spirit_sword")
        with self.assertRaisesRegex(mod.ContractError, "duplicate consumed skill"):
            mod.validate_catalog(catalog)

    def test_recipe_consumes_unrequired_skill_rejected(self):
        catalog = source()
        catalog["transformations"][0]["consumes_skill_ids"] = ["sample.skill.thunder_chain"]
        with self.assertRaisesRegex(mod.ContractError, "consumes without prerequisite"):
            mod.validate_catalog(catalog)

    def test_procs_must_be_acyclic(self):
        catalog = source()
        catalog["proc_rules"].append({"source": "DAMAGE", "target": "HIT", "max_children": 1})
        with self.assertRaisesRegex(mod.ContractError, "proc cycle detected"):
            mod.validate_catalog(catalog)

    def test_procs_must_fit_budget(self):
        catalog = source()
        catalog["proc_rules"][0]["max_children"] = 100
        with self.assertRaisesRegex(mod.ContractError, "exceeds declared budget"):
            mod.validate_catalog(catalog)

    def test_duplicate_catalog_id_rejected(self):
        catalog = source()
        catalog["skills"].append(copy.deepcopy(catalog["skills"][0]))
        with self.assertRaisesRegex(mod.ContractError, "duplicate ID"):
            mod.validate_catalog(catalog)

    def test_gift_capacity_rejected(self):
        catalog = source()
        build = witness(catalog, ".gift")
        build["gifts"] = ["sample.gift.sword_echo", "sample.gift.sword_echo"]
        with self.assertRaisesRegex(mod.ContractError, "capacity exceeded"):
            mod.validate_build(build, mod.tables_for(catalog), catalog["policy"])


    def test_capacity_policy_can_expand_without_rewriting_skills(self):
        catalog = source()
        catalog["policy"]["active_capacity"] = 12
        catalog["policy"]["passive_capacity"] = 12
        catalog["policy"]["gift_capacity"] = 4
        result = mod.validate_catalog(catalog)
        self.assertEqual(result["skills"], 4)

    def test_rank_limit_is_definition_specific_not_globally_five(self):
        catalog = source()
        skill = next(x for x in catalog["skills"] if x["id"] == "sample.skill.spirit_sword")
        skill["max_rank"] = 12
        build = witness(catalog, ".evolution")
        build["active"][0]["rank"] = 12
        mod.validate_build(build, mod.tables_for(catalog), catalog["policy"])
        self.assertIn("sample.evolution.thousand_swords",
                      mod.applicable_recipes(catalog, build, "ritual_reward"))

    def test_bounded_feedback_cycle_accepted_when_policy_explicit(self):
        catalog = source()
        catalog["proc_rules"].append({"source": "DAMAGE", "target": "HIT", "max_children": 1})
        catalog["policy"]["max_generation"] = 8
        catalog["policy"]["max_proc_events_per_root"] = 100000
        bound = mod.max_proc_events(catalog)
        self.assertGreater(bound, 36)
        self.assertLess(bound, 100000)
        self.assertEqual(mod.validate_catalog(catalog)["proc_bound"], bound)

    def test_bounded_feedback_budget_still_checked(self):
        catalog = source()
        catalog["proc_rules"].append({"source": "DAMAGE", "target": "HIT", "max_children": 3})
        catalog["policy"]["max_generation"] = 8
        catalog["policy"]["max_proc_events_per_root"] = 128
        with self.assertRaisesRegex(mod.ContractError, "exceeds declared budget"):
            mod.validate_catalog(catalog)

    def test_generation_limit_not_silent_if_unset(self):
        catalog = source()
        catalog["proc_rules"].append({"source": "DAMAGE", "target": "HIT", "max_children": 1})
        catalog["policy"].pop("max_generation", None)
        with self.assertRaisesRegex(mod.ContractError, "proc cycle detected"):
            mod.validate_catalog(catalog)


if __name__ == "__main__":
    unittest.main()
