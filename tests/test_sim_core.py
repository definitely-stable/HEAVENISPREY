"""P0-01 simulation core reference: committed traces current, movement and command-log
rules checked against independent expectations."""
import hashlib
import importlib.util
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sim_core", ROOT / "tools/content/sim_core.py")
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)

BASE = sim.BASE


def run(config, commands, ticks):
    if not isinstance(config, sim.Config):
        config = sim.Config(config)
    log, world = sim.CommandLog(), sim.World(config)
    for command in commands:
        assert log.append(command, 0) == sim.OK
    for _ in range(ticks):
        sim.step(config, world, log)
    return world


class SimCoreReferenceTests(unittest.TestCase):
    def test_committed_vectors_are_current(self):
        self.assertEqual(sim.VECTORS_PATH.read_bytes(), sim.vectors_bytes())

    def test_diagonal_constant_is_unit_vector(self):
        self.assertEqual(sim.DIAG_Q14, round(16384 / math.sqrt(2)))
        self.assertEqual(sim.DIAG_Q14, sim.fx.sin_q14(8192))

    def test_idle_hero_does_not_move(self):
        world = run(BASE, [], 300)
        self.assertEqual((world.player_x, world.player_y), (BASE[6], BASE[7]))
        self.assertEqual(world.tick, 300)

    def test_axis_move_is_speed_per_tick(self):
        world = run(BASE, [(0, 0, 1, 0)], 60)
        self.assertEqual(world.player_x - BASE[6], 60 * BASE[0])
        self.assertEqual(world.player_y, BASE[7])

    def test_diagonal_is_not_faster_than_axis(self):
        world = run(BASE, [(0, 0, 1, 1)], 60)
        dx, dy = world.player_x - BASE[6], world.player_y - BASE[7]
        self.assertEqual(dx, dy)
        self.assertLessEqual(dx * dx + dy * dy, (60 * BASE[0]) ** 2)
        self.assertAlmostEqual(math.hypot(dx, dy) / (60 * BASE[0]), 1.0, places=4)

    def test_opposite_directions_are_symmetric(self):
        config = [4801, 1000, -500000, -500000, 500000, 500000, 0, 0]
        plus = run(config, [(0, 0, 1, 1)], 50)
        minus = run(config, [(0, 0, -1, -1)], 50)
        self.assertEqual((plus.player_x, plus.player_y), (-minus.player_x, -minus.player_y))

    def test_hero_stays_inside_arena(self):
        speed, r, min_x, min_y, max_x, max_y = BASE[:6]
        world = run(BASE, [(0, 0, 1, 1)], 2000)
        self.assertEqual((world.player_x, world.player_y), (max_x - r, max_y - r))
        world = run(BASE, [(0, 0, -1, -1)], 2000)
        self.assertEqual((world.player_x, world.player_y), (min_x + r, min_y + r))

    def test_command_applies_on_its_tick(self):
        world = run(BASE, [(10, 0, 1, 0)], 10)
        self.assertEqual(world.player_x, BASE[6])
        world = run(BASE, [(10, 0, 1, 0)], 11)
        self.assertEqual(world.player_x, BASE[6] + BASE[0])

    def test_same_tick_last_command_wins(self):
        world = run(BASE, [(0, 0, 1, 0), (0, 1, 0, -1)], 5)
        self.assertEqual((world.player_x, world.player_y), (BASE[6], BASE[7] - 5 * BASE[0]))
        self.assertEqual(world.command_cursor, 2)

    def test_log_rejections(self):
        log = sim.CommandLog()
        self.assertEqual(log.append((3, 5, 0, 0), 3), sim.OK)
        self.assertEqual(log.append((2, 6, 0, 0), 0), sim.TICK_NOT_MONOTONIC)
        self.assertEqual(log.append((4, 5, 0, 0), 0), sim.SEQUENCE_NOT_INCREASING)
        self.assertEqual(log.append((4, 6, 0, 0), 5), sim.PAST_TICK)
        self.assertEqual(log.append((4, 6, 0, -2), 0), sim.INVALID)
        self.assertEqual(len(log.records), 1)

    def test_digest_is_sha256_of_int64_le(self):
        world = sim.World(sim.Config(BASE))
        raw = b"".join(v.to_bytes(8, "little", signed=True) for v in world.ints())
        self.assertEqual(world.digest(), hashlib.sha256(raw).hexdigest())
        self.assertEqual(sim.CommandLog().digest(), hashlib.sha256(b"").hexdigest())

    def test_invalid_configs(self):
        self.assertTrue(sim.config_valid(BASE))
        self.assertFalse(sim.config_valid([1, 0, 0, 0, 10, 10, 5, 5]))
        self.assertFalse(sim.config_valid([1, 2, 0, 0, 10, 10, 0, 5]))
        self.assertFalse(sim.config_valid([1, 2, 0, 0, 1 << 30, 10, 5, 5]))


