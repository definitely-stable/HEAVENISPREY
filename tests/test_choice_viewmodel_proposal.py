"""CHOICE-VIEWMODEL-001 static/proposal acceptance and negative tests.

No user interface, no gameplay or approved randomization weights.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "choice_viewmodel", ROOT / "scripts/validate_choice_viewmodel_proposal.py")
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def baseline():
    base, rc, bc, save_plan = oracle.save.sample_checkpoint()
    plan = oracle.read_plan()
    run, build = base["state"]["run"], base["state"]["build"]
    draft = oracle.start_draft(
        run, build, bc, seed=plan["seed"], hand_size=plan["hand_size"],
        rerolls=plan["rerolls"], banishes=plan["banishes"])
    return base, rc, bc, save_plan, plan, run, build, draft

def before_first_choice():
    """Rev 6 has four eligible offers for a 3-card hand: meaningful rerolls."""
    saved, rc, bc, save_plan = oracle.save.sample_checkpoint()
    base = oracle.save.snapshot_from_journal(
        rc, bc, save_plan, saved["receipts"], [])
    run, build = base["state"]["run"], base["state"]["build"]
    draft = oracle.start_draft(run, build, bc, seed="307", hand_size=3,
                               rerolls=2, banishes=2)
    assert len(oracle.eligible_ids(bc, build, [])) > len(draft["hand"])
    return bc, run, build, draft


def action(draft, run, build, catalog, uid, kind, offer=None):
    return oracle.act(draft, run, build, catalog, uid=uid, kind=kind,
                      offer_id=offer, expected_revision=draft["state_revision"])


class ChoiceViewModelTests(unittest.TestCase):
    def test_end_to_end_draft_overlay_reference(self):
        result = oracle.verify_fixture()
        self.assertTrue(result["verified_overlay"])
        self.assertEqual(result["cards"], 2)
        self.assertEqual(result["rerolls_left"], 2)
        self.assertEqual(result["banishes_left"], 1)
        self.assertEqual(result["choice_still_earned"], 4)

    def test_stable_weighted_draft_given_same_build_and_seed(self):
        base, rc, bc, _, plan, run, build, draft = baseline()
        another = oracle.start_draft(
            run, build, bc, seed=plan["seed"], hand_size=plan["hand_size"],
            rerolls=plan["rerolls"], banishes=plan["banishes"])
        self.assertEqual(draft, another)
        self.assertEqual(len(draft["hand"]), len(set(draft["hand"])))

    def test_different_json_catalog_offer_order_does_not_change_hand(self):
        _, _, bc, _, plan, run, build, draft = baseline()
        changed = copy.deepcopy(bc)
        changed["offers"].reverse()
        another = oracle.start_draft(
            run, build, changed, seed=plan["seed"], hand_size=plan["hand_size"],
            rerolls=plan["rerolls"], banishes=plan["banishes"])
        self.assertEqual(draft, another)

    def test_earned_choice_not_consumed_by_reroll_banish_lock(self):
        _, _, bc, _, _, run, build, draft = baseline()
        before_run = copy.deepcopy(run)
        before_build = copy.deepcopy(build)
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        draft = action(draft, run, build, bc, "sample.banish", "BANISH",
                       "sample.offer.new_thunder")
        self.assertEqual(run, before_run)
        self.assertEqual(build, before_build)
        self.assertEqual(run["build_revision"], 7)
        self.assertEqual(len(run["pending_choices"]), 4)

    def test_locked_offer_survives_reroll(self):
        bc, run, build, draft = before_first_choice()
        locked = draft["hand"][0]
        before_hand = set(draft["hand"])
        draft = action(draft, run, build, bc, "sample.lock", "LOCK", locked)
        draft = action(draft, run, build, bc, "sample.reroll", "REROLL")
        self.assertEqual(draft["locked_offer"], locked)
        self.assertIn(locked, draft["hand"])
        self.assertTrue(set(draft["hand"]) - before_hand,
                        "reroll with alternatives must reveal a new card")

    def test_banished_offer_not_in_current_hand(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.banish", "BANISH",
                       "sample.offer.new_thunder")
        self.assertIn("sample.offer.new_thunder", draft["banned_ids"])
        self.assertNotIn("sample.offer.new_thunder", draft["hand"])

    def test_ban_is_persistable_to_next_choice(self):
        _, _, bc, _, plan, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.banish", "BANISH",
                       "sample.offer.new_thunder")
        replayed = oracle.start_draft(
            run, build, bc, seed=plan["seed"], hand_size=3,
            rerolls=1, banishes=1, banned_ids=draft["banned_ids"])
        self.assertNotIn("sample.offer.new_thunder", replayed["hand"])

    def test_duplicate_same_reroll_receipt_is_noop(self):
        bc, run, build, draft = before_first_choice()
        advanced = action(draft, run, build, bc, "sample.repeat", "REROLL")
        second = oracle.act(advanced, run, build, bc, uid="sample.repeat",
                            kind="REROLL", offer_id=None,
                            expected_revision=draft["state_revision"])
        self.assertEqual(advanced, second)
        self.assertEqual(advanced["rerolls_left"], draft["rerolls_left"] - 1)

    def test_same_action_uid_with_different_args_rejected(self):
        bc, run, build, draft = before_first_choice()
        advanced = action(draft, run, build, bc, "sample.same", "REROLL")
        with self.assertRaisesRegex(oracle.ContractError, "action UID conflict"):
            oracle.act(advanced, run, build, bc, uid="sample.same", kind="LOCK",
                       offer_id="sample.offer.echo",
                       expected_revision=draft["state_revision"])

    def test_stale_hand_revision_does_not_charge_resources(self):
        bc, run, build, draft = before_first_choice()
        advanced = action(draft, run, build, bc, "sample.reroll", "REROLL")
        before = copy.deepcopy(advanced)
        with self.assertRaisesRegex(oracle.ContractError, "stale draft state revision"):
            oracle.act(advanced, run, build, bc, uid="sample.next", kind="REROLL",
                       expected_revision=1)
        self.assertEqual(advanced, before)

    def test_reroll_does_not_spend_charge_on_exhausted_pool(self):
        _, _, bc, _, _, run, build, draft = baseline()
        before = copy.deepcopy(draft)
        self.assertFalse(oracle.view(draft, run, build, bc)["can_reroll"])
        with self.assertRaisesRegex(oracle.ContractError, "cannot reveal any new"):
            action(draft, run, build, bc, "sample.noop", "REROLL")
        self.assertEqual(draft, before)

    def test_no_rerolls_left_negative(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft["rerolls_left"] = 0
        with self.assertRaisesRegex(oracle.ContractError, "no rerolls left"):
            action(draft, run, build, bc, "sample.none", "REROLL")

    def test_no_banishes_left_negative(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft["banishes_left"] = 0
        with self.assertRaisesRegex(oracle.ContractError, "no banishes left"):
            action(draft, run, build, bc, "sample.none", "BANISH",
                   "sample.offer.echo")

    def test_locked_offer_cannot_be_banished(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        with self.assertRaisesRegex(oracle.ContractError, "unlock card before banish"):
            action(draft, run, build, bc, "sample.banish", "BANISH",
                   "sample.offer.echo")

    def test_two_simultaneously_locked_cards_rejected(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        with self.assertRaisesRegex(oracle.ContractError, "another card already locked"):
            action(draft, run, build, bc, "sample.lock2", "LOCK",
                   "sample.offer.new_thunder")

    def test_unlock_allows_replacement_lock(self):
        _, _, bc, _, _, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        draft = action(draft, run, build, bc, "sample.unlock", "UNLOCK")
        self.assertIsNone(draft["locked_offer"])
        draft = action(draft, run, build, bc, "sample.lock.new", "LOCK",
                       "sample.offer.new_thunder")
        self.assertEqual(draft["locked_offer"], "sample.offer.new_thunder")

    def test_card_view_is_grounded_and_does_not_mutate_build(self):
        _, _, bc, _, _, run, build, draft = baseline()
        old = copy.deepcopy(build)
        vm = oracle.view(draft, run, build, bc)
        self.assertEqual(vm["queue_remaining"], 4)
        self.assertEqual(vm["build_revision"], 7)
        for card in vm["cards"]:
            self.assertEqual(card["source_choice_uid"], run["pending_choices"][0]["uid"])
            self.assertIsNone(card["numerical_damage_delta"])
            self.assertIsNone(card["localized_title"])
            self.assertIn(card["offer_id"], draft["hand"])
        self.assertEqual(build, old)

    def test_preview_full_rank_unlocks_recipe_without_invented_dps(self):
        bridge = oracle.load_module(
            "choice_integration_bridge", ROOT / "scripts/validate_choice_bridge_proposal.py")
        catalog, run, build = bridge.sample_run_and_build()
        draft = oracle.start_draft(run, build, catalog, seed="307",
                                   hand_size=20, rerolls=1, banishes=1)
        sword = next(card for card in oracle.view(draft, run, build, catalog)["cards"]
                     if card["offer_id"] == "sample.offer.sword_rank")
        self.assertEqual((sword["current_active_rank"], sword["next_active_rank"]), (4, 5))
        self.assertEqual(sword["newly_eligible_rituals"],
                         ["sample.evolution.thousand_swords"])
        self.assertEqual(sword["active_slots_delta"], 0)
        self.assertIsNone(sword["numerical_damage_delta"])

    def test_view_handles_power_stack_delta(self):
        _, _, bc, _, _, run, build, draft = baseline()
        card = next(x for x in oracle.view(draft, run, build, bc)["cards"]
                    if x["offer_id"] == "sample.offer.echo")
        self.assertEqual(card["power_stack_delta"], 1)

    def test_stale_build_revision_disables_draft_before_commit(self):
        _, _, bc, _, _, run, build, draft = baseline()
        changed = copy.deepcopy(build)
        changed["revision"] += 1
        with self.assertRaisesRegex(oracle.ContractError, "run/build revision mismatch"):
            oracle.view(draft, run, changed, bc)

    def test_unsupported_mandatory_ritual_is_not_general_draft(self):
        _, _, bc, _, _, run, build, draft = baseline()
        altered = copy.deepcopy(run)
        altered["pending_choices"][0]["kind"] = "RITUAL_REWARD"
        with self.assertRaisesRegex(oracle.ContractError, "supports level-up only"):
            oracle.start_draft(altered, build, bc, seed="307",
                               hand_size=3, rerolls=1, banishes=1)

    def test_selection_is_from_visible_hand_and_commits_once(self):
        _, _, bc, _, _, run, build, draft = baseline()
        chosen = "sample.offer.echo"
        result = oracle.consume(
            run, build, draft, bc, uid="sample.consume.1",
            kind="SELECT", offer_id=chosen,
            expected_state_revision=draft["state_revision"])
        self.assertEqual(result["selected_token"], chosen)
        self.assertEqual(result["run"]["build_revision"], 8)
        self.assertEqual(result["build"]["revision"], 8)
        self.assertEqual(len(result["run"]["pending_choices"]), 3)
        self.assertEqual(run["build_revision"], 7)

    def test_selection_of_hidden_card_is_rejected(self):
        _, _, bc, _, _, run, build, draft = baseline()
        with self.assertRaisesRegex(oracle.ContractError, "selection not in visible hand"):
            oracle.consume(run, build, draft, bc,
                           uid="sample.consume.ineligible", kind="SELECT",
                           offer_id="sample.offer.sword_rank",
                           expected_state_revision=draft["state_revision"])

    def test_selection_with_old_hand_revision_is_rejected(self):
        _, _, bc, _, _, run, build, draft = baseline()
        with self.assertRaisesRegex(oracle.ContractError, "stale visible card hand"):
            oracle.consume(run, build, draft, bc, uid="sample.consume.old",
                           kind="SELECT", offer_id="sample.offer.echo",
                           expected_state_revision=0)

    def test_explicit_skip_consumes_one_reward_not_the_remaining_queue(self):
        _, _, bc, _, _, run, build, draft = baseline()
        result = oracle.consume(run, build, draft, bc,
                                uid="sample.consume.skip", kind="SKIP",
                                offer_id=None,
                                expected_state_revision=draft["state_revision"])
        self.assertEqual(result["selected_token"], "sample.choice.explicit_skip")
        self.assertEqual(result["run"]["build_revision"], 8)
        self.assertEqual(result["build"]["revision"], 8)
        self.assertEqual(build["active"], result["build"]["active"])
        self.assertEqual(len(result["run"]["pending_choices"]), 3)

    def test_skip_with_card_target_fails(self):
        _, _, bc, _, _, run, build, draft = baseline()
        with self.assertRaisesRegex(oracle.ContractError, "SKIP has no offer ID"):
            oracle.consume(run, build, draft, bc, uid="sample.skip.target",
                           kind="SKIP", offer_id="sample.offer.echo",
                           expected_state_revision=draft["state_revision"])

    def test_duplicate_select_acknowledgment_is_idempotent(self):
        _, _, bc, _, _, run, build, draft = baseline()
        state = oracle.transaction_bundle(run, build, draft)
        result = oracle.commit_once(
            state, bc, uid="sample.accept.once", kind="SELECT",
            offer_id="sample.offer.echo",
            expected_state_revision=draft["state_revision"])
        repeated = oracle.commit_once(
            result, bc, uid="sample.accept.once", kind="SELECT",
            offer_id="sample.offer.echo",
            expected_state_revision=draft["state_revision"])
        self.assertEqual(repeated, result)
        self.assertEqual(len(result["run"]["committed_choices"]),
                         len(run["committed_choices"]) + 1)
        self.assertEqual(result["build"]["revision"], build["revision"] + 1)

    def test_conflicting_second_choice_intent_is_rejected(self):
        _, _, bc, _, _, run, build, draft = baseline()
        state = oracle.transaction_bundle(run, build, draft)
        result = oracle.commit_once(
            state, bc, uid="sample.accept.once", kind="SELECT",
            offer_id="sample.offer.echo",
            expected_state_revision=draft["state_revision"])
        with self.assertRaisesRegex(oracle.ContractError, "conflicting committed"):
            oracle.commit_once(
                result, bc, uid="sample.accept.other", kind="SKIP",
                offer_id=None,
                expected_state_revision=draft["state_revision"])

    def test_duplicate_explicit_skip_is_not_paid_twice(self):
        _, _, bc, _, _, run, build, draft = baseline()
        state = oracle.transaction_bundle(run, build, draft)
        result = oracle.commit_once(
            state, bc, uid="sample.accept.skip", kind="SKIP",
            offer_id=None, expected_state_revision=draft["state_revision"])
        repeated = oracle.commit_once(
            result, bc, uid="sample.accept.skip", kind="SKIP",
            offer_id=None, expected_state_revision=draft["state_revision"])
        self.assertEqual(result, repeated)
        self.assertEqual(result["run"]["build_revision"], 8)

    def test_missing_or_duplicate_inputs_cannot_confirm(self):
        _, _, bc, _, _, run, build, draft = baseline()
        f = oracle.open_focus(draft, held_buttons={"CONFIRM", "DODGE"})
        with self.assertRaisesRegex(oracle.ContractError, "held/repeated key"):
            oracle.focus_input(f, draft, button="CONFIRM", transition="PRESS",
                               focused_offer="sample.offer.echo")
        f, intent = oracle.focus_input(f, draft, button="CONFIRM",
                                       transition="RELEASE")
        self.assertIsNone(intent)
        with self.assertRaisesRegex(oracle.ContractError, "confirmation not armed"):
            oracle.focus_input(f, draft, button="CONFIRM", transition="PRESS",
                               focused_offer="sample.offer.echo")
        f, _ = oracle.focus_input(f, draft, button="DODGE", transition="RELEASE")
        f, intent = oracle.focus_input(f, draft, button="CONFIRM",
                                       transition="PRESS",
                                       focused_offer="sample.offer.echo")
        self.assertEqual(intent["offer_id"], "sample.offer.echo")
        self.assertEqual(intent["hand_revision"], draft["state_revision"])

    def test_no_confirm_on_card_without_focus(self):
        _, _, bc, _, _, run, build, draft = baseline()
        focus = oracle.open_focus(draft)
        with self.assertRaisesRegex(oracle.ContractError, "no legal focused card"):
            oracle.focus_input(focus, draft, button="CONFIRM",
                               transition="PRESS", focused_offer=None)

    def test_old_focus_invalid_after_reroll(self):
        bc, run, build, draft = before_first_choice()
        old_focus = oracle.open_focus(draft)
        newer = action(draft, run, build, bc, "sample.reroll", "REROLL")
        with self.assertRaisesRegex(oracle.ContractError, "stale focus session"):
            oracle.focus_input(old_focus, newer, button="CONFIRM",
                               transition="PRESS",
                               focused_offer="sample.offer.echo")

    def test_wrong_input_transition_is_rejected(self):
        _, _, bc, _, _, run, build, draft = baseline()
        with self.assertRaisesRegex(oracle.ContractError, "input transition invalid"):
            oracle.focus_input(oracle.open_focus(draft), draft, button="CONFIRM",
                               transition="AUTOREPEAT",
                               focused_offer="sample.offer.echo")

    def test_overlay_roundtrip_replays_all_draft_actions(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        for a in plan["actions"]:
            draft = action(draft, run, build, bc,
                           a["uid"], a["kind"], a["offer_id"])
        snap = oracle.overlay(base, draft, bc, plan)
        roundtrip = json.loads(json.dumps(snap, sort_keys=True))
        restored = oracle.validate_overlay(roundtrip, base, bc, plan)
        self.assertEqual(restored, draft)
        self.assertEqual(len(restored["actions"]), 2)

    def test_overlay_cannot_be_bound_to_another_base_save(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        snap = oracle.overlay(base, draft, bc, plan)
        wrong = copy.deepcopy(base)
        wrong["state"]["run"]["xp_bank"] += 1
        wrong["checksum"] = oracle.save.hash_json({
            k: v for k, v in wrong.items() if k != "checksum"})
        with self.assertRaisesRegex(oracle.ContractError, "different base save"):
            oracle.validate_overlay(snap, wrong, bc, plan)

    def test_overlay_tampered_card_even_with_new_checksum_rejected(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        snap = oracle.overlay(base, draft, bc, plan)
        snap["draft"]["hand"] = ["sample.offer.sword_rank"]
        snap["checksum"] = oracle.json_hash({
            k: v for k, v in snap.items() if k != "checksum"})
        with self.assertRaisesRegex(oracle.ContractError, "draft state diverges"):
            oracle.validate_overlay(snap, base, bc, plan)

    def test_overlay_tampered_cursor_even_with_new_checksum_rejected(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        snap = oracle.overlay(base, draft, bc, plan)
        snap["draft"]["cursor"] += 5
        snap["checksum"] = oracle.json_hash({
            k: v for k, v in snap.items() if k != "checksum"})
        with self.assertRaisesRegex(oracle.ContractError, "draft state diverges"):
            oracle.validate_overlay(snap, base, bc, plan)

    def test_overlay_duplicate_action_rejected(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        snap = oracle.overlay(base, draft, bc, plan)
        snap["actions"].append(copy.deepcopy(snap["actions"][0]))
        snap["checksum"] = oracle.json_hash({
            k: v for k, v in snap.items() if k != "checksum"})
        with self.assertRaisesRegex(oracle.ContractError, "duplicate draft action UID"):
            oracle.validate_overlay(snap, base, bc, plan)

    def test_overlay_old_state_revision_replay_rejected(self):
        base, rc, bc, save_plan, plan, run, build, draft = baseline()
        draft = action(draft, run, build, bc, "sample.lock", "LOCK",
                       "sample.offer.echo")
        snap = oracle.overlay(base, draft, bc, plan)
        snap["actions"][0]["expected_revision"] = 5
        snap["checksum"] = oracle.json_hash({
            k: v for k, v in snap.items() if k != "checksum"})
        with self.assertRaisesRegex(oracle.ContractError, "stale draft state revision"):
            oracle.validate_overlay(snap, base, bc, plan)


if __name__ == "__main__":
    unittest.main()
