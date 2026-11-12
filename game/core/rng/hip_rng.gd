class_name HipRng
extends RefCounted
## `hip-rng-v1` (ADR-007 §c): counter-based Threefry-2x32-20 stream, one per named stream.
##
## The complete state is (run seed, stream name, cursor); restore from the save contract's
## {seed, cursor} is O(1). Exact port of tools/content/hip_rng.py; golden vectors in
## res://tests/fixtures/rng_vectors.json. Only signed int64 arithmetic with every
## intermediate below 2^62: no multiplication, no reliance on overflow wraparound.
## Not Godot's RandomNumberGenerator (its algorithm is not a stable contract).

const POLICY_ID: String = "hip-rng-v1"
## Registered streams of the policy; adding one needs an ADR-007 amendment and new vectors.
const STREAMS: PackedStringArray = ["drops", "enemy", "offers", "stage"]
const MASK32: int = 0xFFFFFFFF
const KS_PARITY: int = 0x1BD11BDA
## Cursor range is 0..2^63-1; next_u32 at the maximum is an error.
const CURSOR_MAX: int = 9223372036854775807
const BELOW_MAX: int = 4294967296
const STREAM_NAME_MAX_BYTES: int = 8

var error: String = ""
var _ok: bool = false
var _seed_text: String = ""
var _name: String = ""
var _k0: int = 0
var _k1: int = 0
var _cursor: int = 0
var _cached_block: int = -1
var _cached_x1: int = 0


## Only streams built by create()/restore() with valid input are valid; HipRng.new() is not.
func is_valid() -> bool:
	return _ok and error.is_empty()


## Canonical uint64 decimal -> [hi, lo] uint32 words; empty array when not canonical.
## Never exceeds int64: limbs stay below 2^36.
static func parse_u64(text: String) -> PackedInt64Array:
	var n: int = text.length()
	if n < 1 or n > 20 or (n > 1 and text.unicode_at(0) == 48):
		return PackedInt64Array()
	var hi: int = 0
	var lo: int = 0
	for i: int in n:
		var digit: int = text.unicode_at(i) - 48
		if digit < 0 or digit > 9:
			return PackedInt64Array()
		lo = lo * 10 + digit
		hi = hi * 10 + (lo >> 32)
		lo &= MASK32
		if hi > MASK32:
			return PackedInt64Array()
	return PackedInt64Array([hi, lo])


static func is_stream_name(stream_name: String) -> bool:
	if stream_name.is_empty() or stream_name.length() > STREAM_NAME_MAX_BYTES:
		return false
	for i: int in stream_name.length():
		var c: int = stream_name.unicode_at(i)
		var lower: bool = c >= 97 and c <= 122
		if i == 0 and not lower:
			return false
		if not (lower or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


## Threefry-2x32-20 block (Random123), rounds unrolled for speed. Returns [x0, x1].
static func threefry(k0: int, k1: int, c0: int, c1: int) -> PackedInt64Array:
	var k2: int = KS_PARITY ^ k0 ^ k1
	var x0: int = (c0 + k0) & MASK32
	var x1: int = (c1 + k1) & MASK32
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 13) & MASK32) | (x1 >> 19)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 15) & MASK32) | (x1 >> 17)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 26) & MASK32) | (x1 >> 6)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 6) & MASK32) | (x1 >> 26)) ^ x0
	x0 = (x0 + k1) & MASK32
	x1 = (x1 + k2 + 1) & MASK32
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 17) & MASK32) | (x1 >> 15)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 29) & MASK32) | (x1 >> 3)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 16) & MASK32) | (x1 >> 16)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 24) & MASK32) | (x1 >> 8)) ^ x0
	x0 = (x0 + k2) & MASK32
	x1 = (x1 + k0 + 2) & MASK32
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 13) & MASK32) | (x1 >> 19)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 15) & MASK32) | (x1 >> 17)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 26) & MASK32) | (x1 >> 6)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 6) & MASK32) | (x1 >> 26)) ^ x0
	x0 = (x0 + k0) & MASK32
	x1 = (x1 + k1 + 3) & MASK32
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 17) & MASK32) | (x1 >> 15)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 29) & MASK32) | (x1 >> 3)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 16) & MASK32) | (x1 >> 16)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 24) & MASK32) | (x1 >> 8)) ^ x0
	x0 = (x0 + k1) & MASK32
	x1 = (x1 + k2 + 4) & MASK32
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 13) & MASK32) | (x1 >> 19)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 15) & MASK32) | (x1 >> 17)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 26) & MASK32) | (x1 >> 6)) ^ x0
	x0 = (x0 + x1) & MASK32
	x1 = (((x1 << 6) & MASK32) | (x1 >> 26)) ^ x0
	x0 = (x0 + k2) & MASK32
	x1 = (x1 + k0 + 5) & MASK32
	return PackedInt64Array([x0, x1])


