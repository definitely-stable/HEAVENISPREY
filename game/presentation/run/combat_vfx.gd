class_name CombatVfx
extends RefCounted
## Combat effects after REF-023, REF-035 and REF-010 (ADR-014 section 18, slice A6): golden
## spirit swords with a light streak, a star spark and a number on every hit, crimson yin decay
## where an enemy falls, a golden sword circle under the hero on each cast, a pillar of light on
## a level, qi wisps and golden lotuses for the gems. Pieces of `asset.vfx.combat` are light
## painted on black: they are drawn on an item with additive blending (draw_light, draw_sword,
## draw_gem); the numbers are text with an outline on a normal item (draw_numbers).
## Effects are kept in world px of the ground and projected when drawn; they only read the run.

const ASSET_ID: String = "asset.vfx.combat"
const SPARK_TIME: float = 0.2
const NUMBER_TIME: float = 0.8
const NUMBER_POP_TIME: float = 0.09
## Seconds after a number appears during which further blows on the same enemy add to it
## (mode `aggregate`).
const AGGREGATE_TIME: float = 0.12
const NUMBER_RISE_PX: float = 26.0
const DEATH_TIME: float = 0.55
## Seconds a fallen body takes to decay once its death clip has played (EnemyReactions).
const DECAY_TIME: float = 0.7
const CAST_TIME: float = 0.45
const LEVEL_TIME: float = 0.9
## The level pillar: width share of its piece and peak strength (levels come often early on;
## the pillar marks one, it must not hide the hero).
const LEVEL_PILLAR_WIDTH: float = 0.7
const LEVEL_PILLAR_ALPHA: float = 0.55
## Older effects give way once this many are alive (a horde under a sword fan).
const MAX_SPARKS: int = 64
const MAX_NUMBERS: int = 40
const MAX_DEATHS: int = 64
## Hits land at chest height of a body standing on the ground point (screen px; the Yin
## Corpse stands nearly as tall as the hero, the wolf at its chest).
const BODY_LIFT_PX: float = 38.0
const NUMBER_FONT_SIZE: int = 17
const NUMBER_KILL_FONT_SIZE: int = 20
## Italic lean of the numbers (x shift per px of height), like the numbers of REF-023.
const NUMBER_SLANT: float = 0.2
const COLOR_NUMBER: Color = Color(1.0, 0.97, 0.9)
const COLOR_NUMBER_KILL: Color = Color(1.0, 0.8, 0.36)
const COLOR_OUTLINE: Color = Color(0.1, 0.05, 0.02, 0.85)
## On-screen length of a flying sword (px), how much thicker than the piece it is drawn (a
## thin streak at this size otherwise), its brightness and how far its point leads its ground
## point (the REF-023 swords are long, bright and read from across the screen).
const SWORD_LENGTH_PX: float = 80.0
const SWORD_THICKNESS: float = 1.6
const SWORD_GAIN: float = 1.35
const SWORD_LEAD: float = 0.12
## Gem pieces: the qi wisp for small gems, the golden lotus for large ones (ADR-010 section 8).
const LARGE_GEM_VALUE: int = 10
const GEM_HEIGHT_PX: float = 16.0
const LOTUS_HEIGHT_PX: float = 18.0
## The cast circle (world px radius at full size) and the level circle.
const CAST_RADIUS_PX: float = 26.0
const LEVEL_RADIUS_PX: float = 60.0

var kit: HudKit
var font: Font = ThemeDB.fallback_font
## [ground px, age, angle, scale]
var sparks: Array[Array] = []
## `off`, `aggregate` or `all` (PresentationSettings.floating_damage_numbers); `all`, a number
## per blow, is the look before the setting existed; any other value acts as `all`.
var number_mode: String = "all"
## Alpha of the hero's own skill effects: cast circles, hit sparks and flying swords
## (PresentationSettings.own_skill_opacity). Bursts of the fallen, the level pillar and the numbers
## keep theirs.
var own_opacity: float = 1.0
## [ground px, age, text, kill, x jitter, enemy uid, damage mhp]
var numbers: Array[Array] = []
## [ground px, age, pose] (pose of the body as it fell, drawn fading by the scene)
var deaths: Array[Array] = []
## [ground px, age]
var casts: Array[Array] = []
## Age of the level-up pillar; negative when there is none.
var level_age: float = -1.0
var level_at: Vector2 = Vector2.ZERO


static func load_default(hud_font: Font = null) -> CombatVfx:
	var vfx: CombatVfx = CombatVfx.new()
	vfx.kit = HudKit.load_kit(ASSET_ID)
	if hud_font != null:
		vfx.font = hud_font
	return vfx


func clear() -> void:
	sparks.clear()
	numbers.clear()
	deaths.clear()
	casts.clear()
	level_age = -1.0


