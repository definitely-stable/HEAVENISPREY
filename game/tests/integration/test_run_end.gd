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
	var config: SimConfig = P0TestSetup.sword_config("101", tuning)
	assert_not_null(config, tuning.error)
	assert_eq(config.run_ticks, 5 * 60 * 60, "stage.jade_grove: 5 minutes")
	# run_ticks, then the attack table, four venom and two root values (ADR-011 E2, E5), the
	# windows and the caps (E6), each table after its size.
	# The arena topology closes the list (ADR-015 A1).
	assert_not_null(config.arena)
	var tail: int = (
		1 + config.attacks.size() + 4 + 2 + 1 + config.windows.size() + 1 + config.caps.size()
		+ config.arena.to_ints().size()
	)
	assert_eq(config.to_ints()[config.to_ints().size() - tail - 1], config.run_ticks)


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
	assert_true(view.start_run("101"))
	view.driver = FixedTickDriver.create(_short_run(120))
	for _i: int in 121:
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_true(view.driver.world.is_over())
	assert_true(view.is_results_open())
	var results: RunResults = view.get("_results")
	assert_eq(results.title.text, "Victory: the grove is held")
	assert_eq(results.class_line.text, "Class: Sword Cultivator")
	assert_eq(results.unlock_line.text, "New class: Thunder Daoist")
	assert_eq(results._stat_labels[0].text, "Time")
	assert_eq(results.stat_values[0].text, "00:02")
	assert_eq(view.get_viewport().gui_get_focus_owner(), results.rewards_button)
	assert_false(view._hud.visible, "results show one set of run statistics")
	var runs: int = view.runs_started
	results.rewards_button.pressed.emit()
	assert_eq(view.runs_started, runs, "the button also waits for the arm delay")
	assert_false(view.confirm_results(), "not armed yet")
	view.advance_frame(RunResults.ARM_DELAY * 0.5, Vector2i.ZERO)
	assert_false(view.confirm_results())
	view.advance_frame(RunResults.ARM_DELAY, Vector2i.ZERO)
	var confirm: InputEventJoypadButton = InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	confirm.pressed = true
	view.get_viewport().push_input(confirm)
	assert_eq(view.runs_started, runs)
	assert_false(view.is_results_open())
	assert_true(view.is_rewards_open())
	assert_eq(view._rewards.unlock_line.text, results.unlock_line.text)
	assert_eq(view._rewards.stones_line.text, "Spirit Stones earned: 0")
	assert_eq(view.session_profile.receipts().size(), 1)
	var receipt: RunResultReceipt = view.session_profile.receipts()[0]
	assert_same(view._finish_run(), receipt, "finalizing the same run keeps the receipt")
	assert_eq(receipt.fields()["world_digest"], view.driver.world.digest())
	assert_eq(receipt.fields()["log_digest"], view.driver.commands.digest())
	assert_true(receipt.fields().is_read_only())
	assert_true((receipt.fields()["reward_events"] as Array).is_read_only())
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	view.get_viewport().push_input(enter)
	assert_true(view.is_rewards_open(), "Enter while arming cannot leave Rewards")
	view.advance_frame(RunRewards.ARM_DELAY, Vector2i.ZERO)
	view.get_viewport().push_input(enter)
	assert_true(view.is_class_select_open())
	assert_eq(view.get_viewport().gui_get_focus_owner(), view._class_select.cards[0])
	assert_eq(view.session_profile.receipts().size(), 1)
	assert_eq(view._class_select.locked, [false, false], "victory unlocks Thunder this session")
	assert_false(view._hud.visible)
	results.rewards_button.pressed.emit()
	assert_eq(view.runs_started, runs, "an old results action cannot start another run")


