class_name PlayerCommand
extends RefCounted
## IC-03: the only way player input reaches the simulation (ADR-008 section a).
##
## A command sets the HELD digital direction from `tick` on: move_x/move_y are -1, 0 or 1
## (8 directions or none). The input layer quantizes analog sticks and keys into these
## values; the simulation never reads Input, delta or the mouse. Integers only.

var tick: int = 0
var sequence: int = 0
var move_x: int = 0
var move_y: int = 0


static func create(p_tick: int, p_sequence: int, p_move_x: int, p_move_y: int) -> PlayerCommand:
	var command: PlayerCommand = PlayerCommand.new()
	command.tick = p_tick
	command.sequence = p_sequence
	command.move_x = p_move_x
	command.move_y = p_move_y
	return command


func is_valid() -> bool:
	return tick >= 0 and sequence >= 0 and absi(move_x) <= 1 and absi(move_y) <= 1


func to_ints() -> PackedInt64Array:
	return PackedInt64Array([tick, sequence, move_x, move_y])
