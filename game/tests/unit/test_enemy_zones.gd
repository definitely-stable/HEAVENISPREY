extends GutTest
## ADR-011 sections 3-4 (E5): the GDScript enemy zones against the oracle rules: the death
## zone telegraph and single hit, leaving it in time, no recursion, the pool limit, the ground
## zone on the hero at the launch, status.root_slow, one zone per caster, the zone drawing and
## the content numbers. The numbers equal tools/content/sim_core.py (PUPPET_KIND,
## PUPPET_BURST, ROOT_KIND, ROOT_GROWTH, P0_ROOT).

const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const TOUGH: int = 500000000
const NO_SPAWN: Array[int] = [TOUGH, 536870912, 0, 1000, 64, 0]
const PUPPET_KIND: Array[int] = [3984, 19680, 8200, 3800, 0, 2]
const PUPPET_BURST: Array[int] = [4, 36, 54, 0, 0, 0, 0, 0, 96000, 0]
const ROOT_KIND: Array[int] = [3072, 25200, 11000, 0, 360, 1]
const ROOT_GROWTH: Array[int] = [5, 57, 165, 45, 384000, 0, 0, 0, 153600, 0]
const P0_ROOT: Array[int] = [90, 720]
const CX: int = 768000
const CY: int = 480000


static func _config(kind: Array[int], record: Array[int], root: Array[int] = P0_ROOT) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(NO_SPAWN), PackedInt64Array(kind), "1"
	).with_attacks(PackedInt64Array(record), PackedInt64Array([0, 0, 0, 0]), PackedInt64Array(root))


static func _place(world: WorldState, x: int, y: int, hp: int) -> int:
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_x[slot] = x
	world.enemy_y[slot] = y
	world.enemy_hp[slot] = hp
	world.next_enemy_uid += 1
	world.enemy_alive += 1
	return slot


