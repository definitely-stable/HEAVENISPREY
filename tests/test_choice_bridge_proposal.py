"""Design-only tests joining the run event/XP ledger to build eligibility.

These are *synthetic integration witnesses*, not Godot gameplay tests.
"""
import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ux_cross_bridge",
                                               ROOT / "scripts/validate_choice_bridge_proposal.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class ChoiceBridgeProposalTests(unittest.TestCase):
    def test_full_cross_contract_witness(self):
        summary = bridge.replay_choice_chain()
        self.assertEqual(summary["level_choices_committed"], 3)
        self.assertEqual(summary["ritual_choices_committed"], 1)
        self.assertEqual(summary["remaining_choices"], ["BREAKTHROUGH"])
        self.assertEqual(summary["final_build_revision"],
                         summary["final_choice_revision"])
        self.assertTrue(summary["ready_after_first_upgrade"])
        self.assertIn("sample.skill.thousand_swords", summary["final_active"])

    def test_preview_explains_newly_ready_evolution(self):
        catalog, _, build = bridge.sample_run_and_build()
        result = bridge.preview_upgrade(catalog, build, "sample.offer.sword_rank")
        self.assertEqual(result["active_rank_before"], 4)
        self.assertEqual(result["active_rank_after"], 5)
        self.assertEqual(result["active_slots_delta"], 0)
        self.assertEqual(result["unlocked_ritual_recipes"],
                         ["sample.evolution.thousand_swords"])
        self.assertEqual(result["revision_after"], build["revision"] + 1)

    def test_preview_does_not_change_build(self):
        catalog, _, build = bridge.sample_run_and_build()
        prior = copy.deepcopy(build)
        bridge.preview_upgrade(catalog, build, "sample.offer.sword_rank")
        self.assertEqual(build, prior)

    def test_card_cannot_offer_rank_up_after_cap(self):
        catalog, _, build = bridge.sample_run_and_build()
        new_build = bridge.buildsystem.apply_upgrade_offer(
            catalog, build, "sample.offer.sword_rank", build["revision"])
        self.assertNotIn("sample.offer.sword_rank",
                         bridge.buildsystem.eligible_offers(catalog, new_build))
        with self.assertRaisesRegex(bridge.buildsystem.ContractError, "ineligible"):
            bridge.preview_upgrade(catalog, new_build, "sample.offer.sword_rank")

    def test_power_cap_prevents_stale_second_choice(self):
        catalog, _, build = bridge.sample_run_and_build()
        for i in range(2):
            build = bridge.buildsystem.apply_upgrade_offer(
                catalog, build, "sample.offer.echo", build["revision"])
        self.assertNotIn("sample.offer.echo",
                         bridge.buildsystem.eligible_offers(catalog, build))
        with self.assertRaisesRegex(bridge.buildsystem.ContractError, "no longer eligible"):
            bridge.buildsystem.apply_upgrade_offer(catalog, build,
                                                   "sample.offer.echo", build["revision"])

    def test_stale_build_revision_rejects_projection(self):
        catalog, _, build = bridge.sample_run_and_build()
        before = copy.deepcopy(build)
        with self.assertRaisesRegex(bridge.buildsystem.ContractError, "stale build revision"):
            bridge.buildsystem.apply_upgrade_offer(
                catalog, build, "sample.offer.sword_rank", build["revision"] + 1)
        self.assertEqual(build, before)

    def test_run_choice_rejects_ineligible_selected_offer(self):
        catalog, session, build = bridge.sample_run_and_build()
        with self.assertRaisesRegex(bridge.runloop.ContractError, "not eligible"):
            bridge.runloop.commit_choice(
                session, choice_uid=session["pending_choices"][0]["uid"],
                expected_build_revision=build["revision"],
                selection_token="sample.offer.gibberish",
                trusted_eligible_tokens=bridge.buildsystem.eligible_offers(catalog, build))


if __name__ == "__main__":
    unittest.main()
