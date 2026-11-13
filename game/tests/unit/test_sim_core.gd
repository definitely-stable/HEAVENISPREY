extends GutTest
## P0-01 simulation core parity with tools/content/sim_core.py: command log rules, hero
## movement, enemies and the hero auto-attack must match the Python reference bit for bit.

const VECTORS: String = "res://tests/fixtures/sim_core_vectors.json"
const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const P0_SKILL: Array[int] = [50000, 384000, 10000, 12000, 10000, 40, 1, 64]
## Frozen, harmless targets with plenty of HP; no spawn for ~536870 ticks.
const TARGET_KINDS: Array[int] = [0, 24000, 1000000, 0, 36, 1]

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


static func _ints(values: Array) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for value: Variant in values:
		out.append(str(value).to_int())
	return out


static func _command(values: Array) -> PlayerCommand:
	return PlayerCommand.from_ints(_ints(values))


func test_cos_table_matches_reference() -> void:
	var expected: Array = _data.get("cos_q14", [])
	assert_eq(expected.size(), 181)
	for k: int in expected.size():
		assert_eq(EnemyAttackSystem.COS_Q14[k], int(expected[k]), "cos %d" % k)


func test_sector_and_launch_cases_match_reference() -> void:
	for entry: Variant in _data.get("sector_cases", []):
		var c: PackedInt64Array = _ints(entry)
		var got: bool = EnemyAttackSystem.in_sector(c[0], c[1], c[2], c[3], c[4], c[5])
		assert_eq(int(got), c[6], "sector " + str(c))
	for entry: Variant in _data.get("launch_cases", []):
		var c: PackedInt64Array = _ints(entry)
		assert_eq(int(EnemyAttackSystem.in_launch_range(c[0], c[1], c[2])), c[3], "launch " + str(c))


func test_vectors_header() -> void:
	assert_eq(str(_data.get("policy_id")), Fx.POLICY_ID)
	assert_eq(int(_data.get("log_schema_version", 0)), CommandLog.SCHEMA_VERSION)
	assert_gt((_data.get("traces", []) as Array).size(), 0)


func test_append_rules_match_reference() -> void:
	for entry: Variant in _data.get("append_cases", []):
		var row: Dictionary = entry
		var commands: CommandLog = CommandLog.new()
		for record: Variant in row["existing"]:
			assert_eq(commands.append(_command(record), 0), CommandLog.OK)
		var got: String = commands.append(_command(row["command"]), int(row["next_tick"]))
		assert_eq(got, str(row["expected"]), str(row["name"]))


static func _config(row: Dictionary) -> SimConfig:
	var config: SimConfig = SimConfig.create(_ints(row["config"]))
	var enemies: Variant = row.get("enemies")
	if typeof(enemies) == TYPE_DICTIONARY:
		var spec: Dictionary = enemies
		config.with_enemies(_ints(spec["values"]), _ints(spec["kinds"]), str(spec["seed"]))
	var skill: Variant = row.get("skill")
	if typeof(skill) == TYPE_ARRAY:
		config.with_skill(_ints(skill))
	var xp: Variant = row.get("xp")
	if typeof(xp) == TYPE_DICTIONARY:
		var spec_xp: Dictionary = xp
		config.with_xp(_ints(spec_xp["values"]), _ints(spec_xp["kind_xp"]), _ints(spec_xp["costs"]))
	var attacks: Variant = row.get("attacks")
	if typeof(attacks) == TYPE_DICTIONARY:
		var spec_attacks: Dictionary = attacks
		config.with_attacks(_ints(spec_attacks["records"]), _ints(spec_attacks["venom"]))
	return config.with_choice_mode(int(row.get("choice_mode", 0))).with_run_ticks(int(row.get("run_ticks", 0)))


static func _live_projectiles(world: WorldState) -> int:
	return world.projectile_slots() - world.proj_damage.count(0)


