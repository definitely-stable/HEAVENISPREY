import unittest

from tools.content import arena_opening_probe as probe


class ArenaOpeningProbeTests(unittest.TestCase):
    def test_observing_a_bot_preserves_the_run(self):
        config = probe.make_config("A", "kiter_upgrades", "101")
        base, base_log, base_steps = probe.bots.play("kiter_upgrades", config, 1200)
        measured, log, steps = probe.bots.play(
            "kiter_upgrades", config, 1200, on_step=probe.OpeningMetrics(config).record
        )
        self.assertEqual((base.digest(), base_log.digest(), base_steps),
                         (measured.digest(), log.digest(), steps))

    def test_candidate_configs_keep_the_production_inputs(self):
        a, b, c = [probe.make_config(v, "idle", "101") for v in "ABC"]
        self.assertEqual((a.spawn_period, b.spawn_period, c.spawn_period), (90000, 78000, 90000))
        self.assertEqual(a.arena.codes, c.arena.codes)
        self.assertEqual(a.arena.spawns, b.arena.spawns)
        self.assertEqual(set(a.arena.spawns) - set(c.arena.spawns), {(41, 14)})
        self.assertEqual(set(c.arena.spawns) - set(a.arena.spawns), {(25, 50)})
        self.assertEqual(a.caps, c.caps)

    def test_bridge_replay_arrives_and_returns_and_changed_input_fails(self):
        config = probe.make_config("A", "idle", "101")
        commands, arrive, turns, finish = probe.route(config)
        self.assertEqual((arrive, turns, finish), (950, 1130, 1480))
        actual = probe.bridge_replay(config, commands, arrive, finish)
        self.assertTrue(actual["reached_court"])
        self.assertTrue(actual["returned"])
        wrong = probe.bridge_replay(config, commands[1:], arrive, finish)
        self.assertFalse(wrong["reached_court"])
        self.assertNotEqual(actual["world_digest"], wrong["world_digest"])

    def test_censoring_and_terminal_hp(self):
        observed = probe.OpeningMetrics(probe.make_config("A", "idle", "101"))
        world = probe.bots.sim.World(probe.make_config("A", "idle", "101"))
        world.hero_hp = 0
        world.hero_dead = True
        world.tick = 30
        observed.record(world)
        self.assertIsNone(observed.first_approach)
        self.assertEqual(observed.first_damage, 30)
        self.assertEqual(observed.result(world)["hp_90"], 0)

    def test_candidate_order_and_return_regression(self):
        current = {"approach": 60, "earliest_damage": 10, "level": 20, "hp_90": 90, "return_count": 3}
        candidate = {"approach": 50, "earliest_damage": 9, "level": 24, "hp_90": 80, "return_count": 3}
        self.assertEqual(probe.select({"A": current, "B": candidate, "C": candidate}), "C")
        self.assertEqual(probe.select({"A": current, "B": candidate, "C": dict(candidate, return_count=2)}), "B")
        self.assertEqual(probe.select({"A": current, "B": dict(candidate, earliest_damage=7),
                                       "C": dict(candidate, approach=40)}), "A")
