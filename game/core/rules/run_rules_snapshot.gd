class_name RunRulesSnapshot
extends RefCounted
## IC-02: immutable rules of one run (class/stage/difficulty/modes/seed + algorithm versions).
##
## Built only from a valid ContentRegistry; unknown or incompatible IDs are an error,
## never a fallback. `rules_hash` binds the run to content_digest and algorithm versions
## (encoding: ADR-007, reference tools/content/rules_identity.py). Changes only with a new run.
##
## Immutability: every public field is a read-only property. A write attempt is ignored and
## permanently invalidates the snapshot (fail-closed, `rules_hash` becomes ""), so a mutated
## snapshot can never be saved or settled. `is_valid()` also recomputes the hash from the
## stored fields, which catches writes to the private backing fields.
##
## Two entry points (IC-02):
## - `create_for_new_run` — authoritative start of a NEW run: rules validity + profile
##   eligibility (RunEligibility). The only way a run may begin.
## - `create` — rules validity only; rebuilds the snapshot of an ALREADY authorized run
##   (save restore, replay). Never use it to start a new run.

## 2 since P0-01E: the simulation changes combat state (ADR-008 section e).
## 3 since P0-01F: enemy slots with uids, spawn ramp, hero skill and projectiles (ADR-009).
## 4: enemy separation (ADR-009 section 2).
## 5: XP gems, pickup and level progression (ADR-010).
## 6: level-up choices: command log schema 2, offers hand, upgrade ranks, projectile snapshot
##    (ADR-010 section 6).
## 7: victory after the stage duration, `won` in the state (ADR-011 section 1).
## 8: enemy attack states and instances, the attack table and status.venom (ADR-011 E2).
## 9: the enemy charge, a hit flag per enemy slot (ADR-011 E3).
## 10: enemy projectiles, the shot pool in the world digest, the 10-field attack record (ADR-011 E4).
## 11: death and ground zones, the zone pool and status.root_slow in the digest (ADR-011 E5).
const SIM_SCHEMA_VERSION: int = 11

var error: String:
	get:
		return _error
	set(_value):
		_reject_write("error")
var content_digest: String:
	get:
		return _content_digest
	set(_value):
		_reject_write("content_digest")
var class_id: String:
	get:
		return _class_id
	set(_value):
		_reject_write("class_id")
var stage_id: String:
	get:
		return _stage_id
	set(_value):
		_reject_write("stage_id")
var difficulty_id: String:
	get:
		return _difficulty_id
	set(_value):
		_reject_write("difficulty_id")
## Sorted, duplicate-free; the getter returns a copy, editing it never changes the snapshot.
var mode_ids: PackedStringArray:
	get:
		return _mode_ids.duplicate()
	set(_value):
		_reject_write("mode_ids")
## Run seed as canonical uint64 decimal string (save contract shape).
var run_seed: String:
	get:
		return _run_seed
	set(_value):
		_reject_write("run_seed")
var rules_hash: String:
	get:
		return _rules_hash if is_valid() else ""
	set(_value):
		_reject_write("rules_hash")

var _ok: bool = false
var _error: String = ""
var _content_digest: String = ""
var _class_id: String = ""
var _stage_id: String = ""
var _difficulty_id: String = ""
var _mode_ids: PackedStringArray = PackedStringArray()
var _run_seed: String = ""
var _rules_hash: String = ""


## Validity is positive: set only when the whole build succeeded (a script error mid-build
## can never produce a valid snapshot) and the stored fields still hash to `rules_hash`.
## RunRulesSnapshot.new() is not valid.
func is_valid() -> bool:
	return _ok and _error.is_empty() and _hash_of_fields() == _rules_hash


## Rules validity only. For save restore / replay of a run that was already authorized.
static func create(
	registry: ContentRegistry,
	p_class_id: String,
	p_stage_id: String,
	p_difficulty_id: String,
	p_mode_ids: PackedStringArray,
	p_seed: String
) -> RunRulesSnapshot:
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.new()
	snapshot._build(registry, p_class_id, p_stage_id, p_difficulty_id, p_mode_ids, p_seed)
	snapshot._seal()
	return snapshot


