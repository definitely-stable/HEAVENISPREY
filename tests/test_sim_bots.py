"""ADR-009 slice 2: scripted bot runs. Exact layer (committed fixture reproduces, logs replay
to the recorded digests) and statistical layer (death-time corridors over 32 seeds and the
idle < circle < kiter ordering) on the P0 placeholder tuning. ADR-010 section 7: the anchors
that end inside roster window w0 keep their slice 4 outcomes with choice_mode 0; kiter_upgrades
meets its smoke goal."""
import hashlib
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
# SHA-256 of the JSON list [id, death_tick, kills, command_count, xp_collected, level] of the
# anchor survey rows of slice 4 (main e5ddffb) that end inside roster window w0 (the 82 rows with
# death_tick < W0_END_TICK); the command log schema changed the log digests only. Since ADR-011
# E6 the later windows change the rows that outlive w0 (13 kiter runs), so only the w0 prefix
# is pinned to slice 4.
SLICE4_ANCHORS = "8472328d7ba314990f363aaab3103481d84f83342dcf6bb02c5cdf4a332723c9"
W0_END_TICK = 5100


def load_runs() -> dict:
    return json.loads(bots.RUNS_PATH.read_text(encoding="utf-8"))


def load_upgrade_runs() -> dict:
    return json.loads(bots.UPGRADE_RUNS_PATH.read_text(encoding="utf-8"))


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
        self.assertEqual(self.runs["log_schema_version"], sim.LOG_SCHEMA_VERSION)
        self.assertEqual([t["id"] for t in self.runs["traces"]],
                         ["botrun.p0.idle.s101", "botrun.p0.circle.s101", "botrun.p0.kiter.s101"])
        self.assertEqual(len(self.runs["survey"]), 96)

    def test_logs_replay_to_recorded_state(self):
        for trace in self.runs["traces"]:
            config = bots.p0_config(trace["enemies"]["seed"])
            self.assertEqual(trace["choice_mode"], 0)
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
        world, _, _ = bots.play("idle", config, 400)
        seen = bots.Observation(config, world)
        self.assertEqual(set(vars(seen)), {"hero_x", "hero_y", "enemies", "gems", "min_x",
                                           "min_y", "max_x", "max_y", "hand",
                                           "build_revision"})
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

    def test_anchors_keep_their_slice_four_outcomes(self):
        rows = [[r["id"], r["death_tick"], r["kills"], r["command_count"], r["xp_collected"],
                 r["level"]] for r in self.runs["survey"] if r["death_tick"] < W0_END_TICK]
        self.assertEqual(len(rows), 82)
        self.assertEqual(sim.P0_WINDOWS[1], W0_END_TICK)
        self.assertEqual(hashlib.sha256(json.dumps(rows).encode()).hexdigest(), SLICE4_ANCHORS)
        self.assertTrue(all(r["choices"] == 0 for r in self.runs["survey"]))

    def test_logs_stay_small(self):
        for row in self.runs["survey"]:
            self.assertLessEqual(row["command_count"], bots.MAX_COMMANDS, row["id"])
        self.assertLessEqual(bots.RUNS_PATH.stat().st_size, bots.MAX_FILE_BYTES)


class SimBotCorridorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        survey = load_runs()["survey"]
        cls.ticks = {name: [r["death_tick"] for r in survey if r["bot_policy"] == name]
                     for name in bots.ANCHORS}
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


