class_name PlayerCommand
extends RefCounted
## IC-03: the only way player input reaches the simulation (ADR-008 section a; command log
## schema 2, ADR-010 section 6).
##
## A record is [tick, sequence, kind, a, b]:
##   MOVE   (kind 0): a = move_x, b = move_y in -1..1, the HELD digital direction from `tick`
##          on (8 directions or none). The input layer quantizes analog sticks and keys.
##   CHOOSE (kind 1): a = card index in the offered hand, b = the build_revision the hand was
##          built for. Validity against the hand is decided by the simulation, not here.
## The simulation never reads Input, delta or the mouse. Integers only.

const MOVE: int = 0
const CHOOSE: int = 1

var tick: int = 0
var sequence: int = 0
var kind: int = MOVE
var move_x: int = 0
var move_y: int = 0
var choice_index: int = 0
var build_revision: int = 0


static func create(p_tick: int, p_sequence: int, p_move_x: int, p_move_y: int) -> PlayerCommand:
	var command: PlayerCommand = PlayerCommand.new()
	command.tick = p_tick
	command.sequence = p_sequence
	command.move_x = p_move_x
	command.move_y = p_move_y
	return command


static func choose(p_tick: int, p_sequence: int, p_index: int, p_revision: int) -> PlayerCommand:
	var command: PlayerCommand = PlayerCommand.new()
	command.tick = p_tick
	command.sequence = p_sequence
	command.kind = CHOOSE
	command.choice_index = p_index
	command.build_revision = p_revision
	return command


## A record of the log ([tick, sequence, kind, a, b]); null for another length.
static func from_ints(values: PackedInt64Array) -> PlayerCommand:
	if values.size() != 5:
		return null
	if values[2] == MOVE:
		return create(values[0], values[1], values[3], values[4])
	var command: PlayerCommand = choose(values[0], values[1], values[3], values[4])
	command.kind = values[2]
	return command


func is_valid() -> bool:
	if tick < 0 or sequence < 0:
		return false
	if kind == MOVE:
		return absi(move_x) <= 1 and absi(move_y) <= 1
	return kind == CHOOSE and choice_index >= 0 and build_revision >= 0


func to_ints() -> PackedInt64Array:
	if kind == MOVE:
		return PackedInt64Array([tick, sequence, kind, move_x, move_y])
	return PackedInt64Array([tick, sequence, kind, choice_index, build_revision])
