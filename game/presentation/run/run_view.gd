class_name RunView
extends Node2D
## P0 placeholder run scene: hero movement and auto-attack, jade_grove w0 enemies, contact
## damage and kills in the courtyard of the ruined sect (ArenaDressing). Reads simulation state only;
## input reaches the simulation through FixedTickDriver. Tuning comes from P0Tuning
## (placeholder bases). Hit reactions, falls and decay (EnemyReactions), gem pickup flights and
## the level-up ring are presentation-only effects (ADR-010 section 8). A pending level-up pauses the run under
## ChoiceMenu; a picked card reaches the simulation as a CHOOSE through FixedTickDriver.
## A finished run (victory after the stage duration or defeat) stays under RunResults until
## the player starts a new one (ADR-011 section 1).
## Sprites (ADR-013): the floor texture, the hero and the enemies with an asset in
## SpriteSet are drawn as atlas frames sorted by depth over blob shadows; anything without an
## asset keeps its primitive, so the scene stays playable with no assets at all.
## Isometric view (ADR-014 section 1): ground things are drawn in world px under
## IsoProjection.ground(), upright things at their projected feet; movement keys are read in
## screen axes. Light and shadow (ADR-014 sections 4-5), back to front:
## - GroundLayer (canvas layer -2; sky, distant spires and mist on -3): the lit paving of the
##   terrace, the seal, the cliff faces with waterfalls, the lights of the dressing props and
##   the hero aura;
## - canvas layer -1: every shadow in one CanvasGroup composited once, then the unlit danger
##   marks (zones, telegraphs, puffs, rings) at their exact colours (PLAYABILITY G3);
## - the fallen bodies decaying (EnemyReactions), behind this node;
## - this node: gems, enemies and the courtyard props (ArenaDressing) by depth, projectiles, lit by
##   RunLighting.light_at(feet) and a moon-side rim; then the hero item (warm rim), the item
##   over it (HP bar, enemy shots, pickups) and the additive glow item.

const CELL_PX: int = P0Tuning.CELL_PX
const HERO_RADIUS_PX: int = P0Tuning.HERO_RADIUS_PX
const HIT_FLASH: float = 0.15
## Seconds a collected gem flies to the hero (6 frames at 60 fps), then its "+N" floats.
const PICKUP_FLY: float = 0.1
const PICKUP_TEXT: float = 0.6
## After a defeat the results open once the hero's death clip has played and this long more (s).
const DEATH_BEAT: float = 0.5

