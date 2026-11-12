extends GutTest
## hip-rng-v1 parity with the Python reference (tools/content/hip_rng.py), GAP-PY-GD-PARITY.

const VECTORS: String = "res://tests/fixtures/rng_vectors.json"

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


func _int(value: Variant) -> int:
	var got: Variant = ContentRegistry.integral(value)
	assert_true(got != null, "non-integral vector value " + str(value))
	return got if got != null else -1


func _ints(values: Variant) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in (values as Array):
		out.append(_int(v))
	return out


func _rows(key: String) -> Array:
	var rows: Array = _data.get(key, [])
	assert_gt(rows.size(), 0, "vectors missing " + key)
	return rows


func _stream(seed_text: String, stream_name: String, cursor_text: String = "0") -> HipRng:
	var rng: HipRng = HipRng.create(seed_text, stream_name, cursor_text)
	assert_true(rng.is_valid(), rng.error)
	return rng


func test_vectors_header() -> void:
	assert_eq(str(_data.get("rng_policy_id")), HipRng.POLICY_ID)
	assert_eq(_int(_data.get("schema_version")), 1)


func test_threefry_known_answers() -> void:
	for kat: Variant in _rows("threefry_kat"):
		var row: Dictionary = kat
		var k: Array[int] = _ints(row["key"])
		var c: Array[int] = _ints(row["counter"])
		var out: PackedInt64Array = HipRng.threefry(k[0], k[1], c[0], c[1])
		assert_eq(Array(out), Array(_ints(row["output"])))


func test_stream_keys_and_first_words() -> void:
	for entry: Variant in _rows("streams"):
		var row: Dictionary = entry
		var rng: HipRng = _stream(str(row["seed"]), str(row["stream"]))
		var got: Array[int] = []
		for i: int in 16:
			got.append(rng.next_u32())
		assert_eq(got, _ints(row["next_u32"]), "stream %s/%s" % [row["seed"], row["stream"]])
		assert_eq(str(rng.cursor()), str(row["cursor_after"]))


func test_below_sequences() -> void:
	for entry: Variant in _rows("below"):
		var row: Dictionary = entry
		var n: int = _int(row["n"])
		var want: Array[int] = _ints(row["values"])
		var rng: HipRng = _stream(str(row["seed"]), str(row["stream"]))
		var got: Array[int] = []
		for i: int in want.size():
			got.append(rng.below(n))
		assert_eq(got, want, "below %s/%s n=%d" % [row["seed"], row["stream"], n])
		assert_eq(str(rng.cursor()), str(row["cursor_after"]))


func test_random_access_far_cursors() -> void:
	for entry: Variant in _rows("random_access"):
		var row: Dictionary = entry
		var rng: HipRng = _stream(str(row["seed"]), str(row["stream"]), str(row["cursor"]))
		var got: Array[int] = []
		for i: int in 4:
			got.append(rng.next_u32())
		assert_eq(got, _ints(row["next_u32"]), "random access %s@%s" % [row["seed"], row["cursor"]])
		assert_eq(str(rng.cursor()), str(row["cursor_after"]))


func test_save_restore_continues_identically() -> void:
	for entry: Variant in _rows("restore"):
		var row: Dictionary = entry
		var rng: HipRng = _stream(str(row["seed"]), str(row["stream"]))
		for i: int in _int(row["advance_next_u32"]):
			rng.next_u32()
		var saved: Dictionary = rng.save()
		assert_eq(saved, row["saved"] as Dictionary)
		var resumed: HipRng = HipRng.restore(str(row["stream"]), saved)
		assert_true(resumed.is_valid(), resumed.error)
		var got: Array[int] = []
		var uninterrupted: Array[int] = []
		for i: int in 8:
			got.append(resumed.next_u32())
			uninterrupted.append(rng.next_u32())
		assert_eq(got, _ints(row["next_u32_after_restore"]))
		assert_eq(uninterrupted, got)


func test_mixed_draws_with_restore() -> void:
	for entry: Variant in _rows("mixed"):
		var row: Dictionary = entry
		var stream_name: String = str(row["stream"])
		var rng: HipRng = _stream(str(row["seed"]), stream_name)
		var restore_after: int = _int(row["restore_after_step"])
		var steps: Array = row["steps"]
		for i: int in steps.size():
			if i == restore_after:
				rng = HipRng.restore(stream_name, rng.save())
			var step: Dictionary = steps[i]
			var value: int = rng.below(_int(step["n"])) if step["op"] == "below" else rng.next_u32()
			assert_eq(value, _int(step["value"]), "mixed step %d" % i)
			assert_eq(str(rng.cursor()), str(step["cursor_after"]))