## A hit of `damage_mhp` (milli-HP) on the enemy `uid` standing at `at` (ground px).
func add_strike(at: Vector2, damage_mhp: int, uid: int, kill: bool) -> void:
	var turn: float = float(posmod(uid * 73, 360)) * PI / 180.0
	sparks.append([at, 0.0, turn, 0.85 + float(posmod(uid * 13, 7)) * 0.05])
	if sparks.size() > MAX_SPARKS:
		sparks.pop_front()
	if number_mode == "off":
		return
	if number_mode == "aggregate":
		for i: int in range(numbers.size() - 1, -1, -1):
			var number: Array = numbers[i]
			if number[5] == uid and number[1] < AGGREGATE_TIME:
				number[6] += damage_mhp
				number[2] = str(roundi(number[6] / 1000.0))
				number[3] = number[3] or kill
				number[0] = at
				return
	var whole: int = roundi(damage_mhp / 1000.0)
	if whole > 0 or number_mode == "aggregate":
		numbers.append([at, 0.0, str(whole), kill, float(posmod(uid * 37, 21) - 10), uid,
			damage_mhp])
		if numbers.size() > MAX_NUMBERS:
			numbers.pop_front()


## An enemy fell at `at` (world) in `pose`; its body decays and the yin burst rises once `fall`
## seconds of its death clip have played.
func add_death(at: Vector2, pose: Array, fall: float = 0.0) -> void:
	deaths.append([at, 0.0, pose, fall])
	if deaths.size() > MAX_DEATHS:
		deaths.pop_front()


func add_cast(at: Vector2) -> void:
	casts.append([at, 0.0])


func level_up(at: Vector2) -> void:
	level_age = 0.0
	level_at = at


func age(delta: float) -> void:
	delta = maxf(delta, 0.0)
	for list: Array[Array] in [sparks, numbers, deaths, casts]:
		for effect: Array in list:
			effect[1] += delta
	sparks = sparks.filter(func(effect: Array) -> bool: return effect[1] < SPARK_TIME)
	numbers = numbers.filter(func(effect: Array) -> bool: return effect[1] < NUMBER_TIME)
	deaths = deaths.filter(func(effect: Array) -> bool: return effect[1] < effect[3] + maxf(DEATH_TIME, DECAY_TIME))
	casts = casts.filter(func(effect: Array) -> bool: return effect[1] < CAST_TIME)
	if level_age >= 0.0:
		level_age += delta
		if level_age >= LEVEL_TIME:
			level_age = -1.0


## 0-1 share of a fading effect's life.
static func share(effect_age: float, life: float) -> float:
	return clampf(effect_age / life, 0.0, 1.0)


## 0-1 decay of a fallen body: 0 while its death clip plays, 1 when it is gone.
static func decay(death: Array) -> float:
	return share(death[1] - death[3], DECAY_TIME)


## Ground marks and bursts (additive): cast and level circles flat on the ground, yin decay,
## hit sparks and the level pillar upright.
func draw_light(canvas: CanvasItem) -> void:
	if kit == null or not kit.has("spark"):
		return
	for cast: Array in casts:
		var t: float = share(cast[1], CAST_TIME)
		_ground_piece(canvas, "sword_circle", cast[0], CAST_RADIUS_PX * (0.55 + 0.45 * _ease_out(t)),
			Color(1.0, 0.85, 0.55, 0.55 * (1.0 - t) * own_opacity))
	if level_age >= 0.0:
		var t: float = share(level_age, LEVEL_TIME)
		_ground_piece(canvas, "sword_circle", level_at, LEVEL_RADIUS_PX * (0.4 + 0.6 * _ease_out(t)),
			Color(1.0, 0.9, 0.6, 1.0 - t))
		var pillar: Vector2 = kit.size_of("light_pillar")
		var grow: float = _ease_out(minf(t * 3.0, 1.0))
		var size: Vector2 = Vector2(pillar.x * LEVEL_PILLAR_WIDTH, pillar.y * grow)
		var foot: Vector2 = IsoProjection.to_screen(level_at)
		kit.draw(canvas, "light_pillar", Rect2(foot - Vector2(size.x * 0.5, size.y), size),
			Color(1.0, 1.0, 1.0, LEVEL_PILLAR_ALPHA * (1.0 - t * t)))
	for death: Array in deaths:
		if death[1] < death[3]:
			continue
		var t: float = share(death[1] - death[3], DEATH_TIME)
		var burst: Vector2 = kit.size_of("yin_burst") * (0.7 + 0.5 * _ease_out(t))
		var foot: Vector2 = IsoProjection.to_screen(death[0]) + Vector2(0.0, 4.0)
		kit.draw(canvas, "yin_burst", Rect2(foot - Vector2(burst.x * 0.5, burst.y), burst),
			Color(1.0, 1.0, 1.0, 1.0 - t))
	for spark: Array in sparks:
		var t: float = share(spark[1], SPARK_TIME)
		var at: Vector2 = IsoProjection.to_screen(spark[0]) - Vector2(0.0, BODY_LIFT_PX)
		var size: Vector2 = kit.size_of("spark") * spark[3] * (0.6 + 0.6 * _ease_out(t))
		canvas.draw_set_transform(at, spark[2], Vector2.ONE)
		kit.draw(canvas, "spark", Rect2(-size * 0.5, size), Color(1.0, 1.0, 1.0, (1.0 - t * t) * own_opacity))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A flying sword (additive) with its point near `at` (screen px), along `heading` (screen).
