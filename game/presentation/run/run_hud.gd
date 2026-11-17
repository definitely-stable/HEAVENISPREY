class_name RunHud
extends Control
## Screen-space status for the run. One position for each read: HP and Qi beside the portrait,
## elapsed time in the centre, kills at the far edge.

const MARGIN: Vector2 = Vector2(22, 22)
const MEDAL_SCALE: float = 0.72
const TIMER_FONT_SIZE: int = 38
const TITLE_FONT_SIZE: int = 20
const COUNT_FONT_SIZE: int = 32
const BAR_FONT_SIZE: int = 22
const LEVEL_FONT_SIZE: int = 19
const LABEL_FONT_SIZE: int = 19
const TITLE_SECONDS: float = 6.0
const TITLE_FADE_SECONDS: float = 1.0
const TRAIL_DELAY: float = 0.45
const TRAIL_SPEED: float = 0.6
const LOW_HP: float = 0.3
const SAMPLE_HP: String = "9999 / 9999"
const SAMPLE_COUNT: String = "99999"
const SAMPLE_LEVEL: String = "99"
const SAMPLE_TIME: String = "00:00"
const SAMPLE_SHORT_COUNT: int = 999999
const COUNT_LIMIT: int = 100000
const STAGE_NAME_KEY: String = "STAGE_JADE_NAME"

const TRACK: Color = Color("#281e29")
const HP_FILL: Color = Color("#cf7277")
const QI_FILL: Color = Color("#a298d9")
const HP_TRAIL: Color = Color("#e0a4a0")

var driver: FixedTickDriver
var kit: HudKit
var _trail: float = 1.0
var _trail_wait: float = 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


static func layout(hud_kit: HudKit, size: Vector2) -> Dictionary:
	var player: Rect2 = Rect2(MARGIN, Vector2(293, 76))
	var medal: Rect2 = Rect2(MARGIN + Vector2(-6, -12), hud_kit.size_of("medallion") * MEDAL_SCALE)
	var hole: Rect2 = hud_kit.window("medallion", medal)
	var seal_size: Vector2 = Vector2(29, 31)
	var seal_centre: Vector2 = hole.get_center() + hole.size * 0.41
	var seal: Rect2 = Rect2((seal_centre - seal_size * 0.5).round(), seal_size)
	var x: float = player.position.x + 71.0
	var y: float = player.position.y
	var text: Rect2 = Rect2(x, y + 8.0, 203.0, 25.0)
	var hp: Rect2 = Rect2(x, y + 36.0, text.size.x, 9.0)
	var qi: Rect2 = Rect2(x + 40.0, y + 59.0, text.size.x - 40.0, 5.0)
	var cartouche: Rect2 = Rect2(size.x * 0.5 - 112.0, y, 224.0, 68.0)
	var timer: Rect2 = Rect2(cartouche.position + Vector2(10.0, 9.0), Vector2(204.0, 32.0))
	var title: Rect2 = Rect2(cartouche.position + Vector2(9.0, 43.0), Vector2(206.0, 20.0))
	var capsule: Rect2 = Rect2(size.x - MARGIN.x - 136.0, y, 136.0, 68.0)
	return {
		"player": player, "medal": medal, "seal": seal, "hp_text": text, "hp": hp, "qi": qi,
		"cartouche": cartouche, "timer": timer, "title": title, "capsule": capsule,
	}


static func shares(run: FixedTickDriver) -> Vector2:
	var world: WorldState = run.world
	var hp: float = clampf(float(world.hero_hp) / float(maxi(world.hero_hp_max, 1)), 0.0, 1.0)
	var xp: float = 0.0
	if run.config.has_xp():
		xp = clampf(float(world.xp_bank) / float(maxi(run.config.xp_cost(world.level), 1)), 0.0, 1.0)
	return Vector2(hp, xp)


static func title_alpha(seconds: float) -> float:
	return clampf((TITLE_SECONDS + TITLE_FADE_SECONDS - seconds) / TITLE_FADE_SECONDS, 0.0, 1.0)


## The trail waits after damage, follows the fill down and jumps with healing.
static func trail_step(trail: float, wait: float, hp: float, delta: float) -> Vector2:
	if hp >= trail:
		return Vector2(hp, 0.0)
	wait += delta
	if wait < TRAIL_DELAY:
		return Vector2(trail, wait)
	return Vector2(maxf(hp, trail - TRAIL_SPEED * delta), wait)


func _process(delta: float) -> void:
	if driver == null:
		return
	var step: Vector2 = trail_step(_trail, _trail_wait, shares(driver).x, delta)
	if _trail != step.x:
		queue_redraw()
	_trail = step.x
	_trail_wait = step.y


