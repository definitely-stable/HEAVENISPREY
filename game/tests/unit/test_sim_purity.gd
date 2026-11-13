extends GutTest
## ADR-008 section e guard: res://core/sim stays integer-only (`hip-fx-v1`).
##
## Lines are preprocessed before matching: string literals become "", comments are
## removed and @warning_ignore lines are skipped. Each rule reports at most one entry
## per line, formatted "<1-based line>: <rule id>".

const SIM_ROOT: String = "res://core/sim"
const CLEAN_FIXTURE: String = "res://tests/fixtures/purity/clean.gd.txt"
const DIRTY_FIXTURE: String = "res://tests/fixtures/purity/dirty.gd.txt"
const WARNING_IGNORE: String = "@warning_ignore"

const DOUBLE_QUOTED: String = "\"(?:[^\"\\\\]|\\\\.)*\""
const SINGLE_QUOTED: String = "'(?:[^'\\\\]|\\\\.)*'"

const RULE_IDS: PackedStringArray = [
	"float_literal",
	"float_type",
	"vector2",
	"transform",
	"random",
	"libm",
	"untyped_math",
	"engine_time",
	"physics",
	"hash",
	"division",
	"modulo",
	"dictionary_iteration",
]

# [rule id, pattern, ...extra patterns]; order defines the report order within a line.
const RULES: Array = [
	["float_literal", "\\b\\d+\\.\\d*|\\b\\d+[eE][+-]?\\d+|(?<![\\w.])\\.\\d+"],
	["float_type", "\\bfloat\\b"],
	["vector2", "\\bVector2\\b", "\\bVector2i\\b"],
	["transform", "\\b(Transform2D|Rect2|Rect2i)\\b"],
	["random", "\\b(randf|randi|randf_range|randi_range|randomize|RandomNumberGenerator)\\b"],
	["libm", "\\b(sin|cos|tan|asin|acos|atan|atan2|sqrt|pow|exp|log|lerp|lerpf|round|floor|ceil|"
		+ "fmod|fposmod|snapped)\\s*\\("],
	["untyped_math", "\\b(min|max|abs|clamp|sign)\\s*\\("],
	["engine_time", "\\b(Time|OS|Engine|Input)\\s*\\.", "\\bdelta\\b"],
	["physics", "\\b(move_and_slide|move_and_collide|PhysicsServer2D|CharacterBody2D|RigidBody2D|Area2D)\\b"],
	["hash", "\\bhash\\s*\\("],
	["division", "(?<!/)/(?![/=])"],
	["modulo", "%(?!=)"],
	["dictionary_iteration", "\\bfor\\s+\\w+(\\s*:\\s*\\w+)?\\s+in\\s+\\w+\\.(keys|values)\\s*\\("],
]

static var _regex_cache: Dictionary = {}


## One entry per forbidden rule per line, in source order: "<line>: <rule id>".
static func violations(source: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = source.split("\n")
	for index: int in lines.size():
		var code: String = _scan_line(lines[index])
		if code.is_empty():
			continue
		for rule: Array in RULES:
			for pattern_index: int in range(1, rule.size()):
				var pattern: String = str(rule[pattern_index])
				if _regex(pattern).search(code) != null:
					found.append("%d: %s" % [index + 1, str(rule[0])])
					break
	return found


static func _scan_line(line: String) -> String:
	if line.strip_edges().begins_with(WARNING_IGNORE):
		return ""
	var code: String = _regex(DOUBLE_QUOTED).sub(line, "\"\"", true)
	code = _regex(SINGLE_QUOTED).sub(code, "\"\"", true)
	var comment: int = code.find("#")
	return code if comment < 0 else code.substr(0, comment)


static func _regex(pattern: String) -> RegEx:
	var cached: Variant = _regex_cache.get(pattern)
	if cached is RegEx:
		return cached as RegEx
	var compiled: RegEx = RegEx.new()
	compiled.compile(pattern)
	_regex_cache[pattern] = compiled
	return compiled


static func _gd_files(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(directory.path_join(file_name))
	for dir_name: String in dir.get_directories():
		found.append_array(_gd_files(directory.path_join(dir_name)))
	return found


static func _entries_for(found: PackedStringArray, lines: PackedInt32Array) -> PackedStringArray:
	var picked: PackedStringArray = PackedStringArray()
	for entry: String in found:
		if lines.has(entry.get_slice(": ", 0).to_int()):
			picked.append(entry)
	return picked


func test_clean_fixture_has_no_violations() -> void:
	var text: String = FileAccess.get_file_as_string(CLEAN_FIXTURE)
	assert_false(text.is_empty(), CLEAN_FIXTURE + " is empty")
	var found: PackedStringArray = violations(text)
	assert_eq(found, PackedStringArray(), "clean fixture violations: " + str(Array(found)))


func test_dirty_fixture_reports_every_rule() -> void:
	var text: String = FileAccess.get_file_as_string(DIRTY_FIXTURE)
	assert_false(text.is_empty(), DIRTY_FIXTURE + " is empty")
	var found: PackedStringArray = violations(text)
	var reported: Dictionary = {}
	for entry: String in found:
		reported[entry.get_slice(": ", 1)] = true
	for rule_id: String in RULE_IDS:
		assert_true(reported.has(rule_id), "%s missing from %s" % [rule_id, str(Array(found))])
	assert_eq(found, PackedStringArray([
		"2: float_literal",
		"3: float_type",
		"4: vector2",
		"5: transform",
		"6: random",
		"7: libm",
		"8: untyped_math",
		"9: engine_time",
		"10: physics",
		"11: hash",
		"12: division",
		"13: modulo",
		"14: dictionary_iteration",
	]), "dirty fixture must trigger every rule once")
	assert_eq(_entries_for(found, PackedInt32Array([2, 12, 13])), PackedStringArray([
		"2: float_literal", "12: division", "13: modulo"]), "exact violations on pinned lines")


func test_strings_and_comments_are_ignored() -> void:
	var quoted: String = 'var a: String = "1.5 / 2 % 3 sin(x)" # float 2.0 / 3'
	assert_eq(violations(quoted), PackedStringArray(), "strings and comments must be ignored")
	assert_eq(violations("var s: String = '1.5 / 2 % 3'"), PackedStringArray(),
		"single-quoted strings must be ignored")
	assert_eq(violations("var b: int = 7 / 2"), PackedStringArray(["1: division"]),
		"a bare slash must be reported")


func test_simulation_sources_are_integer_only() -> void:
	if not DirAccess.dir_exists_absolute(SIM_ROOT):
		pending("res://core/sim does not exist yet")
		return
	var files: PackedStringArray = _gd_files(SIM_ROOT)
	assert_gt(files.size(), 0, "no .gd files under " + SIM_ROOT)
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		var found: PackedStringArray = violations(text)
		assert_eq(found, PackedStringArray(), path + " violations: " + str(Array(found)))
