class_name WorldState
extends RefCounted
## IC-05 (first slice): the complete simulation state, integers only (ADR-008).
##
## `tick` is the next tick to simulate. The state digest is SHA-256 over the
## little-endian bytes of `to_ints()`, never `hash()` or `var_to_bytes`.

var tick: int = 0
var player_x: int = 0
var player_y: int = 0
var move_x: int = 0
var move_y: int = 0
## Index of the next CommandLog record to apply.
var command_cursor: int = 0


static func initial(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.new()
	world.player_x = config.start_x
	world.player_y = config.start_y
	return world


func to_ints() -> PackedInt64Array:
	return PackedInt64Array([tick, player_x, player_y, move_x, move_y, command_cursor])


func digest() -> String:
	return ContentRegistry.sha256_hex(to_ints().to_byte_array())


func copy() -> WorldState:
	var other: WorldState = WorldState.new()
	other.tick = tick
	other.player_x = player_x
	other.player_y = player_y
	other.move_x = move_x
	other.move_y = move_y
	other.command_cursor = command_cursor
	return other