func _draw() -> void:
	if driver == null or kit == null:
		return
	var world: WorldState = driver.world
	var at: Dictionary = layout(kit, size)
	var share: Vector2 = shares(driver)
	HudKit.draw_plate(self, at["player"])
	_draw_portrait(at["medal"])
	var hp: String = "%d / %d" % [roundi(world.hero_hp / 1000.0), roundi(world.hero_hp_max / 1000.0)]
	_draw_hp(at["hp"], at["hp_text"], share.x, hp)
	if driver.config.has_xp():
		_draw_qi(at["qi"], share.y)
		var seal: Rect2 = at["seal"]
		kit.draw(self, "seal_level", seal)
		kit.draw_text_in(self, str(world.level), kit.window("seal_level", seal), LEVEL_FONT_SIZE, HudKit.GOLD, SAMPLE_LEVEL)
	_draw_clock(at, world.tick)
	_draw_counter(at["capsule"], short_count(world.kills))


func _draw_portrait(medal: Rect2) -> void:
	var hole: Rect2 = kit.window("medallion", medal)
	var side: float = maxf(hole.size.x, hole.size.y) + 4.0
	var portrait: Rect2 = Rect2(hole.get_center() - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	kit.draw(self, "portrait", portrait)
	kit.draw(self, "medallion", medal)


func _draw_hp(rect: Rect2, text: Rect2, share: float, label: String) -> void:
	var low: bool = share < LOW_HP
	var heading: Rect2 = Rect2(text.position, Vector2(87.0, text.size.y))
	kit.draw_text_in(self, UiText.text("UI_HUD_HP"), heading,
		LABEL_FONT_SIZE, HudKit.MUTED, "", 0, HORIZONTAL_ALIGNMENT_LEFT)
	var value: Rect2 = Rect2(text.position + Vector2(92.0, 0.0), Vector2(text.size.x - 92.0, text.size.y))
	kit.draw_text_in(self, label, value, BAR_FONT_SIZE,
		HudKit.CRIMSON if low else HudKit.TEXT, SAMPLE_HP, 0, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_rect(rect.grow(1.0), HudKit.BRONZE)
	draw_rect(rect, TRACK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * maxf(_trail, share), rect.size.y)), HP_TRAIL)
	_draw_fill(rect, share, HP_FILL)


func _draw_qi(rect: Rect2, share: float) -> void:
	var label: Rect2 = Rect2(rect.position + Vector2(-40.0, -6.0), Vector2(34.0, 17.0))
	kit.draw_text_in(self, UiText.text("UI_HUD_QI"), label,
		LABEL_FONT_SIZE, HudKit.MUTED, "", 0, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(rect, TRACK)
	_draw_fill(rect, share, QI_FILL)


func _draw_fill(rect: Rect2, share: float, color: Color) -> void:
	if share <= 0.0:
		return
	var fill: Rect2 = Rect2(rect.position, Vector2(roundf(rect.size.x * share), rect.size.y))
	draw_rect(fill, color)
	draw_line(fill.position, Vector2(fill.end.x, fill.position.y), color.lightened(0.28), 1.0)


func _draw_clock(at: Dictionary, tick: int) -> void:
	var panel: Rect2 = at["cartouche"]
	HudKit.draw_plate(self, panel)
	var crest: Vector2 = Vector2(102, 12)
	kit.draw(self, "divider_lotus", Rect2(panel.get_center().x - crest.x * 0.5, panel.position.y - 6.0, crest.x, crest.y))
	var fade: float = title_alpha(tick / float(Fx.TICKS_PER_SECOND))
	var timer: Rect2 = at["timer"]
	timer.position.y += (1.0 - fade) * 10.0
	kit.draw_text_in(self, RunResults.clock(tick), timer, TIMER_FONT_SIZE, HudKit.TEXT, SAMPLE_TIME)
	if fade > 0.0:
		kit.draw_text_in(self, UiText.text(STAGE_NAME_KEY), at["title"], TITLE_FONT_SIZE, Color(HudKit.GOLD, fade))


func _draw_counter(capsule: Rect2, text: String) -> void:
	HudKit.draw_plate(self, capsule)
	var label: Rect2 = Rect2(capsule.position + Vector2(10.0, 6.0), Vector2(capsule.size.x - 20.0, 24.0))
	kit.draw_text_in(self, UiText.text("UI_RUN_KILLS_LABEL"), label, LABEL_FONT_SIZE, HudKit.MUTED)
	kit.draw_text_in(self, text, count_rect(capsule), COUNT_FONT_SIZE, HudKit.TEXT, count_sample())


static func count_sample() -> String:
	var short: String = short_count(SAMPLE_SHORT_COUNT)
	return short if short.length() > SAMPLE_COUNT.length() else SAMPLE_COUNT


static func count_rect(capsule: Rect2) -> Rect2:
	return Rect2(capsule.position + Vector2(10.0, 31.0), Vector2(capsule.size.x - 20.0, 30.0))


static func short_count(count: int) -> String:
	if count < COUNT_LIMIT:
		return str(count)
	return UiText.text("UI_HUD_THOUSANDS") % str(count / 1000)
