class_name RunView
extends Node2D
## P0 placeholder run scene: hero movement and auto-attack, jade_grove w0 enemies, contact
## damage and kills in an empty arena, drawn with primitives. Reads simulation state only;
## input reaches the simulation through FixedTickDriver. Tuning comes from P0Tuning
## (placeholder bases). Hit flashes, death puffs, gem pickup flights and the level-up ring
## are presentation-only effects (ADR-010 section 8). A pending level-up pauses the run under
## ChoiceMenu; a picked card reaches the simulation as a CHOOSE through FixedTickDriver.
## A finished run (victory after the stage duration or defeat) stays under RunResults until
## the player starts a new one (ADR-011 section 1).
## Sprites (ADR-013): the floor texture, the hero and the enemies with an asset in
## SpriteSet are drawn as atlas frames sorted by depth over blob shadows; anything without an
## asset keeps its primitive, so the scene stays playable with no assets at all.
## Isometric view (ADR-014 section 1): the ground (floor, walls, zones, telegraphs, shadows,
## rings) is drawn in world px under IsoProjection.ground(); bodies, gems, projectiles and the
## HUD over them are drawn at their projected points; movement keys are read in screen axes.

const CELL_PX: int = P0Tuning.CELL_PX
const ARENA_CELLS: Vector2i = P0Tuning.ARENA_CELLS
const HERO_RADIUS_PX: int = P0Tuning.HERO_RADIUS_PX
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
## Beyond the arena diamond (ADR-014 section 1; fog and cliffs come with slice A3).
const COLOR_VOID: Color = Color(0.03, 0.03, 0.04)
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
## status.venom on the hero: tint and one pip per stack above the HP bar.
const COLOR_VENOM: Color = Color(0.45, 0.85, 0.3)
## status.root_slow on the hero: a ring of roots.
const COLOR_ROOTED: Color = Color(0.82, 0.2, 0.28, 0.9)
## Enemy shot (lantern wisp): a pale ghost-fire orb with a glow.
const COLOR_WISP: Color = Color(0.72, 1.0, 0.86)
const COLOR_WISP_GLOW: Color = Color(0.45, 0.95, 0.75, 0.3)
const HERO_ASSET: String = "asset.char.hero_sword"
const FLOOR_ASSET: String = "asset.tile.jade_grove_floor"
## Enemy content id -> sprite asset_id; kinds not listed keep their circles.
const ENEMY_ASSETS: Dictionary = {
	"enemy.yin_corpse": "asset.enemy.yin_corpse",
	"enemy.blood_wolf": "asset.enemy.blood_wolf",
}
## Soft contact shadow on the ground: a radial fade over this many body radii.
const SHADOW_RADII: float = 1.25
const SHADOW_ALPHA: float = 0.55
## Hit flash of a sprite (modulate above 1 brightens it). The hero flashes white: the threat
## hue stays reserved for enemies (ADR-014 section 2).
const TINT_ENEMY_HIT: Color = Color(2.2, 2.2, 2.2)
const TINT_HERO_HIT: Color = Color(1.9, 1.9, 1.9)
## Screen px a projectile or an enemy shot flies above its ground point.
const FLIGHT_LIFT_PX: float = 26.0
## Screen px of empty space the camera may show around the arena diamond.
const CAMERA_MARGIN_PX: int = 96
## Px of horizontal hero offset before an enemy turns to face the other way.
const TURN_DEADBAND_PX: float = 6.0
## Screen px from the hero's feet to the top of its sprite (168 atlas px at half size).
const HERO_SPRITE_HEIGHT_PX: float = 84.0
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
var _results: RunResults
var _sprites: SpriteSet = SpriteSet.new()
## Sprite asset_id per enemy kind of the current run ("" = primitive).
var _kind_assets: PackedStringArray = PackedStringArray()
## Enemy uid -> true while it faces left.
var _faces_left: Dictionary = {}
## Seconds of walk animation (stops with the run).
var _anim_time: float = 0.0
var _hero_moving: bool = false
var _shadow_texture: Texture2D = _make_shadow_texture()

@onready var _camera: Camera2D = $Camera


## Movement-only configuration of the arena (kept for tests and tools).
static func placeholder_config() -> SimConfig:
	return P0Tuning.movement_config()


