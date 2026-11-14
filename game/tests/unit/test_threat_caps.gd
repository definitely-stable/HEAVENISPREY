extends GutTest
## ADR-011 section 5 (E6): the GDScript roster windows and threat_caps against the oracle
## rules: the window of a tick, a capped kind giving way to the next allowed one with no extra
## RNG word, a skipped spawn, the shot-tell cap, the control-zone budget near the hero and the
## config checks. The numbers equal tools/content/sim_core.py (SimThreatCapsReferenceTests).

const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const TOUGH: int = 500000000
const NO_SPAWN: Array[int] = [TOUGH, 536870912, 0, 1000, 64, 0]
## One spawn per tick from tick 0 (period == rate).
const EVERY_TICK: Array[int] = [TOUGH, 1000, 0, 1000, 64, 0]
## yin_corpse (contact) and cursed_spirit_lantern (PROJECTILE).
const YIN_LANTERN: Array[int] = [3264, 24000, 12800, 6500, 36, 8, 3936, 16800, 7000, 6400, 204, 3]
const YIN_LANTERN_ATTACKS: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	3, 36, 240, 27, 384000, 0, 0, 2784, 8000, 288000,
]
const LANTERN_KIND: Array[int] = [3936, 16800, 7000, 6400, 204, 3]
const LANTERN_WISP: Array[int] = [3, 36, 240, 27, 384000, 0, 0, 2784, 8000, 288000]
const ROOT_KIND: Array[int] = [3072, 25200, 11000, 0, 360, 1]
const ROOT_GROWTH: Array[int] = [5, 57, 165, 45, 384000, 0, 0, 0, 153600, 0]
const P0_ROOT: Array[int] = [90, 720]
const P0_CAPS: Array[int] = [2, 2, 2, 3, 3, 384000]
const CX: int = 768000
const CY: int = 480000


static func _config(
	values: Array[int], kinds: Array[int], attacks: Array[int], windows: Array[int], caps: Array[int]
) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(values), PackedInt64Array(kinds), "7"
	).with_attacks(
		PackedInt64Array(attacks), PackedInt64Array([0, 0, 0, 0]), PackedInt64Array(P0_ROOT)
	).with_windows(PackedInt64Array(windows), PackedInt64Array(caps))


static func _place(world: WorldState, x: int, y: int) -> void:
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_x[slot] = x
	world.enemy_y[slot] = y
	world.enemy_hp[slot] = 1000000
	world.next_enemy_uid += 1
	world.enemy_alive += 1


static func _live_kinds(world: WorldState) -> Array:
	var kinds: Array = []
	for slot: int in world.enemy_slots():
		if world.is_enemy_live(slot):
			kinds.append(world.enemy_kind[slot])
	return kinds


static func _spawned(config: SimConfig, ticks: int) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	SimKernel.run(config, world, CommandLog.new(), ticks)
	return world


func test_window_of_a_tick() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), "1")
	assert_not_null(config)
	var starts: Array = []
	for tick: int in [0, 5099, 5100, 10499, 10500, 17999, 18000, 90000]:
		starts.append(config.windows[ThreatCaps.window_at(config, tick)])
	assert_eq(starts, [0, 0, 5100, 5100, 10500, 15000, 15000, 15000])
	assert_eq(ThreatCaps.spawn_weights(config, 5100), PackedInt64Array([5, 3, 2, 2, 0, 0, 0, 0, 0, 0]))
	var plain: SimConfig = _config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, [], [])
	assert_eq(ThreatCaps.spawn_weights(plain, 0), PackedInt64Array([8, 3]), "the kind weights")


func test_weights_follow_the_window() -> void:
	var config: SimConfig = _config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, [0, 30, 0, 1, 0, 30, 90, 0, 0, 1], [])
	var kinds: Array = []
	for index: int in 30:
		kinds.append(0)
	for index: int in 30:
		kinds.append(1)
	assert_eq(_live_kinds(_spawned(config, 60)), kinds)


