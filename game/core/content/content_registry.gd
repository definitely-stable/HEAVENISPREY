class_name ContentRegistry
extends RefCounted
## Read-only runtime view of the generated v7 content catalog (IC-01, ADR-007).
##
## Loads `registry.json` + `manifest.json` produced by tools/content/generate_registry.py.
## The content digest is SHA-256 over the exact file bytes, verified here with
## HashingContext before parsing; JSON is never re-serialized for hashing.
## Fail-closed: validity is positive (set only at the end of a complete load), so a
## runtime script error mid-load can never yield a "valid" empty registry. After the
## digest check the whole catalog tree is read-only.

const DEFAULT_DIR: String = "res://content/generated"
const REGISTRY_FILE: String = "registry.json"
const MANIFEST_FILE: String = "manifest.json"
const DIGEST_POLICY: String = "hip-canonical-json-v1"
const REGISTRY_SCHEMA_VERSION: int = 1
const MANIFEST_SCHEMA_VERSION: int = 1
const SOURCE_SCHEMA_VERSION: int = 2
## Largest integer a JSON double carries exactly (2^53 - 1); the generator enforces it too.
## Kept as int: GDScript's lexer rounds large float literals, float(int) is exact here.
const MAX_SAFE_INTEGER: int = 9007199254740991

var error: String = ""
var content_digest: String = ""
var _ok: bool = false
var _catalogs: Dictionary = {}
var _definitions: Dictionary = {}
var _ids_by_catalog: Dictionary = {}


func is_valid() -> bool:
	return _ok and error.is_empty()


static func load_dir(dir: String = DEFAULT_DIR) -> ContentRegistry:
	var registry_bytes: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(REGISTRY_FILE))
	var manifest_bytes: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(MANIFEST_FILE))
	return from_bytes(registry_bytes, manifest_bytes)


static func from_bytes(registry_bytes: PackedByteArray, manifest_bytes: PackedByteArray) -> ContentRegistry:
	var result: ContentRegistry = ContentRegistry.new()
	result._load(registry_bytes, manifest_bytes)
	if not result._ok and result.error.is_empty():
		result.error = "content load aborted before completion"
	if not result.is_valid():
		result._ok = false
		result._catalogs.clear()
		result._definitions.clear()
		result._ids_by_catalog.clear()
		result.content_digest = ""
	return result


static func sha256_hex(data: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


static func _text_is(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


## Containers parsed from JSON become read-only, recursively.
static func _freeze(value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		for key: Variant in dict:
			_freeze(dict[key])
		dict.make_read_only()
	elif typeof(value) == TYPE_ARRAY:
		var array: Array = value
		for item: Variant in array:
			_freeze(item)
		array.make_read_only()


## Returns int for an integral JSON number (Godot parses all numbers as float), else null.
static func integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var number: float = value
	if is_finite(number) and absf(number) <= float(MAX_SAFE_INTEGER) and number == floorf(number):
		return int(number)
	return null


func catalog_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(_catalogs.keys())
	names.sort()
	return names


## Full source object of one catalog (stem of the v7 file), read-only; empty when unknown.
func catalog(stem: String) -> Dictionary:
	return _catalogs.get(stem, {})


func ids(stem: String) -> PackedStringArray:
	var found: PackedStringArray = _ids_by_catalog.get(stem, PackedStringArray())
	return found.duplicate()


func has_definition(id: String) -> bool:
	return _definitions.has(id)


## Definition by globally unique ID, read-only; empty Dictionary when unknown.
func definition(id: String) -> Dictionary:
	return _definitions.get(id, {})


func definition_count() -> int:
	return _definitions.size()


func _fail(message: String) -> void:
	if error.is_empty():
		error = message


func _parse_object(data: PackedByteArray, label: String) -> Dictionary:
	if data.is_empty():
		_fail(label + ": missing or empty")
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(data.get_string_from_utf8()) != OK:
		_fail("%s: JSON parse error at line %d: %s" % [label, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		_fail(label + ": root must be an object")
		return {}
	return parser.data


func _load(registry_bytes: PackedByteArray, manifest_bytes: PackedByteArray) -> void:
	var manifest: Dictionary = _parse_object(manifest_bytes, MANIFEST_FILE)
	if not error.is_empty():
		return
	if integral(manifest.get("schema_version")) != MANIFEST_SCHEMA_VERSION:
		_fail("manifest schema_version unsupported")
	elif not _text_is(manifest.get("kind"), "content-registry-manifest"):
		_fail("manifest kind unsupported")
	elif not _text_is(manifest.get("digest_policy"), DIGEST_POLICY):
		_fail("manifest digest_policy unsupported")
	elif integral(manifest.get("registry_bytes")) != registry_bytes.size():
		_fail("registry byte length differs from manifest")
	if not error.is_empty():
		return
	var actual: String = sha256_hex(registry_bytes)
	if not _text_is(manifest.get("registry_sha256"), actual):
		_fail("content digest mismatch: registry.json is stale or edited by hand")
		return
	var registry: Dictionary = _parse_object(registry_bytes, REGISTRY_FILE)
	if not error.is_empty():
		return
	if integral(registry.get("registry_schema_version")) != REGISTRY_SCHEMA_VERSION:
		_fail("registry_schema_version unsupported")
		return
	if not _text_is(registry.get("digest_policy"), DIGEST_POLICY):
		_fail("registry digest_policy unsupported")
		return
	var catalogs: Variant = registry.get("catalogs")
	var index: Variant = registry.get("index")
	if typeof(catalogs) != TYPE_DICTIONARY or typeof(index) != TYPE_DICTIONARY:
		_fail("registry needs catalogs and index objects")
		return
	_index_catalogs(catalogs, index)
	if error.is_empty() and _definitions.size() != integral(manifest.get("definition_count")):
		_fail("definition count differs from manifest")
	if error.is_empty():
		_freeze(_catalogs)
		_freeze(_definitions)
		content_digest = actual
		_ok = true


func _index_catalogs(catalogs: Dictionary, index: Dictionary) -> void:
	for stem: Variant in catalogs:
		var source: Variant = catalogs[stem]
		if typeof(stem) != TYPE_STRING or typeof(source) != TYPE_DICTIONARY:
			_fail("catalog entries must be objects keyed by name")
			return
		var source_dict: Dictionary = source
		if integral(source_dict.get("schema_version")) != SOURCE_SCHEMA_VERSION:
			_fail("catalog %s: schema_version unsupported" % stem)
			return
		_catalogs[stem] = source_dict
	for stem: Variant in index:
		var list_key: Variant = index[stem]
		if not _catalogs.has(stem) or typeof(list_key) != TYPE_STRING:
			_fail("index references unknown catalog %s" % str(stem))
			return
		var source_dict: Dictionary = _catalogs[stem]
		var items: Variant = source_dict.get(list_key)
		if typeof(items) != TYPE_ARRAY:
			_fail("catalog %s: definition list %s missing" % [stem, list_key])
			return
		var catalog_ids: PackedStringArray = PackedStringArray()
		for item: Variant in items:
			if typeof(item) != TYPE_DICTIONARY:
				_fail("catalog %s: definition must be an object" % stem)
				return
			var item_dict: Dictionary = item
			var id: Variant = item_dict.get("id")
			if typeof(id) != TYPE_STRING or str(id).is_empty():
				_fail("catalog %s: definition id must be nonblank text" % stem)
				return
			if _definitions.has(id):
				_fail("duplicate definition id " + str(id))
				return
			_definitions[id] = item_dict
			catalog_ids.append(id)
		_ids_by_catalog[stem] = catalog_ids
