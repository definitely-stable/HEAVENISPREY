"""Reproduce ADR-015's early spawn experiment without writing game configuration."""
from __future__ import annotations

import argparse
from collections import deque
from concurrent.futures import ProcessPoolExecutor
from functools import cache
import json
from pathlib import Path
from statistics import median

try:
    from . import sim_bots as bots
except ImportError:
    import sim_bots as bots

sim = bots.sim
VARIANTS = ("A", "B", "C")
POLICIES = (*bots.ANCHORS, "kiter_upgrades")
ROUTE_SEEDS = ("101", "109", "117")
COURT = (27, 47)
WALK_AT = 600
COURT_WAIT = 180
TICKS_PER_SECOND = 60
WINDOW = 90 * TICKS_PER_SECOND


@cache
def moved_spawn():
    rows = list(sim.P0_ARENA_DATA["rows"])
    for x, y, old, new in [(41, 14, "S", "."), (25, 50, ".", "S")]:
        assert rows[y][x] == old, (x, y, old)
        rows[y] = rows[y][:x] + new + rows[y][x + 1:]
    return sim.Arena.from_rows(rows, sim.P0_ARENA.cell, sim.P0_ARENA.body)


def make_config(variant: str, policy: str, seed: str):
    config = bots.config_for(policy, seed)
    if variant == "B":
        config.spawn_period = 78000
    elif variant == "C":
        config.arena = moved_spawn()
    elif variant != "A":
        raise ValueError(f"Unknown opening variant: {variant}")
    assert config.valid()
    return config


class OpeningMetrics:
    """Read-only measurements of the world, independent of what a bot can see."""

    def __init__(self, config):
        self.radius_squared = (3 * config.arena.cell) ** 2
        self.previous_hp = config.hero_hp
        self.first_approach = self.first_damage = self.first_level = None

    def record(self, world):
        if self.first_approach is None and any(
            enemy[sim.E_UID] and enemy[sim.E_HP] > 0
            and (enemy[sim.E_X] - world.player_x) ** 2
            + (enemy[sim.E_Y] - world.player_y) ** 2 <= self.radius_squared
            for enemy in world.enemies
        ):
            self.first_approach = world.tick
        if self.first_damage is None and world.hero_hp < self.previous_hp:
            self.first_damage = world.tick
        if self.first_level is None and world.level >= 2:
            self.first_level = world.tick
        self.previous_hp = world.hero_hp

    def result(self, world):
        return {
            "first_approach": self.first_approach,
            "first_damage": self.first_damage,
            "first_level": self.first_level,
            "death_tick": world.tick if world.hero_dead else None,
            "end_tick": world.tick,
            "hp_90": 0 if world.hero_dead else world.hero_hp,
            "kills": world.kills,
        }


def bot_run(job):
    variant, policy, seed = job
    config = make_config(variant, policy, seed)
    measured = OpeningMetrics(config)
    world, log, _ = bots.play(policy, config, WINDOW, on_step=measured.record)
    return {"variant": variant, "policy": policy, "seed": seed, **measured.result(world),
            "log_digest": log.digest(), "world_digest": world.digest()}


def full_run(job):
    variant, policy, seed = job
    config = make_config(variant, policy, seed)
    world, log, steps = bots.play(policy, config)
    row = {
        "id": bots.run_id(policy, seed), "variant": variant, "bot_policy": policy, "seed": seed,
        "death_tick": world.tick if world.hero_dead else -1, "end_tick": world.tick, "won": world.won,
        "kills": world.kills, "level": world.level, "xp_collected": world.xp_collected_total,
        "final_digest": world.digest(), "log_digest": log.digest(), "steps": steps,
    }
    if policy == "kiter_upgrades" and seed == "101":
        row["replay"] = {
            "variant": variant, "seed": seed, "commands": log.records, "finish": steps,
            "choice_mode": config.choice_mode, "spawn_period_mt": config.spawn_period,
            "spawns": config.arena.spawns, "world_digest": row["final_digest"],
            "log_digest": row["log_digest"], "end_tick": world.tick,
        }
    return row