## Beyond the arena diamond (ADR-014 section 1; fog and cliffs come with slice A3).
const COLOR_VOID: Color = Color(0.03, 0.03, 0.04)
const COLOR_HERO: Color = Color(0.93, 0.86, 0.66)
const COLOR_FACING: Color = Color(0.25, 0.2, 0.15)
const COLOR_HP_BACK: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_HP: Color = Color(0.85, 0.2, 0.2)
const COLOR_OVER: Color = Color(0.0, 0.0, 0.0, 0.55)
const COLOR_ENEMY_HIT: Color = Color(1.0, 1.0, 1.0)
## Spirit sword (metal element) projectile.
const COLOR_SWORD: Color = Color(0.78, 0.92, 1.0)
const COLOR_SWORD_GLOW: Color = Color(0.45, 0.62, 0.8, 0.9)
const COLOR_SWORD_TRAIL: Color = Color(0.3, 0.42, 0.55, 0.55)
## XP gems: jade blue (red stays reserved for enemies).
const COLOR_GEM: Color = Color(0.36, 0.84, 0.78)
## A gem resting on the ground away from the hero: dimmer (L ~120), bright again in reach.
const COLOR_GEM_REST: Color = Color(0.24, 0.56, 0.52)
const COLOR_GEM_GLOW: Color = Color(0.2, 0.55, 0.5, 0.8)
## status.venom on the hero: tint and one pip per stack above the HP bar.
const COLOR_VENOM: Color = Color(0.45, 0.85, 0.3)
## status.root_slow on the hero: a ring of roots.
const COLOR_ROOTED: Color = Color(0.82, 0.2, 0.28, 0.9)
## Enemy shot (lantern wisp): a pale ghost-fire orb with a glow.
const COLOR_WISP: Color = Color(0.72, 1.0, 0.86)
const COLOR_WISP_GLOW: Color = Color(0.35, 0.8, 0.6, 0.9)
## Halo over the flame of a lantern or brazier prop.
const COLOR_LANTERN_GLOW: Color = Color(0.85, 0.5, 0.22, 0.9)
const HERO_ASSET: String = "asset.char.hero_sword"
const FLOOR_ASSET: String = "asset.tile.sect_courtyard_floor"
const SEAL_ASSET: String = "asset.tile.sect_seal"
const CLIFF_ASSET: String = "asset.tile.sect_cliff"
const WORN_FLOOR_ASSET: String = "asset.tile.sect_courtyard_floor_worn"
## Enemy content id -> sprite asset_id; kinds not listed keep their circles.
const ENEMY_ASSETS: Dictionary = {
	"enemy.yin_corpse": "asset.enemy.yin_corpse",
	"enemy.blood_wolf": "asset.enemy.blood_wolf",
	"enemy.wandering_spirit": "asset.enemy.wandering_spirit",
	"enemy.venom_spirit_snake": "asset.enemy.venom_spirit_snake",
	"enemy.sickle_mantis": "asset.enemy.sickle_mantis",
	"enemy.fallen_sword_disciple": "asset.enemy.fallen_sword_disciple",
	"enemy.cursed_spirit_lantern": "asset.enemy.cursed_spirit_lantern",
	"enemy.paper_puppet": "asset.enemy.paper_puppet",
}
## Hit flash of a sprite (modulate above 1 brightens it). The hero flashes white: the threat
## hue stays reserved for enemies (ADR-014 section 2).
const TINT_ENEMY_HIT: Color = Color(2.2, 2.2, 2.2)
const TINT_HERO_HIT: Color = Color(1.9, 1.9, 1.9)
## Seconds the hero flash stays at full white before it fades; a new flash waits this long
## after the last one ended.
const HIT_FLASH_PEAK: float = 0.07
const HIT_FLASH_REST: float = 0.3
## Gems float above their ground point and bob; in reach (pickup radius x GEM_NEAR_RADII) they
## brighten and glow.
const GEM_LIFT_PX: float = 7.0
const GEM_BOB_PX: float = 2.0
const GEM_BOB_HZ: float = 0.8
const GEM_REST_SCALE: float = 0.8
const GEM_REST_ALPHA: float = 0.7
const GEM_NEAR_RADII: float = 2.0
## Rim on the moon side of upright sprites (shaders/sprite_rim.gdshader): moonlit blue on the
## enemies, strong enough to cut each one out of the horde and the floor (ADR-014 section 19),
## warm on the hero.
const RIM_ENEMY: Color = Color(0.66, 0.76, 0.98)
const RIM_ENEMY_STRENGTH: float = 0.6
const RIM_HERO: Color = Color(1.0, 0.86, 0.6)
const RIM_HERO_STRENGTH: float = 0.65
const SHADOW_SHADER: Shader = preload("res://presentation/run/shaders/shadow_group.gdshader")
## Lantern pools the shadow shader fills (its MAX_LIGHTS).
const MAX_SHADOW_POOLS: int = 16
## Canvas layer of the HUD, the menu and the results: above the frame grade.
const HUD_LAYER: int = 2
## Camera zoom and the inset (cells) from the walls inside which it follows the hero.
const CAMERA_ZOOM: float = 1.3
const CAMERA_INSET_CELLS: float = 4.0
## Screen px a hero projectile flies above its ground point.
const FLIGHT_LIFT_PX: float = 26.0
## Enemy shots leave the lantern's eye: its hover lift (EnemyMotion.HOVER) plus the eye 36 px
## above its feet (ADR-014 section 27).
const SHOT_LIFT_PX: float = 52.0
## Px of horizontal hero offset before an enemy turns to face the other way.
const TURN_DEADBAND_PX: float = 6.0
## Frame of an enemy attack clip on which its contact damage lands (the claw fully extended).
const CONTACT_STRIKE_FRAME: int = 2
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
var session_profile: P0SessionProfile = P0SessionProfile.new()
var rules_snapshot: RunRulesSnapshot
var _registry: ContentRegistry
var _facing: Vector2 = Vector2.RIGHT
var _flash: float = 0.0
## Blows on the enemies: flash, push and recoil clip (ADR-014 A5b).
var _reactions: EnemyReactions = EnemyReactions.new()
## Seconds of the longest enemy hit clip of the run.
var _hit_keep: float = 0.0
## Gem pickups in flight: [from px, value, age seconds].
var _pickups: Array[Array] = []
## Combat effects (ADR-014 section 18, A6).
var _vfx: CombatVfx
var _chain_line: PackedVector2Array = PackedVector2Array()
var _chain_left: float = 0.0
## Pose of each enemy drawn in the last frame by uid: an enemy killed next frame decays in it.
var _body_poses: Dictionary = {}
## Tone of the world frame, over the scene and under the HUD (ADR-014 section 20).
var _grade: FrameGrade
## Screen-space layer for the HUD (not moved by the camera).
var _hud: RunHud
var _menu: ChoiceMenu
var _results: RunResults
var _rewards: RunRewards
var _run_uid: String = ""
var _class_select: ClassSelect
var _last_class_id: String = "class.sword"
var _sprites: SpriteSet = SpriteSet.new()
## Sprite asset_id per enemy kind of the current run ("" = primitive).
var _kind_assets: PackedStringArray = PackedStringArray()
## Enemy uid -> true while it faces left.
## Screen facing of each enemy as signs (x, y), turned with a deadband per axis (uid -> Vector2i).
var _faces: Dictionary = {}
## Enemy poses of the current frame (slot -> pose): the shadow and the body draw share one.
var _poses: Dictionary = {}
## Seconds of walk animation (stops with the run).
var _anim_time: float = 0.0
var _hero_moving: bool = false
var _hero_stride_time: float = 0.0
## Hero clips (ADR-014 A4): seconds into the attack after a cast (< 0: none) and its aim (world),
## seconds since a defeat started the death clip.
var _attack_time: float = -1.0
var _attack_aim: Vector2 = Vector2.RIGHT
var _death_time: float = -1.0
var _flash_rest: float = 0.0
var _halo_texture: Texture2D = GroundLayer._radial_texture(64)
var _disc_texture: Texture2D = RunLighting.disc_texture(32)
var _ground: GroundLayer
## Courtyard props (ArenaDressing.placements, plus their cached screen point, depth key and
## fixed light: they never move) and the ground points of the lit ones.
var _props: Array[Dictionary] = []
var _lanterns: Array[Vector2] = []
var _flames: Array[Vector2] = []
var _shadow_canvas: Node2D
var _danger: Node2D
var _hero_item: Node2D
var _over: Node2D
var _glow: Node2D
var _decay: Node2D

@onready var _camera: Camera2D = $Camera


## Movement-only configuration of the arena (kept for tests and tools).
static func placeholder_config() -> SimConfig:
	return P0Tuning.movement_config()


func _ready() -> void:
	UiText.apply_locale()
	_registry = ContentRegistry.load_dir()
	session_profile.registry = _registry
	session_profile.unlock_all = OS.get_cmdline_user_args().has("--unlock-all")
	_sprites = SpriteSet.load_default()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	RenderingServer.set_default_clear_color(COLOR_VOID)
	_grade = FrameGrade.new()
	add_child(_grade)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = HUD_LAYER
	add_child(layer)
	_hud = RunHud.new()
	_hud.kit = HudKit.load_default()
	layer.add_child(_hud)
	var theme: Theme = _hud.kit.menu_theme()
	_menu = ChoiceMenu.new()
	_menu.theme = theme
	_menu.kit = _hud.kit
	layer.add_child(_menu)
	_menu.picked.connect(_on_card_picked)
	_results = RunResults.new()
	_results.kit = _hud.kit
	_results.theme = theme
	_results.rewards_requested.connect(confirm_results)
	layer.add_child(_results)
	_rewards = RunRewards.new()
	_rewards.kit = _hud.kit
	_rewards.theme = theme
	_rewards.continue_requested.connect(confirm_rewards)
	layer.add_child(_rewards)
	_class_select = ClassSelect.new()
	_class_select.kit = _hud.kit
	_class_select.theme = theme
	_class_select.class_confirmed.connect(_on_class_confirmed)
	layer.add_child(_class_select)
	_vfx = CombatVfx.load_default(_hud.kit.font)
	_build_layers()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_show_class_select()


