"""CHOICE-SAVE-002: integrated SaveEnvelope v2 for run, build and draft (design oracle)."""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_choice_save", ROOT / "scripts/validate_choice_save_proposal.py")
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)
ERRORS = cs.ERRORS


def cmd(uid, kind, offer=None, rev=None):
    return {"uid": uid, "kind": kind, "offer_id": offer, "expected_hand_revision": rev}


class ChoiceSaveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan, cls.v1, cls.rc, cls.bc, cls.sp, cls.policy = cs.fixture()
        cls.ctx = (cls.rc, cls.bc, cls.sp, cls.policy)
        _, cls.checkpoint, cls.final, cls.store = cs.run_golden()

    def resealed(self, mutate, doc=None):
        doc = copy.deepcopy(self.checkpoint if doc is None else doc)
        mutate(doc)
        return cs.save.seal(doc)

    def assertRejected(self, doc, pattern):
        with self.assertRaisesRegex(ERRORS, pattern):
            cs.validate(doc, *self.ctx)

    # -- golden and reload
    def test_golden_fixture(self):
        self.assertEqual(cs.verify_fixture()["final_build_revision"], 10)

    def test_reload_restores_same_hand_cursor_and_history(self):
        restored = cs.parse(cs.serialize(self.checkpoint))
        bundle = cs.validate(restored, *self.ctx)
        hand = restored["state"]["draft"]["active"]
        self.assertEqual(hand["cards"], self.plan["expected"]["checkpoint_cards"])
        self.assertEqual(str(bundle["draft"]["rng"]["counter"]), restored["rng_policy"]["streams"]["offers"]["cursor"])
        self.assertEqual(restored["draft_commands"], self.plan["before_checkpoint"])

    def test_final_state_matches_save_contract_001_resume(self):
        self.assertEqual(self.final["state"]["run"]["xp_bank"], 3)
        self.assertIn("sample.skill.thousand_swords", {s["id"] for s in self.final["state"]["build"]["active"]})

    # -- single authoritative cursor
    def test_advanced_offers_cursor_is_rejected_even_with_valid_checksum(self):
        doc = self.resealed(lambda d: d["rng_policy"]["streams"]["offers"].update(cursor="4"))
        self.assertRejected(doc, "offers cursor differs")

    def test_second_cursor_copy_in_draft_state_is_rejected(self):
        doc = self.resealed(lambda d: d["state"]["draft"].update(rng={"counter": 3}))
        self.assertRejected(doc, "cursor must live only in rng_policy")

    def test_other_stream_cursor_without_journal_is_rejected(self):
        doc = self.resealed(lambda d: d["rng_policy"]["streams"]["enemy"].update(cursor="1"))
        self.assertRejected(doc, "enemy cursor not justified")

    # -- state tampering
    def test_tampered_hand_is_rejected(self):
        doc = self.resealed(lambda d: d["state"]["draft"]["active"].update(cards=["sample.offer.echo",
                                                                                 "sample.offer.new_thunder"]))
        self.assertRejected(doc, "draft diverges")

    def test_refunded_reroll_charge_is_rejected(self):
        doc = self.resealed(lambda d: d["state"]["draft"].update(rerolls_left=2))
        self.assertRejected(doc, "draft diverges")

    def test_forgotten_ban_is_rejected(self):
        doc = self.resealed(lambda d: d["state"]["draft"].update(banned_ids=[]), self.final)
        self.assertRejected(doc, "draft diverges")

    def test_bad_checksum_is_rejected(self):
        doc = copy.deepcopy(self.checkpoint)
        doc["state"]["draft"]["rerolls_left"] = 2
        self.assertRejected(doc, "checksum")

    # -- identity and versions
    def test_changed_draft_policy_refuses_resume(self):
        policy = copy.deepcopy(self.policy)
        policy["rerolls"] = 3
        with self.assertRaisesRegex(ERRORS, "rules hash mismatch"):
            cs.validate(self.checkpoint, self.rc, self.bc, self.sp, policy)

    def test_unknown_schema_version_is_rejected(self):
        doc = copy.deepcopy(self.checkpoint)
        doc["schema_version"] = 99
        with self.assertRaisesRegex(ERRORS, "unknown save schema"):
            cs.load_any(doc, *self.ctx)

    def test_unknown_header_field_is_rejected(self):
        doc = self.resealed(lambda d: d["header"].update(extra=1))
        self.assertRejected(doc, "header field")

    # -- commands after reload
    def test_stale_hand_revision_after_reload_is_rejected(self):
        with self.assertRaisesRegex(ERRORS, "stale draft hand revision"):
            cs.append(self.checkpoint, *self.ctx, cmd("cs.x", "SELECT", "sample.offer.echo", 2))

    def test_identical_retry_is_idempotent_and_conflict_is_rejected(self):
        again = cs.append(self.checkpoint, *self.ctx, copy.deepcopy(self.plan["before_checkpoint"][-1]))
        self.assertEqual(again, self.checkpoint)
        with self.assertRaisesRegex(ERRORS, "conflict"):
            cs.append(self.checkpoint, *self.ctx, cmd("cs.reroll.1", "REROLL", None, 3))

    def test_old_confirmation_cannot_pay_next_level(self):
        after = cs.append(self.checkpoint, *self.ctx, cmd("cs.select.1", "SELECT", "sample.offer.echo", 3))
        with self.assertRaisesRegex(ERRORS, "no active draft hand"):
            cs.append(after, *self.ctx, cmd("cs.select.late", "SELECT", "sample.offer.echo", 3))

    def test_banned_offer_never_returns_after_reload(self):
        reloaded = cs.parse(cs.serialize(self.final))
        cs.validate(reloaded, *self.ctx)
        banned = set(reloaded["state"]["draft"]["banned_ids"])
        self.assertTrue(banned)
        for row in reloaded["draft_commands"]:
            if row["kind"] == "SELECT":
                self.assertNotIn(row["offer_id"], banned)

    def test_resolve_needs_closed_hand_and_applicable_recipe(self):
        with self.assertRaisesRegex(ERRORS, "close the draft hand"):
            cs.append(self.checkpoint, *self.ctx, cmd("cs.r", "RESOLVE", "sample.evolution.thousand_swords"))
        with self.assertRaisesRegex(ERRORS, "not applicable|pending ritual"):
            cs.append(self.final, *self.ctx, cmd("cs.r2", "RESOLVE", "sample.evolution.thousand_swords"))

    # -- focus
    def test_confirm_is_disarmed_after_load(self):
        focus = cs.restore_focus(cs.parse(cs.serialize(self.checkpoint)))
        self.assertFalse(focus["confirm_armed"])
        self.assertEqual(focus["focused_offer"], self.checkpoint["presentation"]["focus_offer"])
        with self.assertRaisesRegex(ERRORS, "not armed"):
            cs.confirm(self.checkpoint, focus, "cs.c")
        self.assertEqual(cs.confirm(self.checkpoint, cs.release_all(focus), "cs.c")["kind"], "SELECT")

    def test_focus_hint_must_be_visible_card(self):
        doc = self.resealed(lambda d: d["presentation"].update(focus_offer="sample.offer.new_thunder"))
        self.assertRejected(doc, "focus hint")

    def test_stale_focus_after_hand_change_is_rejected(self):
        focus = cs.release_all(cs.restore_focus(self.checkpoint))
        changed = cs.append(self.checkpoint, *self.ctx, cmd("cs.unlock", "UNLOCK", None, 3))
        with self.assertRaisesRegex(ERRORS, "stale focus"):
            cs.confirm(changed, focus, "cs.c")

    # -- crash while choosing
    def test_torn_primary_falls_back_to_backup_without_losing_the_choice(self):
        after = cs.append(self.checkpoint, *self.ctx, cmd("cs.select.1", "SELECT", "sample.offer.echo", 3))
        store = cs.write_slots(self.store, after, *self.ctx)
        self.assertEqual(cs.parse(store["backup"]), self.checkpoint)
        torn = dict(store, primary=store["primary"][: len(store["primary"]) // 2])
        doc, slot = cs.load_slots(torn, *self.ctx)
        self.assertEqual(slot, "backup")
        self.assertEqual(doc["state"]["draft"]["active"]["choice_uid"],
                         self.checkpoint["state"]["draft"]["active"]["choice_uid"])
        redo = cs.append(doc, *self.ctx, cmd("cs.select.1", "SELECT", "sample.offer.echo", 3))
        self.assertEqual(redo, after)

    def test_both_slots_corrupt_fail_closed(self):
        with self.assertRaisesRegex(ERRORS, "fail closed"):
            cs.load_slots({"primary": "{", "backup": "{\"schema_version\": 2}"}, *self.ctx)

    def test_invalid_save_is_never_written(self):
        bad = self.resealed(lambda d: d["rng_policy"]["streams"]["offers"].update(cursor="9"))
        with self.assertRaises(ERRORS):
            cs.write_slots(self.store, bad, *self.ctx)

    # -- migration
    def test_v1_migrates_losslessly_and_loads_through_load_any(self):
        doc = cs.load_any(copy.deepcopy(self.v1), *self.ctx)
        self.assertEqual(doc["schema_version"], 2)
        self.assertEqual(doc["rng_policy"]["streams"]["offers"]["cursor"], "0")
        self.assertEqual(doc["state"]["build"], self.v1["state"]["build"])

    def test_v1_with_advanced_cursor_and_no_journal_is_refused(self):
        v1 = copy.deepcopy(self.v1)
        v1["rng_policy"]["streams"]["offers"]["cursor"] = "5"
        with self.assertRaises(ERRORS):
            cs.migrate_v1(cs.save.seal(v1), *self.ctx)

    def test_v1_plus_draft_overlay_equals_native_v2_replay(self):
        draft = cs.draft
        bundle = draft.start(self.v1, self.bc, self.policy, self.sp["rng_policy"]["streams"]["offers"]["seed"])
        history = [cmd("ov.open", "OPEN"), cmd("ov.lock", "LOCK", "sample.offer.echo", 1),
                   cmd("ov.select", "SELECT", "sample.offer.echo", 2)]
        for row in history:
            bundle = draft.command(bundle, self.bc, self.policy, **row)
        overlay = draft.seal_overlay(self.v1, self.bc, self.policy,
                                     self.sp["rng_policy"]["streams"]["offers"]["seed"], history, bundle)
        migrated = cs.migrate_v1(self.v1, *self.ctx, overlay=overlay)
        native = cs.build_snapshot(self.rc, self.bc, self.sp, self.policy, self.v1["receipts"],
                                   self.v1["choice_actions"], history)
        self.assertEqual(migrated, native)
        self.assertEqual(migrated["rng_policy"]["streams"]["offers"]["cursor"], str(bundle["draft"]["rng"]["counter"]))

    def test_overlay_for_another_base_is_rejected(self):
        draft = cs.draft
        bundle = draft.start(self.v1, self.bc, self.policy, "307")
        overlay = draft.seal_overlay(self.v1, self.bc, self.policy, "307", [], bundle)
        overlay["base_save_checksum"] = "0" * 64
        overlay = {k: v for k, v in overlay.items() if k != "checksum"}
        overlay["checksum"] = cs.save.hash_json(overlay)
        with self.assertRaises(ERRORS):
            cs.migrate_v1(self.v1, *self.ctx, overlay=overlay)


if __name__ == "__main__":
    unittest.main()
