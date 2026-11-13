class_name CommandLog
extends RefCounted
## Append-only, replayable log of PlayerCommand values (IC-03, GAME-ARCH-00 ordering).
##
## Command log schema 2 (ADR-010 section 6): a flat PackedInt64Array of [tick, sequence, kind,
## a, b] records, copied on append, so a caller cannot change a logged command afterwards.
## Accepted order is strictly increasing `sequence` with non-decreasing `tick`; a command for
## a tick the simulation has already processed is rejected (no rewriting the past).
## Rejections return a stable code. Schema 1 logs ([tick, sequence, move_x, move_y]) migrate
## to MOVE records with from_v1().

const SCHEMA_VERSION: int = 2
const STRIDE: int = 5
const V1_STRIDE: int = 4
const OK: String = "ok"
const INVALID: String = "invalid_command"
const PAST_TICK: String = "past_tick"
const TICK_NOT_MONOTONIC: String = "tick_not_monotonic"
const SEQUENCE_NOT_INCREASING: String = "sequence_not_increasing"

var _records: PackedInt64Array = PackedInt64Array()
var _count: int = 0


## A schema 1 log as MOVE records; null when the array is not whole records or the result
## breaks the order rules.
static func from_v1(records: PackedInt64Array) -> CommandLog:
	var log: CommandLog = CommandLog.new()
	var index: int = 0
	while index < records.size():
		if index + V1_STRIDE > records.size():
			return null
		var command: PlayerCommand = PlayerCommand.create(
			records[index], records[index + 1], records[index + 2], records[index + 3]
		)
		if log.append(command, 0) != OK:
			return null
		index += V1_STRIDE
	return log


## `next_tick` is the first tick the simulation has not processed yet.
func append(command: PlayerCommand, next_tick: int) -> String:
	if command == null or not command.is_valid():
		return INVALID
	if command.tick < next_tick:
		return PAST_TICK
	if _count > 0:
		if command.tick < tick_at(_count - 1):
			return TICK_NOT_MONOTONIC
		if command.sequence <= _records[(_count - 1) * STRIDE + 1]:
			return SEQUENCE_NOT_INCREASING
	_records.append_array(command.to_ints())
	_count += 1
	return OK


func size() -> int:
	return _count


func tick_at(index: int) -> int:
	return _records[index * STRIDE]


func kind_at(index: int) -> int:
	return _records[index * STRIDE + 2]


func a_at(index: int) -> int:
	return _records[index * STRIDE + 3]


func b_at(index: int) -> int:
	return _records[index * STRIDE + 4]


func move_x_at(index: int) -> int:
	return a_at(index)


func move_y_at(index: int) -> int:
	return b_at(index)


## Copy of the raw records, for saving and digests.
func records() -> PackedInt64Array:
	return _records.duplicate()


func digest() -> String:
	return ContentRegistry.sha256_hex(_records.to_byte_array())
