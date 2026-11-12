class_name RulesHash
extends RefCounted
## `hip-rules-hash-v1` (ADR-007 §d): SHA-256 over a length-prefixed byte preimage, not JSON.
##
## Exact port of tools/content/rules_identity.py; vectors in
## res://tests/fixtures/rules_hash_vectors.json. Inputs are validated *before*
## to_ascii_buffer() (which would silently mangle non-ASCII); invalid input yields "".

const DOMAIN_PREFIX: String = "HEAVENISPREY/RULES-HASH/v1"
const U32_MAX: int = 0xFFFFFFFF

static var _id_re: RegEx
static var _policy_re: RegEx
static var _digest_re: RegEx


## Whole-string match like Python re.fullmatch: \A...\z. PCRE2 `$` would also match
## before a final newline, which the reference rejects.
static func _full(pattern: String) -> RegEx:
	var re: RegEx = RegEx.new()
	re.compile("\\A(?:" + pattern + ")\\z")
	return re


static func _ensure_patterns() -> void:
	if _id_re == null:
		_id_re = _full("[a-z0-9_]+(\\.[a-z0-9_]+)+")
		_policy_re = _full("[a-z0-9]+(-[a-z0-9]+)*")
		_digest_re = _full("[0-9a-f]{64}")


static func is_content_id(text: String) -> bool:
	_ensure_patterns()
	return _id_re.search(text) != null


static func _u32be(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


static func _field(text: String) -> PackedByteArray:
	var data: PackedByteArray = text.to_ascii_buffer()
	var out: PackedByteArray = _u32be(data.size())
	out.append_array(data)
	return out


## Exact preimage bytes, or an empty array when any field is invalid.
static func preimage(sim_schema_version: int, content_digest: String, rng_policy_id: String,
		stage_id: String, difficulty_id: String, mode_ids: PackedStringArray, class_id: String,
		run_seed: String) -> PackedByteArray:
	_ensure_patterns()
	if sim_schema_version < 0 or sim_schema_version > U32_MAX:
		return PackedByteArray()
	if _digest_re.search(content_digest) == null or _policy_re.search(rng_policy_id) == null:
		return PackedByteArray()
	for id: String in [stage_id, difficulty_id, class_id]:
		if not is_content_id(id):
			return PackedByteArray()
	var ordered: PackedStringArray = mode_ids.duplicate()
	ordered.sort()
	for i: int in ordered.size():
		if not is_content_id(ordered[i]) or (i > 0 and ordered[i] == ordered[i - 1]):
			return PackedByteArray()
	if HipRng.parse_u64(run_seed).is_empty():
		return PackedByteArray()
	var out: PackedByteArray = DOMAIN_PREFIX.to_ascii_buffer()
	out.append(0)
	out.append_array(_field(str(sim_schema_version)))
	out.append_array(_field(content_digest))
	out.append_array(_field(rng_policy_id))
	out.append_array(_field(stage_id))
	out.append_array(_field(difficulty_id))
	out.append_array(_u32be(ordered.size()))
	for mode_id: String in ordered:
		out.append_array(_field(mode_id))
	out.append_array(_field(class_id))
	out.append_array(_field(run_seed))
	return out


## Lowercase hex SHA-256 of the preimage, or "" when any field is invalid.
static func compute(sim_schema_version: int, content_digest: String, rng_policy_id: String,
		stage_id: String, difficulty_id: String, mode_ids: PackedStringArray, class_id: String,
		run_seed: String) -> String:
	var data: PackedByteArray = preimage(sim_schema_version, content_digest, rng_policy_id,
		stage_id, difficulty_id, mode_ids, class_id, run_seed)
	if data.is_empty():
		return ""
	return ContentRegistry.sha256_hex(data)