## The lit ground, the shadow buffer and danger marks, and the items over this node.
func _build_layers() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	_props = ArenaDressing.placements(_sprites, data, CELL_PX)
	var light_points: Array[Dictionary] = ArenaDressing.lights(_props)
	for point: Dictionary in light_points:
		_lanterns.append(point["at"])
		_flames.append(IsoProjection.to_screen(point["at"]) - Vector2(0.0, point["flame"]))
	for index: int in _props.size():
		var prop: Dictionary = _props[index]
		# A strip of a large prop sorts at its own cell but stands and is lit where the prop does.
		var base: Vector2 = prop.get("base", prop["at"])
		prop["screen"] = IsoProjection.to_screen(base)
		prop["order"] = Vector2i(roundi(IsoProjection.depth(prop["at"]) * 16.0), -1 - index)
		prop["fixed_light"] = RunLighting.fixed_light(base, _lanterns)
	_ground = GroundLayer.new(
		_sprites, FLOOR_ASSET, data, CELL_PX, light_points, SEAL_ASSET, CLIFF_ASSET, WORN_FLOOR_ASSET,
		ArenaDressing.backdrop(_sprites))
	add_child(_ground)
	var under: CanvasLayer = CanvasLayer.new()
	under.layer = -1
	under.follow_viewport_enabled = true
	add_child(under)
	var group: CanvasGroup = CanvasGroup.new()
	group.use_mipmaps = true
	group.fit_margin = 16.0
	var shadow_material: ShaderMaterial = ShaderMaterial.new()
	shadow_material.shader = SHADOW_SHADER
	shadow_material.set_shader_parameter("shadow_alpha", RunLighting.SHADOW_ALPHA)
	var pools: PackedVector2Array = PackedVector2Array()
	for lantern: Vector2 in _lanterns.slice(0, MAX_SHADOW_POOLS):
		pools.append(IsoProjection.to_screen(lantern))
	shadow_material.set_shader_parameter("lanterns", pools)
	shadow_material.set_shader_parameter("lantern_count", pools.size())
	shadow_material.set_shader_parameter("lantern_radius", RunLighting.LANTERN_RADIUS_PX)
	group.material = shadow_material
	under.add_child(group)
	_shadow_canvas = Node2D.new()
	_shadow_canvas.draw.connect(_draw_shadow_pass)
	group.add_child(_shadow_canvas)
	_danger = Node2D.new()
	_danger.draw.connect(_draw_danger_pass)
	under.add_child(_danger)
	material = RunLighting.rim_material(RIM_ENEMY, RIM_ENEMY_STRENGTH, _flames)
	_decay = _item(_draw_decay_pass, EnemyReactions.dissolve_material())
	_decay.show_behind_parent = true
	_hero_item = _item(_draw_hero_pass, RunLighting.rim_material(RIM_HERO, RIM_HERO_STRENGTH, _flames))
	_over = _item(_draw_over_pass, null)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = _item(_draw_glow_pass, additive)


func _item(drawer: Callable, item_material: Material) -> Node2D:
	var item: Node2D = Node2D.new()
	item.material = item_material
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	item.draw.connect(drawer)
	add_child(item)
	return item


## Screen point the camera aims at: the projected hero, held inside the arena inset so the
## view does not slide over the void.
func camera_target() -> Vector2:
	var inset: Vector2 = Vector2.ONE * CAMERA_INSET_CELLS * CELL_PX
	var arena: Vector2 = Vector2(P0Tuning.arena_cells() * CELL_PX)
	return IsoProjection.to_screen(driver.hero_position_px().clamp(inset, arena - inset))


## Ground points (world px) of the lit courtyard props.
func lantern_positions() -> Array[Vector2]:
	return _lanterns


## Starts a fresh authorized run. An invalid request leaves the current run intact.
func start_run(seed_text: Variant = null, class_id: String = "class.sword") -> bool:
	if seed_text == null:
		seed_text = P0SessionProfile.random_run_seed()
	if seed_text is not String:
		push_error("P0 run refused: seed must be a canonical uint64 decimal string")
		return false
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		_registry, session_profile.granted_unlock_ids(), class_id, P0Tuning.STAGE_ID,
		"difficulty.standard", PackedStringArray(["mode.normal"]), seed_text
	)
	if not snapshot.is_valid():
		push_error("P0 run refused: " + snapshot.error)
		return false
	var candidate: P0Tuning = P0Tuning.new()
	var config: SimConfig = candidate.run_config(_registry, snapshot)
	if config == null:
		push_error("P0 run refused: " + candidate.error)
		return false
	var uid: String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not RunResultReceipt.valid_run_uid(uid):
		push_error("P0 run refused: could not generate a run_uid")
		return false
	if driver != null and _finish_run() == null:
		return false
	tuning = candidate
	rules_snapshot = snapshot
	_run_uid = uid
	_last_class_id = class_id
	_class_select.hide()
	driver = FixedTickDriver.create(config)
	if _hud != null:
		_hud.driver = driver
		_hud.show()
	runs_started += 1
	_kind_assets = PackedStringArray()
	_hit_keep = 0.0
	for enemy_id: String in tuning.enemy_ids:
		_kind_assets.append(str(ENEMY_ASSETS.get(enemy_id, "")))
		_hit_keep = maxf(_hit_keep, _sprites.clip_length(_kind_assets[-1], "hit"))
	_faces.clear()
	_poses.clear()
	_anim_time = 0.0
	_hero_stride_time = 0.0
	_attack_time = -1.0
	_death_time = -1.0
	_hero_moving = false
	_flash = 0.0
	_flash_rest = 0.0
	if _results != null:
		_results.close()
	_rewards.hide()
	_reactions.clear()
	_pickups.clear()
	_body_poses.clear()
	if _vfx != null:
		_vfx.clear()
	_chain_left = 0.0
	_chain_line.clear()
	_camera.position = camera_target()
	_camera.reset_smoothing()
	_ground.follow(driver.hero_position_px(), _camera.position, CAMERA_ZOOM)
	_sync_menu()
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if not read_player_input:
		return
	if Input.is_action_just_pressed("restart") and restart_run():
		return
	advance_frame(delta, IsoProjection.screen_move_to_world(MoveInput.read()))