func _ready() -> void:
	UiText.apply_locale()
	_registry = ContentRegistry.load_dir()
	_sprites = SpriteSet.load_default()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	RenderingServer.set_default_clear_color(COLOR_VOID)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Node2D.new()
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	_menu = ChoiceMenu.new()
	layer.add_child(_menu)
	_menu.picked.connect(_on_card_picked)
	_results = RunResults.new()
	layer.add_child(_results)
	var view: Rect2 = IsoProjection.bounds(Vector2(ARENA_CELLS * CELL_PX)).grow(CAMERA_MARGIN_PX)
	_camera.limit_left = floori(view.position.x)
	_camera.limit_top = floori(view.position.y)
	_camera.limit_right = ceili(view.end.x)
	_camera.limit_bottom = ceili(view.end.y)
	start_run(str(randi()))


## A radial fade from black to clear: the soft contact shadow under every body.
static func _make_shadow_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	gradient.add_point(0.45, Color(0.0, 0.0, 0.0, 0.8))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Starts a fresh run; falls back to the empty arena when content cannot be assembled.
func start_run(seed_text: String) -> void:
	var config: SimConfig = tuning.run_config(_registry, seed_text)
	if config == null:
		push_error("P0 run without enemies: " + tuning.error)
		config = placeholder_config()
	driver = FixedTickDriver.create(config)
	runs_started += 1
	_kind_assets = PackedStringArray()
	for enemy_id: String in tuning.enemy_ids:
		_kind_assets.append(str(ENEMY_ASSETS.get(enemy_id, "")))
	_faces_left.clear()
	_anim_time = 0.0
	_hero_moving = false
	_flash = 0.0
	if _results != null:
		_results.close()
	_enemy_flash.clear()
	_puffs.clear()
	_pickups.clear()
	_level_ring = 0.0
	_camera.position = IsoProjection.to_screen(driver.hero_position_px())
	_camera.reset_smoothing()
	_sync_menu()
	queue_redraw()


func _process(delta: float) -> void:
	if not read_player_input:
		return
	if Input.is_action_just_pressed("restart"):
		start_run(str(randi()))
		return
	if Input.is_action_just_pressed("ui_accept") and confirm_results():
		return
	advance_frame(delta, IsoProjection.screen_move_to_world(MoveInput.read()))


## Starts a new run from the results screen once it is armed; false otherwise.
func confirm_results() -> bool:
	if _results == null or not _results.is_armed():
		return false
	start_run(str(randi()))
	return true


func is_results_open() -> bool:
	return _results != null and _results.visible


## One presentation frame; `move` is in world axes (tests and replays feed it directly).
func advance_frame(delta: float, move: Vector2i) -> int:
	if driver.world.is_paused():
		# The run waits for a card; effects freeze with it.
		_sync_menu()
		_menu.age(delta)
		return 0
	_age_effects(delta)
	if driver.world.is_over():
		_show_results()
		_results.age(delta)
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
	_anim_time += delta
	_hero_moving = move != Vector2i.ZERO
	if _hero_moving:
		_facing = Vector2(move).normalized()
	_camera.position = IsoProjection.to_screen(driver.hero_position_px())
	_sync_menu()
	if driver.world.is_over():
		_show_results()
	queue_redraw()
	return ticks


func _show_results() -> void:
	if _results != null and not _results.visible:
		_results.open(driver.world)


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
	# Ground plane, in world px under the isometric matrix.
	draw_set_transform_matrix(IsoProjection.ground())
	_draw_floor(arena)
	draw_rect(Rect2(Vector2.ZERO, arena), COLOR_WALL, false, 4.0)
	_draw_puffs()
	_draw_zones()
	_draw_telegraphs()
	_draw_shadows()
	_draw_ground_rings()
	if driver.world.is_over():
		draw_rect(Rect2(Vector2.ZERO, arena), COLOR_OVER)
	# Upright things at their projected points.
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_gems()
	_draw_bodies()
	_draw_projectiles()
	_draw_hero_overlay()
	_draw_shots()
	_draw_pickups()
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


## The floor texture repeated over the arena, or the flat floor and its grid (ground pass).
func _draw_floor(arena: Vector2) -> void:
	var floor_texture: Texture2D = _sprites.texture(FLOOR_ASSET)
	if floor_texture == null:
		draw_rect(Rect2(Vector2.ZERO, arena), COLOR_FLOOR)
		for x: int in range(CELL_PX, int(arena.x), CELL_PX):
			draw_line(Vector2(x, 0), Vector2(x, arena.y), COLOR_GRID, 1.0)
		for y: int in range(CELL_PX, int(arena.y), CELL_PX):
			draw_line(Vector2(0, y), Vector2(arena.x, y), COLOR_GRID, 1.0)
		return
	var repeat: float = _sprites.floor_repeat_px(FLOOR_ASSET, CELL_PX) / float(floor_texture.get_width())
	draw_set_transform_matrix(IsoProjection.ground() * Transform2D(0.0, Vector2(repeat, repeat), 0.0, Vector2.ZERO))
	draw_texture_rect(floor_texture, Rect2(Vector2.ZERO, arena / repeat), true)
	draw_set_transform_matrix(IsoProjection.ground())


