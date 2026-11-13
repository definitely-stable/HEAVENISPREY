"""Reference of the P0-01 simulation core (ADR-008, ADR-009): PlayerCommand log and hero
movement (P0-01b); enemy spawn, chase, contact damage and hero death (P0-01E); hero
auto-attack with projectiles, enemy deaths and kills (P0-01F); enemy separation (ADR-009 2);
XP gems, pickup and level progression (ADR-010); level-up choice: command log schema 2
(MOVE / CHOOSE), the pause at the tick boundary, the offers hand and the seven P0 upgrades
(ADR-010 section 6).

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
VECTORS_SCHEMA_VERSION = 9


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
MAX_GEMS_LIMIT = 4096
MAX_XP_COSTS = 64
MAX_KIND_XP = 1000000
RATE_ONE = 1000
BELOW_LIMIT = 1 << 32

# ADR-011 sections 2-4: enemy attack record per kind (ATTACK_STRIDE values, kind order):
# (form, telegraph_ticks, active_ticks, recovery_ticks, reach_su, arc_degrees, venom,
#  shot_speed_su, shot_radius_su, keep_su).
# FORM_CONTACT kinds hit by touch (the record is all zeros); the other forms run the attack
# machine with the kind's damage and its interval as the cooldown from the start of `tell`.
# A charge has arc 0 and no venom; its reach is the dash length L. A projectile kind launches
# within reach, does not chase closer than keep_su, and its active_ticks is the lifetime of
# the shot (the enemy itself is active for one tick, the release).
ATTACK_STRIDE = 10
FORM_CONTACT, FORM_ARC, FORM_CHARGE, FORM_PROJECTILE = 0, 1, 2, 3
ENEMY_SHOTS_LIMIT = 64     # enemy projectile pool (ADR-011 section 3)
ST_APPROACH, ST_TELL, ST_ACTIVE, ST_RECOVER = range(4)
MAX_ATTACK_REACH = 1 << 22    # su; keeps the sector test inside int64
MAX_ARC_DEGREES = 180
# status.venom (ADR-011 section 4): (max_stacks, duration_ticks, period_ticks, damage_mhp per
# stack and period), all 0 when no attack applies venom.
VENOM_STRIDE = 4
# round(16384 * cos(k degrees)) for k = 0..180, half away from zero (golden, = FxTables).
COS_Q14 = (
    16384, 16382, 16374, 16362, 16344, 16322, 16294, 16262, 16225, 16182, 16135, 16083, 16026,
    15964, 15897, 15826, 15749, 15668, 15582, 15491, 15396, 15296, 15191, 15082, 14968, 14849,
    14726, 14598, 14466, 14330, 14189, 14044, 13894, 13741, 13583, 13421, 13255, 13085, 12911,
    12733, 12551, 12365, 12176, 11982, 11786, 11585, 11381, 11174, 10963, 10749, 10531, 10311,
    10087, 9860, 9630, 9397, 9162, 8923, 8682, 8438, 8192, 7943, 7692, 7438, 7182, 6924, 6664,
    6402, 6138, 5872, 5604, 5334, 5063, 4790, 4516, 4240, 3964, 3686, 3406, 3126, 2845, 2563,
    2280, 1997, 1713, 1428, 1143, 857, 572, 286, 0, -286, -572, -857, -1143, -1428, -1713,
    -1997, -2280, -2563, -2845, -3126, -3406, -3686, -3964, -4240, -4516, -4790, -5063, -5334,
    -5604, -5872, -6138, -6402, -6664, -6924, -7182, -7438, -7692, -7943, -8192, -8438, -8682,
    -8923, -9162, -9397, -9630, -9860, -10087, -10311, -10531, -10749, -10963, -11174, -11381,
    -11585, -11786, -11982, -12176, -12365, -12551, -12733, -12911, -13085, -13255, -13421,
    -13583, -13741, -13894, -14044, -14189, -14330, -14466, -14598, -14726, -14849, -14968,
    -15082, -15191, -15296, -15396, -15491, -15582, -15668, -15749, -15826, -15897, -15964,
    -16026, -16083, -16135, -16182, -16225, -16262, -16294, -16322, -16344, -16362, -16374,
    -16382, -16384)

OK = "ok"
INVALID = "invalid_command"
PAST_TICK = "past_tick"
TICK_NOT_MONOTONIC = "tick_not_monotonic"
SEQUENCE_NOT_INCREASING = "sequence_not_increasing"

# Command log schema 2 (ADR-010 section 6): record (tick, sequence, kind, a, b).
LOG_SCHEMA_VERSION = 2
MOVE = 0     # a = move_x, b = move_y in -1..1: the held direction from `tick` on
CHOOSE = 1   # a = card index in the hand, b = build_revision the hand was built for

# ADR-010 section 6, P0 policy (not engine limits): the seven upgrades in ASCII ID order with
# their maximum rank; the code of an upgrade is its position. RECOVER is offered alone when
# every upgrade is at its maximum rank; it has no rank.
UPGRADES = (("upgrade.p0.hero_speed", 3), ("upgrade.p0.hero_vitality", 5),
            ("upgrade.p0.pickup_radius", 3), ("upgrade.p0.sword_count", 2),
            ("upgrade.p0.sword_damage", 2), ("upgrade.p0.sword_haste", 5),
            ("upgrade.p0.sword_pierce", 2))
U_SPEED, U_VITALITY, U_PICKUP, U_COUNT, U_DAMAGE, U_HASTE, U_PIERCE = range(7)
U_RECOVER = 7
RECOVER_ID = "upgrade.p0.recover"
HAND_SIZE = 3
NO_CARD = -1
SPEED_PER_RANK = 240          # su/tick
VITALITY_PER_RANK = 20000     # mhp of maximum HP, healed at once
RECOVER_HEAL = 20000          # mhp, up to the maximum
PICKUP_PER_RANK = 24000       # su
DAMAGE_PER_RANK = 3000        # mhp
HASTE_PER_RANK = 150          # rate_fx of the skill cooldown accumulator
OFFERS_STREAM = "offers"


def upgrade_id(code: int) -> str:
    return RECOVER_ID if code == U_RECOVER else UPGRADES[code][0]


def ints_digest(values: list[int]) -> str:
    """SHA-256 of little-endian int64 bytes (PackedInt64Array.to_byte_array())."""
    return hashlib.sha256(struct.pack("<%dq" % len(values), *values)).hexdigest()


def command_valid(command) -> bool:
    if len(command) != 5:
        return False
    tick, sequence, kind, a, b = command
    if tick < 0 or sequence < 0:
        return False
    if kind == MOVE:
        return abs(a) <= 1 and abs(b) <= 1
    return kind == CHOOSE and a >= 0 and b >= 0


def migrate_v1(records) -> list[tuple[int, int, int, int, int]]:
    """Schema 1 records (tick, sequence, move_x, move_y) become MOVE records of schema 2."""
    return [(tick, sequence, MOVE, move_x, move_y) for tick, sequence, move_x, move_y in records]


class CommandLog:
    def __init__(self):
        self.records: list[tuple[int, int, int, int, int]] = []

    def append(self, command: tuple[int, int, int, int, int], next_tick: int) -> str:
        if not command_valid(command):
            return INVALID
        tick, sequence = command[0], command[1]
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
    optional hero skill (8 values); optional XP (ADR-010): xp = ((pickup_radius_su, max_gems),
    xp_value per kind in kind order, incremental level costs).

    enemy_values: (hero_hp_mhp, spawn_period_mt, spawn_ramp_ticks, spawn_rate_max_fx,
    max_enemies, spawn_min_distance_su). Kind record: (speed_su_per_tick, radius_su, hp_mhp,
    contact_damage_mhp, contact_interval_ticks, spawn_weight). skill: (period_mt, range_su,
    damage_mhp, projectile_speed_su, projectile_radius_su, projectile_ttl_ticks,
    projectile_pierce, max_projectiles). choice_mode (ADR-010 section 6): 0 = level-ups never
    stop the run (the choices stay pending), 1 = Immediate (the run pauses for each choice).
    run_ticks (ADR-011 section 1): the stage duration; the hero who is not dead after the tick
    that reaches it wins. 0 = no time limit.
    attacks (ADR-011 sections 2-3): empty (every kind hits by contact) or one ATTACK_STRIDE
    record per kind; venom: the status.venom values (VENOM_STRIDE).
    """

    def __init__(self, movement, enemy_values=(0, 0, 0, RATE_ONE, 0, 0), kinds=(), seed="0",
                 skill=(0,) * 8, xp=((0, 0), (), ()), choice_mode=0, run_ticks=0, attacks=(),
                 venom=(0,) * VENOM_STRIDE):
        self.choice_mode = choice_mode
        self.run_ticks = run_ticks
        self.raw_attacks = list(attacks)
        self.venom = list(venom)
        (self.venom_max, self.venom_duration, self.venom_period, self.venom_damage) = \
            (list(venom) + [0] * VENOM_STRIDE)[:VENOM_STRIDE]
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
        (self.pickup_radius, self.max_gems), kind_xp, costs = xp
        self.kind_xp, self.xp_costs = list(kind_xp), list(costs)

    def enemy_values(self) -> list[int]:
        return [self.hero_hp, self.spawn_period, self.spawn_ramp, self.spawn_rate_max,
                self.max_enemies, self.spawn_min_distance]

    def skill_values(self) -> list[int]:
        return [self.skill_period, self.skill_range, self.skill_damage, self.proj_speed,
                self.proj_radius, self.proj_ttl, self.pierce, self.max_projectiles]

    def xp_values(self) -> list[int]:
        return [self.pickup_radius, self.max_gems]

    def ints(self) -> list[int]:
        return [self.speed, self.radius, self.min_x, self.min_y, self.max_x, self.max_y,
                self.start_x, self.start_y] + self.enemy_values() + self.skill_values() \
            + self.raw_kinds + self.xp_values() + self.kind_xp + self.xp_costs \
            + [self.choice_mode, self.run_ticks, len(self.raw_attacks)] + self.raw_attacks \
            + self.venom

    def attack(self, kind: int) -> tuple:
        """The attack record of `kind`; all zeros (contact) without an attack table."""
        if not self.raw_attacks:
            return (0,) * ATTACK_STRIDE
        return tuple(self.raw_attacks[kind * ATTACK_STRIDE:(kind + 1) * ATTACK_STRIDE])

    def form(self, kind: int) -> int:
        return self.attack(kind)[0]

    def ledger_size(self) -> int:
        """Ledger cells of every projectile slot: enough for the largest pierce an upgrade can
        reach; a projectile uses `pierce at cast + 1` of them (its capacity)."""
        return min(MAX_PIERCE, self.pierce + UPGRADES[U_PIERCE][1]) + 1

    def has_enemies(self) -> bool:
        return bool(self.raw_kinds)

    def has_skill(self) -> bool:
        return self.skill_damage > 0

    def has_xp(self) -> bool:
        return bool(self.xp_costs)

    def xp_cost(self, level: int) -> int:
        """XP to go from `level` to `level + 1`; the last listed cost repeats."""
        return self.xp_costs[min(level - 1, len(self.xp_costs) - 1)]

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
        if (self.has_xp() or self.kind_xp) and not self._xp_valid():
            return False
        if self.choice_mode not in (0, 1):
            return False
        if self.choice_mode == 1 and not (self.has_xp() and self.has_skill()):
            return False
        if self.raw_attacks and not self._attacks_valid():
            return False
        if len(self.venom) != VENOM_STRIDE:
            return False
        return self.run_ticks >= 0

    def _attacks_valid(self) -> bool:
        """One record per kind; a contact record is all zeros; an arc needs whole phases, a
        reach up to MAX_ATTACK_REACH, an arc of 1..180 degrees; venom needs its status values."""
        if not self.has_enemies() or len(self.raw_attacks) != len(self.kinds) * ATTACK_STRIDE:
            return False
        venom_used = False
        for kind in range(len(self.kinds)):
            form, tell, active, recover, reach, arc, venom, speed, shot_r, keep = \
                self.attack(kind)
            if form == FORM_CONTACT:
                if any(self.attack(kind)):
                    return False
                continue
            if form not in (FORM_ARC, FORM_CHARGE, FORM_PROJECTILE) or tell < 1 or active < 1 \
                    or recover < 0:
                return False
            if not 0 < reach <= MAX_ATTACK_REACH:
                return False
            if form == FORM_PROJECTILE:
                # A shot must not step over the hero in one tick (no tunnelling) and must
                # deal damage; it is released from the enemy centre.
                if arc != 0 or venom != 0 or not 0 < shot_r <= MAX_ATTACK_REACH \
                        or not 0 < speed <= self.radius + shot_r or not 0 <= keep <= reach \
                        or self.kinds[kind][3] <= 0:
                    return False
                continue
            if speed != 0 or shot_r != 0 or keep != 0:
                return False
            if form == FORM_CHARGE:
                # A dash moves reach // active su per tick: at least 1 su, and no tunnelling
                # through the hero (a step no longer than the two radii).
                step = reach // active
                if arc != 0 or venom != 0 or step < 1 or step > self.radius + self.kinds[kind][1]:
                    return False
                continue
            if not 0 < arc <= MAX_ARC_DEGREES:
                return False
            if venom not in (0, 1):
                return False
            venom_used = venom_used or venom == 1
        if venom_used:
            return (self.venom_max > 0 and self.venom_duration > 0 and self.venom_period > 0
                    and self.venom_damage >= 0)
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

    def _xp_valid(self) -> bool:
        """Gems fall where enemies die: a gem dropped by an enemy touching the hero must be in
        reach (pickup radius >= hero radius - smallest kind radius)."""
        if not self.has_enemies() or len(self.kind_xp) != len(self.kinds):
            return False
        min_radius = min(kind[1] for kind in self.kinds)
        return (0 < len(self.xp_costs) <= MAX_XP_COSTS and all(c > 0 for c in self.xp_costs)
                and all(0 <= v <= MAX_KIND_XP for v in self.kind_xp)
                and self.pickup_radius >= max(0, self.radius - min_radius)
                and 0 < self.max_gems <= MAX_GEMS_LIMIT)


