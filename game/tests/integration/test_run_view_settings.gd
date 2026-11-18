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


func test_the_damage_number_mode_comes_from_the_settings() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.settings = PresentationSettings.new()
	view.settings.floating_damage_numbers = "aggregate"
	add_child_autofree(view)
	assert_eq(view._vfx.number_mode, "aggregate")
	var replay: RunView = packed.instantiate()
	replay.read_player_input = false
	add_child_autofree(replay)
	assert_eq(replay._vfx.number_mode, "all", "replays and captures keep a number per blow")


func test_own_skill_opacity_fades_only_the_hero_effects() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.settings = PresentationSettings.new()
	view.settings.own_skill_opacity = 0.5
	add_child_autofree(view)
	assert_almost_eq(view._vfx.own_opacity, 0.5, 1e-6, "casts, sparks and swords")
	assert_almost_eq(view.own_color(Color(1.0, 1.0, 1.0, 0.8)).a, 0.4, 1e-6, "chain line and fallback swords")
	assert_almost_eq(view.own_color(Color(0.2, 0.4, 0.6, 0.8)).r, 0.2, 1e-6, "only the alpha changes")
	var replay: RunView = packed.instantiate()
	replay.read_player_input = false
	add_child_autofree(replay)
	assert_eq(replay._vfx.own_opacity, 1.0, "replays and captures keep the full effects")
	assert_almost_eq(replay.own_color(Color(1.0, 1.0, 1.0, 0.8)).a, 0.8, 1e-6)
	# PLAYABILITY G3: the threat layer never fades with the hero's own effects.
	for path: String in ["res://presentation/run/attack_telegraph.gd", "res://presentation/run/enemy_shots.gd"]:
		if FileAccess.file_exists(path):
			assert_false(FileAccess.get_file_as_string(path).contains("own_"), path + " ignores own_skill_opacity")
	var source: String = FileAccess.get_file_as_string("res://presentation/run/run_view.gd")
	var danger: String = source.get_slice("func _draw_danger_pass", 1).get_slice("\nfunc ", 0)
	assert_false(danger.is_empty(), "the danger pass is found")
	assert_false(danger.contains("own_"), "the danger pass ignores own_skill_opacity")
