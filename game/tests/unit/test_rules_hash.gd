extends GutTest
## hip-rules-hash-v1 parity with tools/content/rules_identity.py and IC-02 RunRulesSnapshot.

const VECTORS: String = "res://tests/fixtures/rules_hash_vectors.json"

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


func _modes(input: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if typeof(input.get("mode_ids")) != TYPE_ARRAY:
		out.append("<not a list>")
		return out
	for m: Variant in (input["mode_ids"] as Array):
		out.append(str(m))
	return out


func _preimage(input: Dictionary) -> PackedByteArray:
	var version: Variant = ContentRegistry.integral(input.get("sim_schema_version"))
	if version == null:
		return PackedByteArray()
	return RulesHash.preimage(version, str(input.get("content_digest")), str(input.get("rng_policy_id")),
		str(input.get("stage_id")), str(input.get("difficulty_id")), _modes(input),
		str(input.get("class_id")), str(input.get("seed")))


func test_vectors_header() -> void:
	assert_eq(str(_data.get("domain_prefix")), RulesHash.DOMAIN_PREFIX)


func test_valid_cases_match_python_preimage_and_hash() -> void:
	var cases: Array = _data.get("cases", [])
	assert_gt(cases.size(), 0)
	for entry: Variant in cases:
		var row: Dictionary = entry
		var data: PackedByteArray = _preimage(row["input"])
		assert_eq(data.hex_encode(), str(row["preimage_hex"]), "preimage " + str(row["name"]))
		assert_eq(ContentRegistry.sha256_hex(data), str(row["rules_hash"]), "hash " + str(row["name"]))


func test_invalid_cases_are_rejected() -> void:
	var invalid: Array = _data.get("invalid", [])
	assert_gt(invalid.size(), 0)
	for entry: Variant in invalid:
		var row: Dictionary = entry
		assert_true(_preimage(row["input"]).is_empty(), "must reject " + str(row["name"]))


func test_snapshot_binds_registry_digest() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create(registry, "class.sword", "stage.jade_grove",
		"difficulty.standard", PackedStringArray(["mode.normal"]), "123")
	assert_true(snapshot.is_valid(), snapshot.error)
	assert_eq(snapshot.content_digest, registry.content_digest)
	var expected: String = RulesHash.compute(RunRulesSnapshot.SIM_SCHEMA_VERSION, registry.content_digest,
		HipRng.POLICY_ID, "stage.jade_grove", "difficulty.standard", PackedStringArray(["mode.normal"]),
		"class.sword", "123")
	assert_eq(snapshot.rules_hash, expected)
	assert_eq(snapshot.rules_hash.length(), 64)


func test_snapshot_mode_order_does_not_change_hash() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var a: RunRulesSnapshot = RunRulesSnapshot.create(registry, "class.thunder", "stage.mist_cliffs",
		"difficulty.hard", PackedStringArray(["mode.hurry", "mode.ascetic"]), "9")
	var b: RunRulesSnapshot = RunRulesSnapshot.create(registry, "class.thunder", "stage.mist_cliffs",
		"difficulty.hard", PackedStringArray(["mode.ascetic", "mode.hurry"]), "9")
	assert_true(a.is_valid(), a.error)
	assert_eq(a.rules_hash, b.rules_hash)
	var other_seed: RunRulesSnapshot = RunRulesSnapshot.create(registry, "class.thunder", "stage.mist_cliffs",
		"difficulty.hard", PackedStringArray(["mode.hurry", "mode.ascetic"]), "10")
	assert_ne(a.rules_hash, other_seed.rules_hash)


func test_snapshot_rejects_unknown_or_incompatible_rules() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var cases: Array = [
		["class.unknown", "stage.jade_grove", "difficulty.standard", ["mode.normal"], "1", "unknown class"],
		["class.sword", "stage.unknown", "difficulty.standard", ["mode.normal"], "1", "unknown stage"],
		["class.sword", "stage.jade_grove", "difficulty.unknown", ["mode.normal"], "1", "unknown difficulty"],
		["class.sword", "stage.jade_grove", "difficulty.standard", ["mode.frenzy"], "1", "unknown mode"],
		["class.sword", "stage.jade_grove", "difficulty.standard", ["mode.normal", "mode.normal"], "1", "duplicate mode"],
		["class.sword", "stage.jade_grove", "difficulty.standard", ["mode.training", "mode.ascetic"], "1", "excludes"],
		["class.sword", "stage.jade_grove", "difficulty.standard", ["mode.normal"], "01", "seed"],
		["skill.spirit_sword", "stage.jade_grove", "difficulty.standard", [], "1", "unknown class"],
	]
	for c: Variant in cases:
		var row: Array = c
		var snapshot: RunRulesSnapshot = RunRulesSnapshot.create(registry, row[0], row[1], row[2],
			PackedStringArray(row[3] as Array), row[4])
		assert_false(snapshot.is_valid(), "must reject " + str(row))
		assert_string_contains(snapshot.error, str(row[5]))
		assert_eq(snapshot.rules_hash, "")


func test_trailing_newline_ids_are_rejected() -> void:
	assert_false(RulesHash.is_content_id("class.sword\n"))
	assert_true(RulesHash.is_content_id("class.sword"))
	assert_eq(RulesHash.compute(1, "0".repeat(64), "hip-rng-v1\n", "stage.a", "difficulty.b",
		PackedStringArray(), "class.c", "1"), "")


func test_unbuilt_snapshot_is_not_valid() -> void:
	assert_false(RunRulesSnapshot.new().is_valid())


func test_snapshot_requires_valid_registry() -> void:
	var broken: ContentRegistry = ContentRegistry.from_bytes(PackedByteArray(), PackedByteArray())
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create(broken, "class.sword", "stage.jade_grove",
		"difficulty.standard", PackedStringArray(), "1")
	assert_false(snapshot.is_valid())
	assert_eq(snapshot.rules_hash, "")
