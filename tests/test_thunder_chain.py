import unittest
from unittest.mock import patch

from tools.content import sim_core as sim


class ThunderTests(unittest.TestCase):
    def setUp(self):
        self.config = sim.Config(
            sim.BASE, [sim.TOUGH, 1 << 28, 0, 1000, 32, 0], [0, 12000, 100000, 0, 36, 1],
            skill=sim.THUNDER_SKILL, skill_shape=sim.THUNDER_SHAPE,
        )
        self.world = sim.World(self.config)
        self.world.tick = 100
        self.world.skill_acc = self.config.skill_period - sim.RATE_ONE

    def _enemy(self, uid, dx, dy=0, hp=100000):
        self.world.enemies.append([
            uid, 0, self.world.player_x + dx, self.world.player_y + dy, hp, 0, 0, 0, 0, 0, 0, 0,
        ])
        return self.world.enemies[-1]

    def test_first_target_boundary_and_no_target_hold(self):
        enemy = self._enemy(16, self.config.skill_range + 1)
        sim.cast(self.config, self.world)
        self.assertEqual(self.world.skill_acc, self.config.skill_period - sim.RATE_ONE)
        self.assertEqual(self.world.chain_len, 0)
        enemy[sim.E_X] -= 1
        sim.cast(self.config, self.world)
        self.assertEqual(self.world.skill_acc, 0)
        self.assertEqual(self.world.chain_tick, 100)
        self.assertEqual(self.world.chain_uids, [16, 0, 0, 0, 0, 0, 0, 0])

    def test_jumps_from_previous_even_if_killed_and_uses_lower_slot(self):
        self._enemy(20, 200000, hp=1000)
        first_tie = self._enemy(99, 344000)
        other_tie = self._enemy(1, 200000, 144000)
        self._enemy(40, 488001)
        sim.cast(self.config, self.world)
        self.assertEqual(self.world.chain_uids, [20, 99, 0, 0, 0, 0, 0, 0])
        self.assertEqual(first_tie[sim.E_HP], 100000 - self.config.skill_damage)
        self.assertEqual(other_tie[sim.E_HP], 100000)
        self.assertEqual(self.world.ints()[44:54], [100, 2, 20, 99, 0, 0, 0, 0, 0, 0])

    def test_targets_are_unique_and_damage_is_a_cast_snapshot(self):
        for i in range(3):
            self._enemy(20 + i, 24000 * (i + 1))
        real = sim._nearest_chain_target

        def rank_changes_during_jump(world, x, y, reach, exclude):
            if exclude:
                world.ranks[sim.U_THUNDER_DAMAGE] = 2
            return real(world, x, y, reach, exclude)

        with patch.object(sim, "_nearest_chain_target", side_effect=rank_changes_during_jump):
            sim.cast(self.config, self.world)
        self.assertEqual(self.world.chain_uids, [20, 21, 22, 0, 0, 0, 0, 0])
        self.assertEqual([e[sim.E_HP] for e in self.world.enemies], [100000 - self.config.skill_damage] * 3)
        self.world.skill_acc = self.config.skill_period - sim.RATE_ONE
        sim.cast(self.config, self.world)
        remaining = 100000 - 2 * self.config.skill_damage - 2 * sim.THUNDER_DAMAGE_PER_RANK
        self.assertEqual([e[sim.E_HP] for e in self.world.enemies], [remaining] * 3)

    def test_config_reserves_upgrade_headroom(self):
        self.assertTrue(self.config.valid())
        self.config.chain_hits = 8
        self.assertTrue(self.config.valid())
        self.config.choice_mode = 1
        self.config.pickup_radius, self.config.max_gems = 48000, 128
        self.config.kind_xp, self.config.xp_costs = [10], [20]
        self.assertFalse(self.config.valid())
        self.config.chain_hits = 6
        self.assertTrue(self.config.valid())
        self.config.chain_reach = (1 << 22) - 96000
        self.assertTrue(self.config.valid())
        self.config.chain_reach += 1
        self.assertFalse(self.config.valid())

    def test_all_thunder_upgrades_are_witnessed(self):
        name, config, commands, steps = sim.CHAIN_SCENARIOS[-1]
        self.assertEqual(name, "chain_upgrades_cycle")
        _, world, _ = sim.run_trace(config, commands, steps)
        self.assertEqual(world.ranks, [rank for _, rank in sim.UPGRADE_TABLES[sim.SKILL_CHAIN]])

    def test_class_role(self):
        def fight(skill, shape, enemies, hp):
            config = sim.Config(
                sim.BASE, [sim.TOUGH, 1 << 28, 0, 1000, 32, 0], [0, 12000, hp, 0, 36, 1],
                skill=skill, skill_shape=shape,
            )
            world = sim.World(config)
            for i in range(enemies):
                x = world.player_x + 72000 + (i // 5) * 27500
                y = world.player_y + (i % 5 - 2) * 27500
                world.enemies.append([i + 1, 0, x, y, hp, 0, 0, 0, 0, 0, 0, 0])
            world.enemy_alive = enemies
            log = sim.CommandLog()
            for _ in range(600):
                sim.step(config, world, log)
                if world.kills == enemies:
                    return world.tick, enemies * hp
            return world.tick, enemies * hp - sum(e[sim.E_HP] for e in world.enemies)

        self.assertGreater(
            fight(sim.THUNDER_SKILL, sim.THUNDER_SHAPE, 20, 100000)[1],
            fight(sim.P0_SKILL, (0, 0, 0), 20, 100000)[1],
        )
        self.assertGreater(
            fight(sim.THUNDER_SKILL, sim.THUNDER_SHAPE, 1, 10000)[0],
            fight(sim.P0_SKILL, (0, 0, 0), 1, 10000)[0],
        )
