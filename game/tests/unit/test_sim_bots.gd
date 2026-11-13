extends GutTest
## ADR-009 slice 2: command logs produced by the Python bots (tools/content/sim_bots.py)
## replay in SimKernel to the same state digests, death tick and kills.

const RUNS: String = "res://tests/fixtures/sim_bot_runs.json"

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


static func _ints(values: Array) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for value: Variant in values:
		out.append(str(value).to_int())
	return out


## Config of a bot trace (same layout as sim_core_vectors.json traces).
static func config_of(row: Dictionary) -> SimConfig:
	var spec: Dictionary = row["enemies"]
	var xp: Dictionary = row["xp"]
	return SimConfig.create(_ints(row["config"])).with_enemies(
		_ints(spec["values"]), _ints(spec["kinds"]), str(spec["seed"])
	).with_skill(_ints(row["skill"])).with_xp(_ints(xp["values"]), _ints(xp["kind_xp"]), _ints(xp["costs"]))


static func log_of(row: Dictionary) -> CommandLog:
	var commands: CommandLog = CommandLog.new()
	for record: Variant in row["commands"]:
		var v: PackedInt64Array = _ints(record)
		commands.append(PlayerCommand.create(v[0], v[1], v[2], v[3]), 0)
	return commands


func test_header_matches_the_game() -> void:
	assert_eq(str(_data.get("kind")), "hip-sim-bot-runs")
	assert_eq(int(_data.get("sim_schema_version", 0)), RunRulesSnapshot.SIM_SCHEMA_VERSION)
	assert_eq((_data.get("traces", []) as Array).size(), 3)


func test_bot_logs_replay_bit_exact() -> void:
	for entry: Variant in _data.get("traces", []):
		var row: Dictionary = entry
		var name: String = str(row["id"])
		var config: SimConfig = config_of(row)
		assert_true(config.is_valid(), name)
		var commands: CommandLog = log_of(row)
		assert_eq(commands.size(), int(row["command_count"]), name)
		assert_eq(commands.digest(), str(row["log_digest"]), name + " log digest")
		var world: WorldState = WorldState.initial(config)
		var steps: int = 0
		for checkpoint: Variant in row["checkpoints"]:
			var mark: Dictionary = checkpoint
			SimKernel.run(config, world, commands, int(mark["step"]) - steps)
			steps = int(mark["step"])
			assert_eq(world.digest(), str(mark["digest"]), name + " @" + str(steps))
		assert_eq(world.tick, int(row["death_tick"]), name + " death tick")
		assert_true(world.is_over(), name + " hero died")
		assert_eq(world.kills, int(row["kills"]), name + " kills")


func test_the_game_tuning_is_the_bot_config() -> void:
	var tuned: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), "101")
	var row: Dictionary = (_data.get("traces", []) as Array)[0]
	assert_eq(tuned.to_ints(), config_of(row).to_ints(), "bots play the P0 run of the game")
