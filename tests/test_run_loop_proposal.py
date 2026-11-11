"""Design-only acceptance and negative tests for GAME-ARCH-00/01.

The oracle is intentionally not a game simulation: no combat, draft RNG,
build mutation, pathfinding, FPS, or visual quality are asserted.
"""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("run_loop_proposal",
                                               ROOT / "scripts/validate_run_loop_proposal.py")
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def source():
    return oracle.load_json(oracle.SAMPLE)


def pickup_fixture(catalog=None):
    catalog = catalog or source()
    r = catalog["rules"]
    compact = oracle.consolidate_pickups(catalog["pickups"])
    return oracle.collect_pickups(compact, owner_uid=r["player_uid"],
                                  region_id=r["region_id"],
                                  x=r["player_position"]["x"],
                                  y=r["player_position"]["y"],
                                  radius=r["pickup_radius"])


def event_fixture(catalog=None):
    catalog = catalog or source()
    picked, _ = pickup_fixture(catalog)
    r = catalog["rules"]
    return (
        oracle.xp_events_from_pickups(picked, run_uid=catalog["run_uid"],
                                      tick=r["event_tick"],
                                      first_sequence=r["first_sequence"])
        + copy.deepcopy(catalog["other_events"])
    )


def started_run(catalog=None):
    catalog = catalog or source()
    return oracle.apply_events(oracle.initial_run(catalog), event_fixture(catalog),
                               catalog["rules"]["xp_cost_by_level"])


