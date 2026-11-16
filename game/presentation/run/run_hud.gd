class_name RunHud
extends Node2D
## Run HUD in the gold kit (ADR-014 sections 15 and 21), laid out after the REF-023 battle frame:
## the hero portrait in the dragon ring over the left end of a dark plaque (REF-022) that holds the
## level and the slim HP and experience bars (REF-011); the stage plaque, run time and lotus divider
## at the top centre; the slain counter at the top right.
## Screen px of the 1280 x 720 canvas (stretch mode canvas_items, aspect expand: a wider window
## only moves the centre and right groups). Presentation only: reads the world, never writes it.

const MARGIN: Vector2 = Vector2(10, 6)
## The plaque starts under the middle of the ring, so the ring covers its plain left end.
const PLAQUE_UNDER_RING: float = 0.5
## Share of the plaque width its cloud scroll takes on the right: the bars end before it.
const PLAQUE_SCROLL_SHARE: float = 0.13
## Rows inside the plaque (screen px): the level line, the HP bar, the experience bar.
const LEVEL_ROW: float = 17.0
## The troughs hold 14 and 13 px figures with their outline (fit_height), so the percent reads
## as well as the HP.
const BAR_HEIGHT: float = 21.0
const XP_BAR_HEIGHT: float = 20.0
const ROW_GAP: float = 2.0
const TIMER_FONT_SIZE: int = 32
const TITLE_FONT_SIZE: int = 18
const COUNT_FONT_SIZE: int = 17
const BAR_FONT_SIZE: int = 15
## Numbers over the bright gold and red fills get a heavier outline.
const BAR_OUTLINE: int = 1
const LEVEL_FONT_SIZE: int = 17
## The widest values each place is sized for: the size stays put while the run counts up
## (ADR-014 section 21). A count past COUNT_LIMIT is shortened ("123 тыс."); up to
## SAMPLE_SHORT_COUNT the counter keeps its size.
const SAMPLE_HP: String = "9999 / 9999"
const SAMPLE_XP: String = "100%"
const SAMPLE_COUNT: String = "99999"
const SAMPLE_SHORT_COUNT: int = 999999
const COUNT_LIMIT: int = 100000
## The capsule is drawn this much larger than its piece: the count needs the room of five
## figures left of the cloud scroll.
const CAPSULE_SCALE: float = 1.2
## Text keeps this far (screen px) inside the window of its frame, clear of the ornament.
const TEXT_INSET: Vector2 = Vector2(6, 0)
## The plaque window runs under its scrolls; the stage name stays between them.
const PLAQUE_INSET: Vector2 = Vector2(18, 0)
## The capsule ends in a cloud scroll on the right, about a fifth of its width: the count stays
## left of it.
const CAPSULE_RIGHT_CAP_SHARE: float = 0.2
const COLOR_GOLD_TEXT: Color = Color(0.97, 0.85, 0.56)
const COLOR_TEXT: Color = Color(0.97, 0.94, 0.88)
## The stage of the P0 run (stage.jade_grove).
const STAGE_NAME_KEY: String = "STAGE_JADE_NAME"

var driver: FixedTickDriver
var kit: HudKit