func test_parse_u64_is_canonical() -> void:
	for bad: String in ["", "00", "01", "+1", "-1", "1 ", "1e3", "18446744073709551616",
			"99999999999999999999", "111111111111111111111"]:
		assert_true(HipRng.parse_u64(bad).is_empty(), "must reject '%s'" % bad)
	assert_eq(Array(HipRng.parse_u64("18446744073709551615")), [HipRng.MASK32, HipRng.MASK32])
	assert_eq(Array(HipRng.parse_u64("9223372036854775808")), [0x80000000, 0])
	assert_eq(Array(HipRng.parse_u64("0")), [0, 0])


func test_invalid_inputs_fail_closed() -> void:
	assert_false(HipRng.create("01", "drops").is_valid())
	assert_false(HipRng.create("1", "Drops").is_valid())
	assert_false(HipRng.create("1", "toolongname").is_valid())
	assert_false(HipRng.create("1", "drops", "9223372036854775808").is_valid())
	assert_false(HipRng.restore("drops", {"seed": "1"}).is_valid())
	assert_false(HipRng.restore("drops", {"seed": "1", "cursor": 0}).is_valid())
	var invalid: HipRng = HipRng.create("x", "drops")
	assert_eq(invalid.next_u32(), -1)
	assert_false(HipRng.new().is_valid(), "unbuilt stream must not be valid")
	assert_eq(HipRng.new().next_u32(), -1)
	var rng: HipRng = _stream("1", "drops")
	assert_eq(rng.below(0), -1)
	assert_eq(rng.below(HipRng.BELOW_MAX + 1), -1)
	assert_eq(rng.cursor(), 0, "invalid n consumes nothing")
	assert_true(rng.is_valid(), "invalid n does not poison the stream")
	var last: HipRng = _stream("1", "drops", str(HipRng.CURSOR_MAX))
	assert_eq(last.next_u32(), -1)
	assert_string_contains(last.error, "exhausted")


func test_below_one_consumes_a_word() -> void:
	var rng: HipRng = _stream("7", "stage")
	assert_eq(rng.below(1), 0)
	assert_eq(rng.cursor(), 1)


func _saved_streams(seed_text: String, advance: int) -> Dictionary:
	var saved: Dictionary = {}
	var streams: Dictionary = HipRng.new_run_streams(seed_text)
	for stream_name: String in HipRng.STREAMS:
		var rng: HipRng = streams[stream_name]
		for i: int in advance:
			rng.next_u32()
		saved[stream_name] = rng.save()
	return saved


func test_restore_run_streams_accepts_exact_set() -> void:
	var saved: Dictionary = _saved_streams("77", 5)
	var restored: Dictionary = HipRng.restore_run_streams("77", saved)
	assert_eq(restored.size(), HipRng.STREAMS.size())
	var offers: HipRng = restored["offers"]
	assert_eq(offers.cursor(), 5)
	var fresh: HipRng = _stream("77", "offers", "5")
	assert_eq(offers.next_u32(), fresh.next_u32())


func test_restore_run_streams_rejects_foreign_missing_or_unknown() -> void:
	var saved: Dictionary = _saved_streams("77", 1)
	assert_eq(HipRng.restore_run_streams("78", saved), {}, "foreign run seed")
	var missing: Dictionary = saved.duplicate()
	missing.erase("stage")
	assert_eq(HipRng.restore_run_streams("77", missing), {}, "missing stream")
	var unknown: Dictionary = missing.duplicate()
	unknown["bonus"] = {"seed": "77", "cursor": "0"}
	assert_eq(HipRng.restore_run_streams("77", unknown), {}, "unknown stream")
	var mixed: Dictionary = saved.duplicate()
	mixed["enemy"] = {"seed": "78", "cursor": "0"}
	assert_eq(HipRng.restore_run_streams("77", mixed), {}, "stream seed differs from run seed")
	assert_eq(HipRng.restore_run_streams("bad", saved), {}, "invalid run seed")
	assert_eq(HipRng.new_run_streams("bad"), {})


func test_run_streams_are_independent() -> void:
	var streams: Dictionary = HipRng.new_run_streams("42")
	assert_eq(PackedStringArray(streams.keys()), HipRng.STREAMS)
	var drops: HipRng = streams["drops"]
	var enemy: HipRng = streams["enemy"]
	assert_ne(drops.next_u32(), enemy.next_u32())