## New stream at `cursor_text` (default 0). Check `is_valid()`; invalid input never guesses.
static func create(seed_text: String, stream_name: String, cursor_text: String = "0") -> HipRng:
	var rng: HipRng = HipRng.new()
	var seed_words: PackedInt64Array = parse_u64(seed_text)
	var cursor_words: PackedInt64Array = parse_u64(cursor_text)
	if seed_words.is_empty():
		rng.error = "seed must be a canonical uint64 decimal string"
	elif cursor_words.is_empty() or cursor_words[0] > 0x7FFFFFFF:
		rng.error = "cursor must be a canonical decimal in 0..2^63-1"
	elif not is_stream_name(stream_name):
		rng.error = "stream name must match [a-z][a-z0-9_]{0,7}"
	if not rng.error.is_empty():
		return rng
	var bytes: PackedByteArray = stream_name.to_ascii_buffer()
	var n0: int = 0
	var n1: int = 0
	for i: int in bytes.size():
		if i < 4:
			n0 |= bytes[i] << (8 * i)
		else:
			n1 |= bytes[i] << (8 * (i - 4))
	var key: PackedInt64Array = threefry(seed_words[1], seed_words[0], n0, n1)
	rng._seed_text = seed_text
	rng._name = stream_name
	rng._k0 = key[0]
	rng._k1 = key[1]
	rng._cursor = (cursor_words[0] << 32) | cursor_words[1]
	rng._ok = true
	return rng


## Restores one stream from the SaveEnvelope shape {seed, cursor} (exact keys).
static func restore(stream_name: String, saved: Dictionary) -> HipRng:
	if saved.size() != 2 or typeof(saved.get("seed")) != TYPE_STRING or typeof(saved.get("cursor")) != TYPE_STRING:
		var bad: HipRng = HipRng.new()
		bad.error = "saved stream must have exactly string keys seed and cursor"
		return bad
	return create(saved["seed"], stream_name, saved["cursor"])


## All registered streams of a new run (same seed, cursor 0), keyed by name; {} on a bad seed.
static func new_run_streams(seed_text: String) -> Dictionary:
	var streams: Dictionary = {}
	for stream_name: String in STREAMS:
		var rng: HipRng = create(seed_text, stream_name)
		if not rng.is_valid():
			return {}
		streams[stream_name] = rng
	return streams


## Restores SaveEnvelope rng_policy.streams: exactly the registered streams, each with the
## run seed. Any unknown, missing or foreign-seed stream rejects the whole set ({}).
static func restore_run_streams(seed_text: String, saved_streams: Dictionary) -> Dictionary:
	if parse_u64(seed_text).is_empty() or saved_streams.size() != STREAMS.size():
		return {}
	var streams: Dictionary = {}
	for stream_name: String in STREAMS:
		var saved: Variant = saved_streams.get(stream_name)
		if typeof(saved) != TYPE_DICTIONARY:
			return {}
		var rng: HipRng = restore(stream_name, saved)
		if not rng.is_valid() or rng._seed_text != seed_text:
			return {}
		streams[stream_name] = rng
	return streams


func stream_name() -> String:
	return _name


func cursor() -> int:
	return _cursor


## Next uint32 in [0, 2^32); -1 (and `error` set) when invalid or exhausted.
func next_u32() -> int:
	if not is_valid():
		return -1
	if _cursor >= CURSOR_MAX:
		error = "stream exhausted: cursor reached 2^63-1"
		return -1
	var block: int = _cursor >> 1
	var value: int
	if (_cursor & 1) == 1 and block == _cached_block:
		value = _cached_x1
	else:
		var out: PackedInt64Array = threefry(_k0, _k1, block & MASK32, block >> 32)
		_cached_block = block
		_cached_x1 = out[1]
		value = out[_cursor & 1]
	_cursor += 1
	return value


## Exact uniform integer in [0, n) for 1 <= n <= 2^32 (threshold rejection).
## Always consumes at least one word, also for n == 1. An invalid n returns -1 without
## consuming a word or invalidating the stream (as the Python reference raises and keeps it).
## Callers must check for -1 before indexing: -1 is a valid GDScript index.
func below(n: int) -> int:
	if n < 1 or n > BELOW_MAX:
		return -1
	var threshold: int = BELOW_MAX % n
	while true:
		var value: int = next_u32()
		if value < 0:
			return -1
		if value >= threshold:
			return value % n
	return -1


## The {seed, cursor} shape of SaveEnvelope rng_policy.streams.<name>.
func save() -> Dictionary:
	return {"seed": _seed_text, "cursor": str(_cursor)}