## A puppet at 0 HP on the hero centre: it dies in tick 0 and leaves its zone at (CX, CY).
static func _puppet_world(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	_place(world, CX, CY, 0)
	return world


## The root caster on the hero's +x side: its first chase step ends at the launch range.
static func _root_world(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	_place(world, CX + 384000 + ROOT_KIND[0], CY, 1000000)
	return world


static func _zone(world: WorldState, slot: int) -> Array[int]:
	return [
		world.zone_x[slot], world.zone_y[slot], world.zone_radius[slot], world.zone_tell[slot],
		world.zone_left[slot], world.zone_damage[slot], world.zone_form[slot], world.zone_owner[slot],
		world.zone_hit[slot],
	]


static func _run(config: SimConfig, world: WorldState, ticks: int) -> void:
	SimKernel.run(config, world, CommandLog.new(), ticks)


static func _run_dir(config: SimConfig, world: WorldState, from_tick: int, move: Vector2i, ticks: int) -> void:
	var commands: CommandLog = CommandLog.new()
	commands.append(PlayerCommand.create(from_tick, 0, move.x, move.y), 0)
	SimKernel.run(config, world, commands, ticks)


func test_zone_configs_are_valid_and_checked() -> void:
	assert_true(_config(PUPPET_KIND, PUPPET_BURST).is_valid())
	assert_true(_config(ROOT_KIND, ROOT_GROWTH).is_valid())
	for change: Array in [[3, 1], [4, 1], [5, 1], [6, 1], [7, 1], [8, 0], [9, 1]]:
		var burst: Array[int] = PUPPET_BURST.duplicate()
		burst[change[0]] = change[1]
		assert_false(_config(PUPPET_KIND, burst).is_valid(), "burst " + str(change))
	for change: Array in [[4, 0], [5, 1], [6, 1], [7, 1], [8, 0], [9, 1], [2, 0]]:
		var roots: Array[int] = ROOT_GROWTH.duplicate()
		roots[change[0]] = change[1]
		assert_false(_config(ROOT_KIND, roots).is_valid(), "roots " + str(change))
	var harmless: Array[int] = PUPPET_KIND.duplicate()
	harmless[3] = 0
	assert_false(_config(harmless, PUPPET_BURST).is_valid(), "a death zone deals damage")
	var harmful: Array[int] = ROOT_KIND.duplicate()
	harmful[3] = 100
	assert_false(_config(harmful, ROOT_GROWTH).is_valid(), "a ground zone deals no damage")
	var idle: Array[int] = ROOT_KIND.duplicate()
	idle[4] = 0
	assert_false(_config(idle, ROOT_GROWTH).is_valid(), "only a death-zone kind has interval 0")
	for root: Array in [[0, 720], [90, 0], [90, 1001]]:
		var values: Array[int] = []
		values.assign(root)
		assert_false(_config(ROOT_KIND, ROOT_GROWTH, values).is_valid(), str(root))
	var no_attacks: SimConfig = SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(NO_SPAWN), PackedInt64Array(PUPPET_KIND), "1"
	)
	assert_false(no_attacks.is_valid(), "interval 0 without the death-zone record")


func test_puppet_death_zone_telegraph_and_single_hit() -> void:
	var config: SimConfig = _config(PUPPET_KIND, PUPPET_BURST)
	var world: WorldState = _puppet_world(config)
	_run(config, world, 1)
	assert_eq(world.kills, 1)
	assert_eq(_zone(world, 0), [CX, CY, 96000, 36, 54, 3800, SimConfig.FORM_DEATH_ZONE, 1, 0])
	_run(config, world, 35)
	assert_eq(world.hero_hp, TOUGH, "the telegraph is safe")
	_run(config, world, 1)
	assert_eq(world.hero_hp, TOUGH - 3800, "first active tick")
	_run(config, world, 52)
	assert_eq(world.live_zones(), 1)
	_run(config, world, 1)
	assert_eq(world.live_zones(), 0, "54 active ticks")
	assert_eq(world.hero_hp, TOUGH - 3800, "once per zone")


func test_hero_leaves_the_death_zone_during_the_telegraph() -> void:
	for case: Array in [[16, false], [17, true]]:
		var config: SimConfig = _config(PUPPET_KIND, PUPPET_BURST)
		var world: WorldState = _puppet_world(config)
		_run_dir(config, world, case[0], Vector2i(1, 0), 100)
		assert_eq(world.hero_hp < TOUGH, case[1], "walks out from tick " + str(case[0]))


func test_zones_never_touch_enemies_and_the_pool_is_limited() -> void:
	var config: SimConfig = _config(PUPPET_KIND, PUPPET_BURST)
	var world: WorldState = _puppet_world(config)
	var other: int = _place(world, CX + 40000, CY, 5000)
	_run(config, world, 90)
	assert_eq(world.enemy_hp[other], 5000, "no recursion: zones hit only the hero")
	assert_eq(world.kills, 1)
	var full: WorldState = _puppet_world(config)
	for index: int in SimConfig.ZONES_LIMIT:
		var slot: int = full.append_zone_slot()
		full.zone_form[slot] = SimConfig.FORM_DEATH_ZONE
		full.zone_tell[slot] = 1000
		full.zone_left[slot] = 1000
		full.zone_radius[slot] = 1000
		full.zone_owner[slot] = 99
	_run(config, full, 1)
	assert_eq(full.zone_slots(), SimConfig.ZONES_LIMIT, "no free slot: no zone")
	for slot: int in full.zone_slots():
		assert_eq(full.zone_owner[slot], 99)


func test_root_zone_on_the_hero_and_one_active_tick() -> void:
	var config: SimConfig = _config(ROOT_KIND, ROOT_GROWTH)
	var world: WorldState = _root_world(config)
	_run(config, world, 1)
	assert_eq(_zone(world, 0), [CX, CY, 153600, 57, 165, 0, SimConfig.FORM_GROUND_ZONE, 1, 0])
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_TELL)
	_run(config, world, 56)
	assert_eq(world.root_left, 0, "the telegraph does not root")
	_run(config, world, 1)
	assert_eq(world.root_left, 89)
	assert_eq(world.hero_hp, TOUGH, "no damage")
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_ACTIVE)
	_run(config, world, 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_RECOVER, "active is one tick")