## A soft contact shadow under every body (ground pass: the circle becomes a 2:1 ellipse).
func _draw_shadows() -> void:
	var world: WorldState = driver.world
	var tint: Color = Color(1.0, 1.0, 1.0, SHADOW_ALPHA)
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] != 0:
			_draw_shadow(driver.enemy_position_px(slot), _kind_radius_px(world.enemy_kind[slot]), tint)
	_draw_shadow(driver.hero_position_px(), HERO_RADIUS_PX, tint)


func _draw_shadow(feet: Vector2, radius: float, tint: Color) -> void:
	var half: float = radius * SHADOW_RADII
	draw_texture_rect(_shadow_texture, Rect2(feet - Vector2(half, half), Vector2(half, half) * 2.0), false, tint)


## Bodies sorted by depth (then slot), so a body nearer the viewer covers the one behind it;
## the hero is drawn over all of them (readability before depth, PLAYABILITY G3).
func _draw_bodies() -> void:
	var world: WorldState = driver.world
	var order: Array[Vector2i] = []
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] != 0:
			order.append(Vector2i(roundi(IsoProjection.depth(driver.enemy_position_px(slot)) * 16.0), slot))
	order.sort()
	for key: Vector2i in order:
		_draw_enemy(key.y)
	_draw_hero()


func _draw_enemy(slot: int) -> void:
	var world: WorldState = driver.world
	var kind: int = world.enemy_kind[slot]
	var uid: int = world.enemy_uid[slot]
	var radius: float = _kind_radius_px(kind)
	var at: Vector2 = IsoProjection.to_screen(driver.enemy_position_px(slot))
	var asset: String = _kind_assets[kind] if kind < _kind_assets.size() else ""
	if _sprites.has(asset):
		var dx: float = IsoProjection.to_screen(driver.hero_position_px()).x - at.x
		if dx < -TURN_DEADBAND_PX:
			_faces_left[uid] = true
		elif dx > TURN_DEADBAND_PX:
			_faces_left[uid] = false
		var direction: String = "left" if _faces_left.get(uid, false) else "right"
		var tint: Color = TINT_ENEMY_HIT if _enemy_flash.has(uid) else Color.WHITE
		var frame: int = SpriteSet.walk_frame(_anim_time, posmod(uid, 4))
		if _sprites.draw_frame(self, asset, direction, frame, at, tint):
			return
	var color: Color = _enemy_color(kind)
	if _enemy_flash.has(uid):
		color = color.lerp(COLOR_ENEMY_HIT, 0.75)
	draw_circle(at - Vector2(0, radius), radius, color)
	draw_circle(at - Vector2(0, radius), radius, color.darkened(0.45), false, 2.0)


## Hero projectiles fly above their ground point, pointing along their projected heading.
func _draw_projectiles() -> void:
	var world: WorldState = driver.world
	var radius: float = float(driver.config.projectile_radius_su) / Fx.FX_ONE
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(driver.projectile_position_px(slot)) - Vector2(0, FLIGHT_LIFT_PX)
		var heading: Vector2 = IsoProjection.to_screen(Vector2(world.proj_vx[slot], world.proj_vy[slot])).normalized()
		draw_circle(at, radius * 1.3, COLOR_SWORD_GLOW)
		draw_line(at - heading * radius * 2.2, at + heading * radius * 1.2, COLOR_SWORD, radius * 0.6)
		draw_circle(at + heading * radius * 1.2, radius * 0.35, COLOR_SWORD)


## Enemy shots, drawn over the hero so an incoming wisp stays visible.
func _draw_shots() -> void:
	var world: WorldState = driver.world
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(driver.shot_position_px(slot)) - Vector2(0, FLIGHT_LIFT_PX)
		var radius: float = float(world.shot_radius[slot]) / Fx.FX_ONE
		draw_circle(at, radius * 1.8, COLOR_WISP_GLOW)
		draw_circle(at, radius, COLOR_WISP)


## Death puffs spread on the ground (ground pass).
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
			_draw_gem(self, IsoProjection.to_screen(driver.gem_position_px(slot)), world.gem_value[slot], 1.0)


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


