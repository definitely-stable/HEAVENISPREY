class_name P0SessionProfile
extends RefCounted
## Session-only unlocks for the P0 run start.

const THUNDER_UNLOCK: String = "unlock.thunder"

var registry: ContentRegistry
var unlock_all: bool = false
var _finished_stages: Dictionary[int, String] = {}


func record_finished(run_number: int, stage_id: String) -> void:
	if not _finished_stages.has(run_number):
		_finished_stages[run_number] = stage_id


func granted_unlock_ids() -> PackedStringArray:
	var grants: PackedStringArray = []
	if registry == null:
		return grants
	if unlock_all:
		for class_id: String in registry.ids("classes"):
			var class_def: Dictionary = registry.definition(class_id)
			var grant: Variant = class_def.get("unlock_id")
			if class_def.get("planned_first_playable") == true and grant is String:
				grants.append(grant)
		return grants

	var conditions: Array = registry.definition(THUNDER_UNLOCK).get("all", [])
	if conditions.size() != 1:
		return grants
	var condition: Dictionary = conditions[0]
	var required_stage: String = condition.get("stage_id", "")
	var required_count: Variant = ContentRegistry.integral(condition.get("count"))
	if condition.get("event") == "run_finished" and required_count != null and required_count > 0:
		if _finished_stages.values().count(required_stage) >= required_count:
			grants.append(THUNDER_UNLOCK)
	return grants


static func random_run_seed() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	if bytes.size() != 8:
		return ""
	var signed_word: int = bytes.decode_s64(0)
	if signed_word >= 0:
		return str(signed_word)
	# The signed shift supplies the upper 63 bits. Use 10 = 2 * 5 before doubling.
	var upper: int = (signed_word >> 1) & 0x7fffffffffffffff
	var prefix: int = Fx.floor_div(upper, 5)
	return str(prefix) + str((upper - prefix * 5) * 2 + (signed_word & 1))
