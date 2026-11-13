extends GutTest
## ADR-011 sections 2-4 (E2): the GDScript attack machine against the oracle rules: the 3R/4
## launch, the escape margin of each arc, the hit only in the first active tick, holding
## still through the attack, the cooldown from the start of `tell`, venom stacks and expiry.
## The numbers equal tools/content/sim_core.py (ARC_KINDS, ARC_ATTACKS, P0_VENOM).

const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const TOUGH: int = 500000000
const NO_SPAWN: Array[int] = [TOUGH, 536870912, 0, 1000, 64, 0]
const ARC_KINDS: Array[int] = [
	5856, 16800, 6500, 5000, 96, 3,
	4944, 24000, 10500, 9000, 120, 2,
	2592, 30720, 25000, 11800, 180, 1,
]
const ARC_ATTACKS: Array[int] = [
	1, 20, 6, 27, 96000, 85, 1,
	1, 30, 10, 37, 129600, 125, 0,
	1, 48, 12, 40, 153600, 130, 0,
]
const VENOM: Array[int] = [3, 240, 60, 1000]


static func _config() -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(NO_SPAWN), PackedInt64Array(ARC_KINDS), "1"
	).with_attacks(PackedInt64Array(ARC_ATTACKS), PackedInt64Array(VENOM))


## One enemy of `kind` on the hero's +x side: its first chase step ends at 3R/4 (+ extra).
static func _world(config: SimConfig, kind: int, extra: int = 0) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	var slot: int = world.append_enemy_slot()
	var reach: int = config.attack_value(kind, SimConfig.ATTACK_REACH)
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_kind[slot] = kind
	var speed: int = config.kind_value(kind, SimConfig.KIND_SPEED)
	world.enemy_x[slot] = world.player_x + Fx.floor_div(reach * 3, 4) + speed + extra
	world.enemy_y[slot] = world.player_y
	world.enemy_hp[slot] = 1000000
	world.next_enemy_uid += 1
	world.enemy_alive += 1
	return world


## Steps `ticks` ticks; the hero holds -x from tick `from_tick` on (-1 = stands still).
static func _run(config: SimConfig, world: WorldState, from_tick: int, ticks: int) -> void:
	var commands: CommandLog = CommandLog.new()
	if from_tick >= 0:
		commands.append(PlayerCommand.create(from_tick, 0, -1, 0), 0)
	SimKernel.run(config, world, commands, ticks)


func test_config_with_attacks_is_valid_and_checked() -> void:
	var config: SimConfig = _config()
	assert_true(config.is_valid())
	var bad: PackedInt64Array = PackedInt64Array(ARC_ATTACKS)
	bad[5] = 181
	assert_false(_config().with_attacks(bad, PackedInt64Array(VENOM)).is_valid(), "arc over 180")
	var no_stacks: PackedInt64Array = PackedInt64Array([0, 240, 60, 1000])
	assert_false(_config().with_attacks(PackedInt64Array(ARC_ATTACKS), no_stacks).is_valid(), "venom without stacks")
	var short: PackedInt64Array = PackedInt64Array(ARC_ATTACKS.slice(0, 20))
	assert_false(_config().with_attacks(short, PackedInt64Array(VENOM)).is_valid(), "short table")


func test_arc_launches_at_three_quarters_of_the_reach() -> void:
	var config: SimConfig = _config()
	for kind: int in 3:
		var world: WorldState = _world(config, kind)
		_run(config, world, -1, 1)
		assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_TELL, "kind %d" % kind)
		assert_eq(world.enemy_dir_x[0], -16384)
		assert_eq(world.enemy_attack_uid[0], 1)
		world = _world(config, kind, 1)
		_run(config, world, -1, 1)
		assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_APPROACH, "kind %d: 1 su too far" % kind)


func test_escape_margin_of_each_arc() -> void:
	var config: SimConfig = _config()
	for row: Array in [[0, 15, 20, 5000], [1, 24, 30, 9000], [2, 40, 48, 11800]]:
		var world: WorldState = _world(config, row[0])
		_run(config, world, row[1], row[2] + 1)
		assert_eq(world.hero_hp, TOUGH, "kind %d escaped" % row[0])
		world = _world(config, row[0])
		_run(config, world, row[1] + 1, row[2] + 1)
		assert_eq(world.hero_hp, TOUGH - row[3], "kind %d one tick late" % row[0])


