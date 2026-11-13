class_name RunView
extends Node2D
## P0 placeholder run scene: hero movement and auto-attack, jade_grove w0 enemies, contact
## damage and kills in an empty arena, drawn with primitives. Reads simulation state only;
## input reaches the simulation through FixedTickDriver. Tuning comes from P0Tuning
## (placeholder bases). Hit flashes, death puffs, gem pickup flights and the level-up ring
## are presentation-only effects (ADR-010 section 8). A pending level-up pauses the run under
## ChoiceMenu; a picked card reaches the simulation as a CHOOSE through FixedTickDriver.

const CELL_PX: int = P0Tuning.CELL_PX
const ARENA_CELLS: Vector2i = P0Tuning.ARENA_CELLS
const HERO_RADIUS_PX: int = P0Tuning.HERO_RADIUS_PX
## Seconds the finished run stays on screen before a new one starts.
const RESTART_DELAY: float = 2.0
const HIT_FLASH: float = 0.15
const ENEMY_HIT_FLASH: float = 0.1
const PUFF_TIME: float = 0.35
const HUD_FONT_SIZE: int = 22
const HUD_MARGIN: Vector2 = Vector2(20, 34)
## Seconds a collected gem flies to the hero (6 frames at 60 fps), then its "+N" floats.
const PICKUP_FLY: float = 0.1
const PICKUP_TEXT: float = 0.6
const LEVEL_RING: float = 0.6
const XP_BAR_HEIGHT: float = 6.0

const COLOR_FLOOR: Color = Color(0.09, 0.08, 0.11)
const COLOR_GRID: Color = Color(0.16, 0.14, 0.19)
const COLOR_WALL: Color = Color(0.55, 0.47, 0.33)
const COLOR_HERO: Color = Color(0.93, 0.86, 0.66)
const COLOR_HERO_HIT: Color = Color(1.0, 0.35, 0.3)
const COLOR_FACING: Color = Color(0.25, 0.2, 0.15)
const COLOR_HP_BACK: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_HP: Color = Color(0.85, 0.2, 0.2)
const COLOR_OVER: Color = Color(0.0, 0.0, 0.0, 0.55)
const COLOR_ENEMY_HIT: Color = Color(1.0, 1.0, 1.0)
## Spirit sword (metal element) projectile.
const COLOR_SWORD: Color = Color(0.78, 0.92, 1.0)
const COLOR_SWORD_GLOW: Color = Color(0.7, 0.88, 1.0, 0.22)
const COLOR_HUD: Color = Color(0.95, 0.92, 0.85)
## XP gems: jade blue (red stays reserved for enemies).
const COLOR_GEM: Color = Color(0.36, 0.84, 0.78)
const COLOR_XP_BACK: Color = Color(0.0, 0.0, 0.0, 0.55)
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
## Enemy uid -> seconds of hit flash left.
var _enemy_flash: Dictionary = {}
## Death puffs: [position px, kind, age seconds].
var _puffs: Array[Array] = []
## Gem pickups in flight: [from px, value, age seconds].
var _pickups: Array[Array] = []
## Seconds left of the level-up ring.
var _level_ring: float = 0.0
## Screen-space layer for the HUD (not moved by the camera).
var _hud: Node2D
var _menu: ChoiceMenu

@onready var _camera: Camera2D = $Camera


## Movement-only configuration of the arena (kept for tests and tools).
static func placeholder_config() -> SimConfig:
	return P0Tuning.movement_config()


func _ready() -> void:
	UiText.apply_locale()
	_registry = ContentRegistry.load_dir()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Node2D.new()
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	_menu = ChoiceMenu.new()
	layer.add_child(_menu)
	_menu.picked.connect(_on_card_picked)
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
	_enemy_flash.clear()
	_puffs.clear()
	_pickups.clear()
	_level_ring = 0.0
	_camera.position = driver.hero_position_px()
	_camera.reset_smoothing()
	_sync_menu()
	queue_redraw()


func _process(delta: float) -> void:
	if not read_player_input:
		return
	if Input.is_action_just_pressed("restart"):
		start_run(str(randi()))
		return
	advance_frame(delta, MoveInput.read())


