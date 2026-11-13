"""Reference of the P0-01 simulation core (ADR-008, ADR-009): PlayerCommand log and hero
movement (P0-01b); enemy spawn, chase, contact damage and hero death (P0-01E); hero
auto-attack with projectiles, enemy deaths and kills (P0-01F); enemy separation (ADR-009 2).

Oracle for game/core/sim/*.gd. Integers only (hip-fx-v1 via tools/content/fx.py, hip-rng-v1
via tools/content/hip_rng.py). Golden traces:
    python tools/content/sim_core.py            # rewrite game/tests/fixtures/sim_core_vectors.json
    python tools/content/sim_core.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import struct
import sys
from itertools import chain
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_core_vectors.json"
VECTORS_SCHEMA_VERSION = 4


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fx = _load("hip_fx", "fx.py")
hip_rng = _load("hip_rng", "hip_rng.py")

_FAST_A = 1 << 30           # |a| * |q| <= 2^30 * 2^15 stays far below the 2^62 saturation
_FAST_Q = 1 << 15


def mul_q14(a: int, q: int) -> int:
    """fx.mul_q14 without the saturation work when it cannot trigger (same result)."""
    if -_FAST_A <= a <= _FAST_A and -_FAST_Q <= q <= _FAST_Q:
        p = (abs(a) * abs(q)) >> 14
        return p if (a ^ q) >= 0 else -p
    return fx.mul_q14(a, q)


def normalize_q14(x: int, y: int) -> tuple[int, int]:
    """fx.normalize_q14 for vectors that need no halving (same result)."""
    ax, ay = abs(x), abs(y)
    big = ax if ax > ay else ay
    if big > fx.NORM_MAX:
        return fx.normalize_q14(x, y)
    if big == 0:
        return (0, 0)
    if big < fx.NORM_UPSCALE_BELOW:
        x, y, ax, ay = (x * fx.NORM_UPSCALE_BELOW, y * fx.NORM_UPSCALE_BELOW,
                        ax * fx.NORM_UPSCALE_BELOW, ay * fx.NORM_UPSCALE_BELOW)
    length = math.isqrt(x * x + y * y)
    qx = (ax << 14) // length
    qy = (ay << 14) // length
    return (qx if x >= 0 else -qx, qy if y >= 0 else -qy)


def isqrt(n: int) -> int:
    """fx.isqrt (floor square root) for 0 <= n <= 2^62 (same result)."""
    if 0 <= n <= fx.PRODUCT_LIMIT:
        return math.isqrt(n)
    return fx.isqrt(n)

AXIS_Q14 = 16384
DIAG_Q14 = 11585
KIND_STRIDE = 6
SPAWN_ATTEMPTS = 4
MAX_ENEMIES_LIMIT = 4096
MAX_PROJECTILES_LIMIT = 256
MAX_PIERCE = 7
RATE_ONE = 1000
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
    """Mirror of SimConfig: 8 movement values; optional enemies (6 values, kinds, seed);
    optional hero skill (8 values).

    enemy_values: (hero_hp_mhp, spawn_period_mt, spawn_ramp_ticks, spawn_rate_max_fx,
    max_enemies, spawn_min_distance_su). Kind record: (speed_su_per_tick, radius_su, hp_mhp,
    contact_damage_mhp, contact_interval_ticks, spawn_weight). skill: (period_mt, range_su,
    damage_mhp, projectile_speed_su, projectile_radius_su, projectile_ttl_ticks,
    projectile_pierce, max_projectiles).
    """

    def __init__(self, movement, enemy_values=(0, 0, 0, RATE_ONE, 0, 0), kinds=(), seed="0",
                 skill=(0,) * 8):
        (self.speed, self.radius, self.min_x, self.min_y, self.max_x, self.max_y,
         self.start_x, self.start_y) = movement
        (self.hero_hp, self.spawn_period, self.spawn_ramp, self.spawn_rate_max,
         self.max_enemies, self.spawn_min_distance) = enemy_values
        (self.skill_period, self.skill_range, self.skill_damage, self.proj_speed,
         self.proj_radius, self.proj_ttl, self.pierce, self.max_projectiles) = skill
        self.raw_kinds = list(kinds)
        self.kinds = [tuple(kinds[i:i + KIND_STRIDE])
                      for i in range(0, len(kinds) - KIND_STRIDE + 1, KIND_STRIDE)]
        self.seed = seed

    def enemy_values(self) -> list[int]:
        return [self.hero_hp, self.spawn_period, self.spawn_ramp, self.spawn_rate_max,
                self.max_enemies, self.spawn_min_distance]

    def skill_values(self) -> list[int]:
        return [self.skill_period, self.skill_range, self.skill_damage, self.proj_speed,
                self.proj_radius, self.proj_ttl, self.pierce, self.max_projectiles]

    def ints(self) -> list[int]:
        return [self.speed, self.radius, self.min_x, self.min_y, self.max_x, self.max_y,
                self.start_x, self.start_y] + self.enemy_values() + self.skill_values() \
            + self.raw_kinds

    def has_enemies(self) -> bool:
        return bool(self.raw_kinds)

    def has_skill(self) -> bool:
        return self.skill_damage > 0

    def total_weight(self) -> int:
        return sum(kind[5] for kind in self.kinds)

    def spawn_rate(self, tick: int) -> int:
        if self.spawn_ramp <= 0:
            return RATE_ONE
        return min(self.spawn_rate_max, RATE_ONE + fx.floor_div(tick * RATE_ONE, self.spawn_ramp))

    def valid(self) -> bool:
        if any(abs(v) > fx.COORD_MAX for v in self.ints()):
            return False
        r = self.radius
        if not (self.speed >= 0 and r > 0 and self.max_x - self.min_x >= 2 * r
                and self.max_y - self.min_y >= 2 * r
                and self.min_x + r <= self.start_x <= self.max_x - r
                and self.min_y + r <= self.start_y <= self.max_y - r):
            return False
        if self.has_enemies() and not self._enemies_valid():
            return False
        if self.has_skill() and not self._skill_valid():
            return False
        return True

    def _enemies_valid(self) -> bool:
        if len(self.raw_kinds) % KIND_STRIDE != 0:
            return False
        try:
            hip_rng.parse_u64(self.seed)
        except ValueError:
            return False
        if self.hero_hp <= 0 or self.spawn_period <= 0 or self.spawn_ramp < 0 \
                or self.spawn_rate_max < RATE_ONE:
            return False
        if self.spawn_min_distance < 0 or not 0 < self.max_enemies <= MAX_ENEMIES_LIMIT:
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

    def _skill_valid(self) -> bool:
        """A projectile must not step over the smallest enemy in one tick (no tunnelling)."""
        if not self.has_enemies():
            return False
        min_radius = min([fx.COORD_MAX] + [kind[1] for kind in self.kinds])
        return (self.skill_period > 0 and self.skill_range >= 0 and self.proj_speed > 0
                and self.proj_radius > 0 and self.proj_speed <= self.proj_radius + min_radius
                and self.proj_ttl > 0 and 0 <= self.pierce <= MAX_PIERCE
                and 0 < self.max_projectiles <= MAX_PROJECTILES_LIMIT)


def config_valid(movement: list[int]) -> bool:
    return Config(movement).valid()


def direction_q14(move_x: int, move_y: int) -> tuple[int, int]:
    if move_x != 0 and move_y != 0:
        return (fx.sign(move_x) * DIAG_Q14, fx.sign(move_y) * DIAG_Q14)
    return (fx.sign(move_x) * AXIS_Q14, fx.sign(move_y) * AXIS_Q14)


# Slot field indexes.
E_UID, E_KIND, E_X, E_Y, E_HP, E_CD = range(6)
P_X, P_Y, P_VX, P_VY, P_TTL, P_PIERCE, P_DAMAGE = range(7)
P_LEDGER = 7


class World:
    """Enemy slot: [uid, kind, x, y, hp, cooldown], free when uid == 0 (all fields 0).
    Projectile slot: [x, y, vx, vy, ttl, pierce_left, damage] + ledger of pierce + 1 enemy
    uids, free when damage == 0. Lists never shrink; spawns take the lowest free slot."""

    def __init__(self, config: Config):
        self.tick = 0
        self.player_x, self.player_y = config.start_x, config.start_y
        self.move_x = self.move_y = 0
        self.command_cursor = 0
        self.hero_hp = config.hero_hp
        self.hero_dead = 0
        self.spawn_acc = 0
        self.rng_cursor = 0
        self.next_enemy_uid = 1
        self.enemy_alive = 0
        self.kills = 0
        self.skill_acc = 0
        self.sep_cursor = 0
        self.ledger_size = config.pierce + 1
        self.enemies: list[list[int]] = []
        self.projectiles: list[list[int]] = []

    def ints(self) -> list[int]:
        head = [self.tick, self.player_x, self.player_y, self.move_x, self.move_y,
                self.command_cursor, self.hero_hp, self.hero_dead, self.spawn_acc,
                self.rng_cursor, self.next_enemy_uid, self.enemy_alive, self.kills,
                self.skill_acc, self.sep_cursor, len(self.enemies), len(self.projectiles)]
        return head + [v for enemy in self.enemies for v in enemy] \
            + [v for projectile in self.projectiles for v in projectile]

    def digest(self) -> str:
        return ints_digest(self.ints())

    def live_projectiles(self) -> int:
        return sum(1 for p in self.projectiles if p[P_DAMAGE] != 0)


def _dist2(ax: int, ay: int, bx: int, by: int) -> int:
    return (ax - bx) ** 2 + (ay - by) ** 2


def _live(enemy: list[int]) -> bool:
    return enemy[E_UID] != 0 and enemy[E_HP] > 0


def _touching(config: Config, world: World, enemy: list[int]) -> bool:
    reach = config.radius + config.kinds[enemy[E_KIND]][1]
    return _dist2(enemy[E_X], enemy[E_Y], world.player_x, world.player_y) <= reach * reach


def _lowest_free(slots: list[list[int]], field: int) -> int:
    for index, slot in enumerate(slots):
        if slot[field] == 0:
            return index
    return -1


def spawn(config: Config, world: World) -> None:
    rate = config.spawn_rate(world.tick)
    world.spawn_acc += rate
    if world.spawn_acc < config.spawn_period:
        return
    if world.enemy_alive >= config.max_enemies:
        world.spawn_acc -= rate  # a blocked accumulator does not advance
        return
    world.spawn_acc -= config.spawn_period
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
    record = [world.next_enemy_uid, kind, spot[0], spot[1], config.kinds[kind][2], 0]
    slot = _lowest_free(world.enemies, E_UID)
    if slot < 0:
        world.enemies.append(record)
    else:
        world.enemies[slot] = record
    world.next_enemy_uid += 1
    world.enemy_alive += 1


SEP_MAX_CHECKS = 4096
SEP_NEIGHBOURS = ((1, 0), (-1, 1), (0, 1), (1, 1))


def cell_size(config: Config) -> int:
    return 2 * max(kind[1] for kind in config.kinds)


def separate(config: Config, world: World, push_x, push_y) -> None:
    """ADR-009 section 2: grid over tick-N positions, pairs cell by cell (the cell's later
    items, then neighbours (+1,0), (-1,+1), (0,+1), (+1,+1)), at most SEP_MAX_CHECKS checks
    counted between cells; the next tick resumes at world.sep_cursor.

    An overlapping pair (i, j) with dx = x_i - x_j pushes each enemy apart by half the overlap
    (hx = sign(dx) * floor(|dx| * half / d)); coincident centres push along x, the larger slot
    towards +x. Python // is floor division, the same as fx.floor_div for a positive divisor."""
    cell = cell_size(config)
    cols = (config.max_x - config.min_x) // cell + 1
    rows = (config.max_y - config.min_y) // cell + 1
    cells = cols * rows
    min_x, min_y, kinds = config.min_x, config.min_y, config.kinds
    buckets: list[list[tuple[int, int, int, int]]] = [[] for _ in range(cells)]
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0:
            continue
        cx = min(max((enemy[E_X] - min_x) // cell, 0), cols - 1)
        cy = min(max((enemy[E_Y] - min_y) // cell, 0), rows - 1)
        buckets[cy * cols + cx].append((slot, enemy[E_X], enemy[E_Y], kinds[enemy[E_KIND]][1]))
    checks = 0
    index = world.sep_cursor if world.sep_cursor < cells else 0
    while index < cells:
        if checks >= SEP_MAX_CHECKS:
            world.sep_cursor = index
            return
        items = buckets[index]
        if not items:
            index += 1
            continue
        cy, cx = divmod(index, cols)
        near = [buckets[(cy + oy) * cols + cx + ox] for ox, oy in SEP_NEIGHBOURS
                if 0 <= cx + ox < cols and cy + oy < rows]
        near_count = sum(len(bucket) for bucket in near)
        count = len(items)
        for a, (i, xi, yi, ri) in enumerate(items):
            checks += count - a - 1 + near_count
            for j, xj, yj, rj in chain(items[a + 1:], *near):
                dx, dy, reach = xi - xj, yi - yj, ri + rj
                d2 = dx * dx + dy * dy
                if d2 >= reach * reach:
                    continue
                if d2 == 0:
                    h = reach >> 1
                    if i > j:
                        push_x[i] += h
                        push_x[j] -= h
                    else:
                        push_x[j] += h
                        push_x[i] -= h
                    continue
                d = math.isqrt(d2)
                half = (reach - d) >> 1
                hx = abs(dx) * half // d
                hy = abs(dy) * half // d
                if dx < 0:
                    hx = -hx
                if dy < 0:
                    hy = -hy
                push_x[i] += hx
                push_y[i] += hy
                push_x[j] -= hx
                push_y[j] -= hy
        index += 1
    world.sep_cursor = 0


def chase_and_separate(config: Config, world: World) -> None:
    """Chase writes tentative positions (touching enemies stay), separation adds pushes from
    tick-N positions, the move is capped at the kind speed and clamped into the arena."""
    tx = [enemy[E_X] for enemy in world.enemies]
    ty = [enemy[E_Y] for enemy in world.enemies]
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0 or _touching(config, world, enemy):
            continue
        speed = config.kinds[enemy[E_KIND]][0]
        qx, qy = normalize_q14(world.player_x - enemy[E_X], world.player_y - enemy[E_Y])
        tx[slot] += mul_q14(speed, qx)
        ty[slot] += mul_q14(speed, qy)
    push_x = [0] * len(world.enemies)
    push_y = [0] * len(world.enemies)
    separate(config, world, push_x, push_y)
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0:
            continue
        speed, r = config.kinds[enemy[E_KIND]][0], config.kinds[enemy[E_KIND]][1]
        mx = tx[slot] - enemy[E_X] + push_x[slot]
        my = ty[slot] - enemy[E_Y] + push_y[slot]
        if mx * mx + my * my > speed * speed:
            qx, qy = normalize_q14(mx, my)
            mx, my = mul_q14(speed, qx), mul_q14(speed, qy)
        enemy[E_X] = min(max(enemy[E_X] + mx, config.min_x + r), config.max_x - r)
        enemy[E_Y] = min(max(enemy[E_Y] + my, config.min_y + r), config.max_y - r)


def nearest_in_range(config: Config, world: World) -> int:
    best, best_d2 = -1, 0
    range2 = config.skill_range * config.skill_range
    for slot, enemy in enumerate(world.enemies):
        if not _live(enemy):
            continue
        d2 = _dist2(enemy[E_X], enemy[E_Y], world.player_x, world.player_y)
        if d2 <= range2 and (best < 0 or d2 < best_d2):
            best, best_d2 = slot, d2
    return best


def cast(config: Config, world: World) -> None:
    world.skill_acc += RATE_ONE
    if world.skill_acc < config.skill_period:
        return
    target = nearest_in_range(config, world)
    slot = _lowest_free(world.projectiles, P_DAMAGE)
    if target < 0 or (slot < 0 and len(world.projectiles) >= config.max_projectiles):
        world.skill_acc -= RATE_ONE  # a blocked accumulator does not advance
        return
    world.skill_acc -= config.skill_period
    enemy = world.enemies[target]
    qx, qy = normalize_q14(enemy[E_X] - world.player_x, enemy[E_Y] - world.player_y)
    if qx == 0 and qy == 0:
        qx = fx.Q14
    record = [world.player_x, world.player_y, mul_q14(config.proj_speed, qx),
              mul_q14(config.proj_speed, qy), config.proj_ttl, config.pierce,
              max(1, config.skill_damage)] + [0] * world.ledger_size
    if slot < 0:
        world.projectiles.append(record)
    else:
        world.projectiles[slot] = record


def _free_projectile(world: World, slot: int) -> None:
    world.projectiles[slot] = [0] * (P_LEDGER + world.ledger_size)


def _resolve_hits(config: Config, world: World, slot: int) -> None:
    projectile = world.projectiles[slot]
    while True:
        ledger = projectile[P_LEDGER:]
        best, best_d2 = -1, 0
        for index, enemy in enumerate(world.enemies):
            if not _live(enemy) or enemy[E_UID] in ledger:
                continue
            reach = config.proj_radius + config.kinds[enemy[E_KIND]][1]
            d2 = _dist2(enemy[E_X], enemy[E_Y], projectile[P_X], projectile[P_Y])
            if d2 <= reach * reach and (best < 0 or d2 < best_d2):
                best, best_d2 = index, d2
        if best < 0:
            return
        enemy = world.enemies[best]
        enemy[E_HP] = max(0, enemy[E_HP] - projectile[P_DAMAGE])
        projectile[P_LEDGER + config.pierce - projectile[P_PIERCE]] = enemy[E_UID]
        if projectile[P_PIERCE] == 0:
            _free_projectile(world, slot)
            return
        projectile[P_PIERCE] -= 1


def fly_and_hit(config: Config, world: World) -> None:
    for slot, projectile in enumerate(world.projectiles):
        if projectile[P_DAMAGE] == 0:
            continue
        x, y = projectile[P_X] + projectile[P_VX], projectile[P_Y] + projectile[P_VY]
        projectile[P_TTL] -= 1
        if x < config.min_x or x > config.max_x or y < config.min_y or y > config.max_y:
            _free_projectile(world, slot)
            continue
        projectile[P_X], projectile[P_Y] = x, y
        _resolve_hits(config, world, slot)


def contact(config: Config, world: World) -> None:
    for enemy in world.enemies:
        if not _live(enemy):
            continue
        if enemy[E_CD] > 0:
            enemy[E_CD] -= 1
        if enemy[E_CD] == 0 and _touching(config, world, enemy):
            world.hero_hp -= config.kinds[enemy[E_KIND]][3]
            enemy[E_CD] = config.kinds[enemy[E_KIND]][4]


def clear_dead(world: World) -> None:
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0 or enemy[E_HP] > 0:
            continue
        world.enemies[slot] = [0] * 6
        world.enemy_alive -= 1
        world.kills += 1


def clear_expired(world: World) -> None:
    for slot, projectile in enumerate(world.projectiles):
        if projectile[P_DAMAGE] != 0 and projectile[P_TTL] <= 0:
            _free_projectile(world, slot)


def step(config: Config, world: World, log: CommandLog) -> None:
    if world.hero_dead:
        return
    while world.command_cursor < len(log.records) and \
            log.records[world.command_cursor][0] <= world.tick:
        _, _, world.move_x, world.move_y = log.records[world.command_cursor]
        world.command_cursor += 1
    qx, qy = direction_q14(world.move_x, world.move_y)
    r = config.radius
    world.player_x = min(max(world.player_x + mul_q14(config.speed, qx), config.min_x + r),
                         config.max_x - r)
    world.player_y = min(max(world.player_y + mul_q14(config.speed, qy), config.min_y + r),
                         config.max_y - r)
    if config.has_enemies():
        spawn(config, world)
        chase_and_separate(config, world)
        if config.has_skill():
            cast(config, world)
            fly_and_hit(config, world)
        contact(config, world)
        clear_dead(world)
        if config.has_skill():
            clear_expired(world)
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
# ADR-009 section 3 placeholder spawn: hero 100 HP, one spawn per 1.5 s at x1 rate, rate
# rising by x1 every 3 min up to x2, 48 alive, 8 cells minimum distance.
P0_VALUES = [100000, 90000, 10800, 2000, 48, 384000]
# ADR-009 section 3 placeholder skill (`skill.spirit_sword`): 50 tick cooldown, 8 cells
# range, 10 HP damage, 12 px/tick, 10 px radius, 40 ticks, pierce 1, 64 projectile slots.
P0_SKILL = [50000, 384000, 10000, 12000, 10000, 40, 1, 64]
SEED = "20261113"


def _circle(period: int, ticks: int) -> list[tuple[int, int, int, int]]:
    dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    return [(t, i, *dirs[i % 8]) for i, t in enumerate(range(0, ticks, period))]


TOUGH = 500000000
STRESS_VALUES = [500000000, 6000, 0, 1000, 150, 384000]
MAX_SEED = "18446744073709551615"

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
    ("enemies_hero_stands_still", Config(BASE, P0_VALUES, W0_KINDS, SEED), [], 3000),
    ("enemies_hero_circles", Config(BASE, P0_VALUES, W0_KINDS, SEED), _circle(40, 3600), 3600),
    ("enemies_spawn_cap", Config(BASE, [TOUGH, 10000, 0, 1000, 3, 384000], W0_KINDS, "7"),
     [], 600),
    ("enemies_corner_fallback",
     Config([4800, 24000, 0, 0, 300000, 300000, 150000, 150000],
            [TOUGH, 20000, 0, 1000, 6, 1000000], W0_KINDS, "99"), [(0, 0, 1, 1)], 400),
    ("enemies_five_minutes", Config(BASE, [TOUGH, 30000, 0, 1000, 64, 384000], W0_KINDS,
                                    MAX_SEED), _circle(25, 18000), 18000),
    ("combat_hero_stands_still", Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL), [], 3600),
    ("combat_hero_circles", Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL),
     _circle(40, 18000), 18000),
    ("combat_pierce_crowd",
     Config(BASE, [TOUGH, 6000, 0, 1000, 64, 200000], W0_KINDS, "123",
            [10000, 600000, 5000, 20000, 12000, 60, 3, 4]), _circle(25, 6000), 6000),
    ("combat_ramp_five_minutes",
     Config(BASE, [TOUGH, 30000, 3600, 4000, 64, 384000], W0_KINDS, MAX_SEED,
            [30000, 480000, 6000, 12000, 10000, 40, 2, 64]), _circle(25, 18000), 18000),
    # ADR-009 section 2 stress fixture: 150 enemies alive within ~15 s, 10000 ticks.
    ("stress_150_separation", Config(BASE, STRESS_VALUES, W0_KINDS, SEED, P0_SKILL),
     _circle(30, 10000), 10000),
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
                "hero_dead": world.hero_dead, "enemy_alive": world.enemy_alive,
                "kills": world.kills, "projectiles": world.live_projectiles(),
                "digest": world.digest()})
    return log, world, checkpoints


def build_vectors() -> dict:
    traces = []
    for name, config, commands, ticks in SCENARIOS:
        assert config.valid(), name
        log, _, checkpoints = run_trace(config, commands, ticks)
        enemies = None
        if config.has_enemies():
            enemies = {"values": [str(v) for v in config.enemy_values()],
                       "kinds": [str(v) for v in config.raw_kinds], "seed": config.seed}
        skill = [str(v) for v in config.skill_values()] if config.has_skill() else None
        traces.append({"name": name, "config": [str(v) for v in config.ints()[:8]],
                       "enemies": enemies, "skill": skill,
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
            "note": "movement, enemy and skill constants here are trace inputs, not canonical tuning",
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
