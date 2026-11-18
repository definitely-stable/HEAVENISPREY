extends GutTest
## QUALITY-2026-11: the run view's presentation settings. A player run reads user://settings.cfg;
## tests, replays and captures get the reference look; a caller's settings are kept.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
## The scene helpers of the run view tests (the hero at the centre, one frame of a run).
const RunViewTests: GDScript = preload("res://tests/integration/test_run_view.gd")


func test_a_replay_view_gets_the_reference_settings() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	assert_not_null(view.settings, "settings are loaded in _ready")
	assert_eq(view.settings.screenshake, 0.0, "no shake in tests, replays and captures")
	assert_eq(view.settings.floating_damage_numbers, "all")
	assert_eq(view.settings.own_skill_opacity, 1.0)


func test_settings_set_before_ready_are_kept() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	var chosen: PresentationSettings = PresentationSettings.new()
	chosen.screenshake = 0.7
	view.settings = chosen
	add_child_autofree(view)
	assert_same(view.settings, chosen, "a caller's settings are not replaced")


## QUALITY-2026-11 Q2: a blow and a defeat move the camera only through Camera2D.offset and
## only by the settings multiplier; a reference view (tests, replays, captures) keeps it still.
func test_screen_shake_follows_damage_and_the_settings() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	view.settings = PresentationSettings.reference_look()
	add_child_autofree(view)
	assert_true(view.start_run("20261113"))
	RunViewTests._to_centre(view)
	var camera: Camera2D = view.get_node("Camera")
	var world: WorldState = view.driver.world
	var hp: int = world.hero_hp
	var guard: int = 0
	while world.hero_hp == hp and guard < 3000:
		RunViewTests._frame(view, Vector2i.ZERO)
		guard += 1
	assert_lt(world.hero_hp, hp, "the horde hurts the standing hero")
	assert_gt(view._shake.trauma, 0.0, "the blow leaves trauma")
	# The offset of a blow is written as the next frame ages the effects.
	while world.is_paused():
		view.choose(0)
	view.advance_frame(RunViewTests.TICK, Vector2i.ZERO)
	assert_gt(view._shake.trauma, 0.0, "the shake is still running")
	assert_eq(camera.offset, Vector2.ZERO, "no screen shake at reference settings")
	view.settings.screenshake = 1.0
	while world.is_paused():
		view.choose(0)
	view.advance_frame(RunViewTests.TICK, Vector2i.ZERO)
	assert_ne(camera.offset, Vector2.ZERO, "with strength the same blow moves the camera")


func test_hit_flash_setting_scales_the_white_flashes() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.settings = PresentationSettings.reference_look()
	add_child_autofree(view)
	view._reactions.hit(4, 0.0)
	view._flash = RunView.HIT_FLASH
	assert_eq(view._enemy_flash(4), 1.0, "the reference look keeps the full flash")
	assert_eq(view._hero_flash_share(), 1.0)
	view.settings.hit_flash = 0.5
	assert_almost_eq(view._enemy_flash(4), 0.5, 1e-6)
	assert_almost_eq(view._hero_flash_share(), 0.5, 1e-6)
	view.settings.hit_flash = 0.0
	assert_eq(view._enemy_flash(4), 0.0, "0 turns the flashes off")
	assert_eq(view._hero_flash_share(), 0.0)