class SimBotUpgradeTests(unittest.TestCase):
    """The upgrade fixture is checked in full by `sim_bots.py --check` (CI); here: the exact
    trace, one recomputed row per strategy, the smoke goal and the chooser rules."""

    @classmethod
    def setUpClass(cls):
        cls.runs = load_upgrade_runs()

    def test_header(self):
        self.assertEqual(self.runs["sim_schema_version"], bots.sim_schema_version())
        self.assertEqual(self.runs["bot_policy_version"], bots.BOT_POLICY_VERSION)
        self.assertEqual([t["id"] for t in self.runs["traces"]], ["botrun.p0.kiter_upgrades.s101"])
        self.assertEqual(len(self.runs["survey"]), 32 * len(bots.UPGRADE_BOTS))

    def test_survivors_win_at_the_stage_end(self):
        """ADR-011 section 1: a bot that is alive after 18000 ticks has won; the dead have not."""
        for row in self.runs["survey"] + load_runs()["survey"]:
            self.assertEqual(row["won"], int(row["death_tick"] == -1), row["id"])
        trace = self.runs["traces"][0]
        self.assertEqual((trace["won"], trace["end_tick"], trace["run_ticks"]), (1, 18000, 18000))
        self.assertLessEqual(bots.UPGRADE_RUNS_PATH.stat().st_size, bots.MAX_UPGRADE_FILE_BYTES)

    def test_exact_trace_replays(self):
        trace = self.runs["traces"][0]
        config = bots.config_for("kiter_upgrades", trace["enemies"]["seed"])
        self.assertEqual(trace["choice_mode"], 1)
        commands = [tuple(int(v) for v in c) for c in trace["commands"]]
        log, world, checkpoints = sim.run_trace(config, commands, trace["ticks"])
        self.assertEqual(log.digest(), trace["log_digest"])
        self.assertEqual(checkpoints, trace["checkpoints"])
        self.assertEqual((world.tick, world.choices_done), (trace["end_tick"], trace["choices"]))
        self.assertEqual(world.level - 1, world.choices_done, "every earned choice was made")

    def test_one_row_per_strategy_recomputes(self):
        rows = {(r["bot_policy"], r["seed"]): r for r in self.runs["survey"]}
        for name in bots.UPGRADE_BOTS:
            row = bots.survey_row(name, "117", bots.MAX_UPGRADE_COMMANDS)
            self.assertEqual(row, rows[(name, "117")], name)

    def test_smoke_goal(self):
        rows = [r for r in self.runs["survey"] if r["bot_policy"] == "kiter_upgrades"]
        survivors = sum(1 for r in rows if r["death_tick"] == -1)
        self.assertGreaterEqual(survivors, bots.SMOKE_MIN_SURVIVORS)
        for row in rows:
            self.assertLessEqual(row["command_count"], bots.MAX_UPGRADE_COMMANDS)
            self.assertEqual(row["level"] - 1, row["choices"], row["id"])

    def test_diagnostics_are_recorded_per_seed(self):
        for name in ("diag_first_id", "diag_utility_first"):
            seeds = [r["seed"] for r in self.runs["survey"] if r["bot_policy"] == name]
            self.assertEqual(seeds, bots.SURVEY_SEEDS, name)

    def test_choosers(self):
        seen = bots.Observation(bots.p0_config("1"), sim.World(bots.p0_config("1")))
        seen.hand = ["upgrade.p0.pickup_radius", "upgrade.p0.sword_haste",
                     "upgrade.p0.hero_vitality"]
        self.assertEqual(bots.priority_chooser(seen), 1)
        self.assertEqual(bots.utility_chooser(seen), 0)
        self.assertEqual(bots.first_id_chooser(seen), 2)
        seen.hand = [sim.RECOVER_ID]
        self.assertEqual(bots.priority_chooser(seen), 0)

    def test_gem_pull(self):
        config = bots.p0_config("1")
        world = sim.World(config)
        world.gems.append([1, world.player_x, world.player_y - 200000, 10])
        seen = bots.Observation(config, world)
        self.assertEqual(bots.kiter_gems(seen, 0), (0, -1), "no threat: straight to the gem")
        self.assertEqual(bots.kiter(seen, 0), (0, 0), "the anchor kiter ignores gems")
        world.gems[0][sim.G_Y] = world.player_y - 500000
        self.assertEqual(bots.kiter_gems(bots.Observation(config, world), 0), (0, 0), "too far")
        world.gems[0][sim.G_Y] = world.player_y - 200000
        world.enemies.append([1, 0, world.player_x - 100000, world.player_y, 10000, 0])
        self.assertEqual(bots.kiter_gems(bots.Observation(config, world), 0), (1, -1),
                         "under threat the pull only bends the escape")


if __name__ == "__main__":
    unittest.main()