func advance_frame(delta: float, move: Vector2i) -> int:
	if driver.world.is_paused():
		# The run waits for a card; effects freeze with it.
		_sync_menu()
		_menu.age(delta)
		return 0
	_age_effects(delta)
	if driver.world.is_over():
		_over_time += delta
		if _over_time >= RESTART_DELAY:
			start_run(str(randi()))
		queue_redraw()
		return 0
	var hp_before: int = driver.world.hero_hp
	var ticks: int = driver.advance(delta, move)
	var events: Dictionary = driver.take_events()
	for uid: int in events["hit"]:
		_enemy_flash[uid] = ENEMY_HIT_FLASH
	for kill: Array in events["killed"]:
		_puffs.append([kill[0], kill[1], 0.0])
	for gem: Array in events["collected"]:
		_pickups.append([gem[0], gem[1], 0.0])
	if int(events["levels"]) > 0:
		_level_ring = LEVEL_RING
	if driver.world.hero_hp < hp_before:
		_flash = HIT_FLASH
	else:
		_flash = maxf(_flash - delta, 0.0)
	if move != Vector2i.ZERO:
		_facing = Vector2(move).normalized()
	_camera.position = driver.hero_position_px()
	_sync_menu()
	queue_redraw()
	return ticks


## Picks card `index` of the shown hand (the menu's `picked`, tests and replays); false when
## the run is not paused or there is no such card.
func choose(index: int) -> bool:
	if not driver.choose(index):
		return false
	_sync_menu()
	queue_redraw()
	return true


func is_menu_open() -> bool:
	return _menu != null and _menu.visible


func _on_card_picked(index: int) -> void:
	choose(index)


## Opens the menu for a new hand, closes it when the run goes on.
func _sync_menu() -> void:
	if _menu == null:
		return
	var world: WorldState = driver.world
	if not world.is_paused():
		if _menu.visible:
			_menu.close()
	elif not _menu.visible or _menu.revision != world.build_revision:
		_menu.open(driver.config, world)


func _draw() -> void:
	var arena: Vector2 = Vector2(ARENA_CELLS * CELL_PX)
	draw_rect(Rect2(Vector2.ZERO, arena), COLOR_FLOOR)
	for x: int in range(CELL_PX, int(arena.x), CELL_PX):
		draw_line(Vector2(x, 0), Vector2(x, arena.y), COLOR_GRID, 1.0)
	for y: int in range(CELL_PX, int(arena.y), CELL_PX):
		draw_line(Vector2(0, y), Vector2(arena.x, y), COLOR_GRID, 1.0)
	draw_rect(Rect2(Vector2.ZERO, arena), COLOR_WALL, false, 4.0)
	_draw_puffs()
	_draw_gems()
	_draw_enemies()
	_draw_projectiles()
	_draw_hero()
	_draw_pickups()
	if driver.world.is_over():
		draw_rect(Rect2(Vector2.ZERO, arena), COLOR_OVER)
	if _hud != null:
		_hud.queue_redraw()


func _age_effects(delta: float) -> void:
	for uid: Variant in _enemy_flash.keys():
		var left: float = _enemy_flash[uid] - delta
		if left <= 0.0:
			_enemy_flash.erase(uid)
		else:
			_enemy_flash[uid] = left
	for puff: Array in _puffs:
		puff[2] += delta
	_puffs = _puffs.filter(func(puff: Array) -> bool: return puff[2] < PUFF_TIME)
	for pickup: Array in _pickups:
		pickup[2] += delta
	_pickups = _pickups.filter(func(pickup: Array) -> bool: return pickup[2] < PICKUP_FLY + PICKUP_TEXT)
	_level_ring = maxf(_level_ring - delta, 0.0)


func _draw_enemies() -> void:
	var world: WorldState = driver.world
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0:
			continue
		var kind: int = world.enemy_kind[slot]
		var color: Color = _enemy_color(kind)
		if _enemy_flash.has(world.enemy_uid[slot]):
			color = color.lerp(COLOR_ENEMY_HIT, 0.75)
		var radius: float = _kind_radius_px(kind)
		var at: Vector2 = driver.enemy_position_px(slot)
		draw_circle(at, radius, color)
		draw_circle(at, radius, color.darkened(0.45), false, 2.0)


func _draw_projectiles() -> void:
	var world: WorldState = driver.world
	var radius: float = float(driver.config.projectile_radius_su) / Fx.FX_ONE
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var at: Vector2 = driver.projectile_position_px(slot)
		var heading: Vector2 = Vector2(world.proj_vx[slot], world.proj_vy[slot]).normalized()
		draw_circle(at, radius * 1.3, COLOR_SWORD_GLOW)
		draw_line(at - heading * radius * 2.2, at + heading * radius * 1.2, COLOR_SWORD, radius * 0.6)
		draw_circle(at + heading * radius * 1.2, radius * 0.35, COLOR_SWORD)


func _draw_puffs() -> void:
	for puff: Array in _puffs:
		var share: float = puff[2] / PUFF_TIME
		var radius: float = _kind_radius_px(puff[1]) * (1.0 + share)
		var color: Color = _enemy_color(puff[1])
		color.a = 1.0 - share
		draw_circle(puff[0], radius, color, false, 3.0)
		color.a *= 0.35
		draw_circle(puff[0], radius * 0.6, color)