func test_defeat_results_in_russian() -> void:
	var view: RunView = _view()
	TranslationServer.set_locale("ru")  # after _ready, which follows the OS language
	view.start_run("20261113")
	_to_centre(view)
	var guard: int = 0
	while not view.driver.world.is_over() and guard < 5000:
		if view.driver.world.is_paused():
			view.choose(0)
		else:
			view.advance_frame(TICK, Vector2i.ZERO)
		guard += 1
	var world: WorldState = view.driver.world
	assert_eq([world.hero_dead, world.won], [1, 0])
	for _i: int in 90:
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_true(view.is_results_open(), "after the death clip")
	var results: RunResults = view.get("_results")
	assert_eq(results.title.text, "Поражение")
	assert_eq(view.session_profile.granted_unlock_ids(), PackedStringArray(["unlock.thunder"]))
	assert_eq(results._stat_labels.map(func(label: Label) -> String: return label.text),
		["Время", "Побеждено", "Уровень", "Опыт"])
	assert_eq(results.stat_values.map(func(label: Label) -> String: return label.text),
		[RunResults.clock(world.tick - 1), str(world.kills), str(world.level), str(world.xp_collected_total)])
	assert_eq(results.class_line.text, "Класс: Культиватор меча")
	assert_eq(results.unlock_line.text, "Открыт класс: Даос грома")
	view.advance_frame(RunResults.ARM_DELAY, Vector2i.ZERO)
	assert_true(view.confirm_results())
	assert_eq(view._rewards.title.text, "Награды забега")
	assert_eq(view._rewards.unlock_line.text, results.unlock_line.text)


func test_restart_from_choice_stores_one_abandon_and_keeps_class_locked() -> void:
	var view: RunView = _view()
	assert_true(view.start_run("101"))
	var original_uid: String = view._run_uid
	var world: WorldState = view.driver.world
	world.tick = 14400
	world.kills = 50
	world.pending_level_choices = 1
	world.hand = PackedInt64Array([0, 1, 2])
	view.advance_frame(TICK, Vector2i.ZERO)
	assert_true(view.is_menu_open())
	assert_true(view.restart_run())
	assert_false(view.is_menu_open())
	assert_ne(view._run_uid, original_uid)
	assert_eq(view.rules_snapshot.class_id, "class.sword")
	assert_eq(view.driver.world.tick, 0)
	assert_eq(view.session_profile.granted_unlock_ids(), PackedStringArray())
	var receipts: Array[RunResultReceipt] = view.session_profile.receipts()
	assert_eq(receipts.size(), 1)
	var fields: Dictionary = receipts[0].fields()
	assert_eq(fields["run_uid"], original_uid)
	assert_eq(fields["result"], "abandoned")
	assert_eq(fields["survived_ticks"], 14400)
	assert_eq(fields["stones_preview"], 8)
	var events: Array = fields["reward_events"]
	assert_eq(events[0]["reward_event_id"], "reward.minute3:%s:0" % original_uid)
	assert_true((events[0] as Dictionary).is_read_only())
	assert_true((fields["mode_ids"] as Array).is_read_only())


func test_restart_from_results_and_rewards_starts_the_same_class() -> void:
	var view: RunView = _view()
	view.session_profile.unlock_all = true
	assert_true(view.start_run("101", "class.thunder"))
	for screen: String in ["results", "rewards"]:
		view.driver = FixedTickDriver.create(_short_run(1))
		view.advance_frame(TICK, Vector2i.ZERO)
		assert_true(view.is_results_open())
		if screen == "rewards":
			view.advance_frame(RunResults.ARM_DELAY, Vector2i.ZERO)
			assert_true(view.confirm_results())
			assert_true(view.is_rewards_open())
		assert_true(view.restart_run())
		assert_false(view.is_results_open())
		assert_false(view.is_rewards_open())
		assert_eq(view.rules_snapshot.class_id, "class.thunder")
		assert_eq(view.driver.world.tick, 0)
	var receipts: Array[RunResultReceipt] = view.session_profile.receipts()
	assert_eq(receipts.size(), 2)
	assert_eq(receipts[0].fields()["result"], "victory")
	assert_eq(receipts[1].fields()["result"], "victory")


func test_clock_format() -> void:
	assert_eq(RunResults.clock(0), "00:00")
	assert_eq(RunResults.clock(59), "00:00")
	assert_eq(RunResults.clock(3600), "01:00")
	assert_eq(RunResults.clock(18000), "05:00")


## The hero stands at the arena centre, written into the world before the first tick (a
## presentation check): in the open court the horde reaches a standing hero quickly.
static func _to_centre(view: RunView) -> void:
	var centre: Vector2 = GroundLayer.centre_of(P0Tuning.arena_data(), RunView.CELL_PX)
	for state: WorldState in [view.driver.world, view.driver.previous]:
		state.player_x = int(centre.x) * Fx.FX_ONE
		state.player_y = int(centre.y) * Fx.FX_ONE