func test_traces_match_reference() -> void:
	for entry: Variant in _data.get("traces", []):
		var row: Dictionary = entry
		var name: String = str(row["name"])
		var config: SimConfig = _config(row)
		assert_true(config.is_valid(), name + " config")
		var commands: CommandLog = CommandLog.new()
		for record: Variant in row["commands"]:
			assert_eq(commands.append(_command(record), 0), CommandLog.OK, name)
		assert_eq(commands.digest(), str(row["log_digest"]), name + " log digest")
		var world: WorldState = WorldState.initial(config)
		var steps: int = 0
		for checkpoint: Variant in row["checkpoints"]:
			var mark: Dictionary = checkpoint
			SimKernel.run(config, world, commands, int(mark["step"]) - steps)
			steps = int(mark["step"])
			var label: String = name + " @" + str(steps)
			assert_eq(world.tick, int(mark["tick"]), label + " tick")
			assert_eq(world.player_x, str(mark["player_x"]).to_int(), label + " x")
			assert_eq(world.player_y, str(mark["player_y"]).to_int(), label + " y")
			assert_eq(world.hero_hp, str(mark["hero_hp"]).to_int(), label + " hp")
			assert_eq(world.hero_dead, int(mark["hero_dead"]), label + " dead")
			assert_eq(world.enemy_alive, int(mark["enemy_alive"]), label + " enemies")
			assert_eq(world.kills, int(mark["kills"]), label + " kills")
			assert_eq(_live_projectiles(world), int(mark["projectiles"]), label + " projectiles")
			assert_eq(world.gems_alive, int(mark["gems"]), label + " gems")
			assert_eq(world.xp_collected_total, int(mark["xp"]), label + " xp")
			assert_eq(world.level, int(mark["level"]), label + " level")
			assert_eq(world.choices_done, int(mark["choices"]), label + " choices")
			assert_eq(int(world.is_paused()), int(mark["paused"]), label + " paused")
			assert_eq(world.won, int(mark["won"]), label + " won")
			assert_eq(world.next_attack_uid - 1, int(mark["attacks"]), label + " attacks")
			assert_eq(world.venom_stacks, int(mark["venom"]), label + " venom")
			assert_eq(world.digest(), str(mark["digest"]), label + " digest")


func test_replay_from_log_is_identical() -> void:
	var config: SimConfig = SimConfig.create(
		PackedInt64Array([4800, 24000, 0, 0, 1536000, 960000, 768000, 480000])
	).with_enemies(
		PackedInt64Array([500000000, 20000, 300, 3000, 32, 384000]),
		PackedInt64Array([3264, 24000, 12800, 6500, 36, 8, 6144, 21600, 7800, 7600, 42, 2]),
		"42"
	).with_skill(PackedInt64Array([30000, 480000, 6000, 12000, 10000, 40, 2, 8]))
	var commands: CommandLog = CommandLog.new()
	for t: int in range(0, 600, 37):
		commands.append(PlayerCommand.create(t, t, (t % 3) - 1, ((t + 1) % 3) - 1), 0)
	var live: WorldState = WorldState.initial(config)
	var checkpoint: WorldState
	for t: int in 600:
		if t == 300:
			checkpoint = live.copy()
		SimKernel.step(config, live, commands)
	var restored: WorldState = checkpoint.copy()
	SimKernel.run(config, restored, commands, 300)
	assert_eq(restored.digest(), live.digest(), "save at tick 300 and resume == live run")


func test_logged_command_cannot_be_changed_afterwards() -> void:
	var commands: CommandLog = CommandLog.new()
	var command: PlayerCommand = PlayerCommand.create(0, 0, 1, 0)
	commands.append(command, 0)
	var before: String = commands.digest()
	command.move_x = -1
	assert_eq(commands.digest(), before)
	assert_eq(commands.move_x_at(0), 1)


func test_invalid_config_is_rejected() -> void:
	assert_false(SimConfig.create(PackedInt64Array([1, 0, 0, 0, 10, 10, 5, 5])).is_valid())
	assert_false(SimConfig.create(PackedInt64Array([1, 2, 0, 0, 10, 10, 0, 5])).is_valid())
	assert_false(SimConfig.create(PackedInt64Array([1, 2])).is_valid())


func test_invalid_enemy_settings_are_rejected() -> void:
	var movement: PackedInt64Array = PackedInt64Array([4800, 24000, 0, 0, 1536000, 960000, 768000, 480000])
	var kinds: PackedInt64Array = PackedInt64Array([3264, 24000, 12800, 6500, 36, 8])
	var values: PackedInt64Array = PackedInt64Array([100000, 90000, 10800, 2000, 48, 384000])
	assert_true(SimConfig.create(movement).with_enemies(values, kinds, "1").is_valid())
	assert_false(SimConfig.create(movement).with_enemies(values, kinds, "-1").is_valid(), "seed")
	assert_false(SimConfig.create(movement).with_enemies(values, kinds, "01").is_valid(), "seed form")
	var zero_weight: PackedInt64Array = PackedInt64Array([3264, 24000, 12800, 6500, 36, 0])
	assert_false(SimConfig.create(movement).with_enemies(values, zero_weight, "1").is_valid(), "weight")
	var partial: PackedInt64Array = PackedInt64Array([3264, 24000, 12800])
	assert_false(SimConfig.create(movement).with_enemies(values, partial, "1").is_valid(), "stride")
	var no_hp: PackedInt64Array = PackedInt64Array([0, 90000, 10800, 2000, 48, 384000])
	assert_false(SimConfig.create(movement).with_enemies(no_hp, kinds, "1").is_valid(), "hero hp")
	var slow_cap: PackedInt64Array = PackedInt64Array([100000, 90000, 10800, 999, 48, 384000])
	assert_false(SimConfig.create(movement).with_enemies(slow_cap, kinds, "1").is_valid(), "rate cap")
	assert_false(SimConfig.create(movement).with_enemies(values.slice(0, 4), kinds, "1").is_valid(), "values")
	var too_wide: PackedInt64Array = PackedInt64Array([3264, 480000, 12800, 6500, 36, 8])
	assert_false(SimConfig.create(movement).with_enemies(values, too_wide, "1").is_valid(), "radius")


func test_dead_hero_freezes_the_run() -> void:
	var movement: PackedInt64Array = PackedInt64Array([4800, 24000, 0, 0, 300000, 300000, 150000, 150000])
	var kinds: PackedInt64Array = PackedInt64Array([6000, 24000, 1000, 50000, 10, 1])
	var config: SimConfig = SimConfig.create(movement).with_enemies(
		PackedInt64Array([100000, 1000, 0, 1000, 1, 0]), kinds, "5")
	var world: WorldState = WorldState.initial(config)
	var commands: CommandLog = CommandLog.new()
	var guard: int = 0
	while not world.is_over() and guard < 1000:
		SimKernel.step(config, world, commands)
		guard += 1
	assert_true(world.is_over())
	assert_eq(world.hero_hp, 0, "HP is clamped at 0")
	var frozen: String = world.digest()
	SimKernel.run(config, world, commands, 100)
	assert_eq(world.digest(), frozen, "no step after death")


func test_schema_one_log_migrates_to_moves() -> void:
	var migrated: CommandLog = CommandLog.from_v1(PackedInt64Array([0, 0, 1, -1, 5, 3, 0, 0]))
	assert_eq(migrated.records(), PackedInt64Array([0, 0, 0, 1, -1, 5, 3, 0, 0, 0]))
	assert_null(CommandLog.from_v1(PackedInt64Array([0, 0, 1])), "partial record")
	assert_null(CommandLog.from_v1(PackedInt64Array([0, 0, 2, 0])), "bad axis")
	assert_null(CommandLog.from_v1(PackedInt64Array([5, 1, 0, 0, 4, 2, 0, 0])), "order")


func test_empty_digest_is_sha256_of_nothing() -> void:
	var expected: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	assert_eq(CommandLog.new().digest(), expected)


static func _arena(skill: Array[int]) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array([500000000, 536870912, 0, 1000, 64, 0]), PackedInt64Array(TARGET_KINDS), "1"
	).with_skill(PackedInt64Array(skill))


static func _place(world: WorldState, x: int, y: int, hp: int) -> void:
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_x[slot] = x
	world.enemy_y[slot] = y
	world.enemy_hp[slot] = hp
	world.next_enemy_uid += 1
	world.enemy_alive += 1


static func _cast_ticks(config: SimConfig, world: WorldState, ticks: int) -> Array[int]:
	var out: Array[int] = []
	var commands: CommandLog = CommandLog.new()
	for _i: int in ticks:
		var acc: int = world.skill_acc
		SimKernel.step(config, world, commands)
		if world.skill_acc < acc:
			out.append(world.tick - 1)
	return out


func test_skill_casts_every_period_and_holds_without_target() -> void:
	var config: SimConfig = _arena(P0_SKILL)
	assert_true(config.is_valid())
	var world: WorldState = WorldState.initial(config)
	_place(world, 968000, 480000, 1000000)
	assert_eq(_cast_ticks(config, world, 160), [49, 99, 149] as Array[int])
	var idle: WorldState = WorldState.initial(config)
	assert_eq(_cast_ticks(config, idle, 200), [] as Array[int])
	assert_eq(idle.skill_acc, 49000, "a blocked tick does not advance the cooldown")
	_place(idle, 968000, 480000, 1000000)
	assert_eq(_cast_ticks(config, idle, 60), [200, 250] as Array[int])


func test_projectile_hits_each_enemy_once_and_reused_slot_is_new() -> void:
	var config: SimConfig = _arena(P0_SKILL)
	var world: WorldState = WorldState.initial(config)
	_place(world, 968000, 480000, 25000)
	world.proj_x.append(960000)
	world.proj_y.append(480000)
	world.proj_vx.append(0)
	world.proj_vy.append(0)
	world.proj_ttl.append(40)
	world.proj_damage.append(10000)
	world.proj_hits.append(0)
	world.proj_capacity.append(2)
	for _cell: int in world.ledger_stride:
		world.proj_ledger.append(0)
	CombatSystem.fly_and_hit(config, world)
	CombatSystem.fly_and_hit(config, world)
	assert_eq(world.enemy_hp[0], 15000, "the same enemy is hit once per projectile")
	assert_eq(world.proj_ledger[0], 1)
	world.enemy_uid[0] = world.next_enemy_uid
	world.next_enemy_uid += 1
	CombatSystem.fly_and_hit(config, world)
	assert_eq(world.enemy_hp[0], 5000, "uid 2 in a reused slot is a new target")
	assert_eq(world.proj_damage[0], 0, "pierce used up: slot freed")


