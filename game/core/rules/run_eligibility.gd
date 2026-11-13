class_name RunEligibility
extends RefCounted
## `hip-run-eligibility-v1` (IC-02): may a profile START a new run with these rules?
##
## Exact port of tools/content/run_eligibility.py; vectors in
## res://tests/fixtures/run_eligibility_vectors.json. Rules validity (stage compatibility,
## mode exclusions, seed) belongs to RunRulesSnapshot; this check only answers whether the
## granted unlock IDs cover the `unlock_id` of the class, difficulty and every mode
## (null = available from the start; stages carry no unlock_id in v7).
## Returns a stable reason code; the first failing check wins.

const POLICY_ID: String = "hip-run-eligibility-v1"
const OK: String = "ok"
const REGISTRY_INVALID: String = "registry_invalid"
const UNKNOWN_UNLOCK_IN_PROFILE: String = "unknown_unlock_in_profile"
const UNKNOWN_DEFINITION: String = "unknown_definition"
const CONTENT_UNLOCK_UNKNOWN: String = "content_unlock_unknown"
const CLASS_LOCKED: String = "class_locked"
const DIFFICULTY_LOCKED: String = "difficulty_locked"
const MODE_LOCKED: String = "mode_locked"


static func check(
	registry: ContentRegistry,
	granted_unlock_ids: PackedStringArray,
	class_id: String,
	difficulty_id: String,
	mode_ids: PackedStringArray
) -> String:
	if registry == null or not registry.is_valid():
		return REGISTRY_INVALID
	var unlocks: PackedStringArray = registry.ids("unlock_rules")
	for granted: String in granted_unlock_ids:
		if not unlocks.has(granted):
			return UNKNOWN_UNLOCK_IN_PROFILE
	var sorted_modes: PackedStringArray = mode_ids.duplicate()
	sorted_modes.sort()
	var targets: Array[PackedStringArray] = [
		PackedStringArray(["classes", class_id, CLASS_LOCKED]),
		PackedStringArray(["difficulty_profiles", difficulty_id, DIFFICULTY_LOCKED]),
	]
	for mode_id: String in sorted_modes:
		targets.append(PackedStringArray(["modes", mode_id, MODE_LOCKED]))
	for target: PackedStringArray in targets:
		if not registry.ids(target[0]).has(target[1]):
			return UNKNOWN_DEFINITION
	for target: PackedStringArray in targets:
		var unlock_id: Variant = registry.definition(target[1]).get("unlock_id")
		if unlock_id == null:
			continue
		if typeof(unlock_id) != TYPE_STRING or not unlocks.has(unlock_id):
			return CONTENT_UNLOCK_UNKNOWN
		if not granted_unlock_ids.has(unlock_id):
			return target[2]
	return OK
