"""ARCH-04: typed effect ops, damage provenance, finite reaction chains, no hidden discard."""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_effect_chain", ROOT / "scripts/validate_effect_chain_proposal.py")
ec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ec)

BASE, GEN3 = "sample.profile.baseline", "sample.profile.generation_3"
THUNDER, SWORD, TALISMAN, WOLF = ("sample.skill.thunder_chain", "sample.skill.spirit_sword",
                                  "sample.skill.talisman_seal", "sample.skill.wolf_spirit")


class EffectChainTests(unittest.TestCase):
    def setUp(self):
        self.fx = ec.load()

    def model(self, fx=None):
        fx = self.fx if fx is None else fx
        return ec.Model(fx, ec.validate_structure(fx))

    def profile(self, pid, fx=None):
        return next(p for p in (self.fx if fx is None else fx)["profiles"] if p["id"] == pid)

    def trigger(self, fx, tid):
        return next(t for t in fx["triggers"] if t["id"] == tid)

    def op(self, fx, oid):
        return next(o for s in fx["skills"] for o in s["ops"] if o["id"] == oid)

    # -- golden
    def test_golden_bounds_and_verdicts(self):
        self.assertEqual(ec.verify(self.fx)["expectations"], 8)

    def test_acyclic_bound_is_exact_for_worst_case(self):
        v = ec.verdict(self.model(), self.profile(BASE), WOLF)
        self.assertEqual(v["static_bound"], v["worst_case_events"])

    # -- finiteness
    def test_unbounded_self_cycle_is_invalid_semantics(self):
        fx = copy.deepcopy(self.fx)
        del self.trigger(fx, "sample.trigger.resonance")["consumes"]
        with self.assertRaisesRegex(ec.ContractError, "E_UNBOUNDED_CYCLE"):
            ec.static_bound(self.model(fx), self.profile(BASE, fx), ("CAST", "primary", SWORD))

    def test_generation_budget_bounds_the_same_cycle(self):
        fx = copy.deepcopy(self.fx)
        del self.trigger(fx, "sample.trigger.resonance")["consumes"]
        model = self.model(fx)
        # W(HIT/proc, g) = 1 + 2 W(HIT/proc, g-1): 1, 3, 7 -> primary hit 1 + 7 = 8 at g=3
        self.assertEqual(ec.static_bound(model, self.profile(GEN3, fx), ("HIT", "primary", "")), 8)
        v = ec.verdict(model, self.profile(GEN3, fx), WOLF)
        self.assertEqual(v["verdict"], "VALID_FOR_PROFILE")

    def test_resource_replenished_inside_cycle_is_rejected(self):
        fx = copy.deepcopy(self.fx)
        self.trigger(fx, "sample.trigger.resonance")["refunds"] = {"resource": "sample.resource.resonance_charge",
                                                                  "amount": 1}
        with self.assertRaisesRegex(ec.ContractError, "E_CYCLE_REFUND"):
            ec.static_bound(self.model(fx), self.profile(BASE, fx), ("CAST", "primary", SWORD))

    def test_echo_of_echo_needs_explicit_opt_in_and_a_bound(self):
        fx = copy.deepcopy(self.fx)
        self.trigger(fx, "sample.trigger.multicast")["accepts_origins"] = ["primary", "echo"]
        with self.assertRaisesRegex(ec.ContractError, "E_UNBOUNDED_CYCLE"):
            ec.static_bound(self.model(fx), self.profile(BASE, fx), ("CAST", "primary", WOLF))
        self.assertGreater(ec.static_bound(self.model(fx), self.profile(GEN3, fx), ("CAST", "primary", WOLF)), 18)

    # -- no hidden discard
    def test_profile_excess_is_a_verdict_not_a_truncation(self):
        handheld = self.profile("sample.profile.handheld")
        v = ec.verdict(self.model(), handheld, TALISMAN)
        self.assertEqual((v["verdict"], v["worst_case_events"]), ("PROFILE_EXCEEDED", 96))

    def test_expansion_beyond_proven_bound_is_a_proof_failure(self):
        with self.assertRaisesRegex(ec.ContractError, "E_BOUND_PROOF"):
            ec.expand(self.model(), self.profile(BASE), TALISMAN, limit=95)

    # -- provenance
    def test_every_event_has_one_root_and_an_owning_skill(self):
        model = self.model()
        events = ec.expand(model, self.profile(BASE), THUNDER)
        stats = ec.check_provenance(model, events)
        self.assertEqual(stats["events"], 51)
        self.assertEqual({e["root"] for e in events}, {0})
        self.assertTrue(all(e["credited_skill"] == THUNDER for e in events))

    def test_dot_ticks_are_not_hits_and_trigger_nothing(self):
        model = self.model()
        events = ec.expand(model, self.profile(BASE), TALISMAN)
        ticks = [e for e in events if e["node"][0] == "STATUS_TICK"]
        self.assertEqual(len(ticks), 3 * 6)
        tick_uids = {e["uid"] for e in ticks}
        self.assertFalse([e for e in events if e["parent"] in tick_uids])
        self.assertEqual({e["via"] for e in ticks}, {"sample.op.talisman_seal.burn"})

    def test_zone_and_summon_hits_do_not_proc_without_opt_in(self):
        events = ec.expand(self.model(), self.profile(BASE), TALISMAN)
        self.assertFalse([e for e in events if e["via"] == "sample.trigger.static_arc"])
        fx = copy.deepcopy(self.fx)
        self.trigger(fx, "sample.trigger.static_arc")["accepts_origins"] += ["zone"]
        self.assertGreater(ec.verdict(self.model(fx), self.profile(BASE, fx), TALISMAN)["static_bound"], 96)

    def test_reaction_credits_both_status_owners(self):
        model = self.model()
        events = ec.expand(model, self.profile(BASE), THUNDER, world={"status.burn": TALISMAN})
        reactions = [e for e in events if e["node"][0] == "REACTION"]
        self.assertEqual(len(reactions), 3)
        self.assertEqual(reactions[0]["contributors"], sorted([THUNDER, TALISMAN]))

    def test_reaction_needs_its_target_condition(self):
        events = ec.expand(self.model(), self.profile(BASE), THUNDER, world={})
        self.assertFalse([e for e in events if e["node"][0] == "REACTION"])

    def test_echo_casts_keep_owner_and_add_a_generation(self):
        events = ec.expand(self.model(), self.profile(BASE), SWORD)
        echoes = [e for e in events if e["node"] == ("CAST", "echo", SWORD)]
        self.assertEqual([(e["generation"], e["credited_skill"]) for e in echoes], [(1, SWORD)] * 2)

    # -- typed op schema (discriminated union with error ids)
    def test_op_schema_error_ids(self):
        cases = [
            ({"op": "LASER"}, "E_OP_KIND"),
            ({"jumps": None}, "E_OP_VALUE"),
            ({"homing": True}, "E_OP_FIELD_UNKNOWN"),
        ]
        for patch, code in cases:
            fx = copy.deepcopy(self.fx)
            self.op(fx, "sample.op.thunder_chain.jump").update(patch)
            with self.subTest(code=code), self.assertRaisesRegex(ec.ContractError, code):
                ec.validate_structure(fx)
        fx = copy.deepcopy(self.fx)
        del self.op(fx, "sample.op.thunder_chain.jump")["damage_ref"]
        with self.assertRaisesRegex(ec.ContractError, "E_OP_FIELD_MISSING"):
            ec.validate_structure(fx)

    def test_status_rules_follow_canonical_statuses(self):
        for patch, code in (({"status_id": "status.venom"}, "E_STATUS_TARGET"),
                            ({"status_id": "status.frost"}, "E_STATUS_REF"),
                            ({"stacks": 13}, "E_OP_VALUE")):
            fx = copy.deepcopy(self.fx)
            self.op(fx, "sample.op.thunder_chain.shock").update(patch)
            with self.subTest(code=code), self.assertRaisesRegex(ec.ContractError, code):
                ec.validate_structure(fx)

    def test_proc_cannot_claim_primary_origin(self):
        fx = copy.deepcopy(self.fx)
        self.trigger(fx, "sample.trigger.static_arc")["origin"] = "primary"
        with self.assertRaisesRegex(ec.ContractError, "E_ORIGIN_PRIMARY"):
            ec.validate_structure(fx)

    def test_trigger_cannot_emit_dot_ticks(self):
        fx = copy.deepcopy(self.fx)
        self.trigger(fx, "sample.trigger.static_arc")["emits"] = "STATUS_TICK"
        with self.assertRaisesRegex(ec.ContractError, "E_TRIGGER_EMITS"):
            ec.validate_structure(fx)


if __name__ == "__main__":
    unittest.main()