def config_valid(movement: list[int]) -> bool:
    return Config(movement).valid()


def direction_q14(move_x: int, move_y: int) -> tuple[int, int]:
    if move_x != 0 and move_y != 0:
        return (fx.sign(move_x) * DIAG_Q14, fx.sign(move_y) * DIAG_Q14)
    return (fx.sign(move_x) * AXIS_Q14, fx.sign(move_y) * AXIS_Q14)


# Slot field indexes. Enemy: the attack state, ticks left in it, the attack direction (Q14;
# an arc fixes it at the start of `tell`, a charge aims again at its end), the uid of the
# attack instance and whether that instance already hit the hero (ADR-011 section 2).
E_UID, E_KIND, E_X, E_Y, E_HP, E_CD, E_STATE, E_LEFT, E_DX, E_DY, E_ATK, E_HIT = range(12)
ENEMY_FIELDS = 12
P_X, P_Y, P_VX, P_VY, P_TTL, P_DAMAGE, P_HITS, P_CAP = range(8)
P_LEDGER = 8
G_UID, G_X, G_Y, G_VALUE = range(4)
S_X, S_Y, S_VX, S_VY, S_TTL, S_DAMAGE, S_RADIUS = range(7)
SHOT_FIELDS = 7


class World:
    """Enemy slot: [uid, kind, x, y, hp, cooldown, state, left, dir_x, dir_y, attack_uid,
    hit], free when uid == 0 (all fields 0).
    Projectile slot: [x, y, vx, vy, ttl, damage, hit_count, capacity] + config.ledger_size()
    ledger cells (enemy uids, the first hit_count used), free when damage == 0; damage and
    capacity (pierce + 1) are a snapshot taken at the cast. Gem slot: [uid, x, y, value], free
    when uid == 0. Lists never shrink; spawns and drops take the lowest free slot.

    Build (ADR-010 section 6): upgrade ranks in code order, the maximum hero HP, the current
    hand of upgrade codes (non-empty only while the run is paused for a choice).

    Enemy attacks and hero statuses (ADR-011 sections 2 and 4): the attack instance counter and
    status.venom (stacks, ticks left, ticks to the next damage). Enemy shot slot: [x, y, vx, vy,
    ttl, damage, radius], free when damage == 0 (all fields 0); lowest free slot, at most
    ENEMY_SHOTS_LIMIT slots."""

    def __init__(self, config: Config):
        self.tick = 0
        self.player_x, self.player_y = config.start_x, config.start_y
        self.move_x = self.move_y = 0
        self.command_cursor = 0
        self.hero_hp = config.hero_hp
        self.hero_dead = 0
        self.won = 0
        self.spawn_acc = 0
        self.rng_cursor = 0
        self.next_enemy_uid = 1
        self.enemy_alive = 0
        self.kills = 0
        self.skill_acc = 0
        self.sep_cursor = 0
        self.next_gem_uid = 1
        self.gems_alive = 0
        self.gems_merged = 0
        self.xp_dropped_total = 0
        self.xp_collected_total = 0
        self.xp_bank = 0
        self.level = 1
        self.pending_level_choices = 0
        self.choices_voided = 0
        self.choices_done = 0
        self.build_revision = 0
        self.offers_rng_cursor = 0
        self.hand: list[int] = []
        self.ranks = [0] * len(UPGRADES)
        self.hero_hp_max = config.hero_hp
        self.next_attack_uid = 1
        self.venom_stacks = 0
        self.venom_left = 0
        self.venom_phase = 0
        self.ledger_size = config.ledger_size()
        self.enemies: list[list[int]] = []
        self.projectiles: list[list[int]] = []
        self.gems: list[list[int]] = []
        self.shots: list[list[int]] = []

    def over(self) -> bool:
        """Terminal: the hero died or the run was won (ADR-011 section 1)."""
        return bool(self.hero_dead or self.won)

    def paused(self) -> bool:
        """The run waits for a CHOOSE: no tick is simulated while a hand is offered."""
        return bool(self.hand)

    def ints(self) -> list[int]:
        hand = self.hand + [NO_CARD] * (HAND_SIZE - len(self.hand))
        head = [self.tick, self.player_x, self.player_y, self.move_x, self.move_y,
                self.command_cursor, self.hero_hp, self.hero_dead, self.won, self.spawn_acc,
                self.rng_cursor, self.next_enemy_uid, self.enemy_alive, self.kills,
                self.skill_acc, self.sep_cursor, self.next_gem_uid, self.gems_alive,
                self.gems_merged, self.xp_dropped_total, self.xp_collected_total, self.xp_bank,
                self.level, self.pending_level_choices, self.choices_voided,
                self.choices_done, self.build_revision, self.offers_rng_cursor] + hand \
            + self.ranks + [self.hero_hp_max, self.next_attack_uid, self.venom_stacks,
                            self.venom_left, self.venom_phase, len(self.enemies),
                            len(self.projectiles), len(self.gems), len(self.shots)]
        return head + [v for enemy in self.enemies for v in enemy] \
            + [v for projectile in self.projectiles for v in projectile] \
            + [v for gem in self.gems for v in gem] \
            + [v for shot in self.shots for v in shot]

    def digest(self) -> str:
        return ints_digest(self.ints())

    def live_projectiles(self) -> int:
        return sum(1 for p in self.projectiles if p[P_DAMAGE] != 0)

    def live_shots(self) -> int:
        return sum(1 for shot in self.shots if shot[S_DAMAGE] != 0)


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
    record = [world.next_enemy_uid, kind, spot[0], spot[1], config.kinds[kind][2]] \
        + [0] * (ENEMY_FIELDS - E_CD)
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
        if enemy[E_UID] == 0 or enemy[E_STATE] != ST_APPROACH:
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
    tick-N positions, the move is capped at the kind speed and clamped into the arena. An
    enemy in an attack (state other than approach) neither moves nor takes part in the
    separation (ADR-011 section 2)."""
    tx = [enemy[E_X] for enemy in world.enemies]
    ty = [enemy[E_Y] for enemy in world.enemies]
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0 or enemy[E_STATE] != ST_APPROACH or _touching(config, world, enemy):
            continue
        if _keeps_distance(config, world, enemy):
            continue
        speed = config.kinds[enemy[E_KIND]][0]
        qx, qy = normalize_q14(world.player_x - enemy[E_X], world.player_y - enemy[E_Y])
        tx[slot] += mul_q14(speed, qx)
        ty[slot] += mul_q14(speed, qy)
    push_x = [0] * len(world.enemies)
    push_y = [0] * len(world.enemies)
    separate(config, world, push_x, push_y)
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0 or enemy[E_STATE] != ST_APPROACH:
            continue
        speed, r = config.kinds[enemy[E_KIND]][0], config.kinds[enemy[E_KIND]][1]
        mx = tx[slot] - enemy[E_X] + push_x[slot]
        my = ty[slot] - enemy[E_Y] + push_y[slot]
        if mx * mx + my * my > speed * speed:
            qx, qy = normalize_q14(mx, my)
            mx, my = mul_q14(speed, qx), mul_q14(speed, qy)
        enemy[E_X] = min(max(enemy[E_X] + mx, config.min_x + r), config.max_x - r)
        enemy[E_Y] = min(max(enemy[E_Y] + my, config.min_y + r), config.max_y - r)


# Derived stats of the build (ADR-010 section 6): config base + rank x step.
def hero_speed(config: Config, world: World) -> int:
    return config.speed + SPEED_PER_RANK * world.ranks[U_SPEED]


def pickup_radius(config: Config, world: World) -> int:
    return config.pickup_radius + PICKUP_PER_RANK * world.ranks[U_PICKUP]


def skill_rate(world: World) -> int:
    return RATE_ONE + HASTE_PER_RANK * world.ranks[U_HASTE]


def skill_damage(config: Config, world: World) -> int:
    return max(1, config.skill_damage + DAMAGE_PER_RANK * world.ranks[U_DAMAGE])


def projectile_count(world: World) -> int:
    return 1 + world.ranks[U_COUNT]


def projectile_pierce(config: Config, world: World) -> int:
    return min(MAX_PIERCE, config.pierce + world.ranks[U_PIERCE])


def targets_in_range(config: Config, world: World, count: int) -> list[int]:
    """Up to `count` distinct live enemies within the skill range, nearest first (distance^2,
    then the lower slot)."""
    range2 = config.skill_range * config.skill_range
    found = []
    for slot, enemy in enumerate(world.enemies):
        if _live(enemy):
            d2 = _dist2(enemy[E_X], enemy[E_Y], world.player_x, world.player_y)
            if d2 <= range2:
                found.append((d2, slot))
    found.sort()
    return [slot for _, slot in found[:count]]


def nearest_in_range(config: Config, world: World) -> int:
    targets = targets_in_range(config, world, 1)
    return targets[0] if targets else -1


def cast(config: Config, world: World) -> None:
    """One cast fires a projectile at each of up to `count` targets. With no target, or fewer
    free projectile slots than projectiles to fire, the whole cast is held and the tick does not
    advance the accumulator."""
    rate = skill_rate(world)
    world.skill_acc += rate
    if world.skill_acc < config.skill_period:
        return
    targets = targets_in_range(config, world, projectile_count(world))
    free = sum(1 for p in world.projectiles if p[P_DAMAGE] == 0)
    room = free + config.max_projectiles - len(world.projectiles)
    if not targets or room < len(targets):
        world.skill_acc -= rate  # a blocked accumulator does not advance
        return
    world.skill_acc -= config.skill_period
    damage, capacity = skill_damage(config, world), projectile_pierce(config, world) + 1
    for target in targets:
        enemy = world.enemies[target]
        qx, qy = normalize_q14(enemy[E_X] - world.player_x, enemy[E_Y] - world.player_y)
        if qx == 0 and qy == 0:
            qx = fx.Q14
        record = [world.player_x, world.player_y, mul_q14(config.proj_speed, qx),
                  mul_q14(config.proj_speed, qy), config.proj_ttl, damage, 0,
                  capacity] + [0] * world.ledger_size
        slot = _lowest_free(world.projectiles, P_DAMAGE)
        if slot < 0:
            world.projectiles.append(record)
        else:
            world.projectiles[slot] = record


def _free_projectile(world: World, slot: int) -> None:
    world.projectiles[slot] = [0] * (P_LEDGER + world.ledger_size)


def _resolve_hits(config: Config, world: World, slot: int) -> None:
    """Hits the nearest live overlapping enemy not in this projectile's ledger until the
    projectile has used its own capacity (pierce at cast + 1)."""
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
        projectile[P_LEDGER + projectile[P_HITS]] = enemy[E_UID]
        projectile[P_HITS] += 1
        if projectile[P_HITS] >= projectile[P_CAP]:
            _free_projectile(world, slot)
            return


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
        if not _live(enemy) or config.form(enemy[E_KIND]) != FORM_CONTACT:
            continue
        if enemy[E_CD] > 0:
            enemy[E_CD] -= 1
        if enemy[E_CD] == 0 and _touching(config, world, enemy):
            world.hero_hp -= config.kinds[enemy[E_KIND]][3]
            enemy[E_CD] = config.kinds[enemy[E_KIND]][4]


def in_launch_range(reach: int, dx: int, dy: int) -> bool:
    """ADR-011 section 3: an arc starts when the hero centre is within 3R/4 (16 d^2 <= 9 R^2,
    tested after d^2 <= R^2 so the products stay inside int64)."""
    d2 = dx * dx + dy * dy
    return d2 <= reach * reach and 16 * d2 <= 9 * reach * reach


def _keeps_distance(config: Config, world: World, enemy: list[int]) -> bool:
    """A projectile kind does not chase closer than its keep distance (ADR-011 section 3)."""
    record = config.attack(enemy[E_KIND])
    if record[0] != FORM_PROJECTILE:
        return False
    return _dist2(enemy[E_X], enemy[E_Y], world.player_x, world.player_y) <= record[9] * record[9]


def _release(config: Config, world: World, enemy: list[int]) -> None:
    """The shot of a projectile attack: from the enemy centre along the locked direction, the
    lowest free shot slot; with all ENEMY_SHOTS_LIMIT slots taken no shot is fired."""
    record = config.attack(enemy[E_KIND])
    speed, radius, ttl = record[7], record[8], record[2]
    shot = [enemy[E_X], enemy[E_Y], mul_q14(speed, enemy[E_DX]), mul_q14(speed, enemy[E_DY]),
            ttl, config.kinds[enemy[E_KIND]][3], radius]
    slot = _lowest_free(world.shots, S_DAMAGE)
    if slot >= 0:
        world.shots[slot] = shot
    elif len(world.shots) < ENEMY_SHOTS_LIMIT:
        world.shots.append(shot)


def fly_shots(config: Config, world: World) -> None:
    """Enemy shots after the hero's projectiles (ADR-011 section 2), slot order: a shot moves,
    loses a tick of life, and is freed past the arena edge, on touching the hero (the damage,
    once) or when its life runs out. Shots outlive the enemy that fired them."""
    for slot, shot in enumerate(world.shots):
        if shot[S_DAMAGE] == 0:
            continue
        shot[S_X] += shot[S_VX]
        shot[S_Y] += shot[S_VY]
        shot[S_TTL] -= 1
        x, y = shot[S_X], shot[S_Y]
        if x < config.min_x or x > config.max_x or y < config.min_y or y > config.max_y:
            world.shots[slot] = [0] * SHOT_FIELDS
            continue
        reach = config.radius + shot[S_RADIUS]
        if _dist2(x, y, world.player_x, world.player_y) <= reach * reach:
            world.hero_hp -= shot[S_DAMAGE]
            world.shots[slot] = [0] * SHOT_FIELDS
        elif shot[S_TTL] <= 0:
            world.shots[slot] = [0] * SHOT_FIELDS


def _aim(world: World, enemy: list[int]) -> tuple[int, int]:
    """Q14 direction from the enemy to the hero; +x when they coincide."""
    ux, uy = normalize_q14(world.player_x - enemy[E_X], world.player_y - enemy[E_Y])
    return (fx.Q14, 0) if ux == 0 and uy == 0 else (ux, uy)


def _dash(config: Config, world: World, enemy: list[int], step: int) -> None:
    """One active tick of a charge (ADR-011 section 3): `step` su along the fixed direction,
    clamped into the arena; the first touch of the hero in this instance deals the damage."""
    r = config.kinds[enemy[E_KIND]][1]
    enemy[E_X] = min(max(enemy[E_X] + mul_q14(step, enemy[E_DX]), config.min_x + r), config.max_x - r)
    enemy[E_Y] = min(max(enemy[E_Y] + mul_q14(step, enemy[E_DY]), config.min_y + r), config.max_y - r)
    if enemy[E_HIT] == 0 and _touching(config, world, enemy):
        world.hero_hp -= config.kinds[enemy[E_KIND]][3]
        enemy[E_HIT] = 1


def in_sector(reach: int, arc: int, ux: int, uy: int, dx: int, dy: int) -> bool:
    """The point (dx, dy) from the sector centre lies in the sector of radius `reach`, width
    `arc` degrees (1..180) around the Q14 direction (ux, uy): d <= R and the angle theta to
    the direction <= arc / 2, i.e. dot >= 0 and cos(2 theta) >= cos(arc), with
    cos(2 theta) = 2 cos^2(theta) - 1 and dot = d cos(theta) (floored to su). The centre itself
    is inside."""
    d2 = dx * dx + dy * dy
    if d2 > reach * reach:
        return False
    if d2 == 0:
        return True
    dot = ux * dx + uy * dy
    if dot < 0:
        return False
    dot_su = dot >> 14
    return 2 * dot_su * dot_su * fx.Q14 >= d2 * (fx.Q14 + COS_Q14[arc])


def add_venom(config: Config, world: World) -> None:
    """status.venom refresh_and_add (ADR-011 section 4): one more stack up to the cap, the
    duration starts again; the damage period runs from the first stack."""
    if world.venom_stacks == 0:
        world.venom_phase = config.venom_period
    world.venom_stacks = min(world.venom_stacks + 1, config.venom_max)
    world.venom_left = config.venom_duration


def enemy_attacks(config: Config, world: World) -> None:
    """ADR-011 section 2, slot order, live attack-machine enemies: the cooldown counts down;
    an enemy in an attack counts down its state (tell -> active -> recover -> approach); an
    approaching enemy with a ready cooldown and the hero within the launch range starts
    `tell`: the direction to the hero is taken, the cooldown restarts and the attack instance
    gets the next attack uid. The tell starts in this tick and lasts telegraph_ticks ticks.
    MELEE_ARC (launch d <= 3R/4): the direction stays; the sector hits in the first active
    tick (start + telegraph). CHARGE (launch d <= L): the direction is aimed again at the end
    of `tell` and does not change after; each active tick dashes L // active_ticks su and the
    first touch hits."""
    for enemy in world.enemies:
        if not _live(enemy):
            continue
        kind = enemy[E_KIND]
        form, tell, active, recover, reach, arc, venom = config.attack(kind)[:7]
        if form == FORM_CONTACT:
            continue
        if form == FORM_PROJECTILE:
            active = 1  # the enemy releases the shot; the shot lives active_ticks
        if enemy[E_CD] > 0:
            enemy[E_CD] -= 1
        if enemy[E_STATE] != ST_APPROACH:
            enemy[E_LEFT] -= 1
            if enemy[E_LEFT] == 0:
                if enemy[E_STATE] == ST_TELL:
                    enemy[E_STATE], enemy[E_LEFT] = ST_ACTIVE, active
                    if form == FORM_CHARGE:
                        enemy[E_DX], enemy[E_DY] = _aim(world, enemy)
                    elif form == FORM_PROJECTILE:
                        enemy[E_DX], enemy[E_DY] = _aim(world, enemy)
                        _release(config, world, enemy)
                    elif in_sector(reach, arc, enemy[E_DX], enemy[E_DY],
                                   world.player_x - enemy[E_X], world.player_y - enemy[E_Y]):
                        world.hero_hp -= config.kinds[kind][3]
                        if venom:
                            add_venom(config, world)
                elif enemy[E_STATE] == ST_ACTIVE and recover > 0:
                    enemy[E_STATE], enemy[E_LEFT] = ST_RECOVER, recover
                else:
                    enemy[E_STATE], enemy[E_DX], enemy[E_DY], enemy[E_ATK] = ST_APPROACH, 0, 0, 0
                    enemy[E_HIT] = 0
        if form == FORM_CHARGE and enemy[E_STATE] == ST_ACTIVE:
            _dash(config, world, enemy, reach // active)
        dx, dy = world.player_x - enemy[E_X], world.player_y - enemy[E_Y]
        if form in (FORM_CHARGE, FORM_PROJECTILE):
            in_range = dx * dx + dy * dy <= reach * reach
        else:
            in_range = in_launch_range(reach, dx, dy)
        if enemy[E_STATE] == ST_APPROACH and enemy[E_CD] == 0 and in_range:
            enemy[E_STATE], enemy[E_LEFT], enemy[E_CD] = ST_TELL, tell, config.kinds[kind][4]
            enemy[E_DX], enemy[E_DY] = _aim(world, enemy)
            enemy[E_ATK] = world.next_attack_uid
            world.next_attack_uid += 1


def tick_statuses(config: Config, world: World) -> None:
    """Hero statuses before the death phase (ADR-011 section 4). status.venom: the tick it is
    applied counts as the first of its duration and period; damage = stacks x damage per
    period, in the same tick before the expiry."""
    if world.venom_stacks == 0:
        return
    world.venom_left -= 1
    world.venom_phase -= 1
    if world.venom_phase == 0:
        world.hero_hp -= world.venom_stacks * config.venom_damage
        world.venom_phase = config.venom_period
    if world.venom_left == 0:
        world.venom_stacks = world.venom_phase = 0


def clear_dead(config: Config, world: World) -> None:
    """Phase 8a: per dead enemy in slot order the gem drop, then the freed slot and the kill."""
    for slot, enemy in enumerate(world.enemies):
        if enemy[E_UID] == 0 or enemy[E_HP] > 0:
            continue
        if config.has_xp() and config.kind_xp[enemy[E_KIND]] > 0:
            drop(config, world, enemy[E_X], enemy[E_Y], config.kind_xp[enemy[E_KIND]])
        world.enemies[slot] = [0] * ENEMY_FIELDS
        world.enemy_alive -= 1
        world.kills += 1


XP_OVERFLOW_POLICY_ID = "xp.overflow.nearest_v1"


def drop(config: Config, world: World, x: int, y: int, value: int) -> None:
    """ADR-010 sections 1 and 4: the value is fixed at the drop (x1 gain in P0); a new gem takes
    the lowest free slot; with all max_gems slots taken the value joins the gem nearest to the
    death point (d2, then slot) and gems_merged counts it."""
    world.xp_dropped_total += value
    slot = _lowest_free(world.gems, G_UID)
    if slot < 0 and len(world.gems) >= config.max_gems:
        best, best_d2 = -1, -1
        for index, gem in enumerate(world.gems):
            d2 = _dist2(gem[G_X], gem[G_Y], x, y)
            if best < 0 or d2 < best_d2:
                best, best_d2 = index, d2
        world.gems[best][G_VALUE] += value
        world.gems_merged += 1
        return
    record = [world.next_gem_uid, x, y, value]
    if slot < 0:
        world.gems.append(record)
    else:
        world.gems[slot] = record
    world.next_gem_uid += 1
    world.gems_alive += 1


def collect(world: World, slot: int, uid: int) -> bool:
    """Credits one gem once: a stale or repeated (slot, uid) is rejected without changes."""
    if uid == 0 or not 0 <= slot < len(world.gems) or world.gems[slot][G_UID] != uid:
        return False
    value = world.gems[slot][G_VALUE]
    world.gems[slot] = [0, 0, 0, 0]
    world.gems_alive -= 1
    world.xp_collected_total += value
    world.xp_bank += value
    return True


def pickup(config: Config, world: World) -> None:
    """Phase 9: every gem whose centre is within pickup_radius of the hero centre, slot order."""
    radius = pickup_radius(config, world)
    reach = radius * radius
    for slot, gem in enumerate(world.gems):
        if gem[G_UID] != 0 and _dist2(gem[G_X], gem[G_Y], world.player_x, world.player_y) <= reach:
            collect(world, slot, gem[G_UID])


def progress(config: Config, world: World) -> None:
    """Phase 10: each crossed threshold is paid from the bank and earns one pending choice."""
    while world.xp_bank >= config.xp_cost(world.level):
        world.xp_bank -= config.xp_cost(world.level)
        world.level += 1
        world.pending_level_choices += 1


def clear_expired(world: World) -> None:
    for slot, projectile in enumerate(world.projectiles):
        if projectile[P_DAMAGE] != 0 and projectile[P_TTL] <= 0:
            _free_projectile(world, slot)


def build_hand(config: Config, world: World) -> None:
    """ADR-010 section 6: candidates are the upgrades below their maximum rank in ID order;
    for i in 0..k-1 with k = min(HAND_SIZE, n) the card j = below(n - i) of the `offers`
    stream is removed from the candidates into the hand (remove-at, the rest keep their
    order). With no candidate the hand is RECOVER alone and no word is drawn."""
    candidates = [code for code, (_, top) in enumerate(UPGRADES) if world.ranks[code] < top]
    if not candidates:
        world.hand = [U_RECOVER]
        return
    rng = hip_rng.HipRng(hip_rng.parse_u64(config.seed), OFFERS_STREAM, world.offers_rng_cursor)
    hand = []
    for _ in range(min(HAND_SIZE, len(candidates))):
        hand.append(candidates.pop(rng.below(len(candidates))))
    world.hand = hand
    world.offers_rng_cursor = rng.cursor


def apply_upgrade(world: World, code: int) -> None:
    if code == U_RECOVER:
        world.hero_hp = min(world.hero_hp_max, world.hero_hp + RECOVER_HEAL)
        return
    world.ranks[code] += 1
    if code == U_VITALITY:
        world.hero_hp_max += VITALITY_PER_RANK
        world.hero_hp += VITALITY_PER_RANK


def choose(config: Config, world: World, index: int, revision: int) -> bool:
    """Resolves one earned choice atomically; a CHOOSE outside a pause, with an index outside
    the hand or for another build_revision (stale, repeated) is rejected without changes."""
    if not world.hand or not 0 <= index < len(world.hand) or revision != world.build_revision:
        return False
    apply_upgrade(world, world.hand[index])
    world.pending_level_choices -= 1
    world.choices_done += 1
    world.build_revision += 1
    world.hand = []
    if world.pending_level_choices > 0:
        build_hand(config, world)
    return True


def _apply_command(config: Config, world: World, record) -> bool:
    """Applies one log record; True only for an accepted CHOOSE."""
    _, _, kind, a, b = record
    if kind == MOVE:
        world.move_x, world.move_y = a, b
        return False
    return choose(config, world, a, b)


def step(config: Config, world: World, log: CommandLog) -> None:
    """One simulation step. A paused run (a hand is offered) only reads the log: records with
    tick <= world.tick in sequence order up to and including the first accepted CHOOSE (a MOVE
    only sets the held direction, a rejected CHOOSE is skipped); the tick does not advance and
    nothing else changes. One step resolves at most one choice, live and in replay alike.
    The tick that reaches config.run_ticks is terminal: victory beats defeat (ADR-009 section 4,
    ADR-011 section 1), and neither pickup nor progression runs in it."""
    if world.over():
        return
    records = log.records
    if world.paused():
        accepted = False
        while not accepted and world.command_cursor < len(records) and \
                records[world.command_cursor][0] <= world.tick:
            accepted = _apply_command(config, world, records[world.command_cursor])
            world.command_cursor += 1
        return
    while world.command_cursor < len(records) and records[world.command_cursor][0] <= world.tick:
        _apply_command(config, world, records[world.command_cursor])
        world.command_cursor += 1
    qx, qy = direction_q14(world.move_x, world.move_y)
    r, speed = config.radius, hero_speed(config, world)
    world.player_x = min(max(world.player_x + mul_q14(speed, qx), config.min_x + r),
                         config.max_x - r)
    world.player_y = min(max(world.player_y + mul_q14(speed, qy), config.min_y + r),
                         config.max_y - r)
    if config.has_enemies():
        spawn(config, world)
        chase_and_separate(config, world)
        if config.has_skill():
            cast(config, world)
            fly_and_hit(config, world)
        fly_shots(config, world)
        contact(config, world)
        enemy_attacks(config, world)
        tick_statuses(config, world)
        clear_dead(config, world)
        if config.has_skill():
            clear_expired(world)
    if config.run_ticks > 0 and world.tick + 1 == config.run_ticks:
        world.won = 1
        world.hero_hp = max(world.hero_hp, 0)
        _void_choices(world)
    elif config.has_enemies() and world.hero_hp <= 0:
        world.hero_hp = 0
        world.hero_dead = 1
        _void_choices(world)
    elif config.has_enemies() and config.has_xp():
        pickup(config, world)
        progress(config, world)
        if config.choice_mode == 1 and world.pending_level_choices > 0:
            build_hand(config, world)
    world.tick += 1


def _void_choices(world: World) -> None:
    """A terminal tick cancels the pending choices without drawing offers (ADR-009 section 4)."""
    world.choices_voided += world.pending_level_choices
    world.pending_level_choices = 0


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
# ADR-010 placeholder XP: pickup radius 2 hero radii, 512 gems, yin_corpse 10 / blood_wolf 15,
# incremental level costs (5L^2 + 15L + 20) / 2 for levels 2..21, the last one repeats.
P0_XP_COSTS = [20, 35, 55, 80, 110, 145, 185, 230, 280, 335, 395, 460, 530, 605, 685, 770, 860,
               955, 1055, 1160]
P0_XP = ((48000, 512), (10, 15), P0_XP_COSTS)


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
    ("stress_150_separation", Config(BASE, STRESS_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP),
     _circle(30, 10000), 10000),
    # ADR-010: gems, pickup and levels on the P0 tuning; the hero dies with gems on the ground.
    ("xp_hero_stands_still", Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP), [], 3000),
    ("xp_hero_circles", Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP),
     _circle(40, 3600), 3600),
    # Four gem slots and the smallest legal pickup radius: overflow merges into the nearest gem.
    ("xp_overflow_merge",
     Config(BASE, [TOUGH, 6000, 0, 1000, 64, 200000], W0_KINDS, "123",
            [10000, 600000, 5000, 20000, 12000, 60, 3, 4], ((2400, 4), (10, 15), [7, 9, 11])),
     _circle(25, 6000), 6000),
]

# Scenarios above are written as schema 1 records (tick, sequence, move_x, move_y).
SCENARIOS = [(name, config, migrate_v1(commands), ticks)
             for name, config, commands, ticks in SCENARIOS]


def scripted_choices(config: Config, moves, max_ticks: int, pick, junk: bool = False):
    """Plays schema 1 `moves` (logged when their tick comes and the run is not paused) and
    answers every offered hand with CHOOSE pick(world). With `junk` some answers are preceded
    by an out-of-range index and a future build_revision and followed by a repeat, and a
    CHOOSE is sent outside a pause: all of them must be skipped. Returns (records, steps)."""
    log, world = CommandLog(), World(config)
    queue, sequence, steps = list(moves), 0, 0

    def add(kind: int, a: int, b: int) -> None:
        nonlocal sequence
        assert log.append((world.tick, sequence, kind, a, b), world.tick) == OK
        sequence += 1

    while world.tick < max_ticks and not world.over():
        if world.paused():
            revision, noisy = world.build_revision, junk and world.choices_done % 4 == 1
            if noisy:
                add(CHOOSE, len(world.hand), revision)
                add(CHOOSE, 0, revision + 1)
            add(CHOOSE, pick(world), revision)
            if noisy:
                add(CHOOSE, 0, revision)
        else:
            while queue and queue[0][0] <= world.tick:
                _, _, move_x, move_y = queue.pop(0)
                add(MOVE, move_x, move_y)
            if junk and world.tick == 100:
                add(CHOOSE, 0, world.build_revision)
        step(config, world, log)
        steps += 1
    return log.records, steps


def _first(world: World) -> int:
    return 0


def _cycle(world: World) -> int:
    return world.choices_done % len(world.hand)


def _last(world: World) -> int:
    return len(world.hand) - 1


P0_CHOICE = Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP, choice_mode=1)
TOUGH_CHOICE = Config(BASE, [TOUGH, 30000, 3600, 4000, 64, 384000], W0_KINDS, MAX_SEED,
                      P0_SKILL, P0_XP, choice_mode=1)
# Cheap levels in a dense crowd: several levels per tick, every rank maxed, then RECOVER.
CROWD_CHOICE = Config(BASE, [TOUGH, 6000, 0, 1000, 64, 200000], W0_KINDS, "123", P0_SKILL,
                      ((48000, 512), (10, 15), [5, 40]), choice_mode=1)


def _choice_scenarios():
    out = []
    for name, config, moves, ticks, pick, junk in (
            ("choice_circle_first_card", P0_CHOICE, _circle(40, 3600), 3600, _first, False),
            ("choice_tough_cycle_junk", TOUGH_CHOICE, _circle(25, 18000), 18000, _cycle, True),
            ("choice_crowd_all_ranks", CROWD_CHOICE, _circle(25, 3000), 3000, _last, True)):
        records, steps = scripted_choices(config, moves, ticks, pick, junk)
        out.append((name, config, records, steps))
    return out


CHOICE_SCENARIOS = _choice_scenarios()


def _death_tick(config: Config, moves) -> int:
    world, log = World(config), CommandLog()
    for record in migrate_v1(moves):
        assert log.append(record, 0) == OK
    while not world.over():
        step(config, world, log)
    return world.tick


def _run_end_scenarios():
    """ADR-011 section 1: a won run with choices on the way; a lethal hit in the last tick
    (victory beats defeat); choices still pending at the end are voided."""
    out = []
    with_choices = Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP, choice_mode=1,
                          run_ticks=2400)
    records, steps = scripted_choices(with_choices, _circle(40, 2400), 2400, _first)
    out.append(("run_end_victory_with_choices", with_choices, records, steps))
    standing = Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP)
    last = _death_tick(standing, [])
    lethal = Config(BASE, P0_VALUES, W0_KINDS, SEED, P0_SKILL, P0_XP, run_ticks=last)
    out.append(("run_end_lethal_last_tick", lethal, [], last + 5))
    pending = Config(BASE, [TOUGH, 30000, 3600, 4000, 64, 384000], W0_KINDS, MAX_SEED, P0_SKILL,
                     P0_XP, run_ticks=3000)
    out.append(("run_end_voids_pending", pending, migrate_v1(_circle(25, 3000)), 3010))
    return out


RUN_END_SCENARIOS = _run_end_scenarios()

# ADR-011 sections 2-4 trace inputs (not canon): the MELEE_ARC kinds from the catalog
# multipliers on the same bases as W0_KINDS, H = 2 cells = 96 px.
#   venom_spirit_snake: speed 1.22, radius 0.7, hp 0.65, bite 0.5, cooldown 96
#   fallen_sword_disciple: speed 1.03, radius 1.0, hp 1.05, cleave 0.9, cooldown 120
#   ruined_jade_guardian: speed 0.54, radius 1.28, hp 2.5, stomp 1.18, cooldown 180
DANGER_SU = 96000
ARC_KINDS = [5856, 16800, 6500, 5000, 96, 3,
             4944, 24000, 10500, 9000, 120, 2,
             2592, 30720, 25000, 11800, 180, 1]
# (form, telegraph, active, recovery, reach_su = radius_mult x H, arc_degrees, venom)
CONTACT_ATTACK = [FORM_CONTACT, 0, 0, 0, 0, 0, 0, 0, 0, 0]
SNAKE_BITE = [FORM_ARC, 20, 6, 27, DANGER_SU, 85, 1, 0, 0, 0]
DISCIPLE_CLEAVE = [FORM_ARC, 30, 10, 37, 129600, 125, 0, 0, 0, 0]
JADE_STOMP = [FORM_ARC, 48, 12, 40, 153600, 130, 0, 0, 0, 0]
ARC_ATTACKS = SNAKE_BITE + DISCIPLE_CLEAVE + JADE_STOMP
#   sickle_mantis: speed 1.1, radius 0.78, hp 0.72, lunge 0.95, cooldown 150; L = 4.5 hero radii
MANTIS_KIND = [5280, 18720, 7200, 9500, 150, 2]
MANTIS_LUNGE = [FORM_CHARGE, 33, 10, 36, 108000, 0, 0, 0, 0, 0]
#   cursed_spirit_lantern: speed 0.82, radius 0.7, hp 0.7, wisp 0.64, cooldown 204; launch
#   within 8 cells, keeps 6 cells, shot 0.58 x hero speed, 8 px, 240 ticks
LANTERN_KIND = [3936, 16800, 7000, 6400, 204, 3]
LANTERN_WISP = [FORM_PROJECTILE, 36, 240, 27, 384000, 0, 0, 2784, 8000, 288000]
MIXED_KINDS = W0_KINDS + ARC_KINDS
MIXED_ATTACKS = CONTACT_ATTACK * 2 + ARC_ATTACKS
# status.venom: 3 stacks, 240 ticks, damage every 60 ticks, 1 HP per stack.
P0_VENOM = [3, 240, 60, 1000]


def _attack_scenarios():
    """ADR-011 E2: the arc kinds alone around a standing hero (tell, hits, venom stacks and
    expiry), the mixed w0 + arc crowd against the P0 skill with XP, and a circling hero."""
    out = []
    standing = Config(BASE, [TOUGH, 30000, 0, 1000, 12, 384000], ARC_KINDS, SEED,
                      attacks=ARC_ATTACKS, venom=P0_VENOM)
    out.append(("arcs_hero_stands_still", standing, [], 2400))
    mixed = Config(BASE, P0_VALUES, MIXED_KINDS, SEED, P0_SKILL,
                   ((48000, 512), (10, 15, 15, 15, 20), P0_XP_COSTS), attacks=MIXED_ATTACKS,
                   venom=P0_VENOM)
    out.append(("arcs_mixed_hero_circles", mixed, migrate_v1(_circle(40, 3600)), 3600))
    tough = Config(BASE, [TOUGH, 20000, 0, 1000, 24, 384000], MIXED_KINDS, "7",
                   attacks=MIXED_ATTACKS, venom=P0_VENOM)
    out.append(("arcs_tough_hero_circles", tough, migrate_v1(_circle(25, 3000)), 3000))
    # E3: the mantis alone around a standing hero and in the mixed crowd with the skill.
    mantis = Config(BASE, [TOUGH, 30000, 0, 1000, 8, 384000], MANTIS_KIND, SEED,
                    attacks=MANTIS_LUNGE)
    out.append(("charge_hero_stands_still", mantis, [], 2400))
    crowd = Config(BASE, P0_VALUES, MIXED_KINDS + MANTIS_KIND, "7", P0_SKILL,
                   ((48000, 512), (10, 15, 15, 15, 20, 15), P0_XP_COSTS),
                   attacks=MIXED_ATTACKS + MANTIS_LUNGE, venom=P0_VENOM)
    out.append(("charge_mixed_hero_circles", crowd, migrate_v1(_circle(30, 3600)), 3600))
    # E4: lanterns around a standing hero (shots, pool, keep distance) and a circling one.
    lanterns = Config(BASE, [TOUGH, 20000, 0, 1000, 10, 384000], LANTERN_KIND, SEED,
                      attacks=LANTERN_WISP)
    out.append(("shots_hero_stands_still", lanterns, [], 2400))
    out.append(("shots_hero_circles", lanterns, migrate_v1(_circle(20, 2400)), 2400))
    return out


ATTACK_SCENARIOS = _attack_scenarios()

# Golden sector tests (reach, arc, ux, uy, dx, dy): edges of the radius and of the half arc,
# behind the enemy, the centre, a diagonal direction.
SECTOR_CASES = [
    (96000, 85, 16384, 0, 96000, 0), (96000, 85, 16384, 0, 96001, 0),
    (96000, 85, 16384, 0, 0, 0), (96000, 85, 16384, 0, -1, 0),
    (96000, 85, 16384, 0, 50000, 45800), (96000, 85, 16384, 0, 50000, 45900),
    (96000, 85, 16384, 0, 50000, -45800), (96000, 85, 16384, 0, 50000, -45900),
    (129600, 125, 0, -16384, 60000, -31000), (129600, 125, 0, -16384, 60000, -31500),
    (153600, 130, 11585, 11585, 0, 150000), (153600, 130, 11585, 11585, -20000, 100000),
    (153600, 130, 11585, 11585, -40000, 100000), (153600, 180, 16384, 0, 0, 153600),
    (153600, 180, 16384, 0, -1, 1000), (1, 1, 16384, 0, 1, 0),
]
LAUNCH_CASES = [(96000, 72000, 0), (96000, 72001, 0), (96000, 50912, 50912),
                (96000, 50913, 50913), (4194304, 3145728, 0), (4194304, -1 << 30, 1 << 30)]

# Golden hands (ADR-010 section 6): (name, seed, ranks, offers cursor) -> hand, cursor after.
_MAX_RANKS = [top for _, top in UPGRADES]
HAND_CASES = [
    ("n7_fresh", SEED, [0] * 7, 0),
    ("n7_cursor_5", SEED, [0] * 7, 5),
    ("n7_max_seed", MAX_SEED, [0] * 7, 0),
    ("n7_some_ranks", "7", [2, 1, 0, 1, 1, 4, 1], 3),
    ("n3", SEED, [3, 5, 3, 2, 0, 0, 0], 0),
    ("n2", SEED, [3, 5, 3, 2, 2, 0, 0], 0),
    ("n1", SEED, _MAX_RANKS[:6] + [1], 2),
    ("n0_recover", SEED, _MAX_RANKS, 9),
]
# A chain of four pending choices answered with card 0: every hand is built from the build the
# previous answer produced.
CHAIN_PENDING = 4


def hand_vectors() -> dict:
    cases = []
    for name, seed, ranks, cursor in HAND_CASES:
        config = Config(BASE, P0_VALUES, W0_KINDS, seed, P0_SKILL, P0_XP, choice_mode=1)
        world = World(config)
        world.ranks, world.offers_rng_cursor = list(ranks), cursor
        build_hand(config, world)
        cases.append({"name": name, "seed": seed, "ranks": list(ranks), "cursor": cursor,
                      "hand": [upgrade_id(code) for code in world.hand],
                      "cursor_after": world.offers_rng_cursor})
    world = World(P0_CHOICE)
    world.pending_level_choices = CHAIN_PENDING
    build_hand(P0_CHOICE, world)
    chain = []
    while world.paused():
        chain.append({"hand": [upgrade_id(code) for code in world.hand],
                      "cursor": world.offers_rng_cursor, "revision": world.build_revision})
        assert choose(P0_CHOICE, world, 0, world.build_revision)
    return {"cases": cases, "chain": {"seed": P0_CHOICE.seed, "pending": CHAIN_PENDING,
                                      "steps": chain, "ranks": list(world.ranks),
                                      "cursor": world.offers_rng_cursor}}


APPEND_CASES = [
    ("accepts_first", [], (0, 0, MOVE, 1, 0), 0, OK),
    ("rejects_past_tick", [], (4, 0, MOVE, 1, 0), 5, PAST_TICK),
    ("rejects_bad_axis", [], (0, 0, MOVE, 2, 0), 0, INVALID),
    ("rejects_negative_tick", [], (-1, 0, MOVE, 0, 0), 0, INVALID),
    ("rejects_older_tick", [(10, 0, MOVE, 1, 0)], (9, 1, MOVE, 0, 0), 0, TICK_NOT_MONOTONIC),
    ("rejects_repeated_sequence", [(10, 3, MOVE, 1, 0)], (11, 3, MOVE, 0, 0), 0,
     SEQUENCE_NOT_INCREASING),
    ("accepts_same_tick_next_sequence", [(10, 3, MOVE, 1, 0)], (10, 4, MOVE, 0, 1), 0, OK),
    ("accepts_choose", [(10, 3, MOVE, 1, 0)], (10, 4, CHOOSE, 2, 7), 0, OK),
    ("rejects_negative_choice_index", [], (0, 0, CHOOSE, -1, 0), 0, INVALID),
    ("rejects_negative_revision", [], (0, 0, CHOOSE, 0, -1), 0, INVALID),
    ("rejects_unknown_kind", [], (0, 0, 2, 0, 0), 0, INVALID),
]


def _checkpoints(ticks: int) -> list[int]:
    marks = {1, 2, 30, 60, ticks}
    marks.update(range(300, ticks, 300))
    return sorted(m for m in marks if m <= ticks)


def run_trace(config: Config, commands, steps: int):
    """Replays schema 2 `commands` for `steps` steps (a paused step does not advance the
    tick); checkpoints are taken after given step counts."""
    log, world = CommandLog(), World(config)
    for command in commands:
        assert log.append(command, 0) == OK, command
    marks, checkpoints = set(_checkpoints(steps)), []
    for t in range(1, steps + 1):
        step(config, world, log)
        if t in marks:
            checkpoints.append({
                "step": t, "tick": world.tick, "player_x": str(world.player_x),
                "player_y": str(world.player_y), "hero_hp": str(world.hero_hp),
                "hero_dead": world.hero_dead, "enemy_alive": world.enemy_alive,
                "kills": world.kills, "projectiles": world.live_projectiles(),
                "gems": world.gems_alive, "xp": world.xp_collected_total, "level": world.level,
                "choices": world.choices_done, "paused": int(world.paused()), "won": world.won,
                "attacks": world.next_attack_uid - 1, "venom": world.venom_stacks,
                "shots": world.live_shots(),
                "digest": world.digest()})
    return log, world, checkpoints


def config_json(config: Config) -> dict:
    """The trace fields of a config (sim_core_vectors.json and sim_bot_runs.json)."""
    enemies = skill = xp = None
    if config.has_enemies():
        enemies = {"values": [str(v) for v in config.enemy_values()],
                   "kinds": [str(v) for v in config.raw_kinds], "seed": config.seed}
    if config.has_skill():
        skill = [str(v) for v in config.skill_values()]
    if config.has_xp():
        xp = {"values": [str(v) for v in config.xp_values()],
              "kind_xp": [str(v) for v in config.kind_xp],
              "costs": [str(v) for v in config.xp_costs]}
    attacks = None
    if config.raw_attacks:
        attacks = {"records": [str(v) for v in config.raw_attacks],
                   "venom": [str(v) for v in config.venom]}
    return {"config": [str(v) for v in config.ints()[:8]], "enemies": enemies, "skill": skill,
            "xp": xp, "choice_mode": config.choice_mode, "run_ticks": config.run_ticks,
            "attacks": attacks}


def build_vectors() -> dict:
    traces = []
    for name, config, commands, steps in SCENARIOS + CHOICE_SCENARIOS + RUN_END_SCENARIOS \
            + ATTACK_SCENARIOS:
        assert config.valid(), name
        log, _, checkpoints = run_trace(config, commands, steps)
        traces.append({"name": name, **config_json(config),
                       "commands": [[str(v) for v in c] for c in commands], "ticks": steps,
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
            "log_schema_version": LOG_SCHEMA_VERSION,
            "upgrades": [{"id": uid, "max_rank": top} for uid, top in UPGRADES],
            "recover_id": RECOVER_ID,
            "generator": "tools/content/sim_core.py",
            "note": "movement, enemy and skill constants here are trace inputs, not canonical tuning",
            "traces": traces, "append_cases": appends, "hands": hand_vectors(),
            "cos_q14": list(COS_Q14),
            "sector_cases": [list(c) + [int(in_sector(*c))] for c in SECTOR_CASES],
            "launch_cases": [list(c) + [int(in_launch_range(*c))] for c in LAUNCH_CASES]}


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