ENEMY_CONFIG = sim.Config(BASE, sim.P0_VALUES, sim.W0_KINDS, sim.SEED)
# Same kinds frozen in place and harmless: spawn points stay observable.
STILL_KINDS = [0, 24000, 12800, 0, 36, 8, 0, 21600, 7800, 0, 42, 2]
TOUGH = sim.TOUGH


def every_tick(max_alive, min_distance=0, hero_hp=TOUGH):
    """One spawn per tick from tick 0 (period == rate)."""
    return [hero_hp, 1000, 0, 1000, max_alive, min_distance]


class SimEnemyReferenceTests(unittest.TestCase):
    def test_spawn_ticks_follow_the_rate_ramp(self):
        log, world, ticks = sim.CommandLog(), sim.World(ENEMY_CONFIG), []
        while len(ticks) < 3:
            uid = world.next_enemy_uid
            sim.step(ENEMY_CONFIG, world, log)
            if world.next_enemy_uid > uid:
                ticks.append(world.tick - 1)
        self.assertEqual(ticks, [89, 178, 266])

    def test_rate_ramp_is_capped(self):
        self.assertEqual(ENEMY_CONFIG.spawn_rate(0), 1000)
        self.assertEqual(ENEMY_CONFIG.spawn_rate(10800), 2000)
        self.assertEqual(ENEMY_CONFIG.spawn_rate(10799), 1999)
        self.assertEqual(ENEMY_CONFIG.spawn_rate(10 ** 6), 2000)

    def test_spawns_respect_min_distance_and_arena(self):
        config = sim.Config(BASE, [TOUGH, 5000, 0, 1000, 200, 384000], STILL_KINDS, "3")
        log, world = sim.CommandLog(), sim.World(config)
        for _ in range(1000):
            hero = (world.player_x, world.player_y)
            uid = world.next_enemy_uid
            sim.step(config, world, log)
            if world.next_enemy_uid > uid:
                _, kind, x, y = world.enemies[-1][:4]
                r = config.kinds[kind][1]
                self.assertGreaterEqual((x - hero[0]) ** 2 + (y - hero[1]) ** 2, 384000 ** 2)
                self.assertTrue(r <= x <= BASE[4] - r and r <= y <= BASE[5] - r)
        self.assertEqual(world.enemy_alive, 200, "spawns at ticks 4, 9, ..., 999")

    def test_spawn_weights_follow_roster(self):
        config = sim.Config(BASE, every_tick(1000), STILL_KINDS, "11")
        world = run(config, [], 1001)
        wolves = sum(1 for enemy in world.enemies if enemy[sim.E_KIND] == 1)
        self.assertEqual(world.enemy_alive, 1000)
        self.assertAlmostEqual(wolves / 1000, 0.2, delta=0.05)

    def test_corner_fallback_when_no_point_is_far_enough(self):
        config = sim.Config([4800, 24000, 0, 0, 300000, 300000, 150000, 150000],
                            every_tick(4, 1000000), STILL_KINDS, "99")
        world = run(config, [], 3)
        self.assertEqual(world.enemy_alive, 3)
        for _, kind, x, y, _, _ in world.enemies:
            r = config.kinds[kind][1]
            self.assertIn((x, y), [(r, r), (300000 - r, r), (300000 - r, 300000 - r), (r, 300000 - r)])

    def test_cap_holds_the_accumulator_without_extra_charge(self):
        config = sim.Config(BASE, [TOUGH, 90000, 0, 1000, 1, 384000], STILL_KINDS, "4")
        world = run(config, [], 500)
        self.assertEqual(world.enemy_alive, 1)
        self.assertEqual(world.spawn_acc, 89000, "the blocked tick does not advance")
        world.enemies[0][sim.E_HP] = 0
        sim.clear_dead(world)
        log, uid = sim.CommandLog(), world.next_enemy_uid
        sim.step(config, world, log)
        self.assertEqual(world.next_enemy_uid, uid + 1, "spawns on the first free tick")
        self.assertEqual(world.spawn_acc, 0)

    def test_enemies_close_in_and_hit_on_interval(self):
        config = sim.Config(BASE, every_tick(1, 0, 100000), [6000, 24000, 1000, 1000, 30, 1], "1")
        log, world = sim.CommandLog(), sim.World(config)
        hits = []
        for _ in range(2000):
            before = world.hero_hp
            sim.step(config, world, log)
            if world.hero_hp < before:
                hits.append(world.tick)
        self.assertGreaterEqual(len(hits), 3)
        self.assertEqual({b - a for a, b in zip(hits, hits[1:])}, {30})

    def test_death_freezes_state(self):
        config = sim.Config(BASE, every_tick(2, 0, 1000), [8000, 24000, 1000, 600, 5, 1], "2")
        log, world = sim.CommandLog(), sim.World(config)
        while not world.hero_dead:
            sim.step(config, world, log)
        self.assertEqual(world.hero_hp, 0)
        frozen = world.ints()
        for _ in range(50):
            sim.step(config, world, log)
        self.assertEqual(world.ints(), frozen)

    def test_enemy_digest_covers_rng_cursor(self):
        world = run(ENEMY_CONFIG, [], 200)
        self.assertGreater(world.rng_cursor, 0)
        self.assertEqual(world.ints()[9], world.rng_cursor)

    def test_invalid_enemy_configs(self):
        self.assertTrue(ENEMY_CONFIG.valid())
        values = sim.P0_VALUES
        bad = [sim.Config(BASE, values, sim.W0_KINDS, "-1"),
               sim.Config(BASE, [0] + values[1:], sim.W0_KINDS, "1"),
               sim.Config(BASE, values, [3264, 24000, 12800, 6500, 36, 0], "1"),
               sim.Config(BASE, values[:4] + [0, 0], sim.W0_KINDS, "1"),
               sim.Config(BASE, values[:3] + [999] + values[4:], sim.W0_KINDS, "1"),
               sim.Config(BASE, values, [3264, 480000, 12800, 6500, 36, 1], "1"),
               sim.Config(BASE, values, sim.W0_KINDS[:9], "1")]
        for config in bad:
            self.assertFalse(config.valid(), config.ints())


