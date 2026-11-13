"""Scripted test bots for the P0-01 simulation (ADR-009 section 6, slice 2; ADR-010 section 7).

A bot policy is a pure integer function (observation, tick) -> (move_x, move_y) on hip-fx-v1
only (no RNG, no float). It is asked every N ticks (POLICIES) before the tick is simulated;
only changes are logged as MOVE records, so a bot run is fully described by its command log
and replays bit for bit in GDScript (GUT replays the logs).

Observation contract: hero position, position and radius of every enemy in a slot, gems,
arena bounds and, while the run is paused for a level-up choice, the offered hand (upgrade
IDs) with its build_revision. Bots never see the RNG cursor, accumulators, cooldowns or HP. A
bot with a chooser answers every hand with one CHOOSE before the paused step. Any change to a
policy or its constants bumps BOT_POLICY_VERSION and regenerates the fixtures.

Anchors (idle, circle, kiter) play with choice_mode 0 and keep the death tick, kills and
command count of the earlier slices. kiter_upgrades plays with choice_mode 1; its smoke goal is
a survival count, and the diag_* strategies are recorded without a required outcome.

    python tools/content/sim_bots.py            # rewrite both fixtures
    python tools/content/sim_bots.py --check    # fail if a committed fixture differs
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_bot_runs.json"
UPGRADE_RUNS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_bot_upgrade_runs.json"
RUNS_SCHEMA_VERSION = 3
BOT_POLICY_VERSION = 2


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
GEM_PULL_SU = 480000         # 10 cells: kiter_gems is drawn to the nearest gem this close
GEM_PULL_THREAT_Q14 = 6000   # pull weight while an enemy is within KITER_SENSE_SU

MAX_TICKS = 18000            # 300 s
EXACT_SEED = "101"
SURVEY_SEEDS = [str(seed) for seed in range(101, 133)]
MAX_COMMANDS = 700
MAX_UPGRADE_COMMANDS = 2500
MAX_FILE_BYTES = 150 * 1024
MAX_UPGRADE_FILE_BYTES = 256 * 1024   # the exact kiter_upgrades log has ~1400 commands
MAX_UPGRADE_FILE_BYTES = 256 * 1024   # the kiter_upgrades log has ~1500 commands
SMOKE_MIN_SURVIVORS = 28     # ADR-010 section 7: kiter_upgrades reaches MAX_TICKS on 28/32


class Observation:
    """What a bot may see: hero position, enemies (x, y, radius) and gems (x, y) in slot order,
    arena, and the offered hand (upgrade IDs, empty unless paused) with its build_revision.
    The anchor bots read neither gems nor the hand."""

    def __init__(self, config, world):
        self.hero_x, self.hero_y = world.player_x, world.player_y
        self.enemies = [(e[sim.E_X], e[sim.E_Y], config.kinds[e[sim.E_KIND]][1])
                        for e in world.enemies if e[sim.E_UID] != 0]
        self.gems = [(g[sim.G_X], g[sim.G_Y]) for g in world.gems if g[sim.G_UID] != 0]
        self.min_x, self.min_y, self.max_x, self.max_y = (
            config.min_x, config.min_y, config.max_x, config.max_y)
        self.hand = [sim.upgrade_id(code) for code in world.hand]
        self.build_revision = world.build_revision


def idle(seen: Observation, tick: int) -> tuple[int, int]:
    return (0, 0)


def circle(seen: Observation, tick: int) -> tuple[int, int]:
    return DIRS[fx.floor_div(tick, CIRCLE_TURN_TICKS) % 8]


def _flee(seen: Observation) -> tuple[int, int, bool]:
    """Weighted sum of the directions away from enemies within KITER_SENSE_SU plus pushes off
    the walls closer than KITER_WALL_SU; `threat` is True when an enemy is within range."""
    hx, hy = seen.hero_x, seen.hero_y
    vx = vy = 0
    threat = False
    for ex, ey, _radius in seen.enemies:
        dx, dy = hx - ex, hy - ey
        d2 = dx * dx + dy * dy
        if d2 > KITER_SENSE_SU * KITER_SENSE_SU:
            continue
        threat = True
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
    return vx, vy, threat


def _steer(seen: Observation, vx: int, vy: int) -> tuple[int, int]:
    """No pull at all: drift to the centre, or stand near it; else the best of the eight
    directions (largest dot product, first in DIRS on ties)."""
    if vx == 0 and vy == 0:
        cx = fx.floor_div(seen.min_x + seen.max_x, 2) - seen.hero_x
        cy = fx.floor_div(seen.min_y + seen.max_y, 2) - seen.hero_y
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


def kiter(seen: Observation, tick: int) -> tuple[int, int]:
    """Flee the weighted sum of nearby enemies, keep off the walls, else drift to the centre."""
    vx, vy, _threat = _flee(seen)
    return _steer(seen, vx, vy)


def kiter_gems(seen: Observation, tick: int) -> tuple[int, int]:
    """kiter plus a pull towards the nearest gem within GEM_PULL_SU (distance^2, then slot):
    weight GEM_PULL_THREAT_Q14 under threat, a full unit vector without."""
    vx, vy, threat = _flee(seen)
    best, best_d2 = None, 0
    for gx, gy in seen.gems:
        d2 = (gx - seen.hero_x) ** 2 + (gy - seen.hero_y) ** 2
        if d2 <= GEM_PULL_SU * GEM_PULL_SU and (best is None or d2 < best_d2):
            best, best_d2 = (gx, gy), d2
    if best is not None:
        qx, qy = sim.normalize_q14(best[0] - seen.hero_x, best[1] - seen.hero_y)
        weight = GEM_PULL_THREAT_Q14 if threat else fx.Q14
        vx += fx.floor_div(qx * weight, fx.Q14)
        vy += fx.floor_div(qy * weight, fx.Q14)
    return _steer(seen, vx, vy)


def _by_priority(order: list[str]):
    def chooser(seen: Observation) -> int:
        return min(range(len(seen.hand)), key=lambda i: (
            order.index(seen.hand[i]) if seen.hand[i] in order else len(order), i))
    return chooser


# ADR-010 section 6: count > damage > haste > pierce > vitality > speed > pickup.
UPGRADE_PRIORITY = ["upgrade.p0.sword_count", "upgrade.p0.sword_damage",
                    "upgrade.p0.sword_haste", "upgrade.p0.sword_pierce",
                    "upgrade.p0.hero_vitality", "upgrade.p0.hero_speed",
                    "upgrade.p0.pickup_radius"]
UTILITY_FIRST = list(reversed(UPGRADE_PRIORITY))
priority_chooser = _by_priority(UPGRADE_PRIORITY)
utility_chooser = _by_priority(UTILITY_FIRST)


def first_id_chooser(seen: Observation) -> int:
    return min(range(len(seen.hand)), key=lambda i: seen.hand[i])


# name -> (move policy, decide every N ticks, chooser or None). A chooser plays choice_mode 1.
POLICIES = {"idle": (idle, 1, None), "circle": (circle, 1, None), "kiter": (kiter, 6, None),
            "kiter_upgrades": (kiter_gems, 6, priority_chooser),
            "diag_first_id": (kiter_gems, 6, first_id_chooser),
            "diag_utility_first": (kiter_gems, 6, utility_chooser)}
ANCHORS = ["idle", "circle", "kiter"]
UPGRADE_BOTS = ["kiter_upgrades", "diag_first_id", "diag_utility_first"]


def p0_config(seed: str, choice_mode: int = 0):
    """The P0 placeholder run, ending in victory after MAX_TICKS (equal to P0Tuning in the
    game, choice_mode aside)."""
    return sim.Config(sim.BASE, sim.P0_VALUES, sim.W0_KINDS, seed, sim.P0_SKILL, sim.P0_XP,
                      choice_mode=choice_mode, run_ticks=MAX_TICKS)


def config_for(name: str, seed: str):
    return p0_config(seed, 0 if POLICIES[name][2] is None else 1)


def play(name: str, config, max_ticks: int = MAX_TICKS, stats: dict | None = None):
    """Runs bot `name` until the hero dies or `max_ticks` ticks; returns (world, log, steps).
    A paused run gets one CHOOSE from the bot's chooser before the step. With `stats` it
    records the peak number of gems on the ground and the lowest hero HP."""
    policy, every, chooser = POLICIES[name]
    world, log = sim.World(config), sim.CommandLog()
    held, sequence, steps = (0, 0), 0, 0
    while world.tick < max_ticks and not world.over():
        if world.paused():
            seen = Observation(config, world)
            record = (world.tick, sequence, sim.CHOOSE, chooser(seen), seen.build_revision)
            assert log.append(record, world.tick) == sim.OK
            sequence += 1
        elif world.tick % every == 0:
            move = policy(Observation(config, world), world.tick)
            if move != held:
                assert log.append((world.tick, sequence, sim.MOVE, *move), world.tick) == sim.OK
                sequence += 1
                held = move
        sim.step(config, world, log)
        steps += 1
        if stats is not None:
            stats["gems_ground_peak"] = max(stats.get("gems_ground_peak", 0), world.gems_alive)
            stats["hp_min"] = min(stats.get("hp_min", world.hero_hp), world.hero_hp)
    return world, log, steps


def run_id(name: str, seed: str) -> str:
    return "botrun.p0.%s.s%s" % (name, seed)


def sim_schema_version() -> int:
    return _load("rules_identity", "rules_identity.py").SIM_SCHEMA_VERSION


def _exact(name: str, max_commands: int) -> dict:
    config = config_for(name, EXACT_SEED)
    world, log, steps = play(name, config)
    assert len(log.records) <= max_commands, (name, len(log.records))
    _, replayed, checkpoints = sim.run_trace(config, log.records, steps)
    assert replayed.digest() == world.digest(), name
    return {"id": run_id(name, EXACT_SEED), "name": run_id(name, EXACT_SEED),
            "bot_policy": name, "bot_policy_version": BOT_POLICY_VERSION,
            **sim.config_json(config),
            "commands": [[str(v) for v in c] for c in log.records], "ticks": steps,
            "log_digest": log.digest(), "death_tick": world.tick if world.hero_dead else -1,
            "won": world.won,
            "end_tick": world.tick, "kills": world.kills, "command_count": len(log.records),
            "choices": world.choices_done, "checkpoints": checkpoints}


def survey_row(name: str, seed: str, max_commands: int) -> dict:
    stats: dict = {}
    world, log, _steps = play(name, config_for(name, seed), stats=stats)
    assert len(log.records) <= max_commands, (name, seed, len(log.records))
    return {"id": run_id(name, seed), "bot_policy": name, "seed": seed,
            "death_tick": world.tick if world.hero_dead else -1, "won": world.won,
            "kills": world.kills, "command_count": len(log.records),
            "log_digest": log.digest(), "final_digest": world.digest(),
            "xp_dropped": world.xp_dropped_total,
            "xp_collected": world.xp_collected_total, "level": world.level,
            "choices": world.choices_done, "ranks": list(world.ranks),
            "hp_min": stats.get("hp_min", world.hero_hp),
            "gems_ground_end": world.gems_alive,
            "gems_ground_peak": stats.get("gems_ground_peak", 0)}


def _header(note: str) -> dict:
    return {"schema_version": RUNS_SCHEMA_VERSION, "kind": "hip-sim-bot-runs",
            "sim_schema_version": sim_schema_version(), "bot_policy_version": BOT_POLICY_VERSION,
            "log_schema_version": sim.LOG_SCHEMA_VERSION,
            "policy_id": fx.POLICY_ID, "rng_policy_id": sim.hip_rng.POLICY_ID,
            "generator": "tools/content/sim_bots.py", "max_ticks": MAX_TICKS, "note": note}


def build_runs() -> dict:
    return {**_header("P0 placeholder tuning (ADR-009 section 3, ADR-010), choice_mode 0; "
                      "bots are test instruments"),
            "traces": [_exact(name, MAX_COMMANDS) for name in ANCHORS],
            "survey": [survey_row(name, seed, MAX_COMMANDS)
                       for name in ANCHORS for seed in SURVEY_SEEDS]}


def build_upgrade_runs() -> dict:
    return {**_header("P0 placeholder tuning with level-up choices (ADR-010 sections 6-7), "
                      "choice_mode 1; kiter_upgrades is a smoke test, diag_* are baselines"),
            "smoke": {"bot_policy": "kiter_upgrades", "min_survivors": SMOKE_MIN_SURVIVORS,
                      "seeds": len(SURVEY_SEEDS)},
            "traces": [_exact("kiter_upgrades", MAX_UPGRADE_COMMANDS)],
            "survey": [survey_row(name, seed, MAX_UPGRADE_COMMANDS)
                       for name in UPGRADE_BOTS for seed in SURVEY_SEEDS]}


def _bytes(data: dict, limit: int) -> bytes:
    out = (json.dumps(data, sort_keys=True, indent=1) + "\n").encode("utf-8")
    assert len(out) <= limit, len(out)
    return out


def runs_bytes() -> bytes:
    return _bytes(build_runs(), MAX_FILE_BYTES)


def upgrade_runs_bytes() -> bytes:
    return _bytes(build_upgrade_runs(), MAX_UPGRADE_FILE_BYTES)


def main(argv: list[str]) -> int:
    failed = False
    for path, make in ((RUNS_PATH, runs_bytes), (UPGRADE_RUNS_PATH, upgrade_runs_bytes)):
        expected = make()
        rel = path.relative_to(ROOT).as_posix()
        if "--check" in argv:
            if not path.is_file() or path.read_bytes() != expected:
                print("FAIL: " + rel + " differs from the reference")
                failed = True
            else:
                print("OK: " + rel + " matches the reference")
            continue
        path.write_bytes(expected)
        print("written " + rel + " (%d bytes)" % len(expected))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