func draw_sword(canvas: CanvasItem, at: Vector2, heading: Vector2, alpha: float = 1.0) -> void:
	if kit == null or not kit.has("sword"):
		return
	var native: Vector2 = kit.size_of("sword")
	var size: Vector2 = native * (SWORD_LENGTH_PX / maxf(native.x, 1.0)) * Vector2(1.0, SWORD_THICKNESS)
	canvas.draw_set_transform(at, heading.angle(), Vector2.ONE)
	kit.draw(canvas, "sword", Rect2(Vector2(-size.x * (1.0 - SWORD_LEAD), -size.y * 0.5), size),
		Color(SWORD_GAIN, SWORD_GAIN, SWORD_GAIN, alpha * own_opacity))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A gem (additive) centred on `at` (screen px): a qi wisp, or a golden lotus for a large one.
func draw_gem(canvas: CanvasItem, at: Vector2, value: int, alpha: float, scale: float = 1.0) -> void:
	var piece: String = gem_piece(value)
	if kit == null or not kit.has(piece):
		return
	var native: Vector2 = kit.size_of(piece)
	var height: float = (LOTUS_HEIGHT_PX if piece == "qi_lotus" else GEM_HEIGHT_PX) * scale
	var size: Vector2 = native * (height / maxf(native.y, 1.0))
	kit.draw(canvas, piece, Rect2(at - size * 0.5, size), Color(1.0, 1.0, 1.0, alpha))


static func gem_piece(value: int) -> String:
	return "qi_lotus" if value > LARGE_GEM_VALUE else "qi_wisp"


## Damage numbers over the bodies (normal blending): they pop, rise and fade, leaning like the
## numbers of REF-023; a killing blow is gold and a little larger.
func draw_numbers(canvas: CanvasItem) -> void:
	for number: Array in numbers:
		if number[2] == "0":
			continue
		var t: float = share(number[1], NUMBER_TIME)
		var size: int = NUMBER_KILL_FONT_SIZE if number[3] else NUMBER_FONT_SIZE
		var pop: float = 1.0 + 0.35 * (1.0 - share(number[1], NUMBER_POP_TIME))
		var fade: float = clampf((1.0 - t) / 0.4, 0.0, 1.0)
		var color: Color = COLOR_NUMBER_KILL if number[3] else COLOR_NUMBER
		color.a = fade
		var outline: Color = COLOR_OUTLINE
		outline.a *= fade
		var at: Vector2 = IsoProjection.to_screen(number[0]) + Vector2(
			number[4], -BODY_LIFT_PX - 14.0 - NUMBER_RISE_PX * _ease_out(t))
		var text: String = number[2]
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		canvas.draw_set_transform_matrix(Transform2D(Vector2(pop, 0.0), Vector2(-NUMBER_SLANT * pop, pop), at))
		var origin: Vector2 = Vector2(-width * 0.5, 0.0)
		canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, outline)
		canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A round piece laid flat on the ground: `radius` world px around `at` (ground px).
func _ground_piece(canvas: CanvasItem, piece: String, at: Vector2, radius: float, modulate: Color) -> void:
	canvas.draw_set_transform_matrix(IsoProjection.ground())
	kit.draw(canvas, piece, Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), modulate)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## A diamond: 10 px across for value 10 and below, 13 px for more (ADR-010 section 8), times
## `size` (gems at rest on the ground are smaller and dimmer than the HUD icon).
static func draw_gem_primitive(
	canvas: CanvasItem, at: Vector2, value: int, alpha: float, size: float, base: Color
) -> void:
	var half: float = (5.0 if value <= 10 else 6.5) * size
	var color: Color = base
	color.a = alpha
	var points: PackedVector2Array = PackedVector2Array([
		at + Vector2(0, -half * 1.3), at + Vector2(half, 0), at + Vector2(0, half * 1.3), at + Vector2(-half, 0),
	])
	canvas.draw_colored_polygon(points, color)
	canvas.draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.4), 1.5)
