"""GAME-ARCH-02: arena topology, telegraphs, waves, boss pattern, escape routes, reward gates and event order."""
from __future__ import annotations

import copy
import importlib.util
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_encounter", ROOT / "scripts/validate_encounter_proposal.py")
en = importlib.util.module_from_spec(spec)
spec.loader.exec_module(en)


def set_cell(fx, x, y, ch):
    rows = fx["topology"]["terrain"]
    rows[y] = rows[y][:x] + ch + rows[y][x + 1:]


class EncounterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.canon = en.canonical()
        cls.arch02 = en.load(en.ARCH02)

    def setUp(self):
        self.fx = en.load()
        self.fx.pop("expected")

    def rejects(self, code, fx=None, arch02=None):
        with self.assertRaisesRegex(en.ContractError, code):
            en.verify(self.fx if fx is None else fx, self.arch02 if arch02 is None else arch02)

    def phase(self, fx, pid):
        return next(p for p in fx["boss_pattern"]["phases"] if p["id"] == pid)

    def attack(self, fx, aid):
        return next(a for a in fx["boss_pattern"]["attacks"] if a["id"] == aid)

    def log(self, fx=None):
        fx = self.fx if fx is None else fx
        return copy.deepcopy(fx["golden_log"]["events"])

    # -- golden
    def test_golden_fixture(self):
        result = en.verify(en.load(), self.arch02)
        self.assertEqual(result["rewards"], 5)
        self.assertEqual(result["gates"]["RITUAL"], {"sources": 3, "first_second": 90})

    # -- topology
    def test_isolated_pocket_is_rejected(self):
        for x, y in ((2, 8), (3, 8), (4, 8), (2, 10), (3, 10), (4, 10), (1, 9)):
            set_cell(self.fx, x, y, "#")
        set_cell(self.fx, 4, 9, "#")
        self.rejects("E_ISOLATED_POCKET")

    def test_long_one_wide_corridor_is_a_trap(self):
        for x in range(8, 16):
            set_cell(self.fx, x, 7, "#")
            set_cell(self.fx, x, 9, "#")
        self.rejects("E_TRAP_CORRIDOR")

    def test_solid_cell_inside_boss_arena_is_rejected(self):
        set_cell(self.fx, 18, 10, "#")
        self.rejects("E_ARENA_BLOCKER")

    def test_every_player_cell_needs_a_legal_spawn(self):
        self.fx["assumptions"]["min_spawn_distance_cells"] = 40
        self.rejects("E_SPAWN")

    def test_poi_must_be_reachable_within_its_window(self):
        self.fx["pois"][0]["expire_second"] = 96
        self.rejects("E_POI_REACH")
        fx = en.load()
        fx.pop("expected")
        fx["pois"][0]["cell"] = [4, 3]
        self.rejects("E_POI", fx)

    # -- telegraphs and escape (canonical attacks, hypothetical speed)
    def test_telegraph_minimum_applies_to_canonical_attacks(self):
        self.fx["assumptions"]["min_telegraph_ticks"] = 25
        self.rejects("E_TELEGRAPH.*snake_bite")

    def test_slower_player_has_no_escape_from_snake_bite(self):
        self.fx["assumptions"]["player_speed_cells_per_tick"] = 0.095
        self.rejects("E_NO_ESCAPE.*snake_bite")

    def test_root_slow_is_applied_to_attacks_sharing_a_window(self):
        self.fx["assumptions"]["player_speed_cells_per_tick"] = 0.09
        with self.assertRaisesRegex(en.ContractError, "under slow"):
            en.check_waves(self.fx, self.canon)

    def test_spikes_need_recovery_windows(self):
        self.fx["timeline"][1]["second"] = 130
        self.rejects("E_NO_RECOVERY")

    # -- boss pattern
    def test_overlap_must_be_declared(self):
        self.phase(self.fx, "sample.boss_phase.roots")["overlaps"] = []
        self.rejects("E_UNDECLARED_OVERLAP")

    def test_rotation_needs_a_punish_window(self):
        # wrath: busy [0,52] [110,260] [280,326] in a 380-tick loop -> longest pause 58 ticks
        self.fx["boss_pattern"]["min_punish_ticks"] = 60
        self.rejects("E_NO_PUNISH_WINDOW.*wrath")

    def test_overlap_without_safe_cell_in_reach_is_rejected(self):
        self.attack(self.fx, "sample.boss_attack.root_ring").update(inner=3, outer=7)
        self.rejects("E_NO_ESCAPE.*root_ring")

    def test_boss_telegraph_and_transition_limits(self):
        self.attack(self.fx, "sample.boss_attack.jade_charge")["telegraph_ticks"] = 20
        self.rejects("E_TELEGRAPH")
        fx = en.load()
        fx.pop("expected")
        self.phase(fx, "sample.boss_phase.stone")["transition_ticks"] = 600
        self.rejects("E_TRANSITION", fx)

    def test_boss_cannot_shut_out_a_build_family(self):
        self.fx["boss_pattern"]["immunities"] = ["dot"]
        self.rejects("E_BUILD_FAMILY")
        fx = en.load()
        fx.pop("expected")
        fx["boss_pattern"]["control_policy"] = {"kind": "immune"}
        self.rejects("E_BUILD_FAMILY", fx)

    def test_phase_thresholds_must_be_contiguous(self):
        self.phase(self.fx, "sample.boss_phase.roots")["hp_from"] = 55
        self.rejects("E_PHASES")

    # -- rewards and event order
    def test_order_is_independent_of_arrival_order(self):
        expected = en.process_log(self.fx, self.log())
        for seed in range(5):
            shuffled = self.log()
            random.Random(seed).shuffle(shuffled)
            self.assertEqual(en.process_log(self.fx, shuffled), expected)

    def test_same_tick_order_follows_declared_phases(self):
        queue = en.process_log(self.fx, self.log())["queue"]
        self.assertEqual(queue[-3:], ["BOSS_RELIC", "RITUAL", "LEVEL_UP"])

    def test_duplicate_event_is_idempotent_and_conflict_is_rejected(self):
        events = self.log()
        once = en.process_log(self.fx, events)
        self.assertEqual(en.process_log(self.fx, events + [copy.deepcopy(events[5])]), once)
        bad = copy.deepcopy(events[5])
        bad["drop_uid"] = "chest9"
        with self.assertRaisesRegex(en.ContractError, "E_EVENT_CONFLICT"):
            en.process_log(self.fx, events + [bad])

    def test_pickup_needs_a_drop_from_a_dead_carrier(self):
        events = [e for e in self.log() if e["uid"] not in ("e04", "e05")]
        with self.assertRaisesRegex(en.ContractError, "E_DROP_GATE"):
            en.process_log(self.fx, events)

    def test_altar_pays_once_and_only_after_full_channel(self):
        events = self.log()
        again = dict(events[1], uid="e02b", tick=6400)
        with self.assertRaisesRegex(en.ContractError, "E_REWARD_TWICE"):
            en.process_log(self.fx, events + [again])
        short = self.log()
        short[1]["tick"] = 5450
        with self.assertRaisesRegex(en.ContractError, "E_POI_GATE"):
            en.process_log(self.fx, short)

    def test_boss_relic_cannot_precede_boss_entry(self):
        events = self.log()
        events[11]["tick"] = 9000
        with self.assertRaisesRegex(en.ContractError, "E_ENCOUNTER_GATE"):
            en.process_log(self.fx, events)

    # -- cross-contract consistency with ARCH-02
    def test_stage_supplies_exactly_the_gate_budget_arch02_assumes(self):
        arch02 = copy.deepcopy(self.arch02)
        arch02["event_gates"]["RITUAL"]["max_per_run"] = 4
        self.rejects("E_GATE_BUDGET.*RITUAL", arch02=arch02)
        arch02 = copy.deepcopy(self.arch02)
        arch02["event_gates"]["BOSS_RELIC"]["first_second"] = 240
        self.rejects("E_GATE_BUDGET.*BOSS_RELIC", arch02=arch02)


if __name__ == "__main__":
    unittest.main()
