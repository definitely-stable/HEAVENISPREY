"""Reference of the P0-01 simulation core (ADR-008): PlayerCommand log and hero movement
(P0-01b); enemy spawn, chase, contact damage and hero death (P0-01d).

Oracle for game/core/sim/*.gd. Integers only (hip-fx-v1 via tools/content/fx.py, hip-rng-v1
via tools/content/hip_rng.py). Golden traces:
    python tools/content/sim_core.py            # rewrite game/tests/fixtures/sim_core_vectors.json
    python tools/content/sim_core.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_core_vectors.json"
VECTORS_SCHEMA_VERSION = 2


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fx = _load("hip_fx", "fx.py")
hip_rng = _load("hip_rng", "hip_rng.py")

AXIS_Q14 = 16384
DIAG_Q14 = 11585
KIND_STRIDE = 6
SPAWN_ATTEMPTS = 4
MAX_ENEMIES_LIMIT = 4096
BELOW_LIMIT = 1 << 32

OK = "ok"
INVALID = "invalid_command"
PAST_TICK = "past_tick"
TICK_NOT_MONOTONIC = "tick_not_monotonic"
SEQUENCE_NOT_INCREASING = "sequence_not_increasing"


def ints_digest(values: list[int]) -> str:
    """SHA-256 of little-endian int64 bytes (PackedInt64Array.to_byte_array())."""
    return hashlib.sha256(struct.pack("<%dq" % len(values), *values)).hexdigest()


class CommandLog:
    def __init__(self):
        self.records: list[tuple[int, int, int, int]] = []

    def append(self, command: tuple[int, int, int, int], next_tick: int) -> str:
        tick, sequence, move_x, move_y = command
        if tick < 0 or sequence < 0 or abs(move_x) > 1 or abs(move_y) > 1:
            return INVALID
        if tick < next_tick:
            return PAST_TICK
        if self.records:
            if tick < self.records[-1][0]:
                return TICK_NOT_MONOTONIC
            if sequence <= self.records[-1][1]:
                return SEQUENCE_NOT_INCREASING
        self.records.append(command)
        return OK

    def digest(self) -> str:
        return ints_digest([v for record in self.records for v in record])


class Config:
    """Mirror of SimConfig: 8 movement values; optional enemies = 4 values, kinds, seed.

    Kind record: (speed_su_per_tick, radius_su, hp_mhp, contact_damage_mhp,
    contact_interval_ticks, spawn_weight).
    """

    def __init__(self, movement, enemy_values=(0, 0, 0, 0), kinds=(), seed="0"):
        (self.speed, self.radius, self.min_x, self.min_y, self.max_x, self.max_y,
         self.start_x, self.start_y) = movement
        self.hero_hp, self.spawn_period, self.max_enemies, self.spawn_min_distance = enemy_values
        self.kinds = [tuple(kinds[i:i + KIND_STRIDE]) for i in range(0, len(kinds), KIND_STRIDE)]
        self.seed = seed

    def ints(self) -> list[int]:
        return [self.speed, self.radius, self.min_x, self.min_y, self.max_x, self.max_y,
                self.start_x, self.start_y, self.hero_hp, self.spawn_period, self.max_enemies,
                self.spawn_min_distance] + [v for kind in self.kinds for v in kind]

    def total_weight(self) -> int:
        return sum(kind[5] for kind in self.kinds)

    def valid(self) -> bool:
        if any(abs(v) > fx.COORD_MAX for v in self.ints()):
            return False
        r = self.radius
        if not (self.speed >= 0 and r > 0 and self.max_x - self.min_x >= 2 * r
                and self.max_y - self.min_y >= 2 * r
                and self.min_x + r <= self.start_x <= self.max_x - r
                and self.min_y + r <= self.start_y <= self.max_y - r):
            return False
        if not self.kinds:
            return True
        try:
            hip_rng.parse_u64(self.seed)
        except ValueError:
            return False
        if self.hero_hp <= 0 or self.spawn_period <= 0 or self.spawn_min_distance < 0:
            return False
        if not 0 < self.max_enemies <= MAX_ENEMIES_LIMIT:
            return False
        if not 0 < self.total_weight() <= BELOW_LIMIT:
            return False
        for speed, radius, hp, damage, interval, weight in self.kinds:
            perimeter = 2 * (self.max_x - self.min_x - 4 * radius + self.max_y - self.min_y)
            if not (speed >= 0 and radius > 0 and self.max_x - self.min_x > 2 * radius
                    and self.max_y - self.min_y > 2 * radius and perimeter <= BELOW_LIMIT
                    and hp > 0 and damage >= 0 and interval > 0 and weight > 0):
                return False
        return True


def config_valid(movement: list[int]) -> bool:
    return Config(movement).valid()


def direction_q14(move_x: int, move_y: int) -> tuple[int, int]:
    if move_x != 0 and move_y != 0:
        return (fx.sign(move_x) * DIAG_Q14, fx.sign(move_y) * DIAG_Q14)
    return (fx.sign(move_x) * AXIS_Q14, fx.sign(move_y) * AXIS_Q14)


class World:
    def __init__(self, config: Config):
        self.tick = 0
        self.player_x, self.player_y = config.start_x, config.start_y
        self.move_x = self.move_y = 0
        self.command_cursor = 0
        self.hero_hp = config.hero_hp
        self.hero_dead = 0
        self.next_spawn_tick = config.spawn_period
        self.rng_cursor = 0
        self.enemies: list[list[int]] = []  # [kind, x, y, hp, cooldown] in slot order

    def ints(self) -> list[int]:
        head = [self.tick, self.player_x, self.player_y, self.move_x, self.move_y,
                self.command_cursor, self.hero_hp, self.hero_dead, self.next_spawn_tick,
                self.rng_cursor, len(self.enemies)]
        return head + [v for enemy in self.enemies for v in enemy]

    def digest(self) -> str:
        return ints_digest(self.ints())


def _dist2(ax: int, ay: int, bx: int, by: int) -> int:
    return (ax - bx) ** 2 + (ay - by) ** 2


def _touching(config: Config, world: World, enemy: list[int]) -> bool:
    reach = config.radius + config.kinds[enemy[0]][1]
    return _dist2(enemy[1], enemy[2], world.player_x, world.player_y) <= reach * reach


def spawn(config: Config, world: World) -> None:
    if world.tick < world.next_spawn_tick or len(world.enemies) >= config.max_enemies:
        return
    world.next_spawn_tick = world.tick + config.spawn_period
    rng = hip_rng.HipRng(hip_rng.parse_u64(config.seed), "enemy", world.rng_cursor)
    roll = rng.below(config.total_weight())
    kind = len(config.kinds) - 1
    for index, record in enumerate(config.kinds):
        roll -= record[5]
        if roll < 0:
            kind = index
            break
    r = config.kinds[kind][1]
    x0, y0, x1, y1 = config.min_x + r, config.min_y + r, config.max_x - r, config.max_y - r
    w, h = x1 - x0, y1 - y0
    min_d2 = config.spawn_min_distance ** 2
    spot = None
    for _ in range(SPAWN_ATTEMPTS):
        p = rng.below(2 * (w + h))
        if p < w:
            candidate = (x0 + p, y0)
        elif p < w + h:
            candidate = (x1, y0 + p - w)
        elif p < 2 * w + h:
            candidate = (x1 - (p - w - h), y1)
        else:
            candidate = (x0, y1 - (p - 2 * w - h))
        if _dist2(*candidate, world.player_x, world.player_y) >= min_d2:
            spot = candidate
            break
    if spot is None:
        best = -1
        for corner in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            d2 = _dist2(*corner, world.player_x, world.player_y)
            if d2 > best:
                best, spot = d2, corner
    world.rng_cursor = rng.cursor
    world.enemies.append([kind, spot[0], spot[1], config.kinds[kind][2], 0])


def chase(config: Config, world: World) -> None:
    for enemy in world.enemies:
        if _touching(config, world, enemy):
            continue
        speed, r = config.kinds[enemy[0]][0], config.kinds[enemy[0]][1]
        qx, qy = fx.normalize_q14(world.player_x - enemy[1], world.player_y - enemy[2])
        enemy[1] = min(max(enemy[1] + fx.mul_q14(speed, qx), config.min_x + r), config.max_x - r)
        enemy[2] = min(max(enemy[2] + fx.mul_q14(speed, qy), config.min_y + r), config.max_y - r)


def contact(config: Config, world: World) -> None:
    for enemy in world.enemies:
        if enemy[4] > 0:
            enemy[4] -= 1
        if enemy[4] == 0 and _touching(config, world, enemy):
            world.hero_hp -= config.kinds[enemy[0]][3]
            enemy[4] = config.kinds[enemy[0]][4]


def step(config: Config, world: World, log: CommandLog) -> None:
    if world.hero_dead:
        return
    while world.command_cursor < len(log.records) and \
            log.records[world.command_cursor][0] <= world.tick:
        _, _, world.move_x, world.move_y = log.records[world.command_cursor]
        world.command_cursor += 1
    qx, qy = direction_q14(world.move_x, world.move_y)
    r = config.radius
    world.player_x = min(max(world.player_x + fx.mul_q14(config.speed, qx), config.min_x + r),
                         config.max_x - r)
    world.player_y = min(max(world.player_y + fx.mul_q14(config.speed, qy), config.min_y + r),
                         config.max_y - r)
    if config.kinds:
        spawn(config, world)
        chase(config, world)
        contact(config, world)
        if world.hero_hp <= 0:
            world.hero_hp = 0
            world.hero_dead = 1
    world.tick += 1


# Movement hypothesis for traces only (not canon): 0.1 cell/tick with cell = 2 radii
# (GAME-ARCH-02 fixture assumptions), radius 24 px -> 4800 su/tick.
BASE = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
# Enemy trace inputs (not canon): jade_grove.w0 kinds; catalog multipliers applied to
# hero speed/radius and to base 10 HP / 10 contact damage (mhp).
#   yin_corpse: speed 0.68, radius 1.0, hp 1.28, damage 0.65, interval 36, weight 8
#   blood_wolf: speed 1.28, radius 0.9, hp 0.78, damage 0.76, interval 42, weight 2
W0_KINDS = [3264, 24000, 12800, 6500, 36, 8, 6144, 21600, 7800, 7600, 42, 2]
W0_VALUES = [100000, 45, 48, 384000]
SEED = "20261113"


def _circle(period: int, ticks: int) -> list[tuple[int, int, int, int]]:
    dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    return [(t, i, *dirs[i % 8]) for i, t in enumerate(range(0, ticks, period))]


SCENARIOS = [
    ("idle", Config(BASE), [], 120),
    ("east_one_second", Config(BASE), [(0, 0, 1, 0)], 60),
    ("diagonal_north_west", Config(BASE), [(0, 0, -1, -1)], 60),
    ("held_then_released", Config(BASE), [(0, 0, 0, 1), (30, 1, 0, 0)], 90),
    ("clamp_east_wall", Config(BASE), [(0, 0, 1, 0)], 400),
    ("clamp_corner", Config(BASE), [(5, 0, 1, 1)], 600),
    ("same_tick_last_wins", Config(BASE), [(10, 0, 1, 0), (10, 1, -1, 0), (10, 2, 0, -1)], 40),
    ("zigzag", Config(BASE), [(t, t // 7, (1, -1)[(t // 7) % 2], (t // 14) % 3 - 1)
                              for t in range(0, 700, 7)], 720),
    ("odd_speed_symmetry", Config([4801, 1000, -500000, -500000, 500000, 500000, 0, 0]),
     [(0, 0, 1, 1), (100, 1, -1, -1)], 200),
    ("five_minutes", Config(BASE), [(t, t // 90, ((t // 90) % 3) - 1, ((t // 270) % 3) - 1)
                                    for t in range(0, 18000, 90)], 18000),
    ("enemies_hero_stands_still", Config(BASE, W0_VALUES, W0_KINDS, SEED), [], 3000),
    ("enemies_hero_circles", Config(BASE, W0_VALUES, W0_KINDS, SEED), _circle(40, 3600), 3600),
    ("enemies_spawn_cap", Config(BASE, [500000000, 10, 3, 384000], W0_KINDS, "7"), [], 600),
    ("enemies_corner_fallback",
     Config([4800, 24000, 0, 0, 300000, 300000, 150000, 150000], [500000000, 20, 6, 1000000],
            W0_KINDS, "99"), [(0, 0, 1, 1)], 400),
    ("enemies_five_minutes", Config(BASE, [500000000, 30, 64, 384000], W0_KINDS,
                                    "18446744073709551615"), _circle(25, 18000), 18000),
]

APPEND_CASES = [
    ("accepts_first", [], (0, 0, 1, 0), 0, OK),
    ("rejects_past_tick", [], (4, 0, 1, 0), 5, PAST_TICK),
    ("rejects_bad_axis", [], (0, 0, 2, 0), 0, INVALID),
    ("rejects_negative_tick", [], (-1, 0, 0, 0), 0, INVALID),
    ("rejects_older_tick", [(10, 0, 1, 0)], (9, 1, 0, 0), 0, TICK_NOT_MONOTONIC),
    ("rejects_repeated_sequence", [(10, 3, 1, 0)], (11, 3, 0, 0), 0, SEQUENCE_NOT_INCREASING),
    ("accepts_same_tick_next_sequence", [(10, 3, 1, 0)], (10, 4, 0, 1), 0, OK),
]


def _checkpoints(ticks: int) -> list[int]:
    marks = {1, 2, 30, 60, ticks}
    marks.update(range(300, ticks, 300))
    return sorted(m for m in marks if m <= ticks)


def run_trace(config: Config, commands, ticks: int):
    log, world = CommandLog(), World(config)
    for command in commands:
        assert log.append(command, 0) == OK, command
    marks, checkpoints = set(_checkpoints(ticks)), []
    for t in range(1, ticks + 1):
        step(config, world, log)
        if t in marks:
            checkpoints.append({
                "step": t, "tick": world.tick, "player_x": str(world.player_x),
                "player_y": str(world.player_y), "hero_hp": str(world.hero_hp),
                "hero_dead": world.hero_dead, "enemy_count": len(world.enemies),
                "digest": world.digest()})
    return log, world, checkpoints


def build_vectors() -> dict:
    traces = []
    for name, config, commands, ticks in SCENARIOS:
        assert config.valid(), name
        log, _, checkpoints = run_trace(config, commands, ticks)
        enemies = None
        if config.kinds:
            enemies = {"values": [str(v) for v in (config.hero_hp, config.spawn_period,
                                                    config.max_enemies, config.spawn_min_distance)],
                       "kinds": [str(v) for kind in config.kinds for v in kind],
                       "seed": config.seed}
        traces.append({"name": name, "config": [str(v) for v in config.ints()[:8]],
                       "enemies": enemies,
                       "commands": [[str(v) for v in c] for c in commands], "ticks": ticks,
                       "log_digest": log.digest(), "checkpoints": checkpoints})
    appends = []
    for name, existing, command, next_tick, expected in APPEND_CASES:
        log = CommandLog()
        for record in existing:
            assert log.append(record, 0) == OK
        got = log.append(command, next_tick)
        assert got == expected, (name, got)
        appends.append({"name": name, "existing": [list(r) for r in existing],
                        "command": list(command), "next_tick": next_tick, "expected": expected})
    return {"schema_version": VECTORS_SCHEMA_VERSION, "kind": "hip-sim-core-vectors",
            "policy_id": fx.POLICY_ID, "rng_policy_id": hip_rng.POLICY_ID,
            "generator": "tools/content/sim_core.py",
            "note": "movement and enemy constants here are trace inputs, not canonical tuning",
            "traces": traces, "append_cases": appends}


def vectors_bytes() -> bytes:
    return (json.dumps(build_vectors(), sort_keys=True, indent=1) + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    expected = vectors_bytes()
    rel = VECTORS_PATH.relative_to(ROOT).as_posix()
    if "--check" in argv:
        if not VECTORS_PATH.is_file() or VECTORS_PATH.read_bytes() != expected:
            print("FAIL: " + rel + " differs from the reference")
            return 1
        print("OK: sim core vectors match the reference")
        return 0
    VECTORS_PATH.write_bytes(expected)
    print("written " + rel + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
