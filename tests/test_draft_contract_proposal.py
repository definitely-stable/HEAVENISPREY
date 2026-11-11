"""DRAFT-CONTRACT-002 architecture-only RNG, source policy and replay tests."""
from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "draft_contract_002", ROOT / "scripts/validate_draft_contract_proposal.py")
draft = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(draft)


def setup(policy_patch=None, *, seed="307"):
    base, rc, catalog, save_plan, plan = draft.fixture()
    policy = copy.deepcopy(plan["policy"])
    if policy_patch:
        policy.update(policy_patch)
    b = draft.start(base, catalog, policy, seed)
    return base, rc, catalog, save_plan, policy, b


def issue(bundle, catalog, policy, uid, kind, offer=None, revision=None):
    active = bundle["draft"]["active"]
    if revision is None and active is not None:
        revision = active["hand_revision"]
    return draft.command(bundle, catalog, policy, uid=uid, kind=kind,
                         offer_id=offer, expected_hand_revision=revision)


class DraftPolicyTests(unittest.TestCase):
    def test_complete_two_level_witness_and_resumable_log(self):
        result = draft.make_demo()
        self.assertEqual(result["draft_openings"], 2)
        self.assertEqual(result["build_revision"], 9)
        self.assertEqual(result["next_reward_kind"], "RITUAL_REWARD")
        self.assertTrue(result["replayed"])

    def test_fixed_seed_and_catalog_replay_same_hand_and_rng_counter(self):
        _, _, cat, _, policy, one = setup()
        _, _, _, _, _, two = setup()
        a = issue(one, cat, policy, "sample.open.1", "OPEN")
        b = issue(two, cat, policy, "sample.open.1", "OPEN")
        self.assertEqual(a, b)

    def test_catalog_offer_insertion_order_does_not_change_draw(self):
        base, rc, cat, save_plan, policy, a = setup()
        changed = copy.deepcopy(cat)
        changed["offers"].reverse()
        b = draft.start(base, changed, policy, "307")
        a = issue(a, cat, policy, "sample.open.1", "OPEN")
        b = issue(b, changed, policy, "sample.open.1", "OPEN")
        self.assertEqual(a["draft"]["active"]["cards"],
                         b["draft"]["active"]["cards"])
        self.assertEqual(a["draft"]["rng"]["counter"],
                         b["draft"]["rng"]["counter"])

    def test_hand_has_no_duplicates_and_is_subset_of_eligibility(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open.1", "OPEN")
        cards = draft.view(b, cat, policy)["cards"]
        self.assertEqual(len(cards), len(set(cards)))
        self.assertLessEqual(len(cards), policy["hand_size"])
        self.assertLessEqual(set(cards), set(draft.valid_ids(
            cat, b["build"], b["draft"]["banned_ids"])))

    def test_range_rejection_not_biased_modulo_tail(self):
        last = (1 << 256) - 1
        self.assertIsNone(draft.unbiased_mod(last, 3))
        self.assertEqual(draft.unbiased_mod(0, 3), 0)
        self.assertEqual(draft.unbiased_mod(1, 3), 1)
        self.assertEqual(draft.unbiased_mod(2, 3), 2)

    def test_uniform_reducer_rejects_invalid_bounds(self):
        with self.assertRaisesRegex(draft.ContractError, "total integer weight"):
            draft.unbiased_mod(2, 0)
        with self.assertRaisesRegex(draft.ContractError, "raw draw"):
            draft.unbiased_mod(1 << 256, 5)

    def test_rng_counter_is_advanced_only_on_actual_draw(self):
        _, _, cat, _, policy, b = setup()
        self.assertEqual(b["draft"]["rng"]["counter"], 0)
        b = issue(b, cat, policy, "sample.open.1", "OPEN")
        self.assertGreater(b["draft"]["rng"]["counter"], 0)
        counter = b["draft"]["rng"]["counter"]
        first = b["draft"]["active"]["cards"][0]
        b = issue(b, cat, policy, "sample.lock", "LOCK", first)
        self.assertEqual(b["draft"]["rng"]["counter"], counter)

    def test_rng_separates_runs_even_same_seed_and_choice_uid(self):
        _, _, cat, _, policy, b = setup()
        a = copy.deepcopy(b["draft"])
        other = copy.deepcopy(a)
        other["run_uid"] = "sample.run.isolated"
        self.assertNotEqual(draft.raw256(a, "sample.choice.uid"),
                            draft.raw256(other, "sample.choice.uid"))

    def test_rng_separates_choice_uids(self):
        _, _, _, _, _, b = setup()
        a = copy.deepcopy(b["draft"])
        other = copy.deepcopy(a)
        self.assertNotEqual(draft.raw256(a, "sample.choice.one"),
                            draft.raw256(other, "sample.choice.two"))

    def test_seed_rejects_noncanonical_uint64(self):
        base, _, cat, _, policy, _ = setup()
        for bad in ("-1", "03", "", str(2**64), "a", 10):
            with self.subTest(seed=bad):
                with self.assertRaises(draft.ContractError):
                    draft.start(base, cat, policy, bad)

    def test_weight_is_integer_positive_not_bool(self):
        base, _, cat, _, policy, _ = setup()
        for invalid in (0, -1, True, 1.1, 2**32):
            mutated = copy.deepcopy(cat)
            mutated["offers"][0]["weight"] = invalid
            with self.subTest(weight=invalid):
                with self.assertRaisesRegex(draft.ContractError, "weight"):
                    draft.start(base, mutated, policy, "307")

    def test_unknown_protected_offer_rejected(self):
        base, _, cat, _, policy, _ = setup()
        policy["protected_ids"] = ["sample.offer.not_authored"]
        with self.assertRaisesRegex(draft.ContractError, "protected IDs"):
            draft.start(base, cat, policy, "307")

    def test_unimplemented_magic_fallback_rejected(self):
        base, _, cat, _, policy, _ = setup()
        policy["empty_policy"] = "AUTO_GRANT_POWER"
        with self.assertRaisesRegex(draft.ContractError, "fallback not implemented"):
            draft.start(base, cat, policy, "307")

    def test_oversized_hand_offers_only_real_eligible_cards(self):
        _, _, cat, _, policy, b = setup({"hand_size": 100})
        b = issue(b, cat, policy, "sample.open", "OPEN")
        self.assertEqual(set(draft.view(b, cat, policy)["cards"]),
                         set(draft.valid_ids(cat, b["build"], [])))
        self.assertFalse(draft.view(b, cat, policy)["can_reroll"])

    def test_larger_pool_reroll_exposes_fresh_card_and_costs_exactly_one(self):
        _, _, cat, _, policy, b = setup({"hand_size": 1})
        b = issue(b, cat, policy, "sample.open", "OPEN")
        first = set(draft.view(b, cat, policy)["cards"])
        b2 = issue(b, cat, policy, "sample.reroll", "REROLL")
        self.assertTrue(set(draft.view(b2, cat, policy)["cards"]) - first)
        self.assertEqual(b2["draft"]["rerolls_left"], b["draft"]["rerolls_left"] - 1)

    def test_reroll_when_all_cards_displayed_rejects_without_charge(self):
        _, _, cat, _, policy, b = setup({"hand_size": 100})
        b = issue(b, cat, policy, "sample.open", "OPEN")
        old = copy.deepcopy(b)
        with self.assertRaisesRegex(draft.ContractError, "cannot show a new"):
            issue(b, cat, policy, "sample.reroll", "REROLL")
        self.assertEqual(b, old)

    def test_lock_keeps_card_during_reroll_and_does_not_move_rng(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        locked = b["draft"]["active"]["cards"][0]
        rng_before = b["draft"]["rng"]["counter"]
        b = issue(b, cat, policy, "sample.lock", "LOCK", locked)
        self.assertEqual(b["draft"]["rng"]["counter"], rng_before)
        if draft.view(b, cat, policy)["can_reroll"]:
            b = issue(b, cat, policy, "sample.reroll", "REROLL")
            self.assertIn(locked, b["draft"]["active"]["cards"])
            self.assertEqual(b["draft"]["active"]["lock"], locked)

    def test_banish_persists_into_next_earned_level(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open.1", "OPEN")
        banned = b["draft"]["active"]["cards"][-1]
        b = issue(b, cat, policy, "sample.banish.1", "BANISH", banned)
        self.assertIn(banned, b["draft"]["banned_ids"])
        first = b["draft"]["active"]["cards"][0]
        b = issue(b, cat, policy, "sample.select.1", "SELECT", first)
        b = issue(b, cat, policy, "sample.open.2", "OPEN")
        self.assertNotIn(banned, b["draft"]["active"]["cards"])
        self.assertIn(banned, b["draft"]["banned_ids"])
        self.assertEqual(b["draft"]["banishes_left"], policy["banishes"] - 1)

    def test_banish_locked_offer_rejected(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        target = b["draft"]["active"]["cards"][0]
        b = issue(b, cat, policy, "sample.lock", "LOCK", target)
        with self.assertRaisesRegex(draft.ContractError, "unlock before"):
            issue(b, cat, policy, "sample.banish", "BANISH", target)

    def test_no_charges_does_not_allow_reroll_or_banish(self):
        _, _, cat, _, policy, b = setup({"rerolls": 0, "banishes": 0})
        b = issue(b, cat, policy, "sample.open", "OPEN")
        with self.assertRaisesRegex(draft.ContractError, "no rerolls"):
            issue(b, cat, policy, "sample.reroll", "REROLL")
        with self.assertRaisesRegex(draft.ContractError, "no banish"):
            issue(b, cat, policy, "sample.banish", "BANISH",
                  b["draft"]["active"]["cards"][0])

    def test_duplicate_command_receipt_does_not_recharge_or_respend(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        target = b["draft"]["active"]["cards"][-1]
        b = issue(b, cat, policy, "sample.banish", "BANISH", target)
        old = copy.deepcopy(b)
        repeated = draft.command(
            b, cat, policy, uid="sample.banish", kind="BANISH",
            offer_id=target, expected_hand_revision=1)
        self.assertEqual(repeated, old)

    def test_reusing_action_uid_with_different_arguments_rejected(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        target = b["draft"]["active"]["cards"][0]
        b = issue(b, cat, policy, "sample.lock", "LOCK", target)
        with self.assertRaisesRegex(draft.ContractError, "interaction UID conflict"):
            draft.command(b, cat, policy, uid="sample.lock", kind="UNLOCK",
                          offer_id=target, expected_hand_revision=1)

    def test_stale_hand_revision_cannot_consume_reward(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        target = b["draft"]["active"]["cards"][0]
        b = issue(b, cat, policy, "sample.lock", "LOCK", target)
        with self.assertRaisesRegex(draft.ContractError, "stale draft hand revision"):
            draft.command(b, cat, policy, uid="sample.select", kind="SELECT",
                          offer_id=target, expected_hand_revision=1)
        self.assertEqual(b["run"]["build_revision"], 7)

    def test_select_rejects_nonvisible_even_if_globally_eligible(self):
        _, _, cat, _, policy, b = setup({"hand_size": 1})
        b = issue(b, cat, policy, "sample.open", "OPEN")
        hidden = next(x for x in draft.valid_ids(cat, b["build"], [])
                      if x not in b["draft"]["active"]["cards"])
        with self.assertRaisesRegex(draft.ContractError, "not displayed"):
            issue(b, cat, policy, "sample.select", "SELECT", hidden)

    def test_duplicate_select_keeps_committed_build_revision(self):
        _, _, cat, _, policy, b = setup()
        b = issue(b, cat, policy, "sample.open", "OPEN")
        target = b["draft"]["active"]["cards"][0]
        revision = b["draft"]["active"]["hand_revision"]
        b = issue(b, cat, policy, "sample.select", "SELECT", target)
        duplicate = draft.command(
            b, cat, policy, uid="sample.select", kind="SELECT",
            offer_id=target, expected_hand_revision=revision)
        self.assertEqual(duplicate, b)
        self.assertEqual(duplicate["build"]["revision"], 8)

    def test_ban_all_pool_explicit_skip_not_free_card(self):
        _, _, cat, _, policy, b = setup()
        b["draft"]["banned_ids"] = draft.valid_ids(cat, b["build"], [])
        b = issue(b, cat, policy, "sample.open", "OPEN")
        ui = draft.view(b, cat, policy)
        self.assertEqual(ui["cards"], [])
        self.assertEqual(ui["fallback_reason"], "ALL_ELIGIBLE_BANNED")
        self.assertTrue(ui["fallback_requires_explicit_action"])
        with self.assertRaisesRegex(draft.ContractError, "not displayed"):
            issue(b, cat, policy, "sample.select", "SELECT", "sample.offer.echo")
        b = issue(b, cat, policy, "sample.skip", "SKIP")
        self.assertEqual(b["build"]["revision"], 8)
        self.assertEqual(len(b["run"]["pending_choices"]), 3)

    def test_no_offer_is_not_automatically_awarded(self):
        _, _, cat, _, policy, b = setup()
        b["draft"]["banned_ids"] = draft.valid_ids(cat, b["build"], [])
        before = b["run"]["build_revision"]
        b = issue(b, cat, policy, "sample.open", "OPEN")
        self.assertEqual(b["run"]["build_revision"], before)
        self.assertEqual(len(b["run"]["pending_choices"]), 4)

    def test_pity_protects_only_currently_eligible_offer_on_second_hand(self):
        _, _, cat, _, policy, baseline = setup({"hand_size": 1, "pity_after": 2})
        found = None
        for seed in range(1, 100):
            b = draft.start(draft.save.sample_checkpoint()[0], cat, policy, str(seed))
            b = issue(b, cat, policy, "sample.open.1", "OPEN")
            hand = b["draft"]["active"]["cards"]
            if hand and "sample.offer.echo" not in hand:
                found = b
                break
        self.assertIsNotNone(found)
        b = found
        self.assertEqual(b["draft"]["pity_misses"], 1)
        b = issue(b, cat, policy, "sample.select.1", "SELECT",
                  b["draft"]["active"]["cards"][0])
        b = issue(b, cat, policy, "sample.open.2", "OPEN")
        ui = draft.view(b, cat, policy)
        self.assertTrue(ui["pity_guarantee_applied"])
        self.assertIn("sample.offer.echo", ui["cards"])
        self.assertEqual(ui["pity_misses"], 0)

    def test_pity_does_not_create_banned_cards(self):
        _, _, cat, _, policy, b = setup({"hand_size": 1, "pity_after": 1})
        b["draft"]["banned_ids"] = ["sample.offer.echo"]
        b = issue(b, cat, policy, "sample.open", "OPEN")
        self.assertNotIn("sample.offer.echo", b["draft"]["active"]["cards"])
        self.assertFalse(b["draft"]["active"]["forced_pity"])

    def test_policy_conflict_rejected_after_start(self):
        _, _, cat, _, policy, b = setup()
        changed = copy.deepcopy(policy)
        changed["pity_after"] += 1
        with self.assertRaisesRegex(draft.ContractError, "policy/catalog version"):
            issue(b, cat, changed, "sample.open", "OPEN")

    def test_catalog_drift_rejected_after_start(self):
        _, _, cat, _, policy, b = setup()
        changed = copy.deepcopy(cat)
        changed["offers"][0]["weight"] += 1
        with self.assertRaisesRegex(draft.ContractError, "policy/catalog version"):
            issue(b, changed, policy, "sample.open", "OPEN")

    def test_open_rejects_mandatory_ritual_after_consuming_two_levels(self):
        _, _, cat, _, policy, b = setup()
        for i in range(2):
            b = issue(b, cat, policy, f"sample.open.{i}", "OPEN")
            target = b["draft"]["active"]["cards"][0]
            b = issue(b, cat, policy, f"sample.select.{i}", "SELECT", target)
        with self.assertRaisesRegex(draft.ContractError, "only paused ordinary"):
            issue(b, cat, policy, "sample.open.ritual", "OPEN")

    def test_overlay_restore_equals_uninterrupted_and_resists_resealed_tamper(self):
        base, rc, cat, save_plan, policy, b = setup()
        actions = []
        def apply(uid, kind, offer=None):
            nonlocal b
            hand = b["draft"]["active"]
            row = {"uid": uid, "kind": kind, "offer_id": offer,
                   "expected_hand_revision": hand["hand_revision"] if hand else None}
            b = draft.command(b, cat, policy, **row)
            actions.append(row)
        apply("sample.open.1", "OPEN")
        apply("sample.banish.1", "BANISH", b["draft"]["active"]["cards"][1])
        apply("sample.select.1", "SELECT", b["draft"]["active"]["cards"][0])
        apply("sample.open.2", "OPEN")
        sealed = draft.seal_overlay(base, cat, policy, "307", actions, b)
        loaded = json.loads(json.dumps(sealed))
        self.assertEqual(draft.verify_overlay(loaded, base, rc, cat, save_plan, policy), b)
        loaded["bundle"]["draft"]["rng"]["counter"] += 1
        loaded["checksum"] = draft.hash_value({
            k: v for k, v in loaded.items() if k != "checksum"})
        with self.assertRaisesRegex(draft.ContractError, "diverged from deterministic replay"):
            draft.verify_overlay(loaded, base, rc, cat, save_plan, policy)

    def test_overlay_rejects_dropped_command_even_if_resealed(self):
        base, rc, cat, save_plan, policy, b = setup()
        opening = {"uid": "sample.open", "kind": "OPEN", "offer_id": None,
                   "expected_hand_revision": None}
        b = draft.command(b, cat, policy, **opening)
        overlay = draft.seal_overlay(base, cat, policy, "307", [opening], b)
        overlay["commands"] = []
        overlay["checksum"] = draft.hash_value({
            k: v for k, v in overlay.items() if k != "checksum"})
        with self.assertRaisesRegex(draft.ContractError, "diverged from deterministic replay"):
            draft.verify_overlay(overlay, base, rc, cat, save_plan, policy)

    def test_overlay_rejects_duplicate_interaction_id(self):
        base, rc, cat, save_plan, policy, b = setup()
        opening = {"uid": "sample.open", "kind": "OPEN", "offer_id": None,
                   "expected_hand_revision": None}
        b = draft.command(b, cat, policy, **opening)
        overlay = draft.seal_overlay(base, cat, policy, "307", [opening, opening], b)
        with self.assertRaisesRegex(draft.ContractError, "duplicate interaction UID"):
            draft.verify_overlay(overlay, base, rc, cat, save_plan, policy)

    def test_overlay_rejects_changed_base_checkpoint(self):
        base, rc, cat, save_plan, policy, b = setup()
        overlay = draft.seal_overlay(base, cat, policy, "307", [], b)
        changed = copy.deepcopy(base)
        changed["state"]["run"]["xp_bank"] += 5
        changed = draft.save.seal(changed)
        with self.assertRaises((draft.ContractError, draft.save.ContractError)):
            draft.verify_overlay(overlay, changed, rc, cat, save_plan, policy)


if __name__ == "__main__":
    unittest.main()
