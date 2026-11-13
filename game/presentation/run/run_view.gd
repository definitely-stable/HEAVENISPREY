class_name RunView
extends Node2D
## P0 placeholder run scene: hero movement, jade_grove w0 enemies and contact damage in an
## empty arena, drawn with primitives. Reads simulation state only; input reaches the
## simulation through FixedTickDriver. Tuning comes from P0Tuning (placeholder bases).

const CELL_PX: int = P0Tuning.CELL_PX
const ARENA_CELLS: Vector2i = P0Tuning.ARENA_CELLS
const HERO_RADIUS_PX: int = P0Tuning.HERO_RADIUS_PX
## Seconds the finished run stays on screen before a new one starts.
const RESTART_DELAY: float = 2.0
const HIT_FLASH: float = 0.15

const COLOR_FLOOR: Color = Color(0.09, 0.08, 0.11)
const COLOR_GRID: Color = Color(0.16, 0.14, 0.19)
const COLOR_WALL: Color = Color(0.55, 0.47, 0.33)
const COLOR_HERO: Color = Color(0.93, 0.86, 0.66)
const COLOR_HERO_HIT: Color = Color(1.0, 0.35, 0.3)
const COLOR_FACING: Color = Color(0.25, 0.2, 0.15)
const COLOR_HP_BACK: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_HP: Color = Color(0.85, 0.2, 0.2)
const COLOR_OVER: Color = Color(0.0, 0.0, 0.0, 0.55)
## Placeholder enemy colours by kind index (yin corpse, blood wolf, then fallbacks).
const ENEMY_COLORS: Array[Color] = [
	Color(0.45, 0.55, 0.45), Color(0.6, 0.12, 0.14), Color(0.5, 0.45, 0.7), Color(0.7, 0.6, 0.3),
]

## When false, frames advance only through advance_frame() (tests, replays).
@export var read_player_input: bool = true

var driver: FixedTickDriver
var tuning: P0Tuning = P0Tuning.new()
var runs_started: int = 0
var _registry: ContentRegistry
var _facing: Vector2 = Vector2.RIGHT
var _flash: float = 0.0
var _over_time: float = 0.0

@onready var _camera: Camera2D = $Camera


## Movement-only configuration of the arena (kept for tests and tools).
static func placeholder_config() -> SimConfig:
	return P0Tuning.movement_config()


func _ready() -> void:
	_registry = ContentRegistry.load_dir()
	var arena: Vector2i = ARENA_CELLS * CELL_PX
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = arena.x
	_camera.limit_bottom = arena.y
	start_run(str(randi()))


## Starts a fresh run; falls back to the empty arena when content cannot be assembled.
func start_run(seed_text: String) -> void:
	var config: SimConfig = tuning.run_config(_registry, seed_text)
	if config == null:
		push_error("P0 run without enemies: " + tuning.error)
		config = placeholder_config()
	driver = FixedTickDriver.create(config)
	runs_started += 1
	_flash = 0.0
	_over_time = 0.0
	_camera.position = driver.hero_position_px()
	_camera.reset_smoothing()
	queue_redraw()


func _process(delta: float) -> void:
	if not read_player_input:
		return
	if Input.is_action_just_pressed("restart"):
		start_run(str(randi()))
		return
	advance_frame(delta, MoveInput.read())


func advance_frame(delta: float, move: Vector2i) -> int:
	if driver.world.is_over():
		_over_time += delta
		if _over_time >= RESTART_DELAY:
			start_run(str(randi()))
		queue_redraw()
		return 0
	var hp_before: int = driver.world.hero_hp
	var ticks: int = driver.advance(delta, move)
	if driver.world.hero_hp < hp_before:
		_flash = HIT_FLASH
	else:
		_flash = maxf(_flash - delta, 0.0)
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
	_draw_enemies()
	_draw_hero()
	if driver.world.is_over():
		draw_rect(Rect2(Vector2.ZERO, arena), COLOR_OVER)


func _draw_enemies() -> void:
	var world: WorldState = driver.world
	for slot: int in world.enemy_count():
		var kind: int = world.enemy_kind[slot]
		var radius: float = float(driver.config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE
		var color: Color = ENEMY_COLORS[mini(kind, ENEMY_COLORS.size() - 1)]
		var at: Vector2 = driver.enemy_position_px(slot)
		draw_circle(at, radius, color)
		draw_circle(at, radius, color.darkened(0.45), false, 2.0)


func _draw_hero() -> void:
	var hero: Vector2 = driver.hero_position_px()
	var color: Color = COLOR_HERO_HIT if _flash > 0.0 else COLOR_HERO
	draw_circle(hero, HERO_RADIUS_PX, color)
	draw_circle(hero + _facing * (HERO_RADIUS_PX * 0.55), HERO_RADIUS_PX * 0.25, COLOR_FACING)
	var max_hp: int = driver.config.hero_hp_mhp
	if max_hp <= 0:
		return
	var bar: Rect2 = Rect2(hero + Vector2(-HERO_RADIUS_PX, -HERO_RADIUS_PX - 12), Vector2(HERO_RADIUS_PX * 2, 5))
	draw_rect(bar, COLOR_HP_BACK)
	var share: float = clampf(float(driver.world.hero_hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), COLOR_HP)
