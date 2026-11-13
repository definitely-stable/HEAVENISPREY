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


func _record(move: Vector2i) -> void:
	if move == _held:
		return
	var command: PlayerCommand = PlayerCommand.create(world.tick, _sequence, move.x, move.y)
	if commands.append(command, world.tick) == CommandLog.OK:
		_sequence += 1
		_held = move