## The fires flicker on the ground lights, the warm rims and the flame halos.
func _flicker() -> void:
	_ground.flicker(_anim_time)
	for item: CanvasItem in [self, _hero_item]:
		RunLighting.set_flicker(item.material as ShaderMaterial, _anim_time, _flames.size())


func confirm_results() -> bool:
	if not _results.is_armed():
		return false
	var receipt: RunResultReceipt = _finish_run()
	if receipt == null:
		return false
	_results.close()
	_rewards.open(receipt, _registry.definition(RewardPreview.MILESTONE_ID), _unlock_name(receipt))
	return true


func confirm_rewards() -> bool:
	if not _rewards.is_armed():
		return false
	_show_class_select()
	return true


func is_rewards_open() -> bool:
	return _rewards != null and _rewards.visible


func _finish_run() -> RunResultReceipt:
	return session_profile.finish(_run_uid, rules_snapshot, driver)


func _unlock_name(receipt: RunResultReceipt) -> String:
	var definition: Dictionary = _registry.definition(session_profile.unlocked_class_for(receipt))
	return UiText.text(str(definition["name_key"])) if not definition.is_empty() else ""


func _show_class_select() -> void:
	driver = null
	rules_snapshot = null
	_run_uid = ""
	_rewards.hide()
	_hud.hide()
	_menu.close()
	_results.close()
	_vfx.clear()
	_grade.dim = 0.0
	var centre: Vector2 = GroundLayer.centre_of(P0Tuning.arena_data(), CELL_PX)
	_camera.position = IsoProjection.to_screen(centre)
	_camera.reset_smoothing()
	_ground.follow(centre, _camera.position, CAMERA_ZOOM, false)
	_class_select.open(_registry, session_profile.granted_unlock_ids(), _last_class_id)
	queue_redraw()


func _on_class_confirmed(class_id: String) -> void:
	if _class_select.visible:
		start_run(null, class_id)


func is_class_select_open() -> bool:
	return _class_select != null and _class_select.visible


func restart_run() -> bool:
	if driver == null:
		return false
	return start_run(null, _last_class_id)


func is_results_open() -> bool:
	return _results != null and _results.visible


## One presentation frame; `move` is in world axes (tests and replays feed it directly).
func advance_frame(delta: float, move: Vector2i) -> int:
	if driver == null:
		_class_select.age(delta)
		return 0
	if _rewards.visible:
		_rewards.age(delta)
		return 0
	if driver.world.is_paused():
		# The run waits for a card; effects freeze with it.
		_sync_menu()
		_menu.age(delta)
		return 0
	_age_effects(delta)
	_poses.clear()
	if driver.world.is_over():
		_advance_hero_clips(delta, [])
		if _results.visible:
			_results.age(delta)
		else:
			_show_results()
		queue_redraw()
		return 0
	var hp_before: int = driver.world.hero_hp
	var x_before: int = driver.world.player_x
	var y_before: int = driver.world.player_y
	var ticks: int = driver.advance(delta, move)
	var events: Dictionary = driver.take_events()
	for uid: int in events["hit"]:
		_reactions.hit(uid, _hit_keep)
	for gem: Array in events["collected"]:
		_pickups.append([gem[0], gem[1], 0.0])
	_add_effects(events)
	_flash = maxf(_flash - delta, 0.0)
	_flash_rest = maxf(_flash_rest - delta, 0.0)
	if driver.world.hero_hp < hp_before and _flash <= 0.0 and _flash_rest <= 0.0:
		_flash = HIT_FLASH
		_flash_rest = HIT_FLASH + HIT_FLASH_REST
	_anim_time += delta
	_flicker()
	_advance_hero_clips(delta, events["casts"])
	if ticks > 0:
		var travel: Vector2 = Vector2(driver.world.player_x - x_before, driver.world.player_y - y_before)
		_hero_moving = travel != Vector2.ZERO
		if _hero_moving:
			_facing = travel.normalized()
			_hero_stride_time += travel.length() * FixedTickDriver.TICK_SECONDS / P0Tuning.HERO_SPEED_SU_PER_TICK
	_update_facing()
	_camera.position = camera_target()
	_ground.follow(driver.hero_position_px(), _camera.position, CAMERA_ZOOM)
	_sync_menu()
	if driver.world.is_over():
		_show_results()
	queue_redraw()
	return ticks


## Opens the results; after a defeat only once the death clip has played (ADR-014 A4).
func _show_results() -> void:
	if _results == null or _results.visible:
		return
	var receipt: RunResultReceipt = _finish_run()
	if receipt == null:
		return
	if _death_time >= 0.0 and _death_time < _sprites.clip_length(HERO_ASSET, "death") + DEATH_BEAT:
		return
	var class_def: Dictionary = _registry.definition(rules_snapshot.class_id)
	_results.open(receipt, UiText.text(str(class_def["name_key"])), _unlock_name(receipt))
	_hud.hide()


## Picks card `index` of the shown hand (the menu's `picked`, tests and replays); false when
## the run is not paused or there is no such card.
func choose(index: int) -> bool:
	if driver == null or not driver.choose(index):
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
	if _grade != null:
		_grade.dim = ChoiceMenu.DIM if _menu.visible else 0.0


func _draw() -> void:
	_queue_layers()
	if driver != null:
		_draw_gems()
	_draw_bodies()
	if driver != null:
		_draw_projectiles()


func _queue_layers() -> void:
	for item: CanvasItem in [_shadow_canvas, _danger, _decay, _hero_item, _over, _glow, _hud]:
		if item != null:
			item.queue_redraw()


## Effects of this frame's events: a spark and a number for every blow, decay where an enemy
## fell, the sword circle of a cast and the pillar of a level.
func _add_effects(events: Dictionary) -> void:
	var chain_points: PackedVector2Array = events["chain"]
	if chain_points.size() > 1:
		_chain_left = 0.12
		_chain_line.clear()
		for point: Vector2 in chain_points:
			_chain_line.append(IsoProjection.to_screen(point) - Vector2(0, 18))
	if _vfx == null:
		return
	for strike: Array in events["strikes"]:
		_vfx.add_strike(strike[0], strike[1], strike[2], strike[3])
	for kill: Array in events["killed"]:
		# The pose it was drawn in, or (not drawn yet) its kind facing its last diagonal.
		var asset: String = _kind_assets[kill[1]] if kill[1] < _kind_assets.size() else ""
		var standing: Array = [asset, "walk", SpriteSet.diagonal(_faces.get(kill[2], Vector2i(1, 1))), 0]
		var fell: Array = EnemyReactions.death_pose(_sprites, _body_poses.get(kill[2], standing))
		_vfx.add_death(kill[0], fell[0], fell[1])
		_reactions.fallen(kill[2])
	if driver.config.skill_form == SimConfig.SKILL_PROJECTILE and not (events["casts"] as Array).is_empty():
		_vfx.add_cast(driver.hero_position_px())
	if int(events["levels"]) > 0:
		_vfx.level_up(driver.hero_position_px())


