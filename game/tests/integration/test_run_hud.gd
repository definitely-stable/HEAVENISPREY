extends GutTest
## ADR-014 section 21, HUD v1 after REF-067: the gold HUD kit (pieces, frame windows, stretched
## bars, the HUD font) and the run HUD on the 1280 x 720 canvas and on a wider window; numbers
## keep their size while they count and stay inside their frames; the trail of lost health and
## the stage name follow the run.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0
const PIECES: Array[String] = [
	"medallion", "bar_hp", "seal_level", "cartouche", "capsule_skull", "bar_qi", "fill_hp", "fill_qi", "fill_trail",
	"portrait", "divider_lotus",
]
const FRAMES: Array[String] = ["medallion", "bar_hp", "seal_level", "cartouche", "capsule_skull", "bar_qi"]


func test_kit_has_every_piece_and_the_font() -> void:
	var kit: HudKit = HudKit.load_default()
	for piece: String in PIECES:
		assert_true(kit.has(piece), piece)
		assert_gt(kit.size_of(piece).x, 0.0, piece)
	assert_false(kit.has("badge"))
	assert_eq(kit.size_of("badge"), Vector2.ZERO)
	assert_true(kit.font is FontVariation, "Cormorant Garamond with its weight and lining figures")
	assert_false(SpriteSet.load_default().has(HudKit.ASSET_ID), "the HUD kit is not a lit scene sprite")


func test_frame_windows_sit_inside_their_frames() -> void:
	var kit: HudKit = HudKit.load_default()
	for piece: String in FRAMES:
		var rect: Rect2 = Rect2(Vector2(40, 30), kit.size_of(piece))
		var inside: Rect2 = kit.window(piece, rect)
		assert_true(rect.encloses(inside), piece)
		assert_lt(inside.get_area(), rect.get_area(), piece)
	var plain: Rect2 = Rect2(0, 0, 50, 20)
	assert_eq(kit.window("divider_lotus", plain), plain, "a piece without a window gives the rect back")


func test_a_stretched_bar_keeps_its_caps() -> void:
	var kit: HudKit = HudKit.load_default()
	for piece: String in ["bar_hp", "bar_qi"]:
		var height: float = kit.size_of(piece).y
		var short: Rect2 = kit.window(piece, Rect2(0, 0, 200, height))
		var long: Rect2 = kit.window(piece, Rect2(0, 0, 480, height))
		assert_almost_eq(long.position.x, short.position.x, 0.01, piece + " left cap")
		assert_almost_eq(480.0 - long.end.x, 200.0 - short.end.x, 0.01, piece + " right cap")
		assert_almost_eq(long.size.x - short.size.x, 280.0, 0.01, piece + " only the trough grows")
		assert_almost_eq(long.size.y, short.size.y, 0.01)


func test_layout_fits_the_canvas_without_overlaps() -> void:
	var kit: HudKit = HudKit.load_default()
	for size: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1280, 960)]:
		var at: Dictionary = RunHud.layout(kit, size)
		var screen: Rect2 = Rect2(Vector2.ZERO, size)
		for group: String in at:
			assert_true(screen.encloses(at[group]), "%s inside %s" % [group, size])
		for pair: Array in [["player", "cartouche"], ["cartouche", "capsule"], ["hp", "qi"], ["hp_text", "hp"],
				["seal", "hp"], ["timer", "title"]]:
			assert_false((at[pair[0]] as Rect2).intersects(at[pair[1]]), "%s / %s at %s" % [pair[0], pair[1], size])
		assert_almost_eq((at["cartouche"] as Rect2).get_center().x, size.x * 0.5, 1.0, "clock centred")
		assert_almost_eq((at["title"] as Rect2).get_center().x, size.x * 0.5, 1.0, "stage name centred")
		assert_almost_eq((at["capsule"] as Rect2).end.x, size.x - RunHud.MARGIN.x, 0.01, "counter on the right")
		assert_true((at["medal"] as Rect2).intersects(at["seal"]), "level seal sits on the medallion")
		for key: String in ["hp", "hp_text", "qi"]:
			assert_true((at["player"] as Rect2).encloses(at[key]), "%s on a solid backing" % key)


func test_hud_follows_the_run() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("20261113")
	var hud: RunHud = view._hud
	assert_eq(hud.driver, view.driver, "the HUD reads the current run")
	assert_eq(RunHud.shares(view.driver), Vector2(1.0, 0.0), "full HP, no experience yet")
	var world: WorldState = view.driver.world
	var guard: int = 0
	while world.level == 1 and world.xp_bank == 0 and guard < 6000 and not world.is_over():
		if world.is_paused():
			view.choose(0)
		else:
			view.advance_frame(TICK, Vector2i(1, 0) if (guard / 90) % 2 == 0 else Vector2i(-1, 0))
		guard += 1
	var share: Vector2 = RunHud.shares(view.driver)
	assert_true(world.xp_bank > 0 or world.level > 1, "the run gathered experience")
	assert_between(share.x, 0.0, 1.0)
	assert_between(share.y, 0.0, 1.0)
	view.start_run("20261114")
	assert_eq(hud.driver, view.driver, "a new run rebinds the HUD")


