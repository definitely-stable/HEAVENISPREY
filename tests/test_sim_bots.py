"""ADR-009 slice 2: scripted bot runs. Exact layer (committed fixture reproduces, logs replay
to the recorded digests) and statistical layer (death-time corridors over 32 seeds and the
kiter outliving the others) on the P0 placeholder tuning. ADR-010 section 7: the anchors take
no choices; kiter_upgrades meets its smoke goal. ADR-015 A1: every run plays in arena 07 from
its west entry, so the corridors were re-anchored there (a run alive at the stage end counts
as MAX_TICKS)."""
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
# bounds [0.75 x min, 1.25 x max] of a fresh 32-seed survey, rounded out to 300 ticks and at
# most MAX_TICKS; change them by hand only, with a before/after table in the PR. ADR-015 A1
# (arena 07): idle 28 -> 100 s, circle 53 -> 78 s, kiter 84 -> 249 s (median). ADR-015 section
# 12 (the open seal ring): idle 100 -> 138 s, circle 78 -> 75 s, kiter 249 -> 245 s; only the
# idle corridor moved.
MEDIAN = {"idle": (6900, 10200), "circle": (3900, 5700), "kiter": (12600, 18000)}
PER_SEED = {"idle": (2400, 18000), "circle": (2100, 8400), "kiter": (4200, 18000)}
# The kiter outlives the others; in arena 07 the circle leaves the west landing and meets the
# horde on the bridge, so it no longer outlives the idle bot (ADR-015 A1). Since the ring is open
# (section 12) the horde reaches the seal sooner and the idle bot at the west entry later: the
# kiter outlives it 1.78 times, no longer 2.49.
MEDIAN_RATIO = {("idle", "kiter"): 1.7, ("circle", "kiter"): 2.5}
# Idle and circle never reach the stage end; the kiter may, on a few seeds.
MAX_KITER_SURVIVORS = 8


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
        self.assertEqual(set(vars(seen)), {"hero_x", "hero_y", "enemies", "gems", "arena",
                                           "centre_x", "centre_y", "held", "hand",
                                           "build_revision"})
        self.assertIs(seen.arena, config.arena, "the cells of the arena, not the world")
        self.assertEqual(len(seen.enemies), world.enemy_alive)
        kiter_move = bots.kiter(seen, world.tick)
        world.rng_cursor, world.spawn_acc, world.skill_acc = 0, 0, 0
        self.assertEqual(bots.kiter(bots.Observation(config, world), world.tick), kiter_move)

    def test_kiter_flees_and_avoids_walls(self):
        config = bots.p0_config("1")
        world = sim.World(config)
        world.player_x, world.player_y = bots.ARENA_CENTRE
        world.enemies.append([1, 0, world.player_x + 100000, world.player_y, 10000, 0])
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0), (-1, 0))
        world.enemies.clear()
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0), (0, 0), "rests at the seal")
        # Next to the first wall east of the seal: pushed back west.
        arena, cell = config.arena, config.arena.cell
        x = world.player_x
        while arena.code_at(x + cell, world.player_y) == sim.A_WALK:
            x += cell
        world.player_x = x
        self.assertEqual(bots.kiter(bots.Observation(config, world), 0)[0], -1)
        # At the west entry with no threat: down the flow field towards the seal.
        start = sim.World(config)
        move = bots.kiter(bots.Observation(config, start), 0)
        gx, gy = arena.chase_target(start.player_x, start.player_y, *bots.ARENA_CENTRE)
        self.assertNotEqual(move, (0, 0))
        self.assertGreater(move[0] * (gx - start.player_x) + move[1] * (gy - start.player_y), 0)

    def test_anchors_take_no_choices(self):
        self.assertTrue(all(r["choices"] == 0 for r in self.runs["survey"]))

    def test_logs_stay_small(self):
        for row in self.runs["survey"]:
            self.assertLessEqual(row["command_count"], bots.MAX_COMMANDS, row["id"])
        self.assertLessEqual(bots.RUNS_PATH.stat().st_size, bots.MAX_FILE_BYTES)


class SimBotCorridorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        survey = load_runs()["survey"]
        def tick(row):
            return bots.MAX_TICKS if row["death_tick"] == -1 else row["death_tick"]

        cls.ticks = {name: [tick(r) for r in survey if r["bot_policy"] == name]
                     for name in bots.ANCHORS}
        cls.by_seed = {(r["bot_policy"], r["seed"]): tick(r) for r in survey}

    def test_idle_and_circle_die_before_five_minutes(self):
        for name, ticks in self.ticks.items():
            self.assertEqual(len(ticks), 32, name)
            self.assertTrue(all(0 < t <= bots.MAX_TICKS for t in ticks), name)
        for name in ("idle", "circle"):
            self.assertTrue(all(t < bots.MAX_TICKS for t in self.ticks[name]), name)
        survivors = self.ticks["kiter"].count(bots.MAX_TICKS)
        self.assertLessEqual(survivors, MAX_KITER_SURVIVORS)

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
        self.assertEqual(sum(self.by_seed[("circle", s)] < self.by_seed[("kiter", s)] for s in seeds), 32)
        wins = sum(self.by_seed[("idle", s)] < self.by_seed[("kiter", s)] for s in seeds)
        self.assertGreaterEqual(wins, 29, ("idle", "kiter"))


class SimBotUpgradeTests(unittest.TestCase):
    """The upgrade fixture is checked in full by `sim_bots.py --check` (CI); here: the exact
    trace, one recomputed row per strategy, the smoke goal and the chooser rules."""

    @classmethod
    def setUpClass(cls):
        cls.runs = load_upgrade_runs()

    def test_header(self):
        self.assertEqual(self.runs["sim_schema_version"], bots.sim_schema_version())
        self.assertEqual(self.runs["bot_policy_version"], bots.BOT_POLICY_VERSION)
        self.assertEqual([t["id"] for t in self.runs["traces"]],
                         ["botrun.p0.kiter_upgrades.s101", "botrun.p0.thunder.kiter_upgrades.s101"])
        self.assertEqual(len(self.runs["survey"]), 32 * (len(bots.UPGRADE_BOTS) + len(bots.ANCHORS) + 1))

    def test_survivors_win_at_the_stage_end(self):
        """ADR-011 section 1: a bot that is alive after 18000 ticks has won; the dead have not."""
        for row in self.runs["survey"] + load_runs()["survey"]:
            self.assertEqual(row["won"], int(row["death_tick"] == -1), row["id"])
        trace = self.runs["traces"][0]
        self.assertEqual((trace["won"], trace["end_tick"], trace["run_ticks"]), (1, 18000, 18000))
        self.assertLessEqual(bots.UPGRADE_RUNS_PATH.stat().st_size, bots.MAX_UPGRADE_FILE_BYTES)

    def test_exact_trace_replays(self):
        for trace in self.runs["traces"]:
            with self.subTest(trace=trace["id"]):
                config = bots.config_for("kiter_upgrades", trace["enemies"]["seed"], trace["class_id"])
                self.assertEqual(trace["choice_mode"], 1)
                commands = [tuple(int(v) for v in c) for c in trace["commands"]]
                log, world, checkpoints = sim.run_trace(config, commands, trace["ticks"])
                self.assertEqual(log.digest(), trace["log_digest"])
                self.assertEqual(checkpoints, trace["checkpoints"])
                self.assertEqual((world.tick, world.choices_done), (trace["end_tick"], trace["choices"]))
                self.assertEqual(world.level - 1, world.choices_done, "every earned choice was made")

    def test_one_row_per_strategy_recomputes(self):
        rows = {(r["bot_policy"], r["class_id"], r["seed"]): r for r in self.runs["survey"]}
        for name in bots.UPGRADE_BOTS:
            row = bots.survey_row(name, "117", bots.MAX_UPGRADE_COMMANDS)
            self.assertEqual(row, rows[(name, bots.SWORD, "117")], name)
        row = bots.survey_row("kiter_upgrades", "117", bots.MAX_UPGRADE_COMMANDS, bots.THUNDER)
        self.assertEqual(row, rows[("kiter_upgrades", bots.THUNDER, "117")])

    def test_smoke_goal(self):
        for class_id in (bots.SWORD, bots.THUNDER):
            rows = [r for r in self.runs["survey"]
                    if r["bot_policy"] == "kiter_upgrades" and r["class_id"] == class_id]
            self.assertEqual([r["seed"] for r in rows], bots.SURVEY_SEEDS, class_id)
            survivors = sum(1 for r in rows if r["won"] and r["death_tick"] == -1)
            self.assertGreaterEqual(survivors, bots.SMOKE_MIN_SURVIVORS, class_id)
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
        seen.hand = ["upgrade.p0.thunder_damage", "upgrade.p0.thunder_jumps", "upgrade.p0.hero_vitality"]
        self.assertEqual(bots.thunder_chooser(seen), 1)
        self.assertEqual(bots.priority_chooser(seen), 2)
        seen.hand = [sim.RECOVER_ID]
        self.assertEqual(bots.priority_chooser(seen), 0)

    def test_gem_pull(self):
        config = bots.p0_config("1")
        world = sim.World(config)
        world.player_x, world.player_y = bots.ARENA_CENTRE
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
