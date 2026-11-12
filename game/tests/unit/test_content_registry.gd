extends GutTest
## IC-01 ContentRegistry: Python generator <-> Godot loader digest parity (GAP-REGISTRY-GEN).

const DIR: String = ContentRegistry.DEFAULT_DIR


func _bytes(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(DIR.path_join(name))


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_bytes(ContentRegistry.MANIFEST_FILE).get_string_from_utf8())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func test_loads_generated_registry() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	assert_true(registry.is_valid(), "load error: " + registry.error)
	assert_gt(registry.definition_count(), 0)


func test_content_digest_matches_python_manifest() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var manifest: Dictionary = _manifest()
	assert_eq(registry.content_digest, str(manifest.get("registry_sha256")))
	assert_eq(registry.content_digest.length(), 64)
	assert_eq(registry.definition_count(), ContentRegistry.integral(manifest.get("definition_count")))


func test_known_definitions_and_cross_references() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var sword: Dictionary = registry.definition("class.sword")
	assert_eq(str(sword.get("start_skill_id")), "skill.spirit_sword")
	assert_true(registry.has_definition(str(sword.get("start_skill_id"))))
	var stage: Dictionary = registry.definition("stage.jade_grove")
	var difficulties: Array = stage.get("supported_difficulties", [])
	assert_gt(difficulties.size(), 0)
	for difficulty_id: Variant in difficulties:
		assert_true(registry.has_definition(str(difficulty_id)), "unknown " + str(difficulty_id))
	assert_true(registry.ids("enemies").has("enemy.ruined_jade_guardian"))
	assert_false(registry.ids("enemies").has("boss.jade_warden"), "boss must not alias ordinary enemy")


func test_localization_is_not_content() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	assert_false(registry.catalog_names().has("localization_context"))


func test_integral_numbers_recovered_from_json_floats() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var stage: Dictionary = registry.definition("stage.jade_grove")
	assert_eq(ContentRegistry.integral(stage.get("duration_minutes")), 5)
	assert_eq(ContentRegistry.integral(0.85), null)
	assert_eq(ContentRegistry.integral("5"), null)
	assert_eq(ContentRegistry.integral(INF), null)


func test_tampered_registry_is_rejected() -> void:
	var data: PackedByteArray = _bytes(ContentRegistry.REGISTRY_FILE)
	var index: int = data.find(ord("5"))
	assert_gt(index, 0)
	data[index] = ord("6")
	var registry: ContentRegistry = ContentRegistry.from_bytes(data, _bytes(ContentRegistry.MANIFEST_FILE))
	assert_false(registry.is_valid())
	assert_string_contains(registry.error, "digest mismatch")
	assert_eq(registry.definition_count(), 0)
	assert_eq(registry.content_digest, "")


func test_truncated_registry_is_rejected() -> void:
	var data: PackedByteArray = _bytes(ContentRegistry.REGISTRY_FILE)
	data.resize(data.size() - 1)
	var registry: ContentRegistry = ContentRegistry.from_bytes(data, _bytes(ContentRegistry.MANIFEST_FILE))
	assert_false(registry.is_valid())
	assert_string_contains(registry.error, "byte length")


func test_wrongly_typed_manifest_fields_fail_closed() -> void:
	var manifest: Dictionary = _manifest()
	for field: String in ["kind", "digest_policy", "registry_sha256"]:
		for bad: Variant in [5, [1], null]:
			var copy: Dictionary = manifest.duplicate()
			copy[field] = bad
			var registry: ContentRegistry = ContentRegistry.from_bytes(
				_bytes(ContentRegistry.REGISTRY_FILE), JSON.stringify(copy).to_utf8_buffer())
			assert_false(registry.is_valid(), "%s=%s must be rejected" % [field, str(bad)])
			assert_eq(registry.definition_count(), 0)


func test_unloaded_registry_is_not_valid() -> void:
	assert_false(ContentRegistry.new().is_valid())


func test_registry_cannot_be_mutated_by_consumers() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var ids: PackedStringArray = registry.ids("classes")
	ids.append("class.injected")
	assert_false(registry.ids("classes").has("class.injected"))
	var stage: Dictionary = registry.definition("stage.jade_grove")
	assert_true(stage.is_read_only())
	var allowed: Array = stage["allowed_class_ids"]
	assert_true(allowed.is_read_only())
	assert_true(registry.catalog("classes").is_read_only())


func test_integral_rejects_beyond_safe_range() -> void:
	var limit: int = ContentRegistry.MAX_SAFE_INTEGER
	assert_eq(ContentRegistry.integral(float(limit)), limit)
	assert_eq(ContentRegistry.integral(-float(limit)), -limit)
	assert_eq(ContentRegistry.integral(float(limit + 1)), null)
	assert_eq(ContentRegistry.integral(-float(limit + 1)), null)


func test_missing_manifest_is_rejected() -> void:
	var registry: ContentRegistry = ContentRegistry.from_bytes(_bytes(ContentRegistry.REGISTRY_FILE), PackedByteArray())
	assert_false(registry.is_valid())
	assert_eq(registry.definition_count(), 0)