# Frozen, harmless targets with plenty of HP; kind 1 is a small one.
TARGET_KINDS = [0, 24000, 1000000, 0, 36, 1, 0, 21600, 1000000, 0, 42, 1]
NO_SPAWN = [TOUGH, 1 << 29, 0, 1000, 64, 0]
CX, CY = BASE[6], BASE[7]


def arena(enemies, skill=sim.P0_SKILL, kinds=TARGET_KINDS, hero_hp=TOUGH):
    """Config without spawns (first spawn after ~536870 ticks) and a world holding `enemies`
    = [(kind, x, y, hp), ...] in slots 0.. with uids 1.."""
    config = sim.Config(BASE, [hero_hp] + NO_SPAWN[1:], kinds, "1", skill)
    assert config.valid()
    world = sim.World(config)
    for kind, x, y, hp in enemies:
        place(world, kind, x, y, hp)
    return config, world


def place(world, kind, x, y, hp, slot=None):
    record = [world.next_enemy_uid, kind, x, y, hp, 0]
    if slot is None:
        world.enemies.append(record)
    else:
        world.enemies[slot] = record
    world.next_enemy_uid += 1
    world.enemy_alive += 1


def cast_ticks(config, world, ticks, log=None):
    """Ticks in which a projectile was fired (a fresh one has flown exactly once)."""
    log, out = log or sim.CommandLog(), []
    for _ in range(ticks):
        acc = world.skill_acc
        sim.step(config, world, log)
        if world.skill_acc < acc:
            out.append(world.tick - 1)
    return out