func test_root_escape_and_slow() -> void:
	for case: Array in [[25, false], [26, true]]:
		var config: SimConfig = _config(ROOT_KIND, ROOT_GROWTH)
		var world: WorldState = _root_world(config)
		var commands: CommandLog = CommandLog.new()
		commands.append(PlayerCommand.create(case[0], 0, -1, 0), 0)
		var rooted: bool = false
		for _i: int in 120:
			SimKernel.step(config, world, commands)
			rooted = rooted or world.root_left > 0
		assert_eq(rooted, case[1], "walks out from tick " + str(case[0]))
	var slow_config: SimConfig = _config(ROOT_KIND, ROOT_GROWTH)
	var slowed: WorldState = _root_world(slow_config)
	var walk: CommandLog = CommandLog.new()
	walk.append(PlayerCommand.create(60, 0, -1, 0), 0)
	var steps: Array[int] = []
	for _i: int in 200:
		var x: int = slowed.player_x
		SimKernel.step(slow_config, slowed, walk)
		steps.append(x - slowed.player_x)
	assert_eq(steps.slice(60, 193).count(3456), 133, "0.72 x 4800 while rooted")
	assert_eq(steps[193], 4800, "90 ticks after the last tick inside")
	slowed.ranks[UpgradeSystem.SPEED] = 1
	slowed.root_left = 5
	assert_eq(StatusSystem.move_speed(slow_config, slowed), 3628, "5040 x 0.72, floored")


func test_one_zone_per_caster_and_zone_outlives_it() -> void:
	var kind: Array[int] = ROOT_KIND.duplicate()
	kind[4] = 80
	var config: SimConfig = _config(kind, ROOT_GROWTH)
	var world: WorldState = _root_world(config)
	_run(config, world, 221)
	assert_eq(world.next_attack_uid - 1, 1, "the caster waits for its zone")
	_run(config, world, 1)
	assert_eq(world.next_attack_uid - 1, 2)
	var plain: SimConfig = _config(ROOT_KIND, ROOT_GROWTH)
	var orphan: WorldState = _root_world(plain)
	_run(plain, orphan, 10)
	orphan.enemy_hp[0] = 0
	_run(plain, orphan, 48)
	assert_eq(orphan.enemy_alive, 0)
	assert_eq(orphan.root_left, 89, "the zone made in tell still roots")


func test_zone_drawing_follows_the_pool() -> void:
	var config: SimConfig = _config(ROOT_KIND, ROOT_GROWTH)
	var world: WorldState = _root_world(config)
	_run(config, world, 1)
	assert_true(AttackTelegraph.shape(config, world, 0).is_empty(), "no lane for a zone caster")
	var zone: Dictionary = AttackTelegraph.zone_shape(config, world, 0)
	assert_eq(zone["center"], Vector2(768, 480))
	assert_eq(zone["radius"], 153.6)
	assert_eq(zone["progress"], 0.0)
	assert_false(zone["active"])
	_run(config, world, 57)
	assert_true(AttackTelegraph.zone_shape(config, world, 0)["active"])


func test_tuning_builds_zones_from_content() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var tuning: P0Tuning = P0Tuning.new()
	var puppet: PackedInt64Array = tuning.kind_record(registry, "enemy.paper_puppet", 2)
	var roots: PackedInt64Array = tuning.kind_record(registry, "enemy.root_abomination", 1)
	assert_eq(tuning.error, "")
	var expected: PackedInt64Array = PackedInt64Array(PUPPET_KIND)
	expected.append_array(PackedInt64Array(PUPPET_BURST))
	assert_eq(puppet, expected, "the oracle trace inputs are the content numbers")
	expected = PackedInt64Array(ROOT_KIND)
	expected.append_array(PackedInt64Array(ROOT_GROWTH))
	assert_eq(roots, expected)
	assert_eq(tuning.root_values(registry), PackedInt64Array(P0_ROOT))