## The pale trail waits after a blow, then runs down to the health; healing lifts it at once.
func test_trail_of_lost_health() -> void:
	var step: Vector2 = RunHud.trail_step(1.0, 0.0, 0.6, TICK)
	assert_eq(step.x, 1.0, "it waits first")
	var trail: float = 1.0
	var wait: float = 0.0
	var frames: int = 0
	while trail > 0.6 + 0.0001 and frames < 600:
		step = RunHud.trail_step(trail, wait, 0.6, TICK)
		trail = step.x
		wait = step.y
		frames += 1
	assert_almost_eq(trail, 0.6, 0.0001, "it reaches the health")
	var expected: float = RunHud.TRAIL_DELAY + 0.4 / RunHud.TRAIL_SPEED
	assert_almost_eq(frames * TICK, expected, 2.0 * TICK, "after the delay, at its speed")
	assert_eq(RunHud.trail_step(0.6, 0.3, 0.8, TICK), Vector2(0.8, 0.0), "healing lifts it")


func test_stage_name_shows_then_fades() -> void:
	assert_eq(RunHud.title_alpha(0.0), 1.0)
	assert_eq(RunHud.title_alpha(RunHud.TITLE_SECONDS), 1.0)
	assert_almost_eq(RunHud.title_alpha(RunHud.TITLE_SECONDS + RunHud.TITLE_FADE_SECONDS * 0.5), 0.5, 0.001)
	assert_eq(RunHud.title_alpha(RunHud.TITLE_SECONDS + RunHud.TITLE_FADE_SECONDS), 0.0)
	assert_eq(RunHud.title_alpha(300.0), 0.0)


## Long numbers and both locales stay inside their frames: the font shrinks, it never spills.
func test_text_fits_its_frame_at_any_count() -> void:
	var kit: HudKit = HudKit.load_default()
	var at: Dictionary = RunHud.layout(kit, Vector2(1280, 720))
	var capsule: Rect2 = at["capsule"]
	var count: Rect2 = RunHud.count_rect(capsule)
	assert_true(capsule.encloses(count))
	var locale: String = TranslationServer.get_locale()
	for lang: String in ["ru", "en"]:
		TranslationServer.set_locale(lang)
		var sample: String = RunHud.count_sample()
		var fixed: int = kit.line_size(sample, count, RunHud.COUNT_FONT_SIZE)
		assert_gte(fixed, 14, "%s stays readable" % sample)
		assert_eq(RunHud.short_count(99999), "99999")
		assert_ne(RunHud.short_count(123456), "123456", "a count past the limit is shortened")
		for kills: int in [0, 7, 4821, 99999, 123456, RunHud.SAMPLE_SHORT_COUNT]:
			var text: String = RunHud.short_count(kills)
			var size: int = kit.line_size(text, count, RunHud.COUNT_FONT_SIZE, sample)
			assert_eq(size, fixed, "%s keeps the size of the counter" % text)
			assert_lte(kit.text_width(text, size), count.size.x, "%s fits" % text)
		var stage: String = UiText.text(RunHud.STAGE_NAME_KEY)
		assert_eq(kit.fit_size(stage, (at["title"] as Rect2).size.x, RunHud.TITLE_FONT_SIZE), RunHud.TITLE_FONT_SIZE, stage)
	TranslationServer.set_locale(locale)
	var clock: Rect2 = at["timer"]
	assert_gte(kit.line_size(RunHud.SAMPLE_TIME, clock, RunHud.TIMER_FONT_SIZE, RunHud.SAMPLE_TIME), 24, "a large timer")
	var seal: Rect2 = kit.window("seal_level", at["seal"])
	assert_gte(kit.line_size(RunHud.SAMPLE_LEVEL, seal, RunHud.LEVEL_FONT_SIZE, RunHud.SAMPLE_LEVEL), 14, "level")
	var hp: Rect2 = at["hp_text"]
	assert_eq(kit.line_size(RunHud.SAMPLE_HP, hp, RunHud.BAR_FONT_SIZE, RunHud.SAMPLE_HP), RunHud.BAR_FONT_SIZE)
	assert_false(hp.intersects(at["hp"]), "health figures sit off the bright fill")
	assert_almost_eq(kit.text_width("1111", 15), kit.text_width("0000", 15), 0.01, "tabular figures")
	assert_lt(kit.fit_size("a much longer label than any bar can hold", 60.0, 20), 20, "the font shrinks to fit")
	assert_eq(kit.fit_size("a much longer label than any bar can hold", 1.0, 20), HudKit.MIN_FONT_SIZE)
