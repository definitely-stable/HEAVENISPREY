"""Scripted test bots for the P0-01 simulation (ADR-009 section 6, slice 2).

A bot policy is a pure integer function (observation, tick) -> (move_x, move_y) on hip-fx-v1
only (no RNG, no float). It is asked every `DECIDE_EVERY[policy]` ticks before the tick is
simulated; only changes are logged as PlayerCommand records, so a bot run is fully described
by its command log and replays bit for bit in GDScript (GUT replays the logs).

Observation contract: hero position, position and radius of every enemy in a slot, arena
bounds. Bots never see the RNG cursor, accumulators, cooldowns or HP. Any change to a policy
or its constants bumps BOT_POLICY_VERSION and regenerates the fixture.

    python tools/content/sim_bots.py            # rewrite game/tests/fixtures/sim_bot_runs.json
    python tools/content/sim_bots.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_bot_runs.json"
RUNS_SCHEMA_VERSION = 1
BOT_POLICY_VERSION = 1


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sim = _load("sim_core", "sim_core.py")
fx = sim.fx

# Eight directions in turn order, starting east.
DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
CIRCLE_TURN_TICKS = 40
KITER_SENSE_SU = 288000      # 6 cells: enemies closer than this push the kiter away
KITER_WALL_SU = 144000       # 3 cells: walls closer than this push inward
KITER_REST_SU = 96000        # 2 cells: no threat and this close to the centre -> stand

MAX_TICKS = 18000            # 300 s
EXACT_SEED = "101"
SURVEY_SEEDS = [str(seed) for seed in range(101, 133)]
MAX_COMMANDS = 700
MAX_FILE_BYTES = 150 * 1024


class Observation:
    """What a bot may see: hero position, enemies (x, y, radius) and gems (x, y) in slot order,
    arena. The bots of policy version 1 do not read the gems."""

    def __init__(self, config, world):
        self.hero_x, self.hero_y = world.player_x, world.player_y
        self.enemies = [(e[sim.E_X], e[sim.E_Y], config.kinds[e[sim.E_KIND]][1])
                        for e in world.enemies if e[sim.E_UID] != 0]
        self.gems = [(g[sim.G_X], g[sim.G_Y]) for g in world.gems if g[sim.G_UID] != 0]
        self.min_x, self.min_y, self.max_x, self.max_y = (
            config.min_x, config.min_y, config.max_x, config.max_y)


def idle(seen: Observation, tick: int) -> tuple[int, int]:
    return (0, 0)


def circle(seen: Observation, tick: int) -> tuple[int, int]:
    return DIRS[fx.floor_div(tick, CIRCLE_TURN_TICKS) % 8]


def kiter(seen: Observation, tick: int) -> tuple[int, int]:
    """Flee the weighted sum of nearby enemies, keep off the walls, else drift to the centre;
    the result is the best of the eight directions (largest dot product, first in DIRS on
    ties)."""
    hx, hy = seen.hero_x, seen.hero_y
    vx = vy = 0
    for ex, ey, _radius in seen.enemies:
        dx, dy = hx - ex, hy - ey
        d2 = dx * dx + dy * dy
        if d2 > KITER_SENSE_SU * KITER_SENSE_SU:
            continue
        weight = KITER_SENSE_SU - sim.isqrt(d2)
        qx, qy = sim.normalize_q14(dx, dy)
        vx += fx.floor_div(qx * weight, KITER_SENSE_SU)
        vy += fx.floor_div(qy * weight, KITER_SENSE_SU)
    for gap, axis, sign in ((hx - seen.min_x, 0, 1), (seen.max_x - hx, 0, -1),
                            (hy - seen.min_y, 1, 1), (seen.max_y - hy, 1, -1)):
        if gap < KITER_WALL_SU:
            push = sign * fx.floor_div((KITER_WALL_SU - gap) * fx.Q14, KITER_WALL_SU)
            if axis == 0:
                vx += push
            else:
                vy += push
    if vx == 0 and vy == 0:
        cx = fx.floor_div(seen.min_x + seen.max_x, 2) - hx
        cy = fx.floor_div(seen.min_y + seen.max_y, 2) - hy
        if abs(cx) + abs(cy) < KITER_REST_SU:
            return (0, 0)
        vx, vy = cx, cy
    best, best_dot = DIRS[0], None
    for move in DIRS:
        qx, qy = sim.direction_q14(*move)
        dot = qx * vx + qy * vy
        if best_dot is None or dot > best_dot:
            best, best_dot = move, dot
    return best


POLICIES = {"idle": idle, "circle": circle, "kiter": kiter}
DECIDE_EVERY = {"idle": 1, "circle": 1, "kiter": 6}


def p0_config(seed: str):
    """The P0 placeholder run (equal to P0Tuning in the game)."""
    return sim.Config(sim.BASE, sim.P0_VALUES, sim.W0_KINDS, seed, sim.P0_SKILL, sim.P0_XP)


def play(name: str, config, max_ticks: int = MAX_TICKS, stats: dict | None = None):
    """Runs bot `name` until the hero dies or `max_ticks` ticks; returns (world, log). With
    `stats` it records the peak number of gems on the ground."""
    policy, every = POLICIES[name], DECIDE_EVERY[name]
    world, log = sim.World(config), sim.CommandLog()
    held, sequence = (0, 0), 0
    while world.tick < max_ticks and not world.hero_dead:
        if world.tick % every == 0:
            move = policy(Observation(config, world), world.tick)
            if move != held:
                assert log.append((world.tick, sequence, *move), world.tick) == sim.OK
                sequence += 1
                held = move
        sim.step(config, world, log)
        if stats is not None:
            stats["gems_ground_peak"] = max(stats.get("gems_ground_peak", 0), world.gems_alive)
    return world, log


def run_id(name: str, seed: str) -> str:
    return "botrun.p0.%s.s%s" % (name, seed)


def sim_schema_version() -> int:
    return _load("rules_identity", "rules_identity.py").SIM_SCHEMA_VERSION


def _exact(name: str) -> dict:
    config = p0_config(EXACT_SEED)
    world, log = play(name, config)
    assert len(log.records) <= MAX_COMMANDS, (name, len(log.records))
    _, replayed, checkpoints = sim.run_trace(config, log.records, world.tick)
    assert replayed.digest() == world.digest(), name
    return {"id": run_id(name, EXACT_SEED), "name": run_id(name, EXACT_SEED),
            "bot_policy": name, "bot_policy_version": BOT_POLICY_VERSION,
            "config": [str(v) for v in config.ints()[:8]],
            "enemies": {"values": [str(v) for v in config.enemy_values()],
                        "kinds": [str(v) for v in config.raw_kinds], "seed": config.seed},
            "skill": [str(v) for v in config.skill_values()],
            "xp": {"values": [str(v) for v in config.xp_values()],
                   "kind_xp": [str(v) for v in config.kind_xp],
                   "costs": [str(v) for v in config.xp_costs]},
            "commands": [[str(v) for v in c] for c in log.records], "ticks": world.tick,
            "log_digest": log.digest(), "death_tick": world.tick if world.hero_dead else -1,
            "kills": world.kills, "command_count": len(log.records),
            "checkpoints": checkpoints}


def survey() -> list[dict]:
    rows = []
    for name in POLICIES:
        for seed in SURVEY_SEEDS:
            stats: dict = {}
            world, log = play(name, p0_config(seed), stats=stats)
            assert len(log.records) <= MAX_COMMANDS, (name, seed, len(log.records))
            rows.append({"id": run_id(name, seed), "bot_policy": name, "seed": seed,
                         "death_tick": world.tick if world.hero_dead else -1,
                         "kills": world.kills, "command_count": len(log.records),
                         "log_digest": log.digest(), "final_digest": world.digest(),
                         "xp_dropped": world.xp_dropped_total,
                         "xp_collected": world.xp_collected_total, "level": world.level,
                         "gems_ground_end": world.gems_alive,
                         "gems_ground_peak": stats.get("gems_ground_peak", 0)})
    return rows


def build_runs() -> dict:
    return {"schema_version": RUNS_SCHEMA_VERSION, "kind": "hip-sim-bot-runs",
            "sim_schema_version": sim_schema_version(), "bot_policy_version": BOT_POLICY_VERSION,
            "policy_id": fx.POLICY_ID, "rng_policy_id": sim.hip_rng.POLICY_ID,
            "generator": "tools/content/sim_bots.py", "max_ticks": MAX_TICKS,
            "note": "P0 placeholder tuning (ADR-009 section 3, ADR-010); bots are test instruments",
            "traces": [_exact(name) for name in POLICIES], "survey": survey()}


def runs_bytes() -> bytes:
    data = (json.dumps(build_runs(), sort_keys=True, indent=1) + "\n").encode("utf-8")
    assert len(data) <= MAX_FILE_BYTES, len(data)
    return data


def main(argv: list[str]) -> int:
    expected = runs_bytes()
    rel = RUNS_PATH.relative_to(ROOT).as_posix()
    if "--check" in argv:
        if not RUNS_PATH.is_file() or RUNS_PATH.read_bytes() != expected:
            print("FAIL: " + rel + " differs from the reference")
            return 1
        print("OK: sim bot runs match the reference")
        return 0
    RUNS_PATH.write_bytes(expected)
    print("written " + rel + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