func _age_effects(delta: float) -> void:
	_chain_left = maxf(0.0, _chain_left - delta)
	_reactions.age(delta, _hit_keep)
	for pickup: Array in _pickups:
		pickup[2] += delta
	_pickups = _pickups.filter(func(pickup: Array) -> bool: return pickup[2] < PICKUP_FLY + PICKUP_TEXT)
	if _vfx != null:
		_vfx.age(delta)


## Enemies face the hero on screen; each axis turns with a deadband so a horde does not flicker.
func _update_facing() -> void:
	var world: WorldState = driver.world
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px())
	for slot: int in world.enemy_slots():
		var uid: int = world.enemy_uid[slot]
		if uid == 0:
			continue
		var to_hero: Vector2 = hero - IsoProjection.to_screen(driver.enemy_position_px(slot))
		var signs: Vector2i = _faces.get(uid, Vector2i(1, 1))
		if absf(to_hero.x) > TURN_DEADBAND_PX:
			signs.x = 1 if to_hero.x > 0.0 else -1
		if absf(to_hero.y) > TURN_DEADBAND_PX:
			signs.y = 1 if to_hero.y > 0.0 else -1
		_faces[uid] = signs


## _enemy_pose() once per frame and slot.
func _frame_pose(slot: int) -> Array:
	var pose: Variant = _poses.get(slot)
	if pose == null:
		pose = _enemy_pose(slot)
		_poses[slot] = pose
	return pose


## [asset_id, clip, direction, frame] of an enemy sprite (clip "" for a plain atlas); asset ""
## draws the primitive.
func _enemy_pose(slot: int) -> Array:
	var world: WorldState = driver.world
	var kind: int = world.enemy_kind[slot]
	var uid: int = world.enemy_uid[slot]
	var asset: String = _kind_assets[kind] if kind < _kind_assets.size() else ""
	if not _sprites.has(asset):
		return ["", "", "", 0]
	var signs: Vector2i = _faces.get(uid, Vector2i(1, 1))
	if not _sprites.has_clip(asset, "walk"):
		return [asset, "", "left" if signs.x < 0 else "right", SpriteSet.walk_frame(_anim_time, posmod(uid, 4))]
	var direction: String = SpriteSet.diagonal(signs)
	var since: float = _reactions.since(uid)
	if since < _sprites.clip_length(asset, "hit"):
		return [asset, "hit", direction, _sprites.clip_frame(asset, "hit", since)]
	var strike: int = EnemyMotion.attack_frame(driver.config, world, slot, _sprites.clip_frames(asset, "attack"))
	if strike >= 0:
		return [asset, "attack", SpriteSet.diagonal(EnemyMotion.attack_signs(driver.config, world, slot)), strike]
	var contact: bool = driver.config.attack_value(kind, SimConfig.ATTACK_FORM) == SimConfig.FORM_CONTACT
	if contact and _sprites.has_clip(asset, "attack") and EnemySystem.touching(driver.config, world, slot):
		return [asset, "attack", direction, _contact_frame(asset, slot)]
	# Each enemy starts its stride at its own phase, so a horde does not march in step.
	var offset: float = posmod(uid * 7, 16) / 16.0 * _sprites.clip_length(asset, "walk")
	return [asset, "walk", direction, _sprites.clip_frame(asset, "walk", _anim_time + offset)]


## Attack frame of an enemy in contact (ADR-014 A5): the strike frame (CONTACT_STRIKE_FRAME) is
## the tick the contact damage lands, the cooldown to the next hit plays the rest of the swing.
func _contact_frame(asset: String, slot: int) -> int:
	var world: WorldState = driver.world
	var interval: int = maxi(driver.config.kind_value(world.enemy_kind[slot], SimConfig.KIND_INTERVAL), 1)
	var since: float = float(interval - world.enemy_cooldown[slot]) / float(interval)
	if world.enemy_cooldown[slot] == 0:
		since = 1.0 - 1.0 / float(interval)
	var frames: int = _sprites.clip_frames(asset, "attack")
	return posmod(CONTACT_STRIKE_FRAME + floori(since * frames), frames)


## The hero's clip timers: a cast restarts the attack toward its aim, a defeat starts the death.
func _advance_hero_clips(delta: float, casts: Array) -> void:
	if _attack_time >= 0.0:
		_attack_time += delta
		if _attack_time >= _sprites.clip_length(HERO_ASSET, "attack"):
			_attack_time = -1.0
	if not casts.is_empty():
		_attack_time = 0.0
		_attack_aim = casts[-1]
	if _death_time >= 0.0:
		_death_time += delta
	elif driver.world.is_over() and driver.world.hero_dead != 0:
		_death_time = 0.0


## [asset_id, clip, direction, frame] of the hero. An animated atlas (ADR-014 A4) plays death
## after a defeat, run while moving, attack toward the target after a cast while standing, idle
## otherwise, in eight screen directions; a plain atlas walks in four.
func _hero_pose() -> Array:
	if not _sprites.has(HERO_ASSET):
		return ["", "", "", 0]
	var facing: Vector2 = IsoProjection.to_screen(_facing)
	if not _sprites.has_clip(HERO_ASSET, "idle"):
		var frame: int = SpriteSet.walk_frame(_hero_stride_time, 0) if _hero_moving else 0
		return [HERO_ASSET, "", SpriteSet.four_way(facing.normalized()), frame]
	var clip: String = "idle"
	var seconds: float = _anim_time
	if _death_time >= 0.0 and _sprites.has_clip(HERO_ASSET, "death"):
		clip = "death"
		seconds = _death_time
	elif _hero_moving:
		clip = "run"
		seconds = _hero_stride_time
	elif _attack_time >= 0.0:
		clip = "attack"
		seconds = _attack_time
		facing = IsoProjection.to_screen(_attack_aim)
	return [HERO_ASSET, clip, SpriteSet.eight_way(facing), _sprites.clip_frame(HERO_ASSET, clip, seconds)]


