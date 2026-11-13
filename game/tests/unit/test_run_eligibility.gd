extends GutTest
## hip-run-eligibility-v1 parity with tools/content/run_eligibility.py and the IC-02 start gate.

const VECTORS: String = "res://tests/fixtures/run_eligibility_vectors.json"

var _data: Dictionary = {}
var _registry: ContentRegistry


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
	_registry = ContentRegistry.load_dir()


static func _strings(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item: Variant in (value as Array):
		out.append(str(item))
	return out


func test_vectors_header() -> void:
	assert_eq(str(_data.get("policy_id")), RunEligibility.POLICY_ID)
	assert_true(_registry.is_valid(), _registry.error)


func test_cases_match_python_reference() -> void:
	var cases: Array = _data.get("cases", [])
	assert_gt(cases.size(), 0)
	for entry: Variant in cases:
		var row: Dictionary = entry
		var reason: String = RunEligibility.check(
			_registry,
			_strings(row["granted_unlock_ids"]),
			str(row["class_id"]),
			str(row["difficulty_id"]),
			_strings(row["mode_ids"])
		)
		assert_eq(reason, str(row["expected"]), str(row["name"]))


func test_vectors_cover_every_reason_but_registry_invalid() -> void:
	var seen: Dictionary = {}
	for entry: Variant in _data.get("cases", []):
		seen[str((entry as Dictionary)["expected"])] = true
	for code: String in [
		RunEligibility.OK,
		RunEligibility.UNKNOWN_UNLOCK_IN_PROFILE,
		RunEligibility.UNKNOWN_DEFINITION,
		RunEligibility.CLASS_LOCKED,
		RunEligibility.DIFFICULTY_LOCKED,
		RunEligibility.MODE_LOCKED,
	]:
		assert_true(seen.has(code), "no vector for " + code)


func test_invalid_registry_is_not_eligible() -> void:
	var broken: ContentRegistry = ContentRegistry.from_bytes(PackedByteArray(), PackedByteArray())
	var reason: String = RunEligibility.check(
		broken, PackedStringArray(), "class.sword", "difficulty.standard", PackedStringArray()
	)
	assert_eq(reason, RunEligibility.REGISTRY_INVALID)
	assert_eq(
		RunEligibility.check(
			null, PackedStringArray(), "class.sword", "difficulty.standard", PackedStringArray()
		),
		RunEligibility.REGISTRY_INVALID
	)


func test_new_run_requires_eligibility() -> void:
	var locked: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		_registry,
		PackedStringArray(),
		"class.thunder",
		"stage.jade_grove",
		"difficulty.standard",
		PackedStringArray(["mode.normal"]),
		"7"
	)
	assert_false(locked.is_valid())
	assert_eq(locked.error, "not eligible: " + RunEligibility.CLASS_LOCKED)
	assert_eq(locked.rules_hash, "")
	var granted: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		_registry,
		PackedStringArray(["unlock.thunder"]),
		"class.thunder",
		"stage.jade_grove",
		"difficulty.standard",
		PackedStringArray(["mode.normal"]),
		"7"
	)
	assert_true(granted.is_valid(), granted.error)
	var restored: RunRulesSnapshot = RunRulesSnapshot.create(
		_registry,
		"class.thunder",
		"stage.jade_grove",
		"difficulty.standard",
		PackedStringArray(["mode.normal"]),
		"7"
	)
	assert_eq(granted.rules_hash, restored.rules_hash, "eligibility is not part of rules_hash")


func test_rules_are_checked_before_eligibility() -> void:
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		_registry,
		PackedStringArray(),
		"class.thunder",
		"stage.jade_grove",
		"difficulty.standard",
		PackedStringArray(["mode.training", "mode.ascetic"]),
		"7"
	)
	assert_false(snapshot.is_valid())
	assert_string_contains(snapshot.error, "excludes")
