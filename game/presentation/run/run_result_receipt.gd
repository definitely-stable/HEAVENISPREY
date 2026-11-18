class_name RunResultReceipt
extends RefCounted
## A sealed snapshot of the stopped run. Build once per run_uid in P0SessionProfile.

const SCHEMA_VERSION: int = 1

var _fields: Dictionary = {}


func fields() -> Dictionary:
	return _fields


static func create(uid: String, rules: RunRulesSnapshot, driver: FixedTickDriver,
		registry: ContentRegistry) -> RunResultReceipt:
	if not valid_run_uid(uid) or rules == null or not rules.is_valid():
		push_error("Cannot finish a run without a valid identity")
		return null
	var world: WorldState = driver.world
	var result: String = "abandoned"
	var survived_ticks: int = world.tick
	if world.won != 0:
		result = "victory"
		survived_ticks = driver.config.run_ticks
	elif world.is_over():
		result = "defeat"
		survived_ticks = world.tick - 1
	var data: Dictionary = {
		"receipt_schema_version": SCHEMA_VERSION,
		"run_uid": uid, "rules_hash": rules.rules_hash, "class_id": rules.class_id,
		"stage_id": rules.stage_id, "difficulty_id": rules.difficulty_id,
		"mode_ids": Array(rules.mode_ids), "run_seed": rules.run_seed,
		"sim_schema_version": RunRulesSnapshot.SIM_SCHEMA_VERSION,
		"result": result, "survived_ticks": survived_ticks,
		"kills": world.kills, "level": world.level, "xp_collected": world.xp_collected_total,
		"world_digest": world.digest(), "log_digest": driver.commands.digest(),
		"settlement": "preview_only",
	}
	var preview: Dictionary = RewardPreview.compute(data, registry)
	if preview.has("error"):
		push_error("Cannot compute run reward: " + str(preview["error"]))
		return null
	data.merge(preview)
	ContentRegistry._freeze(data)
	var receipt: RunResultReceipt = RunResultReceipt.new()
	receipt._fields = data
	return receipt


static func valid_run_uid(uid: String) -> bool:
	if uid.length() != 32:
		return false
	for digit: String in uid:
		if not digit in "0123456789abcdef":
			return false
	return true


static func test_run_uid(scenario_id: String, seed: String) -> String:
	return ContentRegistry.sha256_hex(("hip-run-uid-test-v1\n%s\n%s" % [scenario_id, seed]).to_utf8_buffer()).left(32)
