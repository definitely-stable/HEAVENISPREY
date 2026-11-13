class_name SimKernel
extends RefCounted
## Fixed 60 Hz simulation step (s04, ADR-008). Exact port of tools/content/sim_core.py.
##
## Phase order inside one tick (P0-01b subset of s04):
##   0. apply every logged command whose tick <= world.tick, in log order (last one wins);
##   1. move the hero by the held direction (Q14 unit vector x speed, symmetric rounding);
##   2. clamp the hero inside the arena rectangle (radius-aware);
##   3. advance the tick.
## No float, no Input, no delta: the same log and config give the same state everywhere.

const AXIS_Q14: int = 16384
## round(16384 / sqrt(2)): diagonal component of a unit vector, equal to FxTables sin(45 deg).
const DIAG_Q14: int = 11585


static func direction_q14(move_x: int, move_y: int) -> PackedInt64Array:
	if move_x != 0 and move_y != 0:
		return PackedInt64Array([signi(move_x) * DIAG_Q14, signi(move_y) * DIAG_Q14])
	return PackedInt64Array([signi(move_x) * AXIS_Q14, signi(move_y) * AXIS_Q14])


static func step(config: SimConfig, world: WorldState, commands: CommandLog) -> void:
	while world.command_cursor < commands.size() and commands.tick_at(world.command_cursor) <= world.tick:
		world.move_x = commands.move_x_at(world.command_cursor)
		world.move_y = commands.move_y_at(world.command_cursor)
		world.command_cursor += 1
	var direction: PackedInt64Array = direction_q14(world.move_x, world.move_y)
	var r: int = config.player_radius_su
	var next_x: int = world.player_x + Fx.mul_q14(config.speed_su_per_tick, direction[0])
	var next_y: int = world.player_y + Fx.mul_q14(config.speed_su_per_tick, direction[1])
	world.player_x = clampi(next_x, config.arena_min_x + r, config.arena_max_x - r)
	world.player_y = clampi(next_y, config.arena_min_y + r, config.arena_max_y - r)
	world.tick += 1


static func run(config: SimConfig, world: WorldState, commands: CommandLog, ticks: int) -> void:
	for _i: int in ticks:
		step(config, world, commands)
