"""P0-01b simulation core reference: committed traces current, movement and command-log
rules checked against independent expectations."""
import hashlib
import importlib.util
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sim_core", ROOT / "tools/content/sim_core.py")
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)

BASE = sim.BASE


def run(config, commands, ticks):
    log, world = sim.CommandLog(), sim.World(config)
    for command in commands:
        assert log.append(command, 0) == sim.OK
    for _ in range(ticks):
        sim.step(config, world, log)
    return world


class SimCoreReferenceTests(unittest.TestCase):
    def test_committed_vectors_are_current(self):
        self.assertEqual(sim.VECTORS_PATH.read_bytes(), sim.vectors_bytes())

    def test_diagonal_constant_is_unit_vector(self):
        self.assertEqual(sim.DIAG_Q14, round(16384 / math.sqrt(2)))
        self.assertEqual(sim.DIAG_Q14, sim.fx.sin_q14(8192))

    def test_idle_hero_does_not_move(self):
        world = run(BASE, [], 300)
        self.assertEqual((world.player_x, world.player_y), (BASE[6], BASE[7]))
        self.assertEqual(world.tick, 300)

    def test_axis_move_is_speed_per_tick(self):
        world = run(BASE, [(0, 0, 1, 0)], 60)
        self.assertEqual(world.player_x - BASE[6], 60 * BASE[0])
        self.assertEqual(world.player_y, BASE[7])

    def test_diagonal_is_not_faster_than_axis(self):
        world = run(BASE, [(0, 0, 1, 1)], 60)
        dx, dy = world.player_x - BASE[6], world.player_y - BASE[7]
        self.assertEqual(dx, dy)
        self.assertLessEqual(dx * dx + dy * dy, (60 * BASE[0]) ** 2)
        self.assertAlmostEqual(math.hypot(dx, dy) / (60 * BASE[0]), 1.0, places=4)

    def test_opposite_directions_are_symmetric(self):
        config = [4801, 1000, -500000, -500000, 500000, 500000, 0, 0]
        plus = run(config, [(0, 0, 1, 1)], 50)
        minus = run(config, [(0, 0, -1, -1)], 50)
        self.assertEqual((plus.player_x, plus.player_y), (-minus.player_x, -minus.player_y))

    def test_hero_stays_inside_arena(self):
        speed, r, min_x, min_y, max_x, max_y = BASE[:6]
        world = run(BASE, [(0, 0, 1, 1)], 2000)
        self.assertEqual((world.player_x, world.player_y), (max_x - r, max_y - r))
        world = run(BASE, [(0, 0, -1, -1)], 2000)
        self.assertEqual((world.player_x, world.player_y), (min_x + r, min_y + r))

    def test_command_applies_on_its_tick(self):
        world = run(BASE, [(10, 0, 1, 0)], 10)
        self.assertEqual(world.player_x, BASE[6])
        world = run(BASE, [(10, 0, 1, 0)], 11)
        self.assertEqual(world.player_x, BASE[6] + BASE[0])

    def test_same_tick_last_command_wins(self):
        world = run(BASE, [(0, 0, 1, 0), (0, 1, 0, -1)], 5)
        self.assertEqual((world.player_x, world.player_y), (BASE[6], BASE[7] - 5 * BASE[0]))
        self.assertEqual(world.command_cursor, 2)

    def test_log_rejections(self):
        log = sim.CommandLog()
        self.assertEqual(log.append((3, 5, 0, 0), 3), sim.OK)
        self.assertEqual(log.append((2, 6, 0, 0), 0), sim.TICK_NOT_MONOTONIC)
        self.assertEqual(log.append((4, 5, 0, 0), 0), sim.SEQUENCE_NOT_INCREASING)
        self.assertEqual(log.append((4, 6, 0, 0), 5), sim.PAST_TICK)
        self.assertEqual(log.append((4, 6, 0, -2), 0), sim.INVALID)
        self.assertEqual(len(log.records), 1)

    def test_digest_is_sha256_of_int64_le(self):
        world = sim.World(BASE)
        raw = b"".join(v.to_bytes(8, "little", signed=True) for v in world.ints())
        self.assertEqual(world.digest(), hashlib.sha256(raw).hexdigest())
        self.assertEqual(sim.CommandLog().digest(), hashlib.sha256(b"").hexdigest())

    def test_invalid_configs(self):
        self.assertTrue(sim.config_valid(BASE))
        self.assertFalse(sim.config_valid([1, 0, 0, 0, 10, 10, 5, 5]))
        self.assertFalse(sim.config_valid([1, 2, 0, 0, 10, 10, 0, 5]))
        self.assertFalse(sim.config_valid([1, 2, 0, 0, 1 << 30, 10, 5, 5]))


if __name__ == "__main__":
    unittest.main()
