"""ADR-009 slice 2: scripted bot runs. Exact layer (committed fixture reproduces, logs replay
to the recorded digests) and statistical layer (death-time corridors over 32 seeds and the
idle < circle < kiter ordering) on the P0 placeholder tuning."""
import importlib.util
import json
import statistics
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sim_bots", ROOT / "tools/content/sim_bots.py")
bots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bots)
sim = bots.sim

# Corridors in ticks (60 per second). Recalibration rule: median x [0.85, 1.20], per-seed
# bounds [0.75 x min, 1.25 x max] of a fresh 32-seed survey, rounded to 300 ticks; change
# them by hand only, with a before/after table in the PR.
MEDIAN = {"idle": (1500, 2100), "circle": (2700, 3900), "kiter": (4500, 6600)}
PER_SEED = {"idle": (900, 3300), "circle": (1800, 5100), "kiter": (3300, 9000)}
MEDIAN_RATIO = {("idle", "circle"): 1.4, ("circle", "kiter"): 1.3}


def load_runs() -> dict:
    return json.loads(bots.RUNS_PATH.read_text(encoding="utf-8"))


class SimBotExactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runs = load_runs()

    def test_committed_runs_are_current(self):
        self.assertEqual(bots.RUNS_PATH.read_bytes(), bots.runs_bytes())

    def test_header(self):
        self.assertEqual(self.runs["kind"], "hip-sim-bot-runs")
        self.assertEqual(self.runs["sim_schema_version"], bots.sim_schema_version())
        self.assertEqual(self.runs["bot_policy_version"], bots.BOT_POLICY_VERSION)
        self.assertEqual([t["id"] for t in self.runs["traces"]],
                         ["botrun.p0.idle.s101", "botrun.p0.circle.s101", "botrun.p0.kiter.s101"])
        self.assertEqual(len(self.runs["survey"]), 96)

    def test_logs_replay_to_recorded_state(self):
        for trace in self.runs["traces"]:
            config = bots.p0_config(trace["enemies"]["seed"])
            commands = [tuple(int(v) for v in c) for c in trace["commands"]]
            log, world, checkpoints = sim.run_trace(config, commands, trace["ticks"])
            self.assertEqual(log.digest(), trace["log_digest"], trace["id"])
            self.assertEqual(checkpoints, trace["checkpoints"], trace["id"])
            self.assertEqual(world.tick if world.hero_dead else -1, trace["death_tick"])
            self.assertEqual(world.kills, trace["kills"])

    def test_shifting_one_command_changes_the_run(self):
        trace = self.runs["traces"][1]
        config = bots.p0_config(trace["enemies"]["seed"])
        commands = [tuple(int(v) for v in c) for c in trace["commands"]]
        commands[3] = (commands[3][0] + 1,) + commands[3][1:]
        _, world, _ = sim.run_trace(config, commands, trace["ticks"])
        self.assertNotEqual(world.digest(), trace["checkpoints"][-1]["digest"])

    def test_bot_sees_only_the_observation(self):
        config = bots.p0_config("101")
        world, _ = bots.play("idle", config, 400)
        seen = bots.Observation(config, world)
        self.assertEqual(set(vars(seen)), {"hero_x", "hero_y", "enemies", "min_x", "min_y",
                                           "max_x", "max_y"})
        self.assertEqual(len(seen.enemies), world.enemy_alive)
        kiter_move = bots.kiter(seen, world.tick)
        world.rng_cursor, world.spawn_acc, world.skill_acc = 0, 0, 0
        self.assertEqual(bots.kiter(bots.Observation(config, world), world.tick), kiter_move)

    def test_kiter_flees_and_avoids_walls(self):
        config = bots.p0_config("1")
        world = sim.World(config)
        world.enemies.append([1, 0, world.player_x + 100000, world.player_y, 10000, 0])
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0), (-1, 0))
        world.enemies.clear()
        world.player_x = config.min_x + 30000
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0), (1, 0))
        world.player_x = (config.min_x + config.max_x) // 2
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0), (0, 0))

    def test_logs_stay_small(self):
        for row in self.runs["survey"]:
            self.assertLessEqual(row["command_count"], bots.MAX_COMMANDS, row["id"])
        self.assertLessEqual(bots.RUNS_PATH.stat().st_size, bots.MAX_FILE_BYTES)


class SimBotCorridorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        survey = load_runs()["survey"]
        cls.ticks = {name: [r["death_tick"] for r in survey if r["bot_policy"] == name]
                     for name in bots.POLICIES}
        cls.by_seed = {(r["bot_policy"], r["seed"]): r["death_tick"] for r in survey}

    def test_every_bot_dies_before_five_minutes(self):
        for name, ticks in self.ticks.items():
            self.assertEqual(len(ticks), 32, name)
            self.assertTrue(all(0 < t < bots.MAX_TICKS for t in ticks), name)

    def test_median_corridors(self):
        for name, (low, high) in MEDIAN.items():
            median = statistics.median(self.ticks[name])
            self.assertTrue(low <= median <= high, (name, median))

    def test_per_seed_corridors(self):
        for name, (low, high) in PER_SEED.items():
            for tick in self.ticks[name]:
                self.assertTrue(low <= tick <= high, (name, tick))

    def test_moving_outlives_standing(self):
        for (worse, better), ratio in MEDIAN_RATIO.items():
            got = statistics.median(self.ticks[better]) / statistics.median(self.ticks[worse])
            self.assertGreaterEqual(got, ratio, (worse, better, got))
        seeds = bots.SURVEY_SEEDS
        self.assertEqual(sum(self.by_seed[("idle", s)] < self.by_seed[("kiter", s)] for s in seeds), 32)
        for worse, better in (("idle", "circle"), ("circle", "kiter")):
            wins = sum(self.by_seed[(worse, s)] < self.by_seed[(better, s)] for s in seeds)
            self.assertGreaterEqual(wins, 29, (worse, better))


if __name__ == "__main__":
    unittest.main()