class SimCombatReferenceTests(unittest.TestCase):
    def test_casts_every_period_while_a_target_is_in_range(self):
        config, world = arena([(0, CX + 200000, CY, 1000000)])
        self.assertEqual(cast_ticks(config, world, 160), [49, 99, 149])

    def test_no_target_holds_then_casts_at_once_and_one_period_later(self):
        config, world = arena([])
        self.assertEqual(cast_ticks(config, world, 200), [])
        self.assertEqual(world.skill_acc, 49000)
        place(world, 0, CX + 200000, CY, 1000000)
        self.assertEqual(cast_ticks(config, world, 60), [200, 250])

    def test_target_is_nearest_then_lowest_slot(self):
        config, world = arena([(0, CX + 300000, CY, 1000000), (0, CX - 200000, CY, 1000000),
                               (0, CX + 200000, CY, 1000000)])
        self.assertEqual(sim.nearest_in_range(config, world), 1, "equal distance: lower slot")
        world.enemies[1] = [0] * 6
        world.enemy_alive -= 1
        self.assertEqual(sim.nearest_in_range(config, world), 2)
        place(world, 0, CX, CY - 200000, 1000000, slot=1)
        self.assertEqual(sim.nearest_in_range(config, world), 1, "reused slot keeps slot order")

    def test_range_is_inclusive(self):
        config, world = arena([(0, CX + 384000, CY, 1000000)])
        self.assertEqual(sim.nearest_in_range(config, world), 0)
        world.enemies[0][sim.E_X] += 1
        self.assertEqual(sim.nearest_in_range(config, world), -1)

    def test_pierce_one_hits_two_in_a_line_once_each(self):
        line = [(0, CX + d, CY, 1000000) for d in (100000, 160000, 220000)]
        config, world = arena(line)
        log = sim.CommandLog()
        cast_ticks(config, world, 50, log)
        self.assertEqual(world.live_projectiles(), 1)
        for _ in range(30):
            sim.step(config, world, log)
            if world.enemies[1][sim.E_HP] < 1000000:
                break
        self.assertEqual([e[sim.E_HP] for e in world.enemies], [990000, 990000, 1000000])
        self.assertEqual(world.live_projectiles(), 0, "slot freed on the second hit")
        self.assertEqual(len(world.projectiles), 1)

    def test_two_projectiles_one_kill_second_keeps_its_pierce(self):
        config, world = arena([(0, CX + 200000, CY, 7800)])
        for slot in range(2):
            world.projectiles.append([CX + 180000, CY, 12000, 0, 40, 1, 10000] + [0, 0])
        sim.fly_and_hit(config, world)
        self.assertEqual(world.enemies[0][sim.E_HP], 0)
        self.assertEqual(world.projectiles[1][sim.P_PIERCE], 1, "dead enemy is not hit again")
        self.assertEqual(world.projectiles[0][sim.P_PIERCE], 0)
        sim.clear_dead(world)
        self.assertEqual((world.kills, world.enemy_alive), (1, 0))
        self.assertEqual(world.enemies[0], [0] * 6)

    def test_projectile_kill_prevents_same_tick_contact(self):
        kinds = [0, 24000, 5000, 9000, 1, 1]
        config, world = arena([(0, CX + 40000, CY, 5000)], kinds=kinds, hero_hp=100000)
        world.skill_acc = 49000
        sim.step(config, world, sim.CommandLog())
        self.assertEqual(world.kills, 1)
        self.assertEqual(world.hero_hp, 100000, "an enemy at 0 HP does not hit")

    def test_hero_death_tick_still_counts_the_kill_and_freezes(self):
        kinds = [0, 24000, 5000, 1000, 1, 1, 0, 24000, 999999, 50000, 1, 1]
        config, world = arena([(0, CX + 200000, CY, 5000), (1, CX, CY + 40000, 999999)],
                              kinds=kinds, hero_hp=50000)
        world.projectiles.append([CX + 190000, CY, 12000, 0, 40, 1, 10000, 0, 0])
        sim.step(config, world, sim.CommandLog())
        self.assertEqual((world.hero_dead, world.hero_hp, world.kills), (1, 0, 1))
        frozen = world.ints()
        sim.step(config, world, sim.CommandLog())
        self.assertEqual(world.ints(), frozen)

    def test_reused_slot_is_a_new_target_for_the_ledger(self):
        config, world = arena([(0, CX + 200000, CY, 5000)])
        world.projectiles.append([CX + 200000, CY, 0, 0, 40, 1, 10000, 0, 0])
        world.projectiles[0][sim.P_LEDGER] = 1
        world.enemies[0] = [0] * 6
        world.enemy_alive = 0
        place(world, 0, CX + 200000, CY, 5000, slot=0)
        self.assertEqual(world.enemies[0][sim.E_UID], 2)
        sim.fly_and_hit(config, world)
        self.assertEqual(world.enemies[0][sim.E_HP], 0, "uid 2 is not in the ledger of uid 1")

    def test_projectile_leaving_the_arena_is_removed_without_hits(self):
        config, world = arena([(0, BASE[4] - 24000, CY, 1000000)])
        world.projectiles.append([BASE[4] - 5000, CY, 12000, 0, 40, 1, 10000, 0, 0])
        sim.fly_and_hit(config, world)
        self.assertEqual(world.live_projectiles(), 0)
        self.assertEqual(world.enemies[0][sim.E_HP], 1000000)

    def test_projectile_expires_after_its_lifetime(self):
        config, world = arena([(0, CX + 200000, CY, 1000000)])
        world.projectiles.append([CX, CY, 0, 1, 2, 1, 10000, 0, 0])
        world.skill_acc = -10 ** 6
        log = sim.CommandLog()
        sim.step(config, world, log)
        self.assertEqual(world.live_projectiles(), 1)
        sim.step(config, world, log)
        self.assertEqual(world.live_projectiles(), 0)
        self.assertEqual(world.projectiles[0], [0] * 9)

    def test_full_projectile_slots_hold_the_cast(self):
        # One slot; the projectile flies until it leaves the arena in the fly phase of tick
        # 113 (after that tick's cast phase), so the second cast waits until tick 114.
        skill = [50000, 384000, 10000, 12000, 10000, 80, 1, 1]
        config, world = arena([(0, CX + 300000, CY, 1000000)], skill=skill)
        log = sim.CommandLog()
        self.assertEqual(cast_ticks(config, world, 100, log), [49])
        self.assertEqual(world.skill_acc, 49000, "held, not advanced")
        self.assertEqual(cast_ticks(config, world, 50, log), [114])
        self.assertEqual(len(world.projectiles), 1)

    def test_zero_direction_fires_along_x(self):
        config, world = arena([(0, CX, CY, 1000000)])
        world.skill_acc = 49000
        sim.step(config, world, sim.CommandLog())
        self.assertEqual(world.projectiles[0][sim.P_VX:sim.P_VY + 1], [12000, 0])

    def test_invalid_skill_configs(self):
        good = sim.Config(BASE, sim.P0_VALUES, sim.W0_KINDS, "1", sim.P0_SKILL)
        self.assertTrue(good.valid())
        self.assertFalse(sim.Config(BASE, skill=sim.P0_SKILL).valid(), "skill needs enemies")
        for index, value in [(0, 0), (3, 0), (3, 31601), (4, 0), (5, 0), (6, 8), (6, -1),
                             (7, 0), (7, 257), (1, -1)]:
            skill = list(sim.P0_SKILL)
            skill[index] = value
            config = sim.Config(BASE, sim.P0_VALUES, sim.W0_KINDS, "1", skill)
            self.assertFalse(config.valid(), (index, value))

    def test_long_run_kills_and_stays_consistent(self):
        config = sim.SCENARIOS[-1][1]
        log, world = sim.CommandLog(), sim.World(config)
        for command in sim._circle(25, 3000):
            log.append(command, 0)
        for _ in range(3000):
            sim.step(config, world, log)
            live = sum(1 for e in world.enemies if e[sim.E_UID] != 0)
            self.assertEqual(live, world.enemy_alive)
            self.assertTrue(all(e[sim.E_HP] > 0 for e in world.enemies if e[sim.E_UID]))
            self.assertLessEqual(world.skill_acc, config.skill_period)
        self.assertGreater(world.kills, 50)
        self.assertEqual(world.next_enemy_uid - 1, world.kills + world.enemy_alive)


