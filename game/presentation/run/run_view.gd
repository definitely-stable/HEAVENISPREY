class_name RunView
extends Node2D
## P0-01c placeholder run scene: hero movement in an empty arena, drawn with primitives.
## Reads simulation state only; input reaches the simulation through FixedTickDriver.

## Placeholder tuning, NOT canonical content: GAME-ARCH-02 fixture hypothesis
## (32 x 20 cells, cell = 2 hero radii, radius 24 px, 0.1 cell per tick = 288 px/s).
const CELL_PX: int = 48
const ARENA_CELLS: Vector2i = Vector2i(32, 20)
const HERO_RADIUS_PX: int = 24
const HERO_SPEED_SU_PER_TICK: int = 4800

const COLOR_FLOOR: Color = Color(0.09, 0.08, 0.11)
const COLOR_GRID: Color = Color(0.16, 0.14, 0.19)
const COLOR_WALL: Color = Color(0.55, 0.47, 0.33)
const COLOR_HERO: Color = Color(0.93, 0.86, 0.66)
const COLOR_FACING: Color = Color(0.25, 0.2, 0.15)

## When false, frames advance only through advance_frame() (tests, replays).
@export var read_player_input: bool = true

var driver: FixedTickDriver
var _facing: Vector2 = Vector2.RIGHT

@onready var _camera: Camera2D = $Camera


static func placeholder_config() -> SimConfig:
	var w: int = ARENA_CELLS.x * CELL_PX * Fx.FX_ONE
	var h: int = ARENA_CELLS.y * CELL_PX * Fx.FX_ONE
	@warning_ignore("integer_division")
	return SimConfig.create(PackedInt64Array([
		HERO_SPEED_SU_PER_TICK, HERO_RADIUS_PX * Fx.FX_ONE, 0, 0, w, h, w / 2, h / 2,
	]))


func _ready() -> void:
	driver = FixedTickDriver.create(placeholder_config())
	var arena: Vector2i = ARENA_CELLS * CELL_PX
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = arena.x
	_camera.limit_bottom = arena.y
	_camera.position = driver.hero_position_px()
	_camera.reset_smoothing()


func _process(delta: float) -> void:
	if read_player_input:
		advance_frame(delta, MoveInput.read())


func advance_frame(delta: float, move: Vector2i) -> int:
	var ticks: int = driver.advance(delta, move)
	if move != Vector2i.ZERO:
		_facing = Vector2(move).normalized()
	_camera.position = driver.hero_position_px()
	queue_redraw()
	return ticks


func _draw() -> void:
	var arena: Vector2 = Vector2(ARENA_CELLS * CELL_PX)
	draw_rect(Rect2(Vector2.ZERO, arena), COLOR_FLOOR)
	for x: int in range(CELL_PX, int(arena.x), CELL_PX):
		draw_line(Vector2(x, 0), Vector2(x, arena.y), COLOR_GRID, 1.0)
	for y: int in range(CELL_PX, int(arena.y), CELL_PX):
		draw_line(Vector2(0, y), Vector2(arena.x, y), COLOR_GRID, 1.0)
	draw_rect(Rect2(Vector2.ZERO, arena), COLOR_WALL, false, 4.0)
	var hero: Vector2 = driver.hero_position_px()
	draw_circle(hero, HERO_RADIUS_PX, COLOR_HERO)
	draw_circle(hero + _facing * (HERO_RADIUS_PX * 0.55), HERO_RADIUS_PX * 0.25, COLOR_FACING)
