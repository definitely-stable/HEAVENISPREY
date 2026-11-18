class_name RunHud
extends Node2D
## Run HUD after REF-067 (HUD v1, ADR-014 section 21): the hero portrait in the dragon medallion
## at the top left with the level seal on its lower right; to its right the crimson health bar
## with lotus caps and the value, under it the slim violet qi bar of the experience to the next
## level; the run time in the lotus cartouche at the top centre, the stage name under it for the
## first seconds of the run; the slain count in the skull capsule at the top right.
## Screen px of the 1280 x 720 canvas (stretch mode canvas_items, aspect expand: a wider window
## only moves the centre and right groups). Presentation only: reads the world, never writes it.

const MARGIN: Vector2 = Vector2(10, 6)
## The bars start this far left of the medallion's right edge: the dragon's head overlaps the
## left lotus cap, as on the board.
const BAR_OVERLAP: float = 6.0
## The health bar's centre sits this far above the portrait's centre; the qi bar follows it.
const HP_RISE: float = 18.0
const HP_WIDTH: float = 300.0
const QI_WIDTH: float = 266.0
const QI_INDENT: float = 14.0
const ROW_GAP: float = 1.0
## The level seal's centre lies on the medallion ring at this angle (degrees, screen y down) and
## this share of the portrait radius out.
const SEAL_ANGLE_DEG: float = 45.0
const SEAL_RADIUS_SHARE: float = 1.08
const CAPSULE_SCALE: float = 1.15
const TIMER_FONT_SIZE: int = 30
const TITLE_FONT_SIZE: int = 17
const COUNT_FONT_SIZE: int = 22
const BAR_FONT_SIZE: int = 18
const LEVEL_FONT_SIZE: int = 19
const HP_VALUE_WIDTH: float = 108.0
const HP_SCRIM: Color = Color(0.10, 0.04, 0.06, 0.56)
## The stage name shows under the cartouche for this many seconds of the run, then fades out.
const TITLE_SECONDS: float = 6.0
const TITLE_FADE_SECONDS: float = 1.0
const TICKS_PER_SECOND: float = 60.0
## The pale trail of lost health waits, then runs down to the fill (shares per second).
const TRAIL_DELAY: float = 0.45
const TRAIL_SPEED: float = 0.6
## Below this share of health the fill pulses (twice a second) and its end glows red.
const LOW_HP: float = 0.3
const LOW_PULSE_HZ: float = 2.0
## The fills are painted bright; they sit deeper in the lacquer track, like the board.
const HP_TINT: Color = Color(0.86, 0.8, 0.8)
const QI_TINT: Color = Color(0.92, 0.92, 1.0)
const FILL_EDGE: Color = Color(1.0, 0.9, 0.78, 0.85)
## The widest values each place is sized for: the size stays put while the run counts up
## (ADR-014 section 21). A count past COUNT_LIMIT is shortened ("123 тыс."); up to
## SAMPLE_SHORT_COUNT the counter keeps its size.
const SAMPLE_HP: String = "9999 / 9999"
const SAMPLE_COUNT: String = "99999"
const SAMPLE_LEVEL: String = "99"
const SAMPLE_TIME: String = "00:00"
const SAMPLE_SHORT_COUNT: int = 999999
const COUNT_LIMIT: int = 100000
## Text keeps this far (screen px) inside the window of its frame, clear of the ornament.
const TEXT_INSET: Vector2 = Vector2(6, 0)
const COLOR_GOLD_TEXT: Color = Color(0.97, 0.85, 0.56)
const COLOR_TEXT: Color = Color(0.97, 0.94, 0.88)
## The stage of the P0 run (stage.jade_grove).
const STAGE_NAME_KEY: String = "STAGE_JADE_NAME"

var driver: FixedTickDriver
var kit: HudKit
## Share of health the pale trail still shows, and how long it has waited (s).
var _trail: float = 1.0
var _trail_wait: float = 0.0
var _clock: float = 0.0
var _hp_scrim: GradientTexture1D = _make_hp_scrim()