## Authoritative start of a new run: rules validity, then RunEligibility against the
## profile's granted unlock IDs. Ineligible input yields an invalid snapshot whose error
## starts with "not eligible: " followed by a RunEligibility reason code.
static func create_for_new_run(
	registry: ContentRegistry,
	granted_unlock_ids: PackedStringArray,
	p_class_id: String,
	p_stage_id: String,
	p_difficulty_id: String,
	p_mode_ids: PackedStringArray,
	p_seed: String
) -> RunRulesSnapshot:
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.new()
	snapshot._build(registry, p_class_id, p_stage_id, p_difficulty_id, p_mode_ids, p_seed)
	if snapshot._ok:
		var reason: String = RunEligibility.check(
			registry, granted_unlock_ids, p_class_id, p_difficulty_id, p_mode_ids
		)
		if reason != RunEligibility.OK:
			snapshot._ok = false
			snapshot._fail("not eligible: " + reason)
	snapshot._seal()
	return snapshot


func _seal() -> void:
	if not _ok and _error.is_empty():
		_error = "rules snapshot build aborted before completion"
	if not is_valid():
		_ok = false
		_rules_hash = ""


func _reject_write(field: String) -> void:
	_ok = false
	_rules_hash = ""
	_fail("rules snapshot is immutable: write to " + field)


func _hash_of_fields() -> String:
	return RulesHash.compute(
		SIM_SCHEMA_VERSION,
		_content_digest,
		HipRng.POLICY_ID,
		_stage_id,
		_difficulty_id,
		_mode_ids,
		_class_id,
		_run_seed
	)


func _fail(message: String) -> void:
	if _error.is_empty():
		_error = message


func _known(registry: ContentRegistry, catalog: String, id: String) -> bool:
	return registry.ids(catalog).has(id)


## Array field of a definition; anything else (missing, null, wrong type) is an empty list.
static func _list(definition: Dictionary, key: String) -> Array:
	var value: Variant = definition.get(key)
	return value if typeof(value) == TYPE_ARRAY else []


## First rule violation for the inputs, or "" when the rules are valid.
func _rules_violation(
	registry: ContentRegistry,
	p_class_id: String,
	p_stage_id: String,
	p_difficulty_id: String,
	sorted_modes: PackedStringArray,
	p_seed: String
) -> String:
	if registry == null or not registry.is_valid():
		return "content registry invalid"
	if HipRng.parse_u64(p_seed).is_empty():
		return "seed must be a canonical uint64 decimal string"
	if not _known(registry, "classes", p_class_id):
		return "unknown class " + p_class_id
	if not _known(registry, "stages", p_stage_id):
		return "unknown stage " + p_stage_id
	if not _known(registry, "difficulty_profiles", p_difficulty_id):
		return "unknown difficulty " + p_difficulty_id
	var stage: Dictionary = registry.definition(p_stage_id)
	if not _list(stage, "allowed_class_ids").has(p_class_id):
		return "class %s not allowed on %s" % [p_class_id, p_stage_id]
	if not _list(stage, "supported_difficulties").has(p_difficulty_id):
		return "difficulty %s not supported on %s" % [p_difficulty_id, p_stage_id]
	return _modes_violation(registry, stage, p_stage_id, sorted_modes)


func _modes_violation(
	registry: ContentRegistry, stage: Dictionary, p_stage_id: String, sorted_modes: PackedStringArray
) -> String:
	for i: int in sorted_modes.size():
		var mode_id: String = sorted_modes[i]
		if i > 0 and sorted_modes[i - 1] == mode_id:
			return "duplicate mode " + mode_id
		if not _known(registry, "modes", mode_id):
			return "unknown mode " + mode_id
		if not _list(stage, "allowed_modes").has(mode_id):
			return "mode %s not allowed on %s" % [mode_id, p_stage_id]
	for mode_id: String in sorted_modes:
		for other: Variant in _list(registry.definition(mode_id), "excludes"):
			if sorted_modes.has(str(other)):
				return "mode %s excludes %s" % [mode_id, str(other)]
	return ""


func _build(
	registry: ContentRegistry,
	p_class_id: String,
	p_stage_id: String,
	p_difficulty_id: String,
	p_mode_ids: PackedStringArray,
	p_seed: String
) -> void:
	var sorted_modes: PackedStringArray = p_mode_ids.duplicate()
	sorted_modes.sort()
	var violation: String = _rules_violation(
		registry, p_class_id, p_stage_id, p_difficulty_id, sorted_modes, p_seed
	)
	if not violation.is_empty():
		_fail(violation)
		return
	_content_digest = registry.content_digest
	_class_id = p_class_id
	_stage_id = p_stage_id
	_difficulty_id = p_difficulty_id
	_mode_ids = sorted_modes
	_run_seed = p_seed
	_rules_hash = _hash_of_fields()
	if _rules_hash.is_empty():
		_fail("rules hash rejected an input field")
		return
	_ok = true
