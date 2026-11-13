class_name CommandLog
extends RefCounted
## Append-only, replayable log of PlayerCommand values (IC-03, GAME-ARCH-00 ordering).
##
## Stored as a flat PackedInt64Array of [tick, sequence, move_x, move_y] records, copied on
## append, so a caller cannot change a logged command afterwards. Accepted order is strictly
## increasing `sequence` with non-decreasing `tick`; a command for a tick the simulation has
## already processed is rejected (no rewriting the past). Rejections return a stable code.

const STRIDE: int = 4
const OK: String = "ok"
const INVALID: String = "invalid_command"
const PAST_TICK: String = "past_tick"
const TICK_NOT_MONOTONIC: String = "tick_not_monotonic"
const SEQUENCE_NOT_INCREASING: String = "sequence_not_increasing"

var _records: PackedInt64Array = PackedInt64Array()


## `next_tick` is the first tick the simulation has not processed yet.
func append(command: PlayerCommand, next_tick: int) -> String:
	if command == null or not command.is_valid():
		return INVALID
	if command.tick < next_tick:
		return PAST_TICK
	var count: int = size()
	if count > 0:
		if command.tick < tick_at(count - 1):
			return TICK_NOT_MONOTONIC
		if command.sequence <= _records[(count - 1) * STRIDE + 1]:
			return SEQUENCE_NOT_INCREASING
	_records.append_array(command.to_ints())
	return OK


func size() -> int:
	return _records.size() >> 2


func tick_at(index: int) -> int:
	return _records[index * STRIDE]


func move_x_at(index: int) -> int:
	return _records[index * STRIDE + 2]


func move_y_at(index: int) -> int:
	return _records[index * STRIDE + 3]


## Copy of the raw records, for saving and digests.
func records() -> PackedInt64Array:
	return _records.duplicate()


func digest() -> String:
	return ContentRegistry.sha256_hex(_records.to_byte_array())