## Rects of the HUD groups on a canvas of `size` (screen px), for the kit `kit`.
static func layout(hud_kit: HudKit, size: Vector2) -> Dictionary:
	var ring: Rect2 = Rect2(MARGIN, hud_kit.size_of("portrait_ring"))
	var status_size: Vector2 = hud_kit.size_of("status_plaque")
	var status: Rect2 = Rect2(
		Vector2(ring.position.x + ring.size.x * PLAQUE_UNDER_RING, roundf(ring.get_center().y - status_size.y * 0.5)),
		status_size
	)
	var panel: Rect2 = hud_kit.window("status_plaque", status)
	var left: float = ring.end.x + TEXT_INSET.x
	var right: float = status.end.x - status.size.x * PLAQUE_SCROLL_SHARE
	var top: float = roundf(panel.get_center().y - (LEVEL_ROW + BAR_HEIGHT + XP_BAR_HEIGHT + ROW_GAP * 2.0) * 0.5)
	var level: Rect2 = Rect2(left, top, right - left, LEVEL_ROW)
	var hp: Rect2 = Rect2(left, level.end.y + ROW_GAP, right - left, BAR_HEIGHT)
	var xp: Rect2 = Rect2(left, hp.end.y + ROW_GAP, right - left, XP_BAR_HEIGHT)
	var plaque_size: Vector2 = hud_kit.size_of("title_plaque")
	var plaque: Rect2 = Rect2(Vector2(roundf((size.x - plaque_size.x) * 0.5), MARGIN.y), plaque_size)
	var divider_size: Vector2 = hud_kit.size_of("divider_lotus")
	var divider: Rect2 = Rect2(Vector2(roundf((size.x - divider_size.x) * 0.5), plaque.end.y + 34.0), divider_size)
	var capsule_size: Vector2 = (hud_kit.size_of("counter_capsule") * CAPSULE_SCALE).round()
	var capsule: Rect2 = Rect2(Vector2(size.x - MARGIN.x - capsule_size.x, MARGIN.y + 4.0), capsule_size)
	return {
		"ring": ring, "status": status, "level": level, "hp": hp, "xp": xp, "plaque": plaque, "divider": divider,
		"capsule": capsule,
	}


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
	kit.draw(self, "status_plaque", at["status"])
	_draw_portrait(at["ring"])
	var hp_text: String = "%d / %d" % [roundi(world.hero_hp / 1000.0), roundi(world.hero_hp_max / 1000.0)]
	_draw_bar(at["hp"], "fill_red", share.x, hp_text, SAMPLE_HP)
	if driver.config.has_xp():
		_draw_bar(at["xp"], "fill_gold", share.y, "%d%%" % floori(share.y * 100.0), SAMPLE_XP)
		var level: Rect2 = at["level"]
		var text: String = UiText.text("UI_HUD_LEVEL") % world.level
		var size: int = kit.line_size(text, level, LEVEL_FONT_SIZE)
		var span: float = kit.text_width(text, size)
		kit.draw_text(self, text, level.position.x + span * 0.5, level.get_center().y + size * HudKit.CAP_CENTER, size,
			COLOR_GOLD_TEXT)
	var plaque: Rect2 = at["plaque"]
	kit.draw(self, "title_plaque", plaque)
	var panel: Rect2 = _inset(kit.window("title_plaque", plaque), PLAQUE_INSET)
	kit.draw_text_in(self, UiText.text(STAGE_NAME_KEY), panel, TITLE_FONT_SIZE, COLOR_GOLD_TEXT)
	var clock: String = RunResults.clock(world.tick)
	kit.draw_text(self, clock, plaque.get_center().x, plaque.end.y + 29.0, TIMER_FONT_SIZE, COLOR_TEXT)
	kit.draw(self, "divider_lotus", at["divider"])
	_draw_counter(at["capsule"], UiText.text("UI_HUD_SLAIN") % short_count(world.kills))


func _draw_portrait(ring: Rect2) -> void:
	var hole: Rect2 = kit.window("portrait_ring", ring)
	var side: float = maxf(hole.size.x, hole.size.y) + 6.0
	kit.draw(self, "portrait", Rect2(hole.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)))
	kit.draw(self, "portrait_ring", ring)


func _draw_bar(rect: Rect2, fill: String, share: float, label: String, sample: String) -> void:
	kit.draw(self, "bar_slim", rect)
	var trough: Rect2 = kit.window("bar_slim", rect)
	kit.draw_fill(self, fill, trough, share)
	kit.draw_text_in(self, label, _inset(trough, TEXT_INSET), BAR_FONT_SIZE, COLOR_TEXT, sample, BAR_OUTLINE)


func _draw_counter(capsule: Rect2, text: String) -> void:
	kit.draw(self, "counter_capsule", capsule)
	var socket: Rect2 = kit.window("counter_capsule", capsule)
	var side: float = maxf(socket.size.x, socket.size.y) + 4.0
	kit.draw(self, "icon_slain", Rect2(socket.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)))
	kit.draw_text_in(self, text, count_rect(kit, capsule), COUNT_FONT_SIZE, COLOR_TEXT, count_sample(kit))


## The widest counter text the size is set for: five figures or the shortened thousands, whichever
## is wider in the locale ("Убито: 999 тыс.", "Slain: 99999").
static func count_sample(hud_kit: HudKit) -> String:
	var whole: String = UiText.text("UI_HUD_SLAIN") % SAMPLE_COUNT
	var short: String = UiText.text("UI_HUD_SLAIN") % short_count(SAMPLE_SHORT_COUNT)
	return whole if hud_kit.text_width(whole, COUNT_FONT_SIZE) >= hud_kit.text_width(short, COUNT_FONT_SIZE) else short


## Where the slain count sits in the capsule: right of the icon socket, left of the cloud scroll.
static func count_rect(hud_kit: HudKit, capsule: Rect2) -> Rect2:
	var socket: Rect2 = hud_kit.window("counter_capsule", capsule)
	var left: float = socket.end.x + TEXT_INSET.x
	return Rect2(left, socket.position.y, capsule.end.x - capsule.size.x * CAPSULE_RIGHT_CAP_SHARE - left, socket.size.y)


## A count as the HUD shows it: whole figures up to COUNT_LIMIT, then thousands ("123 тыс.").
static func short_count(count: int) -> String:
	if count < COUNT_LIMIT:
		return str(count)
	return UiText.text("UI_HUD_THOUSANDS") % str(count / 1000)


static func _inset(rect: Rect2, by: Vector2) -> Rect2:
	return rect.grow_individual(-by.x, -by.y, -by.x, -by.y)
