class_name FixedTickDriver
extends RefCounted
## Runs SimKernel at a fixed 60 Hz from variable frame time and records player input as
## PlayerCommand entries. Frame timing decides only *when* ticks run; the command log alone
## decides *what* happens, so replaying the log reproduces the run bit for bit.
##
## Level-up pause (ADR-010 section 6): while the world waits for a choice, advance() neither
## accumulates nor spends time and records no MOVE; choose() writes the CHOOSE into the same
## log and resolves it with one paused step, so a replay sees the whole chain.

## Longest catch-up per frame; older backlog is dropped instead of spiralling.
const MAX_TICKS_PER_FRAME: int = 8
const TICK_SECONDS: float = 1.0 / Fx.TICKS_PER_SECOND

var config: SimConfig
var world: WorldState
var previous: WorldState
var commands: CommandLog = CommandLog.new()
## Presentation events since the last take_events(), in tick order: enemies hit (uids),
## enemies killed ([position px, kind]), gems collected ([position px, value]) and levels
## gained. Read-only views of the simulation, never inputs.
var hit_uids: PackedInt64Array = PackedInt64Array()
var killed: Array[Array] = []
var collected: Array[Array] = []
var levels_gained: int = 0

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
	if world.is_paused():
		_accumulator = 0.0
		return 0
	_accumulator += maxf(delta, 0.0)
	var ticks: int = 0
	while _accumulator >= TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_SECONDS
		_record(move)
		previous = world.copy()
		SimKernel.step(config, world, commands)
		_collect_events()
		ticks += 1
		if world.is_paused():
			# The rest of the frame is dropped; the paused world is drawn as it is.
			_accumulator = 0.0
			previous = world.copy()
			break
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, TICK_SECONDS)
	return ticks


## Picks card `index` of the shown hand: records CHOOSE for the current build_revision and
## resolves it with one paused step. A card that does not exist is not recorded (false).
func choose(index: int) -> bool:
	if not world.is_paused() or index < 0 or index >= world.hand.size():
		return false
	var command: PlayerCommand = PlayerCommand.choose(world.tick, _sequence, index, world.build_revision)
	if commands.append(command, world.tick) != CommandLog.OK:
		return false
	_sequence += 1
	var done: int = world.choices_done
	SimKernel.step(config, world, commands)
	previous = world.copy()
	return world.choices_done == done + 1


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


## Gem position in pixels (gems do not move).
func gem_position_px(slot: int) -> Vector2:
	return Vector2(world.gem_x[slot], world.gem_y[slot]) / float(Fx.FX_ONE)


## Returns and clears the collected events: {"hit": PackedInt64Array, "killed": Array,
## "collected": Array, "levels": int}.
func take_events() -> Dictionary:
	var events: Dictionary = {
		"hit": hit_uids, "killed": killed, "collected": collected, "levels": levels_gained,
	}
	hit_uids = PackedInt64Array()
	killed = []
	collected = []
	levels_gained = 0
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
	# A gem collected this tick: its uid is gone from the slot (a gem dropped and collected in
	# the same tick never shows up on the ground, so it is not animated).
	for slot: int in previous.gem_slots():
		var gem: int = previous.gem_uid[slot]
		if gem != 0 and world.gem_uid[slot] != gem:
			var at: Vector2 = Vector2(previous.gem_x[slot], previous.gem_y[slot]) / float(Fx.FX_ONE)
			collected.append([at, previous.gem_value[slot]])
	levels_gained += world.level - previous.level


func _record(move: Vector2i) -> void:
	if move == _held:
		return
	var command: PlayerCommand = PlayerCommand.create(world.tick, _sequence, move.x, move.y)
	if commands.append(command, world.tick) == CommandLog.OK:
		_sequence += 1
		_held = move