func _draw_gems() -> void:
	var world: WorldState = driver.world
	for slot: int in world.gem_slots():
		if world.gem_uid[slot] != 0:
			_draw_gem(self, driver.gem_position_px(slot), world.gem_value[slot], 1.0)


## A diamond: 10 px across for value 10 and below, 13 px for more (ADR-010 section 8).
static func _draw_gem(canvas: CanvasItem, at: Vector2, value: int, alpha: float) -> void:
	var half: float = (5.0 if value <= 10 else 6.5)
	var color: Color = COLOR_GEM
	color.a = alpha
	var points: PackedVector2Array = PackedVector2Array([
		at + Vector2(0, -half * 1.3), at + Vector2(half, 0), at + Vector2(0, half * 1.3), at + Vector2(-half, 0),
	])
	canvas.draw_colored_polygon(points, color)
	canvas.draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.4), 1.5)


func _draw_pickups() -> void:
	var hero: Vector2 = driver.hero_position_px()
	var font: Font = ThemeDB.fallback_font
	for pickup: Array in _pickups:
		var age: float = pickup[2]
		if age < PICKUP_FLY:
			_draw_gem(self, (pickup[0] as Vector2).lerp(hero, age / PICKUP_FLY), pickup[1], 1.0)
			continue
		var share: float = (age - PICKUP_FLY) / PICKUP_TEXT
		var color: Color = COLOR_GEM
		color.a = 1.0 - share
		var at: Vector2 = hero + Vector2(HERO_RADIUS_PX * 0.6, -HERO_RADIUS_PX - 18 - 24 * share)
		draw_string(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if _level_ring > 0.0:
		var share: float = 1.0 - _level_ring / LEVEL_RING
		var ring: Color = COLOR_GEM
		ring.a = 1.0 - share
		draw_circle(hero, HERO_RADIUS_PX * (1.2 + 1.6 * share), ring, false, 3.0)


## XP bar along the top edge, then run time, kills and level in the top-left screen corner
## (digits and icons only, no text keys yet).
func _draw_hud() -> void:
	if driver == null:
		return
	var width: float = _hud.get_viewport_rect().size.x
	_hud.draw_rect(Rect2(0, 0, width, XP_BAR_HEIGHT), COLOR_XP_BACK)
	if driver.config.has_xp():
		var cost: int = driver.config.xp_cost(driver.world.level)
		var share: float = clampf(float(driver.world.xp_bank) / float(cost), 0.0, 1.0)
		_hud.draw_rect(Rect2(0, 0, width * share, XP_BAR_HEIGHT), COLOR_GEM)
	var corner: Vector2 = HUD_MARGIN
	var seconds: int = floori(driver.world.tick / float(Fx.TICKS_PER_SECOND))
	var font: Font = ThemeDB.fallback_font
	var clock: String = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	_hud.draw_string(font, corner, clock, HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD)
	var icon: Vector2 = corner + Vector2(90, -HUD_FONT_SIZE * 0.35)
	_hud.draw_circle(icon, 8.0, ENEMY_COLORS[1])
	_hud.draw_circle(icon, 8.0, ENEMY_COLORS[1].darkened(0.45), false, 2.0)
	var kills: String = str(driver.world.kills)
	_hud.draw_string(font, corner + Vector2(104, 0), kills, HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD)
	if driver.config.has_xp():
		_draw_gem(_hud, corner + Vector2(170, -HUD_FONT_SIZE * 0.35), 15, 1.0)
		var level: String = str(driver.world.level)
		_hud.draw_string(font, corner + Vector2(184, 0), level, HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD)


func _enemy_color(kind: int) -> Color:
	return ENEMY_COLORS[mini(kind, ENEMY_COLORS.size() - 1)]


func _kind_radius_px(kind: int) -> float:
	if kind >= driver.config.kind_count():
		return 0.0
	return float(driver.config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE


func _draw_hero() -> void:
	var hero: Vector2 = driver.hero_position_px()
	var color: Color = COLOR_HERO_HIT if _flash > 0.0 else COLOR_HERO
	draw_circle(hero, HERO_RADIUS_PX, color)
	draw_circle(hero + _facing * (HERO_RADIUS_PX * 0.55), HERO_RADIUS_PX * 0.25, COLOR_FACING)
	var max_hp: int = driver.world.hero_hp_max
	if max_hp <= 0:
		return
	var bar: Rect2 = Rect2(hero + Vector2(-HERO_RADIUS_PX, -HERO_RADIUS_PX - 12), Vector2(HERO_RADIUS_PX * 2, 5))
	draw_rect(bar, COLOR_HP_BACK)
	var share: float = clampf(float(driver.world.hero_hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), COLOR_HP)