# Separation (ADR-009 section 2): two kinds that move, radius 24000 and 21600 (cell 48000).
MOVING_KINDS = [3264, 24000, 1000000, 0, 36, 1, 6144, 21600, 1000000, 0, 42, 1]


def brute_push(config, world):
    """Independent all-pairs reference of one complete separation pass."""
    n = len(world.enemies)
    push_x, push_y = [0] * n, [0] * n
    live = [slot for slot, e in enumerate(world.enemies) if e[sim.E_UID]]
    for a, i in enumerate(live):
        for j in live[a + 1:]:
            ei, ej = world.enemies[i], world.enemies[j]
            reach = config.kinds[ei[sim.E_KIND]][1] + config.kinds[ej[sim.E_KIND]][1]
            dx, dy = ei[sim.E_X] - ej[sim.E_X], ei[sim.E_Y] - ej[sim.E_Y]
            d2 = dx * dx + dy * dy
            if d2 >= reach * reach:
                continue
            if d2 == 0:
                push_x[j] += reach // 2  # j > i: the larger slot goes towards +x
                push_x[i] -= reach // 2
                continue
            d = math.isqrt(d2)
            half = (reach - d) // 2
            hx = int(math.copysign(abs(dx) * half // d, dx))
            hy = int(math.copysign(abs(dy) * half // d, dy))
            push_x[i], push_y[i] = push_x[i] + hx, push_y[i] + hy
            push_x[j], push_y[j] = push_x[j] - hx, push_y[j] - hy
    return push_x, push_y


def crowd(count=80, spread=400000, seed=7):
    """Enemies scattered around the arena centre (overlaps across cell borders), one
    coincident pair, kinds alternating."""
    rnd = random.Random(seed)
    enemies = [(k % 2, CX + rnd.randrange(-spread, spread), CY + rnd.randrange(-spread, spread),
                1000000) for k in range(count)]
    enemies.append((0, enemies[0][1], enemies[0][2], 1000000))
    return arena(enemies, skill=(0,) * 8, kinds=MOVING_KINDS)


def one_pass(config, world):
    n = len(world.enemies)
    push_x, push_y = [0] * n, [0] * n
    sim.separate(config, world, push_x, push_y)
    return push_x, push_y


class SimSeparationReferenceTests(unittest.TestCase):
    def test_half_overlap_push(self):
        config, world = arena([(0, CX, CY, 1), (0, CX + 30000, CY, 1)], skill=(0,) * 8,
                              kinds=MOVING_KINDS)
        # reach 48000, distance 30000: each goes half of the 18000 overlap.
        self.assertEqual(one_pass(config, world), ([-9000, 9000], [0, 0]))

    def test_touching_pair_is_not_pushed(self):
        config, world = arena([(0, CX, CY, 1), (1, CX, CY + 45600, 1)], skill=(0,) * 8,
                              kinds=MOVING_KINDS)
        self.assertEqual(one_pass(config, world), ([0, 0], [0, 0]))

    def test_coincident_centres_push_the_larger_slot_towards_plus_x(self):
        config, world = arena([(0, CX, CY, 1), (0, CX + 900000, CY, 1), (1, CX, CY, 1)],
                              skill=(0,) * 8, kinds=MOVING_KINDS)
        # reach 45600: slot 2 (larger) +22800, slot 0 -22800; slot 1 is far away.
        self.assertEqual(one_pass(config, world), ([-22800, 0, 22800], [0, 0, 0]))

    def test_every_pair_once_matches_all_pairs_reference(self):
        for seed in (7, 8, 9):
            config, world = crowd(seed=seed)
            self.assertEqual(one_pass(config, world), brute_push(config, world), seed)
            self.assertEqual(world.sep_cursor, 0)

    def test_budget_splits_the_pass_and_resumes_at_the_cursor(self):
        config, world = crowd()
        expected = brute_push(config, world)
        original = sim.SEP_MAX_CHECKS
        self.addCleanup(setattr, sim, "SEP_MAX_CHECKS", original)
        sim.SEP_MAX_CHECKS = 40
        total_x, total_y = [0] * len(world.enemies), [0] * len(world.enemies)
        cursors = []
        while True:
            push_x, push_y = one_pass(config, world)
            total_x = [a + b for a, b in zip(total_x, push_x)]
            total_y = [a + b for a, b in zip(total_y, push_y)]
            cursors.append(world.sep_cursor)
            if world.sep_cursor == 0:
                break
            self.assertLess(len(cursors), 1000)
        self.assertGreater(len(cursors), 2, "the budget must split the pass")
        self.assertEqual(cursors[:-1], sorted(cursors[:-1]), "the cursor only moves forward")
        self.assertEqual((total_x, total_y), expected, "split passes add up to one full pass")

    def test_move_never_exceeds_the_kind_speed(self):
        config, world = crowd()
        before = [(e[sim.E_X], e[sim.E_Y]) for e in world.enemies]
        sim.chase_and_separate(config, world)
        capped = 0
        for (x, y), e in zip(before, world.enemies):
            speed = config.kinds[e[sim.E_KIND]][0]
            dx, dy = e[sim.E_X] - x, e[sim.E_Y] - y
            self.assertLessEqual(dx * dx + dy * dy, speed * speed)
            capped += dx * dx + dy * dy > (speed - 2) * (speed - 2)
        self.assertGreater(capped, 0)

    def test_touching_enemy_stays_unless_pushed(self):
        config, world = arena([(0, CX + 48000, CY, 1)], skill=(0,) * 8, kinds=MOVING_KINDS)
        sim.chase_and_separate(config, world)
        self.assertEqual(world.enemies[0][sim.E_X:sim.E_Y + 1], [CX + 48000, CY])
        place(world, 0, CX + 58000, CY, 1)
        sim.chase_and_separate(config, world)
        # Push -19000 along x, capped at the speed 3264; no chase towards the hero.
        self.assertEqual(world.enemies[0][sim.E_X:sim.E_Y + 1], [CX + 48000 - 3264, CY])

    def test_fast_helpers_equal_fx(self):
        fx, rnd = sim.fx, random.Random(5)
        edges = [0, 1, -1, 2, (1 << 15) - 1, 1 << 15, (1 << 15) + 1, (1 << 30) - 1, 1 << 30,
                 (1 << 30) + 1, fx.NORM_MAX, fx.NORM_MAX + 1, fx.NORM_UPSCALE_BELOW - 1,
                 fx.NORM_UPSCALE_BELOW, 1 << 40, (1 << 62) - 1]
        values = edges + [-v for v in edges] + [rnd.randrange(-(1 << 44), 1 << 44)
                                                for _ in range(300)]
        for a in values:
            for q in values[:40]:
                self.assertEqual(sim.mul_q14(a, q), fx.mul_q14(a, q), (a, q))
                self.assertEqual(sim.normalize_q14(a, q), fx.normalize_q14(a, q), (a, q))
        for n in [abs(v) for v in values] + [fx.PRODUCT_LIMIT, fx.PRODUCT_LIMIT + 1]:
            self.assertEqual(sim.isqrt(n), fx.isqrt(n), n)


if __name__ == "__main__":
    unittest.main()