func test_capped_kind_gives_way_to_the_next_allowed_one() -> void:
	var windows: Array[int] = [0, 1000, 0, 1, 1]
	var world: WorldState = _spawned(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, windows, P0_CAPS), 40)
	var loose: WorldState = _spawned(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, windows, []), 40)
	assert_eq(_live_kinds(world).count(1), 3, "ordinary_ranged_on_screen")
	assert_gt(_live_kinds(loose).count(1), 3)
	assert_eq(world.enemy_alive, 40, "a capped lantern becomes a yin corpse")
	assert_eq(world.enemy_rng_cursor, loose.enemy_rng_cursor, "no extra RNG word")


func test_spawn_is_skipped_while_every_kind_is_capped() -> void:
	var caps: Array[int] = [2, 2, 2, 3, 2, 384000]
	var every_third: Array[int] = [TOUGH, 3000, 0, 1000, 64, 0]
	var config: SimConfig = _config(every_third, YIN_LANTERN, YIN_LANTERN_ATTACKS, [0, 1000, 0, 0, 1], caps)
	var world: WorldState = _spawned(config, 9)
	assert_eq(world.enemy_alive, 2, "spawns in ticks 2 and 5, skipped in tick 8")
	assert_eq(world.spawn_acc, 2000)
	for tick: int in 5:
		var cursor: int = world.enemy_rng_cursor
		SimKernel.run(config, world, CommandLog.new(), 1)
		assert_eq([world.enemy_alive, world.spawn_acc], [2, 2000], "the accumulator stays at period - rate")
		assert_gt(world.enemy_rng_cursor, cursor, "each skipped spawn spends its roll")


func test_shot_tells_are_capped() -> void:
	var config: SimConfig = _config(NO_SPAWN, LANTERN_KIND, LANTERN_WISP, [], [1, 2, 2, 3, 3, 384000])
	assert_true(config.is_valid())
	var world: WorldState = WorldState.initial(config)
	for index: int in 2:
		_place(world, CX + 384000 + LANTERN_KIND[0], CY)
	SimKernel.run(config, world, CommandLog.new(), 1)
	assert_eq(world.next_attack_uid - 1, 1, "the second lantern waits")
	SimKernel.run(config, world, CommandLog.new(), 36)
	assert_eq(world.next_attack_uid - 1, 2, "it winds up once the first one has released")


## The hero offset from the first root zone (at CX) when the second one is cast, or -1 within
## 200 ticks; the hero walks +x past the casters from tick 1.
static func _second_launch(near: int) -> int:
	var config: SimConfig = _config(NO_SPAWN, ROOT_KIND, ROOT_GROWTH, [0, 1000, near, 1], P0_CAPS)
	var world: WorldState = WorldState.initial(config)
	for index: int in 2:
		_place(world, CX + 384000 + ROOT_KIND[0], CY)
	var commands: CommandLog = CommandLog.new()
	commands.append(PlayerCommand.create(1, 0, 1, 0), 0)
	for tick: int in 200:
		SimKernel.step(config, world, commands)
		if world.next_attack_uid - 1 == 2:
			return world.player_x - CX
	return -1


func test_control_zones_near_the_hero_follow_the_window() -> void:
	assert_eq(_second_launch(0), -1, "no root zone with a budget of 0")
	assert_eq(_second_launch(1), 388800, "the first tick past 8 cells (384 px)")
	assert_eq(_second_launch(2), 4800, "a budget of 2 lets the second one cast")


func test_windows_and_caps_are_validated() -> void:
	var windows: Array[int] = [0, 600, 0, 1, 1, 600, 1200, 1, 0, 1]
	assert_true(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, windows, P0_CAPS).is_valid())
	assert_false(_config(EVERY_TICK, YIN_LANTERN, [], [], P0_CAPS).is_valid(), "caps need attacks")
	for index: int in 6:
		var caps: Array[int] = P0_CAPS.duplicate()
		caps[index] = 0
		assert_false(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, [], caps).is_valid(), str(index))
	assert_false(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, [], P0_CAPS.slice(0, 5)).is_valid())
	for change: Array in [[0, 1], [1, 0], [2, -1], [3, -1], [5, 500], [6, 600]]:
		var bad: Array[int] = windows.duplicate()
		bad[change[0]] = change[1]
		assert_false(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, bad, []).is_valid(), str(change))
	assert_false(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, windows.slice(0, 9), []).is_valid())
	assert_false(_config(EVERY_TICK, YIN_LANTERN, YIN_LANTERN_ATTACKS, [0, 600, 0, 0, 0], []).is_valid())