def route(config):
    arena = config.arena
    start = (config.start_x // arena.cell, config.start_y // arena.cell)
    successors = {start: None}
    frontier = deque([start])
    while frontier and COURT not in successors:
        x, y = frontier.popleft()
        for dx, dy in sim.ARENA_STEPS:
            next_cell = (x + dx, y + dy)
            if next_cell not in successors and arena.code(*next_cell) == sim.A_WALK:
                successors[next_cell] = (x, y)
                frontier.append(next_cell)
    cells = [COURT]
    while cells[-1] != start:
        cells.append(successors[cells[-1]])
    cells.reverse()
    ticks_per_cell, remainder = divmod(arena.cell, config.speed)
    assert remainder == 0
    commands = []

    def walk(path, tick):
        held = (0, 0)
        for (x, y), (nx, ny) in zip(path, path[1:]):
            direction = (nx - x, ny - y)
            if direction != held:
                commands.append((tick, len(commands), sim.MOVE, *direction))
                held = direction
            tick += ticks_per_cell
        commands.append((tick, len(commands), sim.MOVE, 0, 0))
        return tick

    arrive = walk(cells, WALK_AT)
    turn = arrive + COURT_WAIT
    finish = walk(cells[::-1], turn)
    return commands, arrive, turn, finish


def bridge_replay(config, commands, arrive: int, finish: int):
    world, log = sim.World(config), sim.CommandLog()
    for command in commands:
        assert log.append(command, 0) == sim.OK, command
    cell = config.arena.cell
    court_position = tuple(v * cell + cell // 2 for v in COURT)
    reached_court = False
    last_hp = world.hero_hp
    first_bridge_damage = None
    world_start = (config.start_x, config.start_y)
    rows = sim.P0_ARENA_DATA["rows"]
    for tick in range(1, finish + 1):
        sim.step(config, world, log)
        x, y = world.player_x, world.player_y
        if first_bridge_damage is None and world.hero_hp < last_hp and rows[y // cell][x // cell] == "B":
            first_bridge_damage = tick
        last_hp = world.hero_hp
        if tick == arrive:
            reached_court = (x, y) == court_position and not world.hero_dead
    return {
        "reached_court": reached_court,
        "returned": reached_court and (world.player_x, world.player_y) == world_start and not world.hero_dead,
        "first_bridge_damage": first_bridge_damage,
        "end_tick": world.tick,
        "world_digest": world.digest(),
        "log_digest": log.digest(),
    }


def routes():
    traces = []
    for seed in ROUTE_SEEDS:
        shared = route(make_config("A", "idle", seed))
        commands, arrive, turn, finish = shared
        for variant in VARIANTS:
            config = make_config(variant, "idle", seed)
            assert route(config) == shared
            traces.append({
                "variant": variant, "seed": seed, "commands": commands,
                "start": WALK_AT, "arrival": arrive, "turn": turn, "finish": finish,
                "spawn_period_mt": config.spawn_period, "spawns": config.arena.spawns,
                **bridge_replay(config, commands, arrive, finish),
            })
    return {"schema_version": 1, "sim_schema_version": bots.sim_schema_version(), "traces": traces}


def summarize(bots_rows, bridge_rows):
    summaries = {}
    for variant in VARIANTS:
        rows = [row for row in bots_rows if row["variant"] == variant]
        idle = [row for row in rows if row["policy"] == "idle"]
        upgraded = [row for row in rows if row["policy"] == "kiter_upgrades"]

        def times(series, field):
            return sorted((row[field] if row[field] is not None else WINDOW) / TICKS_PER_SECOND
                          for row in series)

        summaries[variant] = {
            "approach": median(times(idle, "first_approach")),
            "earliest_damage": min(times(rows, "first_damage")),
            "level": median(times(upgraded, "first_level")),
            "hp_90": median(row["hp_90"] for row in upgraded),
            "return_count": sum(row["returned"] for row in bridge_rows if row["variant"] == variant),
            "policies": {
                policy: {
                    "count": len(series),
                    "median_s": {field: median(times(series, field))
                                 for field in ("first_approach", "first_damage", "first_level")},
                    "first_damage_p10_s": times(series, "first_damage")[(len(series) - 1) // 10],
                    "censored": {field: sum(row[field] is None for row in series)
                                 for field in ("first_approach", "first_damage", "first_level")},
                    "deaths": sum(row["death_tick"] is not None for row in series),
                    "kills_median": median(row["kills"] for row in series),
                    "hp_90_median": median(row["hp_90"] for row in series),
                }
                for policy in POLICIES
                if (series := [row for row in rows if row["policy"] == policy])
            },
        }
    return summaries


def select(summaries):
    baseline = summaries["A"]
    candidates = []
    for variant in ("B", "C"):
        row = summaries[variant]
        if (0.75 * baseline["approach"] <= row["approach"] <= 0.9 * baseline["approach"]
                and row["earliest_damage"] > 8
                and row["level"] <= baseline["level"] + 5
                and row["return_count"] >= baseline["return_count"]):
            candidates.append(variant)
    return max(candidates, key=lambda variant: (summaries[variant]["hp_90"], variant), default="A")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="directory for survey.json and bridge.json")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--seed", action="append", help="run a partial survey for diagnostics")
    parser.add_argument("--full", choices=VARIANTS, help="run the five-minute acceptance survey")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    seeds = args.seed or bots.SURVEY_SEEDS
    if args.full:
        jobs = [(args.full, policy, seed) for policy in POLICIES for seed in seeds]
        with ProcessPoolExecutor(args.jobs) as pool:
            rows = list(pool.map(full_run, jobs))
        path = args.output / f"full-{args.full}.json"
        replays = [row.pop("replay") for row in rows if "replay" in row]
        if replays:
            package = {"schema_version": 1, "sim_schema_version": bots.sim_schema_version(), "traces": replays}
            (args.output / f"full-replay-{args.full}.json").write_text(
                json.dumps(package, indent=2) + "\n", encoding="utf-8"
            )
        report = {"schema_version": 1, "sim_schema_version": bots.sim_schema_version(),
                  "bot_policy_version": bots.BOT_POLICY_VERSION, "runs": rows}
        path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Five-minute survey {args.full}: {len(rows)} runs, {path}")
        return
    bridge = routes()
    (args.output / "bridge.json").write_text(json.dumps(bridge, indent=2) + "\n", encoding="utf-8")
    jobs = [(variant, policy, seed) for variant in VARIANTS for policy in POLICIES
            for seed in seeds]
    with ProcessPoolExecutor(args.jobs) as pool:
        rows = list(pool.map(bot_run, jobs))
    summaries = summarize(rows, bridge["traces"])
    survey = {
        "schema_version": 1, "sim_schema_version": bots.sim_schema_version(),
        "bot_policy_version": bots.BOT_POLICY_VERSION, "window_ticks": WINDOW,
        "candidate": select(summaries) if not args.seed else None,
        "summary": summaries, "runs": rows,
    }
    (args.output / "survey.json").write_text(json.dumps(survey, indent=2) + "\n", encoding="utf-8")
    for name, summary in summaries.items():
        print(name, {key: value for key, value in summary.items() if key != "policies"})
    print(f"Candidate: {survey['candidate']}; {len(rows)} runs")


if __name__ == "__main__":
    main()