func test_invalid_skill_settings_are_rejected() -> void:
	assert_true(_arena(P0_SKILL).is_valid())
	assert_false(SimConfig.create(PackedInt64Array(BASE)).with_skill(PackedInt64Array(P0_SKILL)).is_valid())
	for change: Array in [[0, 0], [3, 0], [3, 34001], [4, 0], [5, 0], [6, 8], [7, 0], [7, 257]]:
		var skill: Array[int] = P0_SKILL.duplicate()
		skill[change[0]] = change[1]
		assert_false(_arena(skill).is_valid(), str(change))


func test_acquire_range_is_inclusive() -> void:
	var config: SimConfig = _arena(P0_SKILL)
	var world: WorldState = WorldState.initial(config)
	_place(world, 768000 + 384000, 480000, 1000000)
	world.skill_acc = 49000
	SimKernel.step(config, world, CommandLog.new())
	assert_eq(world.skill_acc, 0, "a target exactly at range is acquired")
	world.enemy_x[0] += 1
	world.skill_acc = 49000
	SimKernel.step(config, world, CommandLog.new())
	assert_eq(world.skill_acc, 49000, "one su further is out of range")


## Separation (ADR-009 section 2), checked directly; the stress trace covers it end to end.
static func _push_pass(config: SimConfig, world: WorldState) -> Array[PackedInt64Array]:
	var push_x: PackedInt64Array = PackedInt64Array()
	var push_y: PackedInt64Array = PackedInt64Array()
	push_x.resize(world.enemy_slots())
	push_y.resize(world.enemy_slots())
	push_x.fill(0)
	push_y.fill(0)
	SeparationSystem._separate(config, world, push_x, push_y)
	return [push_x, push_y]


func test_separation_pushes_half_the_overlap_and_coincident_along_x() -> void:
	var config: SimConfig = _arena(P0_SKILL)
	var world: WorldState = WorldState.initial(config)
	_place(world, 768000, 480000, 1)
	_place(world, 798000, 480000, 1)
	var push: Array[PackedInt64Array] = _push_pass(config, world)
	assert_eq(push[0], PackedInt64Array([-9000, 9000]), "half of the 18000 overlap each")
	assert_eq(push[1], PackedInt64Array([0, 0]))
	var same: WorldState = WorldState.initial(config)
	_place(same, 768000, 480000, 1)
	_place(same, 1268000, 480000, 1)
	_place(same, 768000, 480000, 1)
	push = _push_pass(config, same)
	assert_eq(push[0], PackedInt64Array([-24000, 0, 24000]), "the larger slot goes towards +x")
	assert_eq(push[1], PackedInt64Array([0, 0, 0]))


func test_separation_budget_resumes_at_the_cursor() -> void:
	var config: SimConfig = _arena(P0_SKILL)
	var world: WorldState = WorldState.initial(config)
	# Three crowds of 70 in cells (2,2), (10,10), (20,15): 2415 checks each, 33 columns.
	for centre: Array in [[120000, 120000], [504000, 504000], [984000, 744000]]:
		for k: int in 70:
			_place(world, centre[0] + k * 100, centre[1], 1)
	var push: Array[PackedInt64Array] = _push_pass(config, world)
	assert_eq(world.sep_cursor, 10 * 33 + 11, "stops before the first cell after 4096 checks")
	assert_ne(push[0][70], 0, "the second crowd is finished")
	assert_eq(push[0][140], 0, "the third crowd waits for the next tick")
	push = _push_pass(config, world)
	assert_eq(world.sep_cursor, 0, "the resumed pass completes")
	assert_eq(push[0][0], 0, "the resumed pass starts at the cursor")
	assert_ne(push[0][140], 0)


func test_separated_move_is_capped_and_touching_enemy_stays() -> void:
	var config: SimConfig = SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array([500000000, 536870912, 0, 1000, 64, 0]),
		PackedInt64Array([3264, 24000, 1000000, 0, 36, 1]), "1"
	)
	var world: WorldState = WorldState.initial(config)
	_place(world, 816000, 480000, 1)
	SeparationSystem.chase_and_separate(config, world)
	assert_eq([world.enemy_x[0], world.enemy_y[0]], [816000, 480000], "touching the hero: stays")
	_place(world, 826000, 480000, 1)
	SeparationSystem.chase_and_separate(config, world)
	assert_eq(world.enemy_x[0], 816000 - 3264, "push of 19000 capped at the speed 3264")
	assert_eq(world.enemy_y[0], 480000)
