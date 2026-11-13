extends GutTest
## hip-fx-v1 parity with tools/content/fx.py (ADR-008): every op returns the same int.

const VECTORS: String = "res://tests/fixtures/fx_vectors.json"

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


static func _ints(values: Array) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for value: Variant in values:
		out.append(str(value).to_int())
	return out


static func _call(op: String, a: PackedInt64Array) -> PackedInt64Array:
	match op:
		"floor_div":
			return PackedInt64Array([Fx.floor_div(a[0], a[1])])
		"floor_mod":
			return PackedInt64Array([Fx.floor_mod(a[0], a[1])])
		"mul":
			return PackedInt64Array([Fx.mul(a[0], a[1])])
		"mul_sym":
			return PackedInt64Array([Fx.mul_sym(a[0], a[1])])
		"mul_q14":
			return PackedInt64Array([Fx.mul_q14(a[0], a[1])])
		"div":
			return PackedInt64Array([Fx.div(a[0], a[1])])
		"mul_hp":
			return PackedInt64Array([Fx.mul_hp(a[0], a[1])])
		"clamp_coord":
			return PackedInt64Array([Fx.clamp_coord(a[0])])
		"isqrt":
			return PackedInt64Array([Fx.isqrt(a[0])])
		"normalize_q14":
			return Fx.normalize_q14(a[0], a[1])
		"sin_q14":
			return PackedInt64Array([Fx.sin_q14(a[0])])
		"cos_q14":
			return PackedInt64Array([Fx.cos_q14(a[0])])
		"seconds_to_ticks":
			return PackedInt64Array([Fx.seconds_to_ticks(a[0])])
		"period_mt":
			return PackedInt64Array([Fx.period_mt(a[0])])
		"speed_to_su_per_tick":
			return PackedInt64Array([Fx.speed_to_su_per_tick(a[0])])
		"period_step":
			return Fx.period_step(a[0], a[1], a[2])
	return PackedInt64Array([-1, -1, -1])


func test_vectors_header() -> void:
	assert_eq(str(_data.get("policy_id")), Fx.POLICY_ID)


func test_decimal_string_parsing_is_exact() -> void:
	assert_eq("-9223372036854775808".to_int(), -9223372036854775807 - 1)
	assert_eq("4611686018427387904".to_int(), Fx.PRODUCT_LIMIT)


func test_ops_match_python_reference() -> void:
	var ops: Array = _data.get("ops", [])
	assert_gt(ops.size(), 1000)
	var failures: int = 0
	for entry: Variant in ops:
		var row: Dictionary = entry
		var op: String = str(row["op"])
		var got: PackedInt64Array = _call(op, _ints(row["args"]))
		var expected: PackedInt64Array = _ints(row["expected"])
		if got != expected:
			failures += 1
			if failures <= 20:
				fail_test("%s%s: got %s, expected %s" % [op, str(row["args"]), str(got), str(expected)])
	assert_eq(failures, 0, "mismatching ops")


func test_sin_table_digest() -> void:
	var text: PackedStringArray = PackedStringArray()
	for value: int in FxTables.SIN_Q14_QUARTER:
		text.append(str(value))
	assert_eq(FxTables.SIN_Q14_QUARTER.size(), Fx.SIN_QUARTER + 1)
	var digest: String = ContentRegistry.sha256_hex(",".join(text).to_ascii_buffer())
	assert_eq(digest, str(_data.get("sin_table_sha256")))


func test_from_catalog_matches_every_registry_number() -> void:
	var rows: Array = _data.get("from_catalog", [])
	assert_gt(rows.size(), 0)
	for entry: Variant in rows:
		var row: Dictionary = entry
		assert_eq(Fx.from_catalog(row["value"]), str(row["expected"]).to_int(), str(row["value"]))


func test_from_catalog_rejects_unrepresentable() -> void:
	for text: Variant in _data.get("from_catalog_rejected", []):
		assert_null(Fx.from_catalog(str(text).to_float()), "must reject " + str(text))
	assert_null(Fx.from_catalog("1.5"))
	assert_null(Fx.from_catalog(INF))
	assert_null(Fx.from_catalog(NAN))
	assert_null(Fx.from_catalog(true))


func test_symmetry_and_saturation_properties() -> void:
	assert_eq(Fx.mul_sym(-3, 333), -Fx.mul_sym(3, 333))
	assert_eq(Fx.mul(Fx.PRODUCT_LIMIT, Fx.PRODUCT_LIMIT), Fx.floor_div(Fx.PRODUCT_LIMIT, 1000))
	assert_eq(Fx.mul_hp(Fx.HP_MAX, Fx.MULT_MAX), Fx.HP_MAX)
	var n: PackedInt64Array = Fx.normalize_q14(-1, 1)
	assert_eq(n[0], -n[1])
	assert_eq(Fx.normalize_q14(0, 0), PackedInt64Array([0, 0]))
