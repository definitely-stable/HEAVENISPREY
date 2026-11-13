class_name SimConfig
extends RefCounted
## Integer parameters of one simulated run (hip-fx-v1 units: su, su/tick).
##
## P0-01b holds only what movement needs: hero speed and radius and the arena rectangle.
## Values come from typed content definitions in later slices; tests pass them directly.

var speed_su_per_tick: int = 0
var player_radius_su: int = 0
var arena_min_x: int = 0
var arena_min_y: int = 0
var arena_max_x: int = 0
var arena_max_y: int = 0
var start_x: int = 0
var start_y: int = 0


static func create(values: PackedInt64Array) -> SimConfig:
	var config: SimConfig = SimConfig.new()
	if values.size() != 8:
		return config
	config.speed_su_per_tick = values[0]
	config.player_radius_su = values[1]
	config.arena_min_x = values[2]
	config.arena_min_y = values[3]
	config.arena_max_x = values[4]
	config.arena_max_y = values[5]
	config.start_x = values[6]
	config.start_y = values[7]
	return config


func to_ints() -> PackedInt64Array:
	return PackedInt64Array([
		speed_su_per_tick, player_radius_su, arena_min_x, arena_min_y,
		arena_max_x, arena_max_y, start_x, start_y,
	])


## Bounds stay inside hip-fx-v1 coordinate limits, the hero fits, the start is reachable.
func is_valid() -> bool:
	for value: int in to_ints():
		if absi(value) > Fx.COORD_MAX:
			return false
	var r: int = player_radius_su
	return (
		speed_su_per_tick >= 0
		and r > 0
		and arena_max_x - arena_min_x >= 2 * r
		and arena_max_y - arena_min_y >= 2 * r
		and start_x >= arena_min_x + r
		and start_x <= arena_max_x - r
		and start_y >= arena_min_y + r
		and start_y <= arena_max_y - r
	)