## Draws a pose from _hero_pose() / _enemy_pose() with its feet on `at`; false without a sprite.
func _draw_pose(canvas: CanvasItem, pose: Array, at: Vector2, tint: Color) -> bool:
	if pose[0] == "":
		return false
	if pose[1] != "":
		return _sprites.draw_clip(canvas, pose[0], pose[1], pose[2], pose[3], at, tint)
	return _sprites.draw_frame(canvas, pose[0], pose[2], pose[3], at, tint)


## Light on an upright thing standing at `feet` (world px), RunLighting model.
func _light_at(feet: Vector2) -> Color:
	return RunLighting.light_at(feet, driver.hero_position_px(), _lanterns)


# --- shadow layer: one buffer, composited once (ADR-014 section 5) ---

func _draw_shadow_pass() -> void:
	var canvas: Node2D = _shadow_canvas
	var world: WorldState = driver.world if driver != null else null
	# Draw silhouettes first. White contacts on top preserve their coverage in lit areas.
	if world != null:
		for slot: int in world.enemy_slots():
			if world.enemy_uid[slot] != 0:
				var pose: Array = _frame_pose(slot)
				_cast_shadow(canvas, pose, _enemy_feet(slot), EnemyMotion.lift(pose[0], world.enemy_uid[slot], _anim_time))
		_cast_shadow(canvas, _hero_pose(), driver.hero_position_px())
	for prop: Dictionary in _props:
		if prop["prop"] == ArenaDressing.BLOCK_PROP or prop["prop"] == ArenaDressing.RAIL_PROP or prop.has("clip"):
			continue
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(prop["screen"]))
		_sprites.draw_prop(canvas, prop["asset"], prop["prop"], Vector2.ZERO, Color.BLACK, prop["flip"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	# A ruin as wide as several cells has no single base point to lay its silhouette from: its
	# cells darken the ground around its foot instead.
	for prop: Dictionary in _props:
		for polygon: PackedVector2Array in prop.get("footprint", []):
			canvas.draw_colored_polygon(polygon, Color.WHITE)
	for lantern: Vector2 in _lanterns:
		RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(lantern), CELL_PX * 0.65)
	if world == null:
		return
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] != 0:
			var radius: float = _kind_radius_px(world.enemy_kind[slot]) * 0.95
			RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(_enemy_feet(slot)), radius)
	if _vfx != null:
		for death: Array in _vfx.deaths:
			var left: float = 1.0 - CombatVfx.decay(death)
			RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(death[0]), HERO_RADIUS_PX * 0.9 * left)
	RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(driver.hero_position_px()), HERO_RADIUS_PX * 0.95)
	for slot: int in world.gem_slots():
		if world.gem_uid[slot] != 0:
			RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(driver.gem_position_px(slot)), 3.5)
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] != 0:
			RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(driver.projectile_position_px(slot)), 3.0)
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] != 0:
			RunLighting.contact(canvas, _disc_texture, IsoProjection.to_screen(driver.shot_position_px(slot)), 4.0)


## The silhouette laid down away from the moon.
func _cast_shadow(canvas: Node2D, pose: Array, feet_world: Vector2, lift: float = 0.0) -> void:
	if pose[0] != "":
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(IsoProjection.to_screen(feet_world)))
		_draw_pose(canvas, pose, Vector2(0.0, -lift), Color.BLACK)


# --- danger layer: unlit ground marks over the shadows (PLAYABILITY G3) ---

func _draw_danger_pass() -> void:
	if driver == null:
		return
	_danger.draw_set_transform_matrix(IsoProjection.ground())
	for slot: int in driver.world.zone_slots():
		var zone: Dictionary = AttackTelegraph.zone_shape(driver.config, driver.world, slot)
		if not zone.is_empty():
			AttackTelegraph.draw_zone(_danger, zone)
	for slot: int in driver.world.enemy_slots():
		var telegraph: Dictionary = AttackTelegraph.shape(driver.config, driver.world, slot)
		if not telegraph.is_empty():
			AttackTelegraph.draw(_danger, telegraph, driver.enemy_position_px(slot))
	_draw_ground_rings(_danger)
	if driver.world.is_over():
		for rect: Rect2 in GroundLayer.footprint(P0Tuning.arena_data(), CELL_PX):
			_danger.draw_rect(rect, COLOR_OVER)


## The root ring lies on the ground around the hero.
func _draw_ground_rings(canvas: CanvasItem) -> void:
	var hero: Vector2 = driver.hero_position_px()
	if driver.world.root_left > 0:
		canvas.draw_arc(hero, HERO_RADIUS_PX + 4.0, 0.0, TAU, 32, COLOR_ROOTED, 3.0)


# --- upright layer (this node, rim shader) ---

## Bodies and courtyard props sorted by depth (then slot), so a thing nearer the viewer covers
## the one behind it; the hero is drawn over all of them on its own item (PLAYABILITY G3).
func _draw_bodies() -> void:
	_body_poses.clear()
	var order: Array[Vector2i] = []
	if driver != null:
		var world: WorldState = driver.world
		for slot: int in world.enemy_slots():
			if world.enemy_uid[slot] != 0:
				order.append(Vector2i(roundi(IsoProjection.depth(driver.enemy_position_px(slot)) * 16.0), slot))
	for prop: Dictionary in _props:
		order.append(prop["order"])
	order.sort()
	for key: Vector2i in order:
		if key.y < 0:
			_draw_prop(_props[-1 - key.y])
		else:
			_draw_enemy(key.y)


func _draw_enemy(slot: int) -> void:
	var world: WorldState = driver.world
	var kind: int = world.enemy_kind[slot]
	var uid: int = world.enemy_uid[slot]
	var feet: Vector2 = _enemy_feet(slot)
	var at: Vector2 = IsoProjection.to_screen(feet)
	var light: Color = _light_at(feet)
	var pose: Array = _frame_pose(slot)
	var flash: float = _reactions.flash(uid)
	_body_poses[uid] = pose
	var tint: Color = light.lerp(TINT_ENEMY_HIT, flash)
	tint.a = EnemyMotion.opacity(pose[0])
	if pose[0] != "" and _draw_pose(self, pose, at - Vector2(0.0, EnemyMotion.lift(pose[0], uid, _anim_time)), tint):
		return
	var radius: float = _kind_radius_px(kind)
	var color: Color = (_enemy_color(kind) * light).lerp(COLOR_ENEMY_HIT, 0.75 * flash)
	color.a = 1.0
	draw_circle(at - Vector2(0, radius), radius, color)
	draw_circle(at - Vector2(0, radius), radius, color.darkened(0.45), false, 2.0)


