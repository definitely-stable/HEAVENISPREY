class_name RunRulesSnapshot
extends RefCounted
## IC-02: immutable rules of one run (class/stage/difficulty/modes/seed + algorithm versions).
##
## Built only from a valid ContentRegistry; unknown or incompatible IDs are an error,
## never a fallback. `rules_hash` binds the run to content_digest and algorithm versions
## (encoding: ADR-007, reference tools/content/rules_identity.py). Changes only with a new run.

const SIM_SCHEMA_VERSION: int = 1

var error: String = ""
var _ok: bool = false
var content_digest: String = ""
var class_id: String = ""
var stage_id: String = ""
var difficulty_id: String = ""
var mode_ids: PackedStringArray = PackedStringArray()
## Run seed as canonical uint64 decimal string (save contract shape).
var run_seed: String = ""
var rules_hash: String = ""


## Validity is positive: set only when the whole build succeeded (a script error mid-build
## can never produce a valid snapshot). RunRulesSnapshot.new() is not valid.
func is_valid() -> bool:
	return _ok and error.is_empty()


static func create(registry: ContentRegistry, p_class_id: String, p_stage_id: String,
		p_difficulty_id: String, p_mode_ids: PackedStringArray, p_seed: String) -> RunRulesSnapshot:
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.new()
	snapshot._build(registry, p_class_id, p_stage_id, p_difficulty_id, p_mode_ids, p_seed)
	if not snapshot._ok and snapshot.error.is_empty():
		snapshot.error = "rules snapshot build aborted before completion"
	if not snapshot.is_valid():
		snapshot._ok = false
		snapshot.rules_hash = ""
	return snapshot


func _fail(message: String) -> void:
	if error.is_empty():
		error = message


func _known(registry: ContentRegistry, catalog: String, id: String) -> bool:
	return registry.ids(catalog).has(id)


## Array field of a definition; anything else (missing, null, wrong type) is an empty list.
static func _list(definition: Dictionary, key: String) -> Array:
	var value: Variant = definition.get(key)
	return value if typeof(value) == TYPE_ARRAY else []


func _build(registry: ContentRegistry, p_class_id: String, p_stage_id: String,
		p_difficulty_id: String, p_mode_ids: PackedStringArray, p_seed: String) -> void:
	if registry == null or not registry.is_valid():
		_fail("content registry invalid")
		return
	if HipRng.parse_u64(p_seed).is_empty():
		_fail("seed must be a canonical uint64 decimal string")
		return
	if not _known(registry, "classes", p_class_id):
		_fail("unknown class " + p_class_id)
		return
	if not _known(registry, "stages", p_stage_id):
		_fail("unknown stage " + p_stage_id)
		return
	if not _known(registry, "difficulty_profiles", p_difficulty_id):
		_fail("unknown difficulty " + p_difficulty_id)
		return
	var stage: Dictionary = registry.definition(p_stage_id)
	if not _list(stage, "allowed_class_ids").has(p_class_id):
		_fail("class %s not allowed on %s" % [p_class_id, p_stage_id])
		return
	if not _list(stage, "supported_difficulties").has(p_difficulty_id):
		_fail("difficulty %s not supported on %s" % [p_difficulty_id, p_stage_id])
		return
	var sorted_modes: PackedStringArray = p_mode_ids.duplicate()
	sorted_modes.sort()
	for i: int in sorted_modes.size():
		var mode_id: String = sorted_modes[i]
		if i > 0 and sorted_modes[i - 1] == mode_id:
			_fail("duplicate mode " + mode_id)
			return
		if not _known(registry, "modes", mode_id):
			_fail("unknown mode " + mode_id)
			return
		if not _list(stage, "allowed_modes").has(mode_id):
			_fail("mode %s not allowed on %s" % [mode_id, p_stage_id])
			return
	for mode_id: String in sorted_modes:
		for other: Variant in _list(registry.definition(mode_id), "excludes"):
			if sorted_modes.has(str(other)):
				_fail("mode %s excludes %s" % [mode_id, str(other)])
				return
	content_digest = registry.content_digest
	class_id = p_class_id
	stage_id = p_stage_id
	difficulty_id = p_difficulty_id
	mode_ids = sorted_modes
	run_seed = p_seed
	rules_hash = RulesHash.compute(SIM_SCHEMA_VERSION, content_digest, HipRng.POLICY_ID,
		stage_id, difficulty_id, mode_ids, class_id, run_seed)
	if rules_hash.is_empty():
		_fail("rules hash rejected an input field")
		return
	_ok = true