## Rects of the HUD groups on a canvas of `size` (screen px), for the kit `kit`.
static func layout(hud_kit: HudKit, size: Vector2) -> Dictionary:
	var medal: Rect2 = Rect2(MARGIN, hud_kit.size_of("medallion"))
	var hole: Rect2 = hud_kit.window("medallion", medal)
	var radius: float = maxf(hole.size.x, hole.size.y) * 0.5
	var seal_size: Vector2 = hud_kit.size_of("seal_level")
	var angle: float = deg_to_rad(SEAL_ANGLE_DEG)
	var seal_centre: Vector2 = hole.get_center() + Vector2(cos(angle), sin(angle)) * radius * SEAL_RADIUS_SHARE
	var seal: Rect2 = Rect2((seal_centre - seal_size * 0.5).round(), seal_size)
	var hp_height: float = hud_kit.size_of("bar_hp").y
	var left: float = medal.end.x - BAR_OVERLAP
	var hp: Rect2 = Rect2(left, roundf(hole.get_center().y - HP_RISE - hp_height * 0.5), HP_WIDTH, hp_height)
	var qi: Rect2 = Rect2(left + QI_INDENT, hp.end.y + ROW_GAP, QI_WIDTH, hud_kit.size_of("bar_qi").y)
	var cartouche_size: Vector2 = hud_kit.size_of("cartouche")
	var cartouche: Rect2 = Rect2(Vector2(roundf((size.x - cartouche_size.x) * 0.5), MARGIN.y), cartouche_size)
	var title: Rect2 = Rect2(cartouche.position.x - 40.0, cartouche.end.y + 2.0, cartouche.size.x + 80.0, 24.0)
	var capsule_size: Vector2 = (hud_kit.size_of("capsule_skull") * CAPSULE_SCALE).round()
	var capsule: Rect2 = Rect2(Vector2(size.x - MARGIN.x - capsule_size.x, MARGIN.y + 4.0), capsule_size)
	return {
		"medal": medal, "seal": seal, "hp": hp, "qi": qi, "cartouche": cartouche, "title": title, "capsule": capsule,
	}


## Share of the hero's HP left and of the experience to the next level (0-1).
static func shares(run: FixedTickDriver) -> Vector2:
	var world: WorldState = run.world
	var hp: float = clampf(float(world.hero_hp) / float(maxi(world.hero_hp_max, 1)), 0.0, 1.0)
	var xp: float = 0.0
	if run.config.has_xp():
		xp = clampf(float(world.xp_bank) / float(maxi(run.config.xp_cost(world.level), 1)), 0.0, 1.0)
	return Vector2(hp, xp)


## Opacity of the stage name `seconds` into the run: full, then fading out, then gone.
static func title_alpha(seconds: float) -> float:
	return clampf((TITLE_SECONDS + TITLE_FADE_SECONDS - seconds) / TITLE_FADE_SECONDS, 0.0, 1.0)


## The trail share one frame later: it never falls below the health, jumps up with healing,
## waits TRAIL_DELAY after a blow and then runs down at TRAIL_SPEED. Returns [trail, wait].
static func trail_step(trail: float, wait: float, hp: float, delta: float) -> Vector2:
	if hp >= trail:
		return Vector2(hp, 0.0)
	wait += delta
	if wait < TRAIL_DELAY:
		return Vector2(trail, wait)
	return Vector2(maxf(hp, trail - TRAIL_SPEED * delta), wait)


func _process(delta: float) -> void:
	_clock += delta
	if driver == null:
		return
	var step: Vector2 = trail_step(_trail, _trail_wait, shares(driver).x, delta)
	_trail = step.x
	_trail_wait = step.y


func _draw() -> void:
	if driver == null or kit == null or not kit.has("medallion"):
		return
	var world: WorldState = driver.world
	var at: Dictionary = layout(kit, get_viewport_rect().size)
	var share: Vector2 = shares(driver)
	_draw_portrait(at["medal"])
	if driver.config.has_xp():
		_draw_qi(at["qi"], share.y)
	_draw_hp(at["hp"], share.x, "%d / %d" % [roundi(world.hero_hp / 1000.0), roundi(world.hero_hp_max / 1000.0)])
	var seal: Rect2 = at["seal"]
	kit.draw(self, "seal_level", seal)
	if driver.config.has_xp():
		kit.draw_text_in(self, str(world.level), kit.window("seal_level", seal), LEVEL_FONT_SIZE, COLOR_GOLD_TEXT,
			SAMPLE_LEVEL)
	var cartouche: Rect2 = at["cartouche"]
	kit.draw(self, "cartouche", cartouche)
	kit.draw_text_in(self, RunResults.clock(world.tick), kit.window("cartouche", cartouche), TIMER_FONT_SIZE,
		COLOR_TEXT, SAMPLE_TIME)
	var fade: float = title_alpha(world.tick / TICKS_PER_SECOND)
	if fade > 0.0:
		var gold: Color = COLOR_GOLD_TEXT
		gold.a = fade
		kit.draw_text_in(self, UiText.text(STAGE_NAME_KEY), at["title"], TITLE_FONT_SIZE, gold)
	_draw_counter(at["capsule"], short_count(world.kills))