## A courtyard prop at its base, lit like an upright body standing there.
func _draw_prop(prop: Dictionary) -> void:
	var base: Vector2 = prop.get("base", prop["at"])
	var light: Color = prop["fixed_light"]
	if driver != null:
		light = RunLighting.with_aura(light, base, driver.hero_position_px())
	if prop.has("clip"):
		_sprites.draw_prop(self, prop["asset"], prop["prop"], prop["screen"], light, false, prop["clip"])
		return
	if prop["prop"] == ArenaDressing.BLOCK_PROP:
		ArenaDressing.draw_block(self, prop, light)
		return
	if prop["prop"] == ArenaDressing.RAIL_PROP:
		ArenaDressing.draw_rail(self, _sprites, prop, light)
		return
	_sprites.draw_prop(self, prop["asset"], prop["prop"], prop["screen"], light, prop["flip"])


## Feet of an enemy sprite (world px): its simulation point, pushed back for a moment by a blow.
func _enemy_feet(slot: int) -> Vector2:
	var feet: Vector2 = driver.enemy_position_px(slot)
	return feet + _reactions.knock(driver.world.enemy_uid[slot], feet - driver.hero_position_px())


## A fallen enemy plays its death clip where it stood and decays there (EnemyReactions), behind
## the living; the yin burst over it is light (glow item).
func _draw_decay_pass() -> void:
	if _vfx != null:
		EnemyReactions.draw_fallen(_decay, _sprites, _vfx.deaths, _light_at)


## Hero projectiles fly above their ground point (their shadow dot marks it), blade along the
## projected heading; with the effects atlas the sword is light and is drawn on the glow item.
func _draw_projectiles() -> void:
	if _vfx != null and _vfx.kit.has("sword"):
		return
	var world: WorldState = driver.world
	var radius: float = float(driver.config.projectile_radius_su) / Fx.FX_ONE
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(driver.projectile_position_px(slot)) - Vector2(0, FLIGHT_LIFT_PX)
		var heading: Vector2 = _projectile_heading(slot)
		draw_line(at - heading * radius * 2.2, at + heading * radius * 1.2, COLOR_SWORD, radius * 0.6)
		draw_circle(at + heading * radius * 1.2, radius * 0.35, COLOR_SWORD)


func _projectile_heading(slot: int) -> Vector2:
	var world: WorldState = driver.world
	return IsoProjection.ground().basis_xform(Vector2(world.proj_vx[slot], world.proj_vy[slot])).normalized()


func _draw_gems() -> void:
	if _vfx != null and _vfx.kit.has("qi_wisp"):
		return
	var world: WorldState = driver.world
	var hero: Vector2 = driver.hero_position_px()
	var near_px: float = float(UpgradeSystem.pickup_radius(driver.config, world)) / Fx.FX_ONE * GEM_NEAR_RADII
	for slot: int in world.gem_slots():
		var uid: int = world.gem_uid[slot]
		if uid == 0:
			continue
		var ground: Vector2 = driver.gem_position_px(slot)
		var bob: float = sin(_anim_time * GEM_BOB_HZ * TAU + float(uid)) * GEM_BOB_PX
		var at: Vector2 = IsoProjection.to_screen(ground) - Vector2(0, GEM_LIFT_PX + bob)
		var near: bool = ground.distance_to(hero) <= near_px
		CombatVfx.draw_gem_primitive(
			self, at, world.gem_value[slot], 1.0, GEM_REST_SCALE, COLOR_GEM if near else COLOR_GEM_REST
		)


# --- hero item (warm rim) and the items over it ---

func _draw_hero_pass() -> void:
	if driver == null:
		return
	var canvas: Node2D = _hero_item
	var feet: Vector2 = driver.hero_position_px()
	var hero: Vector2 = IsoProjection.to_screen(feet)
	var light: Color = _light_at(feet)
	var stacks: int = driver.world.venom_stacks
	var pose: Array = _hero_pose()
	if pose[0] != "":
		var tint: Color = light.lerp(TINT_HERO_HIT, _hero_flash_share())
		if stacks > 0 and _flash <= 0.0:
			tint = tint.lerp(COLOR_VENOM, 0.25 + 0.15 * stacks)
		if _draw_pose(canvas, pose, hero, tint):
			return
	var facing: Vector2 = IsoProjection.to_screen(_facing).normalized()
	var color: Color = COLOR_HERO.lerp(Color.WHITE, _hero_flash_share())
	if stacks > 0 and _flash <= 0.0:
		color = color.lerp(COLOR_VENOM, 0.25 + 0.15 * stacks)
	var body: Vector2 = hero - Vector2(0, HERO_RADIUS_PX)
	canvas.draw_circle(body, HERO_RADIUS_PX, color)
	canvas.draw_circle(body + facing * (HERO_RADIUS_PX * 0.55), HERO_RADIUS_PX * 0.25, COLOR_FACING)


## 0..1 strength of the hero's white hit flash: full for the first HIT_FLASH_PEAK seconds,
## then it fades (ADR-014 A2: a short peak, not a steady white).
func _hero_flash_share() -> float:
	if _flash <= 0.0:
		return 0.0
	var age: float = HIT_FLASH - _flash
	if age <= HIT_FLASH_PEAK:
		return 1.0
	return clampf(_flash / (HIT_FLASH - HIT_FLASH_PEAK), 0.0, 1.0)


## Screen px from the hero's feet to the top of its sprite (or of its primitive).
func _hero_height() -> float:
	return HERO_SPRITE_HEIGHT_PX if _sprites.has(HERO_ASSET) else HERO_RADIUS_PX * 2.0


