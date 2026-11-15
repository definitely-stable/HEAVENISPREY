extends GutTest
## ADR-014 section 15: the gold HUD kit (pieces, frame windows, stretched bars, the HUD font) and
## the run HUD laid out after REF-023 on the 1280 x 720 canvas and on a wider window.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0
const PIECES: Array[String] = [
	"portrait_ring", "level_seal", "bar_frame", "title_plaque", "counter_capsule", "divider_lotus",
	"fill_red", "fill_gold", "icon_slain", "portrait",
]


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
	for piece: String in ["portrait_ring", "level_seal", "bar_frame", "title_plaque", "counter_capsule"]:
		var rect: Rect2 = Rect2(Vector2(40, 30), kit.size_of(piece))
		var inside: Rect2 = kit.window(piece, rect)
		assert_true(rect.encloses(inside), piece)
		assert_lt(inside.get_area(), rect.get_area(), piece)
	var plain: Rect2 = Rect2(0, 0, 50, 20)
	assert_eq(kit.window("divider_lotus", plain), plain, "a piece without a window gives the rect back")


func test_a_stretched_bar_keeps_its_caps() -> void:
	var kit: HudKit = HudKit.load_default()
	var short: Rect2 = kit.window("bar_frame", Rect2(0, 0, 200, 24))
	var long: Rect2 = kit.window("bar_frame", Rect2(0, 0, 480, 24))
	assert_almost_eq(long.position.x, short.position.x, 0.01, "left cap")
	assert_almost_eq(480.0 - long.end.x, 200.0 - short.end.x, 0.01, "right cap")
	assert_almost_eq(long.size.x - short.size.x, 280.0, 0.01, "only the trough grows")
	assert_almost_eq(long.size.y, short.size.y, 0.01)


func test_layout_fits_the_canvas_without_overlaps() -> void:
	var kit: HudKit = HudKit.load_default()
	for size: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1280, 960)]:
		var at: Dictionary = RunHud.layout(kit, size)
		var screen: Rect2 = Rect2(Vector2.ZERO, size)
		for group: String in at:
			assert_true(screen.encloses(at[group]), "%s inside %s" % [group, size])
		for pair: Array in [["ring", "hp"], ["ring", "xp"], ["hp", "xp"], ["hp", "plaque"], ["plaque", "capsule"],
				["plaque", "divider"], ["hp", "capsule"]]:
			assert_false((at[pair[0]] as Rect2).intersects(at[pair[1]]), "%s / %s at %s" % [pair[0], pair[1], size])
		assert_almost_eq((at["plaque"] as Rect2).get_center().x, size.x * 0.5, 1.0, "plaque centred")
		assert_almost_eq((at["capsule"] as Rect2).end.x, size.x - RunHud.MARGIN.x, 0.01, "counter on the right")
		assert_true((at["ring"] as Rect2).intersects(at["seal"]), "the level seal sits on the ring")


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