func test_enemy_holds_still_through_the_attack() -> void:
	var config: SimConfig = _config()
	var world: WorldState = _world(config, 2)
	_run(config, world, -1, 1)
	var x: int = world.enemy_x[0]
	_run(config, world, -1, 99)
	assert_eq(world.enemy_x[0], x)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_RECOVER)
	_run(config, world, -1, 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_APPROACH)
	assert_eq(world.enemy_attack_uid[0], 0)
	_run(config, world, -1, 1)
	assert_lt(world.enemy_x[0], x, "chases again after recover")


func test_cooldown_and_venom_stacks() -> void:
	var config: SimConfig = _config()
	var world: WorldState = _world(config, 0)
	var stacks: PackedInt64Array = PackedInt64Array()
	for _tick: int in 309:
		_run(config, world, -1, 1)
		stacks.append(world.venom_stacks)
	assert_eq(world.next_attack_uid, 5, "launches in ticks 0, 96, 192 and 288")
	assert_eq([stacks[19], stacks[20], stacks[116], stacks[212], stacks[308]], [0, 1, 2, 3, 3])


func test_venom_damage_and_expiry() -> void:
	var config: SimConfig = _config()
	var world: WorldState = WorldState.initial(config)
	StatusSystem.add_venom(config, world)
	var hits: Array = []
	var hp: int = world.hero_hp
	for tick: int in 340:
		if tick == 100:
			StatusSystem.add_venom(config, world)
		StatusSystem.tick(config, world)
		if world.hero_hp != hp:
			hits.append([tick, hp - world.hero_hp])
			hp = world.hero_hp
	assert_eq(hits, [[59, 1000], [119, 2000], [179, 2000], [239, 2000], [299, 2000]])
	assert_eq([world.venom_stacks, world.venom_left, world.venom_phase], [0, 0, 0])


func test_single_stack_deals_its_last_damage_in_the_expiry_tick() -> void:
	var config: SimConfig = _config()
	var world: WorldState = WorldState.initial(config)
	StatusSystem.add_venom(config, world)
	var ticks: Array = []
	var hp: int = world.hero_hp
	for tick: int in 300:
		StatusSystem.tick(config, world)
		if world.hero_hp != hp:
			ticks.append(tick)
			hp = world.hero_hp
	assert_eq(ticks, [59, 119, 179, 239], "four periods, the last one in the expiry tick")
	assert_eq(world.venom_stacks, 0)


func test_tuning_builds_the_arc_kinds_from_content() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var tuning: P0Tuning = P0Tuning.new()
	var weights: Array[int] = [3, 2, 1]
	var ids: Array[String] = [
		"enemy.venom_spirit_snake", "enemy.fallen_sword_disciple", "enemy.ruined_jade_guardian",
	]
	for kind: int in ids.size():
		var record: PackedInt64Array = tuning.kind_record(registry, ids[kind], weights[kind])
		assert_eq(tuning.error, "", ids[kind])
		var expected: PackedInt64Array = PackedInt64Array(ARC_KINDS.slice(kind * 6, kind * 6 + 6))
		expected.append_array(PackedInt64Array(ARC_ATTACKS.slice(kind * 7, kind * 7 + 7)))
		assert_eq(record, expected, ids[kind] + ": the oracle trace inputs are the content numbers")
	assert_eq(tuning.venom_values(registry), PackedInt64Array(VENOM))


func test_w0_run_has_no_attack_table() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), "101")
	assert_not_null(config)
	assert_true(config.attacks.is_empty(), "w0 enemies hit by contact only")


func test_telegraph_shape_follows_the_attack_state() -> void:
	var config: SimConfig = _config()
	var world: WorldState = _world(config, 0)
	assert_true(AttackTelegraph.shape(config, world, 0).is_empty(), "approach: nothing to show")
	_run(config, world, -1, 1)
	var tell: Dictionary = AttackTelegraph.shape(config, world, 0)
	assert_eq(tell["radius"], 96.0)
	assert_almost_eq(float(tell["half_arc"]), deg_to_rad(42.5), 0.0001)
	assert_almost_eq(float(tell["angle"]), PI, 0.0001)
	assert_eq(tell["progress"], 0.0)
	assert_false(tell["active"])
	_run(config, world, -1, 10)
	assert_eq(AttackTelegraph.shape(config, world, 0)["progress"], 0.5)
	_run(config, world, -1, 10)
	assert_true(AttackTelegraph.shape(config, world, 0)["active"], "the hit tick flashes")
	_run(config, world, -1, 6)
	assert_true(AttackTelegraph.shape(config, world, 0).is_empty(), "recover: nothing to show")
	assert_eq(AttackTelegraph.sector(Vector2.ZERO, 10.0, 0.0, 0.5).size(), AttackTelegraph.ARC_POINTS + 2)