## Venom pips and the HP bar above the hero's head, enemy shots over the hero (an incoming
## wisp stays visible), gem flights and "+N".
func _draw_over_pass() -> void:
	if driver == null:
		return
	var canvas: Node2D = _over
	if _chain_left > 0.0:
		var alpha: float = _chain_left / 0.12
		canvas.draw_polyline(_chain_line, Color(0.50, 0.49, 1.0, alpha), 5.0, true)
		canvas.draw_polyline(_chain_line, Color(0.85, 0.92, 1.0, alpha), 2.0, true)
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px())
	var stacks: int = driver.world.venom_stacks
	var top: float = -_hero_height() - 8.0
	for pip: int in stacks:
		canvas.draw_circle(hero + Vector2(-8.0 + 8.0 * pip, top - 6.0), 3.0, COLOR_VENOM)
	var max_hp: int = driver.world.hero_hp_max
	if max_hp > 0:
		var bar: Rect2 = Rect2(hero + Vector2(-HERO_RADIUS_PX, top), Vector2(HERO_RADIUS_PX * 2, 5))
		canvas.draw_rect(bar, COLOR_HP_BACK)
		var share: float = clampf(float(driver.world.hero_hp) / float(max_hp), 0.0, 1.0)
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), COLOR_HP)
	var world: WorldState = driver.world
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(driver.shot_position_px(slot)) - Vector2(0, SHOT_LIFT_PX)
		canvas.draw_circle(at, float(world.shot_radius[slot]) / Fx.FX_ONE, COLOR_WISP)
	var font: Font = _hud.kit.font if _hud != null and _hud.kit != null else ThemeDB.fallback_font
	var gem_light: bool = _vfx != null and _vfx.kit.has("qi_wisp")
	for pickup: Array in _pickups:
		var age: float = pickup[2]
		if age < PICKUP_FLY:
			if not gem_light:
				CombatVfx.draw_gem_primitive(canvas, _pickup_flight(pickup), pickup[1], 1.0, GEM_REST_SCALE, COLOR_GEM)
			continue
		var fade: float = (age - PICKUP_FLY) / PICKUP_TEXT
		var color: Color = COLOR_GEM
		color.a = 1.0 - fade
		var at: Vector2 = hero + Vector2(HERO_RADIUS_PX * 0.6, -_hero_height() - 6 - 24 * fade)
		canvas.draw_string_outline(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3,
			Color(0.02, 0.06, 0.08, 0.8 * color.a))
		canvas.draw_string(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if _vfx != null:
		_vfx.draw_numbers(canvas)


## Where a collected gem is on its short flight to the hero (screen px).
func _pickup_flight(pickup: Array) -> Vector2:
	var hero: Vector2 = IsoProjection.to_screen(driver.hero_position_px()) - Vector2(0, GEM_LIFT_PX)
	var from: Vector2 = IsoProjection.to_screen(pickup[0]) - Vector2(0, GEM_LIFT_PX)
	return from.lerp(hero, clampf(pickup[2] / PICKUP_FLY, 0.0, 1.0))


# --- glow item (additive): flames, blades and trails, wisps, gems near the hero ---

func _draw_glow_pass() -> void:
	var canvas: Node2D = _glow
	for index: int in _flames.size():
		RunLighting.halo(
			canvas, _halo_texture, _flames[index], 26.0 * RunLighting.flicker(_anim_time, index), COLOR_LANTERN_GLOW
		)
	var radius: float = float(driver.config.projectile_radius_su) / Fx.FX_ONE
	var light: bool = _vfx != null and _vfx.kit.has("sword")
	if light:
		_draw_vfx_light(canvas)
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(driver.projectile_position_px(slot)) - Vector2(0, FLIGHT_LIFT_PX)
		var heading: Vector2 = _projectile_heading(slot)
		if light:
			_vfx.draw_sword(canvas, at, heading)
			continue
		canvas.draw_line(at - heading * radius * 6.0, at, COLOR_SWORD_TRAIL, radius * 0.9)
		RunLighting.halo(canvas, _halo_texture, at, radius * 2.6, COLOR_SWORD_GLOW)
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] != 0:
			var at: Vector2 = IsoProjection.to_screen(driver.shot_position_px(slot)) - Vector2(0, SHOT_LIFT_PX)
			RunLighting.halo(
				canvas, _halo_texture, at, float(world.shot_radius[slot]) / Fx.FX_ONE * 3.2, COLOR_WISP_GLOW
			)
	var hero: Vector2 = driver.hero_position_px()
	var near_px: float = float(UpgradeSystem.pickup_radius(driver.config, world)) / Fx.FX_ONE * GEM_NEAR_RADII
	for slot: int in world.gem_slots():
		if world.gem_uid[slot] != 0 and driver.gem_position_px(slot).distance_to(hero) <= near_px:
			var at: Vector2 = IsoProjection.to_screen(driver.gem_position_px(slot)) - Vector2(0, GEM_LIFT_PX)
			RunLighting.halo(canvas, _halo_texture, at, 14.0, COLOR_GEM_GLOW)


## Effects light of the atlas: bursts and circles, the gems (a qi wisp brighter near the hero, as
## it is about to be drawn in) and the gems flying in.
func _draw_vfx_light(canvas: Node2D) -> void:
	_vfx.draw_light(canvas)
	var world: WorldState = driver.world
	var hero: Vector2 = driver.hero_position_px()
	var near_px: float = float(UpgradeSystem.pickup_radius(driver.config, world)) / Fx.FX_ONE * GEM_NEAR_RADII
	for slot: int in world.gem_slots():
		var uid: int = world.gem_uid[slot]
		if uid == 0:
			continue
		var ground: Vector2 = driver.gem_position_px(slot)
		var bob: float = sin(_anim_time * GEM_BOB_HZ * TAU + float(uid)) * GEM_BOB_PX
		var at: Vector2 = IsoProjection.to_screen(ground) - Vector2(0, GEM_LIFT_PX + bob)
		var near: bool = ground.distance_to(hero) <= near_px
		_vfx.draw_gem(canvas, at, world.gem_value[slot], 1.0 if near else GEM_REST_ALPHA, 1.0 if near else GEM_REST_SCALE)
	for pickup: Array in _pickups:
		if pickup[2] < PICKUP_FLY:
			_vfx.draw_gem(canvas, _pickup_flight(pickup), pickup[1], 1.0)


func _enemy_color(kind: int) -> Color:
	return ENEMY_COLORS[mini(kind, ENEMY_COLORS.size() - 1)]


func _kind_radius_px(kind: int) -> float:
	if kind >= driver.config.kind_count():
		return 0.0
	return float(driver.config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE
