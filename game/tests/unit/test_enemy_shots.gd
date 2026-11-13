extends GutTest
## ADR-011 section 3 (E4): the GDScript enemy shots against the oracle rules: the launch
## range, the release at the end of tell, no homing, the lifetime, the pool limit, shots
## outliving their lantern, the keep distance, the lane telegraph and the content numbers.
## The numbers equal tools/content/sim_core.py (LANTERN_KIND, LANTERN_WISP).

const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const TOUGH: int = 500000000
const NO_SPAWN: Array[int] = [TOUGH, 536870912, 0, 1000, 64, 0]
const LANTERN_KIND: Array[int] = [3936, 16800, 7000, 6400, 204, 3]
const LANTERN_WISP: Array[int] = [3, 36, 240, 27, 384000, 0, 0, 2784, 8000, 288000]


static func _lantern(record: Array[int] = LANTERN_WISP) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(NO_SPAWN), PackedInt64Array(LANTERN_KIND), "1"
	).with_attacks(PackedInt64Array(record), PackedInt64Array([0, 0, 0, 0]))


## The lantern on the hero's +x side: its first chase step ends at the launch range (+ extra).
static func _lantern_world(config: SimConfig, extra: int = 0) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_x[slot] = world.player_x + 384000 + LANTERN_KIND[0] + extra
	world.enemy_y[slot] = world.player_y
	world.enemy_hp[slot] = 1000000
	world.next_enemy_uid += 1
	world.enemy_alive += 1
	return world


static func _shot(world: WorldState, slot: int) -> Array[int]:
	return [
		world.shot_x[slot], world.shot_y[slot], world.shot_vx[slot], world.shot_vy[slot],
		world.shot_ttl[slot], world.shot_damage[slot], world.shot_radius[slot],
	]


## Steps `ticks` ticks; the hero stands still.
static func _run(config: SimConfig, world: WorldState, ticks: int) -> void:
	SimKernel.run(config, world, CommandLog.new(), ticks)


static func _run_dir(config: SimConfig, world: WorldState, from_tick: int, move: Vector2i, ticks: int) -> void:
	var commands: CommandLog = CommandLog.new()
	commands.append(PlayerCommand.create(from_tick, 0, move.x, move.y), 0)
	SimKernel.run(config, world, commands, ticks)

func test_projectile_config_is_valid_and_checked() -> void:
	assert_true(_lantern().is_valid())
	for change: Array in [[5, 1], [6, 1], [7, 0], [7, 32001], [8, 0], [9, -1], [9, 384001]]:
		var record: Array[int] = LANTERN_WISP.duplicate()
		record[change[0]] = change[1]
		assert_false(_lantern(record).is_valid(), str(change))
	var lunge: Array[int] = [2, 33, 10, 36, 108000, 0, 0, 0, 0, 1]
	var mantis: SimConfig = SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(NO_SPAWN), PackedInt64Array([5280, 18720, 7200, 9500, 150, 2]), "1"
	)
	var charge: SimConfig = mantis.with_attacks(PackedInt64Array(lunge), PackedInt64Array([0, 0, 0, 0]))
	assert_false(charge.is_valid(), "keep on a charge")


func test_lantern_releases_one_shot_at_the_end_of_tell() -> void:
	var config: SimConfig = _lantern()
	var far: WorldState = _lantern_world(config, 1)
	_run(config, far, 1)
	assert_eq(far.enemy_state[0], EnemyAttackSystem.ST_APPROACH, "1 su too far")
	var world: WorldState = _lantern_world(config)
	_run(config, world, 36)
	assert_eq(world.shot_slots(), 0, "nothing during tell")
	_run(config, world, 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_ACTIVE)
	var start: int = world.player_x + 384000
	assert_eq(_shot(world, 0), [start, world.player_y, -2784, 0, 240, 6400, 8000])
	_run(config, world, 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_RECOVER, "active is one tick")
	_run(config, world, 125)
	assert_eq(world.hero_hp, TOUGH, "not yet")
	_run(config, world, 1)
	assert_eq(world.hero_hp, TOUGH - 6400, "the touch after 127 ticks of flight")
	assert_eq(world.live_shots(), 0, "freed on the hit")


func test_shot_does_not_home() -> void:
	var config: SimConfig = _lantern()
	for row: Array in [[37, false], [161, false], [162, true]]:
		var world: WorldState = _lantern_world(config)
		_run_dir(config, world, row[0], Vector2i(0, 1), 170)
		assert_eq(world.hero_hp < TOUGH, row[1], str(row))


func test_shot_lifetime_and_pool_limit() -> void:
	var config: SimConfig = _lantern()
	var world: WorldState = _lantern_world(config)
	_run(config, world, 37)
	world.enemy_cooldown[0] = 1000
	_run_dir(config, world, 37, Vector2i(0, 1), 239)
	assert_eq(world.live_shots(), 1)
	_run(config, world, 1)
	assert_eq(world.live_shots(), 0, "240 ticks of flight")
	var full: WorldState = _lantern_world(config)
	for slot: int in SimConfig.ENEMY_SHOTS_LIMIT:
		full.append_shot_slot()
		full.shot_x[slot] = 1000
		full.shot_y[slot] = 1000
		full.shot_ttl[slot] = 1000
		full.shot_damage[slot] = 1
		full.shot_radius[slot] = 8000
	_run(config, full, 37)
	assert_eq(full.shot_slots(), SimConfig.ENEMY_SHOTS_LIMIT, "no shot past the pool")
	assert_eq(full.shot_vx.count(-2784), 0)


func test_shot_outlives_the_lantern_and_lantern_keeps_distance() -> void:
	var config: SimConfig = _lantern()
	var world: WorldState = _lantern_world(config)
	_run(config, world, 40)
	world.enemy_hp[0] = 0
	_run(config, world, 124)
	assert_eq(world.enemy_alive, 0)
	assert_eq(world.hero_hp, TOUGH - 6400)
	var keeper: WorldState = _lantern_world(config)
	keeper.enemy_x[0] = keeper.player_x + 288000
	keeper.enemy_cooldown[0] = 100
	_run(config, keeper, 50)
	assert_eq(keeper.enemy_x[0] - keeper.player_x, 288000, "no chase within keep")


func test_projectile_lane_follows_the_hero_until_the_release() -> void:
	var config: SimConfig = _lantern()
	var world: WorldState = _lantern_world(config)
	_run(config, world, 1)
	var tell: Dictionary = AttackTelegraph.shape(config, world, 0)
	assert_eq(tell["form"], SimConfig.FORM_PROJECTILE)
	assert_eq(tell["radius"], 384.0)
	assert_eq(tell["width"], 16.0)
	world.player_y += 100000
	assert_almost_eq(float(AttackTelegraph.shape(config, world, 0)["angle"]), PI - atan2(100.0, 384.0), 0.001)


func test_tuning_builds_the_lantern_from_content() -> void:
	var tuning: P0Tuning = P0Tuning.new()
	var record: PackedInt64Array = tuning.kind_record(ContentRegistry.load_dir(), "enemy.cursed_spirit_lantern", 3)
	assert_eq(tuning.error, "")
	var expected: PackedInt64Array = PackedInt64Array(LANTERN_KIND)
	expected.append_array(PackedInt64Array(LANTERN_WISP))
	assert_eq(record, expected, "the oracle trace inputs are the content numbers")
