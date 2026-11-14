extends GutTest
## End of the run (ADR-011 section 1, slice E1): the stage duration from content, victory
## through the driver and the scene, the results screen in RU and EN, and no automatic restart.
## The victory rules themselves are covered by the run_end_* traces in test_sim_core.gd.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0

var _locale: String = ""


func before_each() -> void:
	_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_locale)


func _view() -> RunView:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	return view


## The arena without enemies, ending after `ticks`.
static func _short_run(ticks: int) -> SimConfig:
	return P0Tuning.movement_config().with_run_ticks(ticks)


func test_stage_duration_comes_from_content() -> void:
	var tuning: P0Tuning = P0Tuning.new()
	var config: SimConfig = tuning.run_config(ContentRegistry.load_dir(), "101")
	assert_not_null(config, tuning.error)
	assert_eq(config.run_ticks, 5 * 60 * 60, "stage.jade_grove: 5 minutes")
	# run_ticks, then the attack table size, four venom and two root values (ADR-011 E2, E5).
	assert_eq(config.to_ints()[config.to_ints().size() - 8], config.run_ticks)


func test_config_rejects_a_negative_duration() -> void:
	assert_false(_short_run(-1).is_valid())
	assert_true(_short_run(0).is_valid(), "0 = no time limit")


func test_driver_stops_at_the_victory_tick() -> void:
	var driver: FixedTickDriver = FixedTickDriver.create(_short_run(120))
	for _i: int in 200:
		driver.advance(TICK, Vector2i(1, 0))
	assert_eq([driver.world.tick, driver.world.won, driver.world.hero_dead], [120, 1, 0])
	assert_true(driver.world.is_over())
	assert_eq(driver.world.copy().won, 1, "the copy keeps the result")


func test_scene_shows_victory_and_waits_for_the_player() -> void:
	var view: RunView = _view()
	TranslationServer.set_locale("en")  # after _ready, which follows the OS language
	view.driver = FixedTickDriver.create(_short_run(120))
	for _i: int in 121:
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_true(view.driver.world.is_over())
	assert_true(view.is_results_open())
	var results: RunResults = view.get("_results")
	assert_eq(results.title.text, "Victory: the grove is held")
	assert_string_contains(results.lines.text, "Time 00:02")
	assert_false(view.confirm_results(), "not armed yet")
	view.advance_frame(RunResults.ARM_DELAY * 0.5, Vector2i.ZERO)
	assert_false(view.confirm_results())
	view.advance_frame(RunResults.ARM_DELAY, Vector2i.ZERO)
	var runs: int = view.runs_started
	assert_true(view.confirm_results())
	assert_eq(view.runs_started, runs + 1)
	assert_false(view.is_results_open())


func test_defeat_results_in_russian() -> void:
	var view: RunView = _view()
	TranslationServer.set_locale("ru")  # after _ready, which follows the OS language
	view.start_run("20261113")
	var guard: int = 0
	while not view.driver.world.is_over() and guard < 5000:
		if view.driver.world.is_paused():
			view.choose(0)
		else:
			view.advance_frame(TICK, Vector2i.ZERO)
		guard += 1
	var world: WorldState = view.driver.world
	assert_eq([world.hero_dead, world.won], [1, 0])
	var results: RunResults = view.get("_results")
	assert_eq(results.title.text, "Поражение")
	assert_string_contains(results.lines.text, "Убито врагов: %d" % world.kills)
	assert_string_contains(results.lines.text, "Уровень: %d" % world.level)
	assert_string_contains(results.lines.text, "Собрано опыта: %d" % world.xp_collected_total)


func test_clock_format() -> void:
	assert_eq(RunResults.clock(0), "00:00")
	assert_eq(RunResults.clock(59), "00:00")
	assert_eq(RunResults.clock(3600), "01:00")
	assert_eq(RunResults.clock(18000), "05:00")
