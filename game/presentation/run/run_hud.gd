class_name RunHud
extends Node2D
## Run HUD in the gold kit (ADR-014 section 15), laid out after the REF-023 battle frame: the hero
## portrait in the dragon ring with the level seal, HP and experience bars to its right; the stage
## plaque, run time and lotus divider at the top centre; the slain counter at the top right.
## Screen px of the 1280 x 720 canvas (stretch mode canvas_items, aspect expand: a wider window
## only moves the centre and right groups). Presentation only: reads the world, never writes it.

const MARGIN: Vector2 = Vector2(10, 6)
const BAR_SIZE: Vector2 = Vector2(280, 24)
const XP_BAR_SIZE: Vector2 = Vector2(240, 20)
const BAR_GAP: float = 4.0
## The level seal sits on the lower right of the ring, over its rim.
const SEAL_OFFSET: Vector2 = Vector2(-22, 62)
const TIMER_FONT_SIZE: int = 32
const TITLE_FONT_SIZE: int = 18
const COUNT_FONT_SIZE: int = 17
const BAR_FONT_SIZE: int = 15
const SEAL_FONT_SIZE: int = 22
const COLOR_GOLD_TEXT: Color = Color(0.97, 0.85, 0.56)
const COLOR_TEXT: Color = Color(0.97, 0.94, 0.88)
## The stage of the P0 run (stage.jade_grove).
const STAGE_NAME_KEY: String = "STAGE_JADE_NAME"

var driver: FixedTickDriver
var kit: HudKit


## Rects of the HUD groups on a canvas of `size` (screen px), for the kit `kit`.
static func layout(hud_kit: HudKit, size: Vector2) -> Dictionary:
	var ring: Rect2 = Rect2(MARGIN, hud_kit.size_of("portrait_ring"))
	var seal_size: Vector2 = hud_kit.size_of("level_seal")
	var seal: Rect2 = Rect2(Vector2(ring.end.x, ring.position.y) + SEAL_OFFSET, seal_size)
	var hp: Rect2 = Rect2(Vector2(ring.end.x + 6.0, MARGIN.y + 16.0), BAR_SIZE)
	var xp: Rect2 = Rect2(Vector2(hp.position.x, hp.end.y + BAR_GAP), XP_BAR_SIZE)
	var plaque_size: Vector2 = hud_kit.size_of("title_plaque")
	var plaque: Rect2 = Rect2(Vector2(roundf((size.x - plaque_size.x) * 0.5), MARGIN.y), plaque_size)
	var divider_size: Vector2 = hud_kit.size_of("divider_lotus")
	var divider: Rect2 = Rect2(Vector2(roundf((size.x - divider_size.x) * 0.5), plaque.end.y + 34.0), divider_size)
	var capsule_size: Vector2 = hud_kit.size_of("counter_capsule")
	var capsule: Rect2 = Rect2(Vector2(size.x - MARGIN.x - capsule_size.x, MARGIN.y + 4.0), capsule_size)
	return {"ring": ring, "seal": seal, "hp": hp, "xp": xp, "plaque": plaque, "divider": divider, "capsule": capsule}


## Share of the hero's HP left and of the experience to the next level (0-1).
static func shares(run: FixedTickDriver) -> Vector2:
	var world: WorldState = run.world
	var hp: float = clampf(float(world.hero_hp) / float(maxi(world.hero_hp_max, 1)), 0.0, 1.0)
	var xp: float = 0.0
	if run.config.has_xp():
		xp = clampf(float(world.xp_bank) / float(maxi(run.config.xp_cost(world.level), 1)), 0.0, 1.0)
	return Vector2(hp, xp)


func _draw() -> void:
	if driver == null or kit == null or not kit.has("portrait_ring"):
		return
	var world: WorldState = driver.world
	var at: Dictionary = layout(kit, get_viewport_rect().size)
	var share: Vector2 = shares(driver)
	_draw_portrait(at["ring"])
	var hp_text: String = "%d / %d" % [roundi(world.hero_hp / 1000.0), roundi(world.hero_hp_max / 1000.0)]
	_draw_bar(at["hp"], "fill_red", share.x, hp_text)
	if driver.config.has_xp():
		_draw_bar(at["xp"], "fill_gold", share.y, "%d%%" % floori(share.y * 100.0))
		var seal: Rect2 = at["seal"]
		kit.draw(self, "level_seal", seal)
		var inside: Rect2 = kit.window("level_seal", seal)
		kit.draw_text(self, str(world.level), inside.get_center().x, inside.get_center().y + SEAL_FONT_SIZE * 0.32,
			SEAL_FONT_SIZE, COLOR_GOLD_TEXT)
	var plaque: Rect2 = at["plaque"]
	kit.draw(self, "title_plaque", plaque)
	var panel: Rect2 = kit.window("title_plaque", plaque)
	kit.draw_text(self, UiText.text(STAGE_NAME_KEY), panel.get_center().x, panel.get_center().y + TITLE_FONT_SIZE * 0.32,
		TITLE_FONT_SIZE, COLOR_GOLD_TEXT)
	var clock: String = RunResults.clock(world.tick)
	kit.draw_text(self, clock, plaque.get_center().x, plaque.end.y + 29.0, TIMER_FONT_SIZE, COLOR_TEXT)
	kit.draw(self, "divider_lotus", at["divider"])
	_draw_counter(at["capsule"], UiText.text("UI_HUD_SLAIN") % world.kills)


func _draw_portrait(ring: Rect2) -> void:
	var hole: Rect2 = kit.window("portrait_ring", ring)
	var side: float = maxf(hole.size.x, hole.size.y) + 6.0
	kit.draw(self, "portrait", Rect2(hole.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)))
	kit.draw(self, "portrait_ring", ring)


func _draw_bar(rect: Rect2, fill: String, share: float, label: String) -> void:
	kit.draw(self, "bar_frame", rect)
	var trough: Rect2 = kit.window("bar_frame", rect)
	kit.draw_fill(self, fill, trough, share)
	var baseline: float = trough.get_center().y + BAR_FONT_SIZE * 0.34
	kit.draw_text(self, label, trough.get_center().x, baseline, BAR_FONT_SIZE, COLOR_TEXT)


func _draw_counter(capsule: Rect2, text: String) -> void:
	kit.draw(self, "counter_capsule", capsule)
	var socket: Rect2 = kit.window("counter_capsule", capsule)
	var side: float = maxf(socket.size.x, socket.size.y) + 4.0
	kit.draw(self, "icon_slain", Rect2(socket.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)))
	var text_x: float = (socket.end.x + capsule.end.x - 8.0) * 0.5
	kit.draw_text(self, text, text_x, capsule.get_center().y + COUNT_FONT_SIZE * 0.32, COUNT_FONT_SIZE, COLOR_TEXT)
