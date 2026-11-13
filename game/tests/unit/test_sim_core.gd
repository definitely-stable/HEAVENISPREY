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


func test_traces_match_reference() -> void:
	for entry: Variant in _data.get("traces", []):
		var row: Dictionary = entry
		var name: String = str(row["name"])
		var config: SimConfig = SimConfig.create(_ints(row["config"]))
		assert_true(config.is_valid(), name + " config")
		var commands: CommandLog = CommandLog.new()
		for record: Variant in row["commands"]:
			assert_eq(commands.append(_command(record), 0), CommandLog.OK, name)
		assert_eq(commands.digest(), str(row["log_digest"]), name + " log digest")
		var world: WorldState = WorldState.initial(config)
		for checkpoint: Variant in row["checkpoints"]:
			var mark: Dictionary = checkpoint
			SimKernel.run(config, world, commands, int(mark["tick"]) - world.tick)
			var label: String = name + " @" + str(mark["tick"])
			assert_eq(world.player_x, str(mark["player_x"]).to_int(), label + " x")
			assert_eq(world.player_y, str(mark["player_y"]).to_int(), label + " y")
			assert_eq(world.digest(), str(mark["digest"]), label + " digest")


func test_replay_from_log_is_identical() -> void:
	var config: SimConfig = SimConfig.create(
		PackedInt64Array([4800, 24000, 0, 0, 1536000, 960000, 768000, 480000])
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


func test_empty_digest_is_sha256_of_nothing() -> void:
	var expected: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	assert_eq(CommandLog.new().digest(), expected)
