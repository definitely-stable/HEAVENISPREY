"""SAVE-CONTRACT-001: architecture-only checkpoint/replay acceptance cases."""
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "save_contract_proposal", ROOT / "scripts/validate_save_contract_proposal.py")
save = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(save)


def witness():
    return save.sample_checkpoint()


def recheck(snapshot, rc, bc, plan):
    return save.validate_snapshot(snapshot, rc, bc, plan)


class SaveContractTests(unittest.TestCase):
    def test_checkpoint_replay_matches_uninterrupted(self):
        result = save.verify_fixture()
        self.assertTrue(result["same_as_uninterrupted"])
        self.assertEqual(result["checkpoint_pending"], 4)
        self.assertEqual(result["final_revision"], 10)
        self.assertEqual(result["credited_xp"], 40)

    def test_versioned_schema_is_proposal_only(self):
        snap, rc, bc, plan = witness()
        self.assertEqual(snap["schema_version"], 1)
        self.assertEqual(snap["status"], "design-proposal-not-canonical")
        self.assertEqual(snap["header"]["rng_policy_id"], "sample.counter_only_v1")
        self.assertEqual(snap["header"]["sim_schema_version"], 1)
        self.assertEqual(len(snap["header"]["rules_hash"]), 64)
        self.assertEqual(len(snap["header"]["content_digest"]), 64)
        recheck(snap, rc, bc, plan)

    def test_serialization_roundtrip_preserves_digest_and_snapshot(self):
        snap, rc, bc, plan = witness()
        data = json.dumps(snap, sort_keys=True, ensure_ascii=False, allow_nan=False)
        parsed = json.loads(data)
        self.assertEqual(snap, parsed)
        self.assertEqual(parsed["checksum"], save.hash_json({
            k: v for k, v in parsed.items() if k != "checksum"}))
        recheck(parsed, rc, bc, plan)

    def test_json_property_order_does_not_change_reference_checksum(self):
        snap, _, _, _ = witness()
        self.assertEqual(save.hash_json({"a": 5, "z": 1}),
                         save.hash_json({"z": 1, "a": 5}))
        self.assertEqual(save.seal(snap), snap)

    def test_input_snapshot_remains_immutable_after_choice(self):
        snap, rc, bc, plan = witness()
        before = copy.deepcopy(snap)
        advanced = save.choose(snap, "sample.offer.echo", rc, bc, plan)
        self.assertEqual(snap, before)
        self.assertNotEqual(advanced, snap)
        self.assertEqual(advanced["state"]["build"]["revision"], 8)

    def test_two_power_upgrades_and_evolution_keep_source_provenance(self):
        snap, rc, bc, plan = witness()
        original_claims = snap["state"]["run"]["claimed_xp_sources"]
        for token in plan["resume_choice_tokens"]:
            snap = save.choose(snap, token, rc, bc, plan)
        state, build = recheck(snap, rc, bc, plan)
        self.assertEqual(state["claimed_xp_sources"], original_claims)
        self.assertEqual(state["build_revision"], build["revision"])
        self.assertEqual([c["kind"] for c in state["pending_choices"]],
                         ["BREAKTHROUGH"])
        self.assertIn("sample.skill.thousand_swords",
                      [x["id"] for x in build["active"]])

    def test_checkpoint_revisions_match_durable_choice_actions(self):
        snap, rc, bc, plan = witness()
        self.assertEqual(len(snap["choice_actions"]), 1)
        self.assertEqual(snap["choice_actions"][0]["expected_revision"], 6)
        self.assertEqual(snap["state"]["run"]["committed_choices"][0]["revision_after"], 7)
        recheck(snap, rc, bc, plan)

    def test_stale_content_catalog_rejected_even_with_valid_checksum(self):
        snap, rc, bc, plan = witness()
        changed = copy.deepcopy(bc)
        changed["policy"]["active_capacity"] += 1
        with self.assertRaisesRegex(save.ContractError, "content digest mismatch"):
            recheck(snap, rc, changed, plan)

    def test_changed_run_level_cost_rejected(self):
        snap, rc, bc, plan = witness()
        changed = copy.deepcopy(rc)
        changed["rules"]["xp_cost_by_level"][0] += 1
        with self.assertRaisesRegex(save.ContractError, "content digest mismatch"):
            recheck(snap, changed, bc, plan)

    def test_changed_choice_mode_requires_new_rules_hash(self):
        snap, rc, bc, plan = witness()
        changed = copy.deepcopy(rc)
        changed["rules"]["choice_mode"] = "BANK_LEVELS"
        with self.assertRaisesRegex(save.ContractError, "rules hash mismatch"):
            recheck(snap, changed, bc, plan)

    def test_tampered_snapshot_without_new_checksum_rejected(self):
        snap, rc, bc, plan = witness()
        snap["state"]["run"]["xp_bank"] += 100
        with self.assertRaisesRegex(save.ContractError, "checksum mismatch"):
            recheck(snap, rc, bc, plan)

    def test_tampered_xp_even_with_resealed_checksum_rejected_by_replay(self):
        snap, rc, bc, plan = witness()
        snap["state"]["run"]["xp_bank"] += 100
        snap = save.seal(snap)
        with self.assertRaisesRegex(save.ContractError, "run state diverges"):
            recheck(snap, rc, bc, plan)

    def test_tampered_skill_even_with_resealed_checksum_rejected(self):
        snap, rc, bc, plan = witness()
        snap["state"]["build"]["active"][0]["rank"] = 1
        snap = save.seal(snap)
        with self.assertRaisesRegex(save.ContractError, "build state diverges"):
            recheck(snap, rc, bc, plan)

    def test_claimed_sources_cannot_be_silently_erased(self):
        snap, rc, bc, plan = witness()
        snap["state"]["run"]["claimed_xp_sources"] = []
        with self.assertRaisesRegex(save.ContractError, "run state diverges"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_repeated_receipt_uid_rejected(self):
        snap, rc, bc, plan = witness()
        snap["receipts"].append(copy.deepcopy(snap["receipts"][0]))
        with self.assertRaisesRegex(save.ContractError, "receipt journal differs"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_missing_receipt_rejected(self):
        snap, rc, bc, plan = witness()
        snap["receipts"].pop(0)
        with self.assertRaisesRegex(save.ContractError, "receipt journal differs"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_forged_receipt_amount_rejected(self):
        snap, rc, bc, plan = witness()
        xp = next(ev for ev in snap["receipts"] if ev["kind"] == "XP_GAIN")
        xp["payload"]["amount"] += 1000
        with self.assertRaisesRegex(save.ContractError, "receipt journal differs"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_unapproved_source_manifest_rejected(self):
        snap, rc, bc, plan = witness()
        key = next(iter(snap["source_manifest"]))
        snap["source_manifest"][key] += 1
        with self.assertRaisesRegex(save.ContractError, "source manifest mismatch"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_rng_stream_name_missing_rejected(self):
        snap, rc, bc, plan = witness()
        snap["rng_policy"]["streams"].pop("offers")
        with self.assertRaisesRegex(save.ContractError, "named RNG stream set mismatch"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_rng_seed_mismatch_rejected(self):
        snap, rc, bc, plan = witness()
        snap["rng_policy"]["streams"]["drops"]["seed"] = "900"
        with self.assertRaisesRegex(save.ContractError, "seed differs"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_rng_cursor_forgery_rejected_in_reference(self):
        snap, rc, bc, plan = witness()
        snap["rng_policy"]["streams"]["stage"]["cursor"] = "3"
        with self.assertRaisesRegex(save.ContractError, "cursor not justified"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_rng_malformed_decimal_rejected(self):
        snap, rc, bc, plan = witness()
        snap["rng_policy"]["streams"]["enemy"]["cursor"] = "0001"
        with self.assertRaisesRegex(save.ContractError, "unsigned decimal"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_rng_overflow_rejected(self):
        snap, rc, bc, plan = witness()
        snap["rng_policy"]["streams"]["enemy"]["cursor"] = str(2**64)
        with self.assertRaisesRegex(save.ContractError, "overflow"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_malformed_rules_hash_rejected_even_when_resealed(self):
        snap, rc, bc, plan = witness()
        snap["header"]["rules_hash"] = "garbage"
        with self.assertRaisesRegex(save.ContractError, "rules hash mismatch"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_cross_run_checkpoint_rejected(self):
        snap, rc, bc, plan = witness()
        snap["header"]["run_uid"] = "sample.run.other"
        with self.assertRaisesRegex(save.ContractError, "different run"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_pause_phase_corruption_rejected(self):
        snap, rc, bc, plan = witness()
        snap["header"]["phase"] = "RUNNING"
        with self.assertRaisesRegex(save.ContractError, "paused/running phase mismatch"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_event_cursor_mismatch_rejected(self):
        snap, rc, bc, plan = witness()
        snap["header"]["event_cursor"] += 1
        with self.assertRaisesRegex(save.ContractError, "event cursor mismatch"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_choice_queue_reordering_rejected(self):
        snap, rc, bc, plan = witness()
        pending = snap["state"]["run"]["pending_choices"]
        pending[0], pending[1] = pending[1], pending[0]
        with self.assertRaisesRegex(save.ContractError, "run state diverges"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_stale_choice_revision_in_journal_rejected(self):
        snap, rc, bc, plan = witness()
        snap["choice_actions"][0]["expected_revision"] += 1
        with self.assertRaisesRegex(save.ContractError, "stale choice/build revision"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_unearned_choice_uid_rejected(self):
        snap, rc, bc, plan = witness()
        snap["choice_actions"][0]["choice_uid"] = "sample.not.earned"
        with self.assertRaisesRegex(save.ContractError, "stale or out-of-order"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_choice_uid_reuse_rejected(self):
        snap, rc, bc, plan = witness()
        snap["choice_actions"].append(copy.deepcopy(snap["choice_actions"][0]))
        with self.assertRaisesRegex(save.ContractError, "duplicate choice action UID"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_invalid_new_offer_does_not_mutate_checkpoint(self):
        snap, rc, bc, plan = witness()
        before = copy.deepcopy(snap)
        with self.assertRaisesRegex(save.builds.ContractError,
                                    "upgrade offer no longer eligible"):
            save.choose(snap, "sample.offer.sword_rank", rc, bc, plan)
        self.assertEqual(snap, before)

    def test_invalid_evolution_before_required_choice_rejected(self):
        snap, rc, bc, plan = witness()
        with self.assertRaisesRegex(save.ContractError, "ineligible upgrade offer"):
            save.choose(snap, "sample.evolution.thousand_swords", rc, bc, plan)

    def test_unsupported_future_schema_rejected(self):
        snap, rc, bc, plan = witness()
        snap["schema_version"] = 999
        with self.assertRaisesRegex(save.ContractError, "unsupported snapshot schema"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_unknown_extra_header_field_rejected(self):
        snap, rc, bc, plan = witness()
        snap["header"]["unknown_command"] = "execute"
        with self.assertRaisesRegex(save.ContractError, "unknown or missing snapshot header"):
            recheck(save.seal(snap), rc, bc, plan)

    def test_lossless_v0_header_migration_preserves_state(self):
        snap, rc, bc, plan = witness()
        legacy = copy.deepcopy(snap)
        legacy["schema_version"] = 0
        legacy["header"]["captured_tick"] = legacy["header"].pop("tick")
        legacy = save.seal(legacy)
        migrated = save.migrate_legacy_header_v0(legacy, rc, bc, plan)
        self.assertEqual(migrated, snap)
        self.assertEqual(migrated["state"]["run"], snap["state"]["run"])

    def test_legacy_unknown_or_missing_tick_rejected(self):
        snap, rc, bc, plan = witness()
        legacy = copy.deepcopy(snap)
        legacy["schema_version"] = 0
        legacy = save.seal(legacy)
        with self.assertRaisesRegex(save.ContractError, "captured_tick missing"):
            save.migrate_legacy_header_v0(legacy, rc, bc, plan)

    def test_v0_cannot_migrate_a_corrupted_payload(self):
        snap, rc, bc, plan = witness()
        legacy = copy.deepcopy(snap)
        legacy["schema_version"] = 0
        legacy["header"]["captured_tick"] = legacy["header"].pop("tick")
        legacy["state"]["run"]["xp_bank"] += 4000
        legacy = save.seal(legacy)
        with self.assertRaisesRegex(save.ContractError, "run state diverges"):
            save.migrate_legacy_header_v0(legacy, rc, bc, plan)

    def test_migration_rejects_unsupported_version(self):
        snap, rc, bc, plan = witness()
        snap["schema_version"] = 3
        with self.assertRaisesRegex(save.ContractError, "unsupported legacy"):
            save.migrate_legacy_header_v0(save.seal(snap), rc, bc, plan)

    def test_json_duplicate_property_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "duplicate.json"
            p.write_text('{"schema_version": 1, "schema_version": 99}', encoding="utf-8")
            with self.assertRaisesRegex(save.ContractError, "duplicate JSON property"):
                save.load_json(p)

    def test_json_nonfinite_number_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "nan.json"
            p.write_text('{"value": NaN}', encoding="utf-8")
            with self.assertRaisesRegex(save.ContractError, "nonfinite number"):
                save.load_json(p)

    def test_snapshot_reseal_is_checksum_not_security_signature(self):
        snap, rc, bc, plan = witness()
        tampered = copy.deepcopy(snap)
        tampered["header"]["phase"] = "RUNNING"
        tampered = save.seal(tampered)
        self.assertNotEqual(tampered["checksum"], snap["checksum"])
        with self.assertRaisesRegex(save.ContractError, "phase mismatch"):
            recheck(tampered, rc, bc, plan)


if __name__ == "__main__":
    unittest.main()