func _draw_portrait(medal: Rect2) -> void:
	var hole: Rect2 = kit.window("medallion", medal)
	var side: float = maxf(hole.size.x, hole.size.y) + 6.0
	kit.draw(self, "portrait", Rect2(hole.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)))
	kit.draw(self, "medallion", medal)


func _draw_hp(rect: Rect2, share: float, label: String) -> void:
	kit.draw(self, "bar_hp", rect)
	var trough: Rect2 = kit.window("bar_hp", rect)
	kit.draw_fill(self, "fill_trail", trough, maxf(_trail, share), Color(1, 1, 1, 0.7))
	var tint: Color = HP_TINT
	if share < LOW_HP:
		tint = tint.lerp(Color(1.25, 0.95, 0.95), 0.5 + 0.5 * sin(_clock * TAU * LOW_PULSE_HZ))
	kit.draw_fill(self, "fill_hp", trough, share, tint)
	_draw_fill_edge(trough, share)
	var value_box: Rect2 = hp_value_box(trough)
	draw_texture_rect(_hp_scrim, value_box, false)
	kit.draw_text_in(self, label, value_box, BAR_FONT_SIZE, COLOR_TEXT, SAMPLE_HP)


static func hp_value_box(trough: Rect2) -> Rect2:
	var width: float = minf(HP_VALUE_WIDTH, trough.size.x)
	return Rect2(trough.get_center().x - width * 0.5, trough.position.y, width, trough.size.y)


static func _make_hp_scrim() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	var faint: Color = Color(HP_SCRIM, 0.0)
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.88, 1.0])
	gradient.colors = PackedColorArray([faint, HP_SCRIM, HP_SCRIM, faint])
	var result: GradientTexture1D = GradientTexture1D.new()
	result.gradient = gradient
	return result


func _draw_qi(rect: Rect2, share: float) -> void:
	kit.draw(self, "bar_qi", rect)
	var trough: Rect2 = kit.window("bar_qi", rect)
	kit.draw_fill(self, "fill_qi", trough, share, QI_TINT)
	_draw_fill_edge(trough, share)


## A bright meniscus at the end of a fill, as the liquid catches the light.
func _draw_fill_edge(trough: Rect2, share: float) -> void:
	if share <= 0.0 or share >= 1.0:
		return
	var x: float = roundf(trough.position.x + trough.size.x * share)
	draw_line(Vector2(x - 0.5, trough.position.y + 1.0), Vector2(x - 0.5, trough.end.y - 1.0), FILL_EDGE, 1.5)


func _draw_counter(capsule: Rect2, text: String) -> void:
	kit.draw(self, "capsule_skull", capsule)
	kit.draw_text_in(self, text, count_rect(kit, capsule), COUNT_FONT_SIZE, COLOR_TEXT, count_sample())


## The widest counter text the size is set for: five figures or the shortened thousands, whichever
## is longer in the locale ("99999", "999 тыс.").
static func count_sample() -> String:
	var short: String = short_count(SAMPLE_SHORT_COUNT)
	return short if short.length() > SAMPLE_COUNT.length() else SAMPLE_COUNT


## Where the slain count sits in the capsule: the dark window right of the skull.
static func count_rect(hud_kit: HudKit, capsule: Rect2) -> Rect2:
	return _inset(hud_kit.window("capsule_skull", capsule), TEXT_INSET)


## A count as the HUD shows it: whole figures up to COUNT_LIMIT, then thousands ("123 тыс.").
static func short_count(count: int) -> String:
	if count < COUNT_LIMIT:
		return str(count)
	return UiText.text("UI_HUD_THOUSANDS") % str(count / 1000)


static func _inset(rect: Rect2, by: Vector2) -> Rect2:
	return rect.grow_individual(-by.x, -by.y, -by.x, -by.y)
