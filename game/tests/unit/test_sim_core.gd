extends GutTest
## P0-01b simulation core parity with tools/content/sim_core.py: command log rules and
## hero movement traces must match the Python reference bit for bit.

const VECTORS: String = "res://tests/fixtures/sim_core_vectors.json"

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
	var v: PackedInt64Array = _ints(values)
	return PlayerCommand.create(v[0], v[1], v[2], v[3])


func test_vectors_header() -> void:
	assert_eq(str(_data.get("policy_id")), Fx.POLICY_ID)
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
	return config


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
			assert_eq(world.enemy_count(), int(mark["enemy_count"]), label + " enemies")
			assert_eq(world.digest(), str(mark["digest"]), label + " digest")


func test_replay_from_log_is_identical() -> void:
	var config: SimConfig = SimConfig.create(
		PackedInt64Array([4800, 24000, 0, 0, 1536000, 960000, 768000, 480000])
	).with_enemies(
		PackedInt64Array([500000000, 20, 32, 384000]),
		PackedInt64Array([3264, 24000, 12800, 6500, 36, 8, 6144, 21600, 7800, 7600, 42, 2]),
		"42"
	)
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
	var values: PackedInt64Array = PackedInt64Array([100000, 45, 48, 384000])
	assert_true(SimConfig.create(movement).with_enemies(values, kinds, "1").is_valid())
	assert_false(SimConfig.create(movement).with_enemies(values, kinds, "-1").is_valid(), "seed")
	assert_false(SimConfig.create(movement).with_enemies(values, kinds, "01").is_valid(), "seed form")
	var zero_weight: PackedInt64Array = PackedInt64Array([3264, 24000, 12800, 6500, 36, 0])
	assert_false(SimConfig.create(movement).with_enemies(values, zero_weight, "1").is_valid(), "weight")
	var partial: PackedInt64Array = PackedInt64Array([3264, 24000, 12800])
	assert_false(SimConfig.create(movement).with_enemies(values, partial, "1").is_valid(), "stride")
	var no_hp: PackedInt64Array = PackedInt64Array([0, 45, 48, 384000])
	assert_false(SimConfig.create(movement).with_enemies(no_hp, kinds, "1").is_valid(), "hero hp")
	var too_wide: PackedInt64Array = PackedInt64Array([3264, 480000, 12800, 6500, 36, 8])
	assert_false(SimConfig.create(movement).with_enemies(values, too_wide, "1").is_valid(), "radius")


func test_dead_hero_freezes_the_run() -> void:
	var movement: PackedInt64Array = PackedInt64Array([4800, 24000, 0, 0, 300000, 300000, 150000, 150000])
	var kinds: PackedInt64Array = PackedInt64Array([6000, 24000, 1000, 50000, 10, 1])
	var config: SimConfig = SimConfig.create(movement).with_enemies(
		PackedInt64Array([100000, 1, 1, 0]), kinds, "5")
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


func test_empty_digest_is_sha256_of_nothing() -> void:
	var expected: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	assert_eq(CommandLog.new().digest(), expected)