## Gem flights and "+N" (screen pass).
func _draw_pickups() -> void:
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px())
	var font: Font = ThemeDB.fallback_font
	for pickup: Array in _pickups:
		var age: float = pickup[2]
		if age < PICKUP_FLY:
			var from: Vector2 = IsoProjection.to_screen(pickup[0])
			_draw_gem(self, from.lerp(hero, age / PICKUP_FLY), pickup[1], 1.0)
			continue
		var share: float = (age - PICKUP_FLY) / PICKUP_TEXT
		var color: Color = COLOR_GEM
		color.a = 1.0 - share
		var at: Vector2 = hero + Vector2(HERO_RADIUS_PX * 0.6, -_hero_height() - 6 - 24 * share)
		draw_string(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


## The level-up ring and the root ring lie on the ground around the hero (ground pass).
func _draw_ground_rings() -> void:
	var hero: Vector2 = driver.hero_position_px()
	if _level_ring > 0.0:
		var share: float = 1.0 - _level_ring / LEVEL_RING
		var ring: Color = COLOR_GEM
		ring.a = 1.0 - share
		draw_circle(hero, HERO_RADIUS_PX * (1.2 + 1.6 * share), ring, false, 3.0)
	if driver.world.root_left > 0:
		draw_arc(hero, HERO_RADIUS_PX + 4.0, 0.0, TAU, 32, COLOR_ROOTED, 3.0)


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
	var font: Font = ThemeDB.fallback_font
	var clock: String = RunResults.clock(driver.world.tick)
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


## Enemy zones on the floor, under the telegraphs and the enemies (ADR-011 E5).
func _draw_zones() -> void:
	for slot: int in driver.world.zone_slots():
		var zone: Dictionary = AttackTelegraph.zone_shape(driver.config, driver.world, slot)
		if not zone.is_empty():
			AttackTelegraph.draw_zone(self, zone)


## Attack telegraphs under the enemies (AttackTelegraph, ADR-011).
func _draw_telegraphs() -> void:
	for slot: int in driver.world.enemy_slots():
		var telegraph: Dictionary = AttackTelegraph.shape(driver.config, driver.world, slot)
		if not telegraph.is_empty():
			AttackTelegraph.draw(self, telegraph, driver.enemy_position_px(slot))


func _enemy_color(kind: int) -> Color:
	return ENEMY_COLORS[mini(kind, ENEMY_COLORS.size() - 1)]


func _kind_radius_px(kind: int) -> float:
	if kind >= driver.config.kind_count():
		return 0.0
	return float(driver.config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE


func _draw_hero() -> void:
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px())
	var facing: Vector2 = IsoProjection.to_screen(_facing).normalized()
	var color: Color = COLOR_HERO_HIT if _flash > 0.0 else COLOR_HERO
	var stacks: int = driver.world.venom_stacks
	if _sprites.has(HERO_ASSET):
		var tint: Color = TINT_HERO_HIT if _flash > 0.0 else Color.WHITE
		if stacks > 0 and _flash <= 0.0:
			tint = tint.lerp(COLOR_VENOM, 0.25 + 0.15 * stacks)
		var frame: int = SpriteSet.walk_frame(_anim_time, 0) if _hero_moving else 0
		if _sprites.draw_frame(self, HERO_ASSET, SpriteSet.four_way(facing), frame, hero, tint):
			return
	if stacks > 0 and _flash <= 0.0:
		color = color.lerp(COLOR_VENOM, 0.25 + 0.15 * stacks)
	var body: Vector2 = hero - Vector2(0, HERO_RADIUS_PX)
	draw_circle(body, HERO_RADIUS_PX, color)
	draw_circle(body + facing * (HERO_RADIUS_PX * 0.55), HERO_RADIUS_PX * 0.25, COLOR_FACING)


## Screen px from the hero's feet to the top of its sprite (or of its primitive).
func _hero_height() -> float:
	return HERO_SPRITE_HEIGHT_PX if _sprites.has(HERO_ASSET) else HERO_RADIUS_PX * 2.0


## Venom pips and the HP bar above the hero's head, over every body (screen pass).
func _draw_hero_overlay() -> void:
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px())
	var stacks: int = driver.world.venom_stacks
	var top: float = -_hero_height() - 8.0
	for pip: int in stacks:
		draw_circle(hero + Vector2(-8.0 + 8.0 * pip, top - 6.0), 3.0, COLOR_VENOM)
	var max_hp: int = driver.world.hero_hp_max
	if max_hp <= 0:
		return
	var bar: Rect2 = Rect2(hero + Vector2(-HERO_RADIUS_PX, top), Vector2(HERO_RADIUS_PX * 2, 5))
	draw_rect(bar, COLOR_HP_BACK)
	var share: float = clampf(float(driver.world.hero_hp) / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), COLOR_HP)