class RunLoopDesignTests(unittest.TestCase):
    def test_reference_witness_passes(self):
        self.assertEqual(oracle.validate_reference(source()), {
            "original_pickups": 5, "consolidated_pickups": 3,
            "collected_value": 40, "earned_levels": 3,
            "choice_count": 5, "xp_remaining": 3, "commit_revision": 6,
        })

    def test_pickup_merge_preserves_value_and_sources(self):
        catalog = source()
        before = copy.deepcopy(catalog["pickups"])
        merged = oracle.consolidate_pickups(before)
        self.assertEqual(sum(p["value"] for p in merged), 52)
        self.assertEqual(sum(p["value"] for p in before), 52)
        self.assertEqual(set(s for p in before for s in p["source_uids"]),
                         set(s for p in merged for s in p["source_uids"]))
        self.assertEqual(before, catalog["pickups"])

    def test_consolidation_independent_of_json_order(self):
        catalog = source()
        forward = oracle.consolidate_pickups(catalog["pickups"])
        backward = oracle.consolidate_pickups(list(reversed(catalog["pickups"])))
        self.assertEqual(forward, backward)

    def test_different_positions_are_not_consolidated(self):
        catalog = source()
        catalog["pickups"][1]["x"] = 9
        self.assertEqual(len(oracle.consolidate_pickups(catalog["pickups"])), 4)

    def test_different_regions_are_not_consolidated(self):
        catalog = source()
        catalog["pickups"][1]["region_id"] = "sample.region.sealed"
        self.assertEqual(len(oracle.consolidate_pickups(catalog["pickups"])), 4)

    def test_different_owner_not_consolidated(self):
        catalog = source()
        catalog["pickups"][1]["owner_uid"] = "sample.owner.other"
        self.assertEqual(len(oracle.consolidate_pickups(catalog["pickups"])), 4)

    def test_different_kind_not_consolidated(self):
        catalog = source()
        catalog["pickups"][1]["kind"] = "HEALTH"
        self.assertEqual(len(oracle.consolidate_pickups(catalog["pickups"])), 4)

    def test_different_collection_policies_not_consolidated(self):
        catalog = source()
        catalog["pickups"][1]["collection_policy"] = "EXPLICIT_INTERACT"
        self.assertEqual(len(oracle.consolidate_pickups(catalog["pickups"])), 4)

    def test_duplicate_pickup_id_rejected(self):
        catalog = source()
        catalog["pickups"].append(copy.deepcopy(catalog["pickups"][0]))
        with self.assertRaisesRegex(oracle.ContractError, "duplicate pickup ID"):
            oracle.consolidate_pickups(catalog["pickups"])

    def test_duplicate_source_uid_rejected(self):
        catalog = source()
        catalog["pickups"][1]["source_uids"] = catalog["pickups"][0]["source_uids"][:]
        with self.assertRaisesRegex(oracle.ContractError, "source UID counted twice"):
            oracle.consolidate_pickups(catalog["pickups"])

    def test_nonpositive_pickup_value_rejected(self):
        catalog = source()
        catalog["pickups"][0]["value"] = 0
        with self.assertRaisesRegex(oracle.ContractError, "positive integer"):
            oracle.consolidate_pickups(catalog["pickups"])

    def test_noninteger_position_rejected(self):
        catalog = source()
        catalog["pickups"][0]["x"] = 0.5
        with self.assertRaisesRegex(oracle.ContractError, "grid integer"):
            oracle.consolidate_pickups(catalog["pickups"])

    def test_only_local_reachable_pickups_collect(self):
        picked, rem = pickup_fixture()
        self.assertEqual(sum(p["value"] for p in picked), 40)
        self.assertEqual(sum(p["value"] for p in rem), 12)

    def test_wider_radius_collects_adjacent_same_region(self):
        catalog = source()
        r = catalog["rules"]
        collected, rem = oracle.collect_pickups(
            oracle.consolidate_pickups(catalog["pickups"]),
            owner_uid=r["player_uid"], region_id=r["region_id"],
            x=8, y=2, radius=1)
        self.assertEqual(sum(p["value"] for p in collected), 47)
        self.assertEqual(sum(p["value"] for p in rem), 5)

    def test_explicit_interaction_requires_separate_service(self):
        catalog = source()
        catalog["pickups"][0]["collection_policy"] = "EXPLICIT_INTERACT"
        picked, rem = pickup_fixture(catalog)
        self.assertEqual(sum(p["value"] for p in picked), 26)
        self.assertEqual(sum(p["value"] for p in rem), 26)

    def test_health_pickup_does_not_award_xp(self):
        picked, _ = pickup_fixture()
        fake = copy.deepcopy(picked[0])
        fake["kind"] = "HEALTH"
        events = oracle.xp_events_from_pickups(
            [fake], run_uid="sample.run.x", tick=100, first_sequence=10)
        self.assertEqual(events, [])

    def test_same_pickup_sources_generate_same_event_uid(self):
        picked, _ = pickup_fixture()
        a = oracle.xp_events_from_pickups(picked, run_uid="sample.run.x",
                                          tick=100, first_sequence=10)
        b = oracle.xp_events_from_pickups(list(reversed(picked)),
                                          run_uid="sample.run.x", tick=100,
                                          first_sequence=10)
        self.assertEqual(a, b)

    def test_event_batch_order_independent(self):
        catalog = source()
        state = oracle.initial_run(catalog)
        costs = catalog["rules"]["xp_cost_by_level"]
        self.assertEqual(oracle.apply_events(state, event_fixture(catalog), costs),
                         oracle.apply_events(state, list(reversed(event_fixture(catalog))), costs))
        self.assertEqual(state, oracle.initial_run(catalog))

    def test_multiple_levels_and_xp_overflow_preserved(self):
        catalog = source()
        state = started_run(catalog)
        self.assertEqual((state["level"], state["xp_bank"]), (4, 3))
        self.assertEqual([x["kind"] for x in state["pending_choices"]],
                         ["LEVEL_UP"] * 3 + ["RITUAL_REWARD", "BREAKTHROUGH"])
        self.assertTrue(state["paused"])

    def test_ladder_end_does_not_erase_overflow(self):
        catalog = source()
        event = event_fixture(catalog)[0]
        event["payload"]["amount"] = 1000
        state = oracle.apply_events(oracle.initial_run(catalog), [event],
                                    catalog["rules"]["xp_cost_by_level"])
        self.assertEqual(state["level"], 5)
        self.assertEqual(state["xp_bank"], 933)
        self.assertEqual(len(state["pending_choices"]), 4)

    def test_replayed_identical_reward_is_idempotent_while_paused(self):
        catalog = source()
        state = started_run(catalog)
        repeat = oracle.apply_events(state, [event_fixture(catalog)[0]],
                                     catalog["rules"]["xp_cost_by_level"])
        self.assertEqual(state, repeat)

    def test_reused_event_uid_with_changed_payload_rejected(self):
        catalog = source()
        state = started_run(catalog)
        before = copy.deepcopy(state)
        changed = event_fixture(catalog)[0]
        changed["payload"]["amount"] += 1
        with self.assertRaisesRegex(oracle.ContractError, "different payload"):
            oracle.apply_events(state, [changed], catalog["rules"]["xp_cost_by_level"])
        self.assertEqual(state, before)

    def test_cross_run_receipt_rejected(self):
        catalog = source()
        event = event_fixture(catalog)[0]
        event["run_uid"] = "sample.run.other"
        with self.assertRaisesRegex(oracle.ContractError, "cross-run"):
            oracle.apply_events(oracle.initial_run(catalog), [event],
                                catalog["rules"]["xp_cost_by_level"])

    def test_event_seq_collision_rejected(self):
        catalog = source()
        events = event_fixture(catalog)
        events[1]["sequence"] = events[0]["sequence"]
        with self.assertRaisesRegex(oracle.ContractError, "sequence collision"):
            oracle.apply_events(oracle.initial_run(catalog), events,
                                catalog["rules"]["xp_cost_by_level"])

    def test_event_seq_backwards_rejected(self):
        catalog = source()
        state = started_run(catalog)
        for choice in list(state["pending_choices"]):
            state = oracle.commit_choice(
                state, choice_uid=choice["uid"],
                expected_build_revision=state["build_revision"],
                selection_token="sample.option",
                trusted_eligible_tokens=["sample.option"])
        e = {"uid": "sample.event.late", "run_uid": catalog["run_uid"],
             "tick": 100, "sequence": 9, "kind": "XP_GAIN",
             "payload": {"amount": 2}}
        with self.assertRaisesRegex(oracle.ContractError, "sequence moved backwards"):
            oracle.apply_events(state, [e], catalog["rules"]["xp_cost_by_level"])

    def test_event_tick_backwards_rejected(self):
        catalog = source()
        state = started_run(catalog)
        for choice in list(state["pending_choices"]):
            state = oracle.commit_choice(
                state, choice_uid=choice["uid"],
                expected_build_revision=state["build_revision"],
                selection_token="sample.option",
                trusted_eligible_tokens=["sample.option"])
        e = {"uid": "sample.event.oldtick", "run_uid": catalog["run_uid"],
             "tick": 99, "sequence": 13, "kind": "XP_GAIN",
             "payload": {"amount": 2}}
        with self.assertRaisesRegex(oracle.ContractError, "tick moved backwards"):
            oracle.apply_events(state, [e], catalog["rules"]["xp_cost_by_level"])

    def test_new_world_event_rejected_while_paused(self):
        catalog = source()
        state = started_run(catalog)
        e = {"uid": "sample.event.other", "run_uid": catalog["run_uid"],
             "tick": 100, "sequence": 13, "kind": "XP_GAIN",
             "payload": {"amount": 2}}
        with self.assertRaisesRegex(oracle.ContractError, "while choice queue paused"):
            oracle.apply_events(state, [e], catalog["rules"]["xp_cost_by_level"])

    def test_chest_before_xp_when_authored_sequence_earlier(self):
        catalog = source()
        events = event_fixture(catalog)
        events[1]["sequence"] = 9
        state = oracle.apply_events(oracle.initial_run(catalog), events,
                                    catalog["rules"]["xp_cost_by_level"])
        self.assertEqual(state["pending_choices"][0]["kind"], "RITUAL_REWARD")
        self.assertEqual(state["pending_choices"][1]["kind"], "LEVEL_UP")

    def test_choice_out_of_order_rejected(self):
        state = started_run()
        before = copy.deepcopy(state)
        with self.assertRaisesRegex(oracle.ContractError, "out of order"):
            oracle.commit_choice(state, choice_uid=state["pending_choices"][1]["uid"],
                                 expected_build_revision=1, selection_token="sample.x",
                                 trusted_eligible_tokens=["sample.x"])
        self.assertEqual(state, before)

    def test_invalid_choice_token_rejected(self):
        state = started_run()
        with self.assertRaisesRegex(oracle.ContractError, "selection not eligible"):
            oracle.commit_choice(state, choice_uid=state["pending_choices"][0]["uid"],
                                 expected_build_revision=1, selection_token="sample.bad",
                                 trusted_eligible_tokens=["sample.good"])

    def test_build_revision_is_optimistic_and_atomic(self):
        state = started_run()
        before = copy.deepcopy(state)
        with self.assertRaisesRegex(oracle.ContractError, "stale build revision"):
            oracle.commit_choice(state, choice_uid=state["pending_choices"][0]["uid"],
                                 expected_build_revision=2, selection_token="sample.x",
                                 trusted_eligible_tokens=["sample.x"])
        self.assertEqual(state, before)

    def test_choice_consumed_once(self):
        state = started_run()
        uid = state["pending_choices"][0]["uid"]
        advanced = oracle.commit_choice(state, choice_uid=uid, expected_build_revision=1,
                                        selection_token="sample.x",
                                        trusted_eligible_tokens=["sample.x"])
        with self.assertRaisesRegex(oracle.ContractError, "out of order"):
            oracle.commit_choice(advanced, choice_uid=uid, expected_build_revision=2,
                                 selection_token="sample.x",
                                 trusted_eligible_tokens=["sample.x"])

    def test_every_choice_requires_current_revision(self):
        state = started_run()
        first = state["pending_choices"][0]["uid"]
        second = state["pending_choices"][1]["uid"]
        advanced = oracle.commit_choice(state, choice_uid=first, expected_build_revision=1,
                                        selection_token="sample.x",
                                        trusted_eligible_tokens=["sample.x"])
        with self.assertRaisesRegex(oracle.ContractError, "stale build revision"):
            oracle.commit_choice(advanced, choice_uid=second, expected_build_revision=1,
                                 selection_token="sample.x",
                                 trusted_eligible_tokens=["sample.x"])

    def test_all_choices_resume_simulation_without_advancing_tick(self):
        state = started_run()
        tick = state["last_tick"]
        for choice in list(state["pending_choices"]):
            state = oracle.commit_choice(state, choice_uid=choice["uid"],
                                         expected_build_revision=state["build_revision"],
                                         selection_token="sample.x",
                                         trusted_eligible_tokens=["sample.x"])
        self.assertFalse(state["paused"])
        self.assertEqual(state["last_tick"], tick)
        self.assertEqual(state["build_revision"], 6)
        self.assertEqual(len(state["committed_choices"]), 5)
        self.assertFalse(state["pending_choices"])

    def test_zero_xp_threshold_rejected(self):
        catalog = source()
        catalog["rules"]["xp_cost_by_level"][0] = 0
        with self.assertRaisesRegex(oracle.ContractError, "positive integer"):
            oracle.validate_reference(catalog)

    def test_invalid_class_reference_rejected(self):
        catalog = source()
        catalog["rules"]["class_id"] = "class.not_in_v7"
        with self.assertRaisesRegex(oracle.ContractError, "unknown canonical class"):
            oracle.validate_reference(catalog)

    def test_bad_event_payload_rejected(self):
        event = event_fixture()[0]
        event["payload"]["status"] = "free"
        with self.assertRaisesRegex(oracle.ContractError, "XP payload"):
            oracle.validate_event(event)

    def test_duplicate_identical_receipt_in_batch_is_idempotent(self):
        catalog = source()
        e = event_fixture(catalog)[0]
        result = oracle.apply_events(oracle.initial_run(catalog), [e, copy.deepcopy(e)],
                                     catalog["rules"]["xp_cost_by_level"])
        self.assertEqual(result["level"], 4)
        self.assertEqual(len(result["pending_choices"]), 3)


if __name__ == "__main__":
    unittest.main()
