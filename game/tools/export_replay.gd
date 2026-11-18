class_name ExportReplay
extends RefCounted
## The release builds replay the Python fixtures through their packed catalog and runtime rules.

const ARG: String = "--verify-export-replay"
const SWORD: String = "class.sword"
const THUNDER: String = "class.thunder"


static func launch_requested(scene: Node2D) -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or args[0] != ARG:
		return false
	scene.hide()
	scene.set_process(false)
	var verified: bool = args.size() == 2 and verify(args[1])
	scene.get_tree().quit(0 if verified else 1)
	return true


static func verify(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _fail("Expected a bot run fixture object")
	var package: Dictionary = parsed
	if int(package.get("log_schema_version", 0)) != CommandLog.SCHEMA_VERSION \
		or int(package.get("sim_schema_version", 0)) != RunRulesSnapshot.SIM_SCHEMA_VERSION:
		return _fail("Fixture has incompatible replay schema versions")
	var traces: Variant = package.get("traces")
	if not traces is Array or traces.size() != 2:
		return _fail("Expected exactly two class replays")
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var verified: Dictionary = {}
	for entry: Variant in traces:
		if not entry is Dictionary:
			return _fail("Expected a replay object")
		var trace: Dictionary = entry
		var class_id: String = str(trace.get("class_id", ""))
		if (class_id != SWORD and class_id != THUNDER) or verified.has(class_id):
			return _fail("Missing or duplicate class replay: " + class_id)
		if not _verify_trace(registry, trace, class_id):
			return false
		verified[class_id] = true
	print("PASS: both class replays match Python in the desktop build")
	return true


static func _verify_trace(registry: ContentRegistry, trace: Dictionary, class_id: String) -> bool:
	var enemies: Variant = trace.get("enemies")
	if not enemies is Dictionary or enemies.get("seed") != "101":
		return _fail("Expected seed 101 for " + class_id)
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		registry, PackedStringArray(["unlock.thunder"]), class_id, "stage.jade_grove",
		"difficulty.standard", PackedStringArray(["mode.normal"]), "101"
	)
	var config: SimConfig = P0Tuning.new().run_config(registry, snapshot)
	if config == null:
		return _fail("Release content cannot start " + class_id + ": " + snapshot.error)
	var log: CommandLog = _read_log(trace.get("commands"))
	if log == null or log.digest() != trace.get("log_digest"):
		return _fail("Command digest mismatch for " + class_id)
	var checkpoints: Variant = trace.get("checkpoints")
	var steps: int = int(trace.get("ticks", 0))
	if not checkpoints is Array or checkpoints.is_empty() or steps < 1 or steps > config.run_ticks + 1024:
		return _fail("Invalid length for " + class_id)
	var last: Variant = checkpoints.back()
	if not last is Dictionary or int(last.get("step", -1)) != steps:
		return _fail("Final checkpoint is missing for " + class_id)
	var world: WorldState = WorldState.initial(config)
	for step: int in steps:
		SimKernel.step(config, world, log)
	var digest: String = world.digest()
	if world.tick != int(last.get("tick", -1)) or digest != last.get("digest"):
		return _fail("World digest mismatch for " + class_id + ": " + digest)
	print("PASS: exported ", class_id, " seed 101, ", world.tick, " ticks, ", digest)
	return true


static func _read_log(commands: Variant) -> CommandLog:
	if not commands is Array:
		return null
	var log: CommandLog = CommandLog.new()
	for record: Variant in commands:
		if not record is Array or record.size() != CommandLog.STRIDE:
			return null
		var values: PackedInt64Array = []
		for field: Variant in record:
			if not field is String or not field.is_valid_int():
				return null
			values.append(int(field))
		if log.append(PlayerCommand.from_ints(values), 0) != CommandLog.OK:
			return null
	return log


static func _fail(message: String) -> bool:
	push_error("Export replay: " + message)
	return false
