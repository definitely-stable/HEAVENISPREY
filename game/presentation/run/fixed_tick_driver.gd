class_name FixedTickDriver
extends RefCounted
## Runs SimKernel at a fixed 60 Hz from variable frame time and records player input as
## PlayerCommand entries. Frame timing decides only *when* ticks run; the command log alone
## decides *what* happens, so replaying the log reproduces the run bit for bit.

## Longest catch-up per frame; older backlog is dropped instead of spiralling.
const MAX_TICKS_PER_FRAME: int = 8
const TICK_SECONDS: float = 1.0 / Fx.TICKS_PER_SECOND

var config: SimConfig
var world: WorldState
var previous: WorldState
var commands: CommandLog = CommandLog.new()
## Presentation events since the last take_events(), in tick order: enemies hit (uids) and
## enemies killed ([position px, kind]). Read-only views of the simulation, never inputs.
var hit_uids: PackedInt64Array = PackedInt64Array()
var killed: Array[Array] = []

var _accumulator: float = 0.0
var _sequence: int = 0
var _held: Vector2i = Vector2i.ZERO


static func create(p_config: SimConfig) -> FixedTickDriver:
	var driver: FixedTickDriver = FixedTickDriver.new()
	driver.config = p_config
	driver.world = WorldState.initial(p_config)
	driver.previous = driver.world.copy()
	return driver


## Advance by one rendered frame holding `move`; returns the number of ticks simulated.
func advance(delta: float, move: Vector2i) -> int:
	_accumulator += maxf(delta, 0.0)
	var ticks: int = 0
	while _accumulator >= TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_SECONDS
		_record(move)
		previous = world.copy()
		SimKernel.step(config, world, commands)
		_collect_events()
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, TICK_SECONDS)
	return ticks


## Fraction of the next tick already elapsed, for interpolating between previous and world.
func alpha() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


## Interpolated hero position in pixels (1 px = Fx.FX_ONE su).
func hero_position_px() -> Vector2:
	var from: Vector2 = Vector2(previous.player_x, previous.player_y)
	var to: Vector2 = Vector2(world.player_x, world.player_y)
	return from.lerp(to, alpha()) / float(Fx.FX_ONE)


## Interpolated enemy position in pixels. Only the same enemy (same uid in the slot on both
## ticks) is interpolated; one spawned this tick is drawn where it is.
func enemy_position_px(slot: int) -> Vector2:
	var to: Vector2 = Vector2(world.enemy_x[slot], world.enemy_y[slot])
	if slot >= previous.enemy_slots() or previous.enemy_uid[slot] != world.enemy_uid[slot]:
		return to / float(Fx.FX_ONE)
	var from: Vector2 = Vector2(previous.enemy_x[slot], previous.enemy_y[slot])
	return from.lerp(to, alpha()) / float(Fx.FX_ONE)


## Interpolated projectile position in pixels; one fired this tick is drawn where it is.
func projectile_position_px(slot: int) -> Vector2:
	var to: Vector2 = Vector2(world.proj_x[slot], world.proj_y[slot])
	var same: bool = (
		slot < previous.projectile_slots()
		and previous.proj_damage[slot] != 0
		and previous.proj_ttl[slot] == world.proj_ttl[slot] + 1
	)
	if not same:
		return to / float(Fx.FX_ONE)
	var from: Vector2 = Vector2(previous.proj_x[slot], previous.proj_y[slot])
	return from.lerp(to, alpha()) / float(Fx.FX_ONE)


## Returns and clears the collected events: {"hit": PackedInt64Array, "killed": Array}.
func take_events() -> Dictionary:
	var events: Dictionary = {"hit": hit_uids, "killed": killed}
	hit_uids = PackedInt64Array()
	killed = []
	return events


func _collect_events() -> void:
	for slot: int in previous.enemy_slots():
		var uid: int = previous.enemy_uid[slot]
		if uid == 0:
			continue
		if world.enemy_uid[slot] != uid:
			var at: Vector2 = Vector2(previous.enemy_x[slot], previous.enemy_y[slot]) / float(Fx.FX_ONE)
			killed.append([at, previous.enemy_kind[slot]])
		elif world.enemy_hp[slot] < previous.enemy_hp[slot]:
			hit_uids.append(uid)


func _record(move: Vector2i) -> void:
	if move == _held:
		return
	var command: PlayerCommand = PlayerCommand.create(world.tick, _sequence, move.x, move.y)
	if commands.append(command, world.tick) == CommandLog.OK:
		_sequence += 1
		_held = move
