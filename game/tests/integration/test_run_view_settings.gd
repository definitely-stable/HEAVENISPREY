extends GutTest
## QUALITY-2026-11: the run view's presentation settings. A player run reads user://settings.cfg;
## tests, replays and captures get the reference look; a caller's settings are kept.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"


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
