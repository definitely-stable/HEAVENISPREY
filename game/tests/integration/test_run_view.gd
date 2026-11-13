extends GutTest
## P0-01c placeholder run scene: input quantization, fixed-tick driver, scene wiring.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0


func test_quantize_eight_directions() -> void:
	assert_eq(MoveInput.quantize(Vector2.ZERO), Vector2i.ZERO)
	assert_eq(MoveInput.quantize(Vector2(0.1, 0.1)), Vector2i.ZERO, "inside deadzone")
	assert_eq(MoveInput.quantize(Vector2(1, 0)), Vector2i(1, 0))
	assert_eq(MoveInput.quantize(Vector2(-1, 0)), Vector2i(-1, 0))
	assert_eq(MoveInput.quantize(Vector2(0, -1)), Vector2i(0, -1))
	assert_eq(MoveInput.quantize(Vector2(0.7, 0.7)), Vector2i(1, 1))
	assert_eq(MoveInput.quantize(Vector2(-0.7, -0.7)), Vector2i(-1, -1))
	assert_eq(MoveInput.quantize(Vector2(0.9, 0.3)), Vector2i(1, 0), "18 deg snaps to east")
	assert_eq(MoveInput.quantize(Vector2(0.9, 0.5)), Vector2i(1, 1), "29 deg snaps to south-east")


func test_input_actions_are_bound() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		assert_true(InputMap.has_action(action), action)
		assert_eq(InputMap.action_get_events(action).size(), 4, action)
	assert_true(InputMap.has_action("restart"))
	assert_eq(InputMap.action_get_events("restart").size(), 2)


func test_driver_runs_sixty_ticks_per_second() -> void:
	var config: SimConfig = RunView.placeholder_config()
	var driver: FixedTickDriver = FixedTickDriver.create(config)
	var ticks: int = 0
	for _i: int in 60:
		ticks += driver.advance(TICK, Vector2i(1, 0))
	assert_eq(ticks, 60)
	assert_eq(driver.world.tick, 60)
	assert_eq(driver.world.player_x, config.start_x + 60 * config.speed_su_per_tick)
	assert_eq(driver.commands.size(), 1, "held direction is logged once")


func test_driver_logs_only_direction_changes() -> void:
	var driver: FixedTickDriver = FixedTickDriver.create(RunView.placeholder_config())
	driver.advance(5 * TICK + 0.001, Vector2i(1, 0))
	driver.advance(3 * TICK, Vector2i(1, 0))
	driver.advance(2 * TICK, Vector2i(0, 1))
	driver.advance(2 * TICK, Vector2i.ZERO)
	assert_eq(driver.commands.size(), 3)
	assert_eq(driver.commands.tick_at(0), 0)
	assert_eq(driver.commands.tick_at(1), 8)
	assert_eq(driver.commands.tick_at(2), 10)


func test_frame_spike_is_capped() -> void:
	var driver: FixedTickDriver = FixedTickDriver.create(RunView.placeholder_config())
	assert_eq(driver.advance(5.0, Vector2i(1, 0)), FixedTickDriver.MAX_TICKS_PER_FRAME)
	assert_eq(driver.advance(0.0, Vector2i(1, 0)), 1, "only one tick of backlog kept")
	assert_eq(driver.advance(-1.0, Vector2i(1, 0)), 0, "negative delta ignored")


func test_frame_timing_does_not_change_the_run() -> void:
	var config: SimConfig = RunView.placeholder_config()
	var jittery: FixedTickDriver = FixedTickDriver.create(config)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var moves: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 0), Vector2i(-1, 1)]
	var frame: int = 0
	while jittery.world.tick < 900:
		var move: Vector2i = moves[(jittery.world.tick / 120) % moves.size()]
		jittery.advance(rng.randf_range(0.002, 0.05), move)
		frame += 1
	assert_gt(frame, 0)
	var replayed: WorldState = WorldState.initial(config)
	SimKernel.run(config, replayed, jittery.commands, jittery.world.tick)
	assert_eq(replayed.digest(), jittery.world.digest(), "log replay == live run")


func test_interpolated_position_stays_between_ticks() -> void:
	var driver: FixedTickDriver = FixedTickDriver.create(RunView.placeholder_config())
	driver.advance(TICK * 1.5, Vector2i(1, 0))
	var from: float = float(driver.previous.player_x) / Fx.FX_ONE
	var to: float = float(driver.world.player_x) / Fx.FX_ONE
	var x: float = driver.hero_position_px().x
	assert_between(x, from, to)
	assert_almost_eq(driver.alpha(), 0.5, 0.01)


func test_scene_moves_hero_and_camera() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	var start: Vector2 = view.driver.hero_position_px()
	assert_eq(start, Vector2(768, 480), "hero starts at the arena centre")
	for _i: int in 30:
		view.advance_frame(TICK, Vector2i(0, -1))
	var hero: Vector2 = view.driver.hero_position_px()
	assert_lt(hero.y, start.y)
	assert_eq(hero.x, start.x)
	var camera: Camera2D = view.get_node("Camera")
	assert_eq(camera.position, hero)
	assert_eq(camera.limit_right, 32 * 48)


func test_hero_cannot_leave_arena() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.driver = FixedTickDriver.create(RunView.placeholder_config())
	for _i: int in 600:
		view.advance_frame(TICK, Vector2i(-1, -1))
	assert_eq(view.driver.world.player_x, 24000)
	assert_eq(view.driver.world.player_y, 24000)


func test_tuning_reads_w0_roster_from_content() -> void:
	var tuning: P0Tuning = P0Tuning.new()
	var config: SimConfig = tuning.run_config(ContentRegistry.load_dir(), "20261113")
	assert_not_null(config, tuning.error)
	assert_true(config.is_valid())
	assert_eq(tuning.enemy_ids, PackedStringArray(["enemy.yin_corpse", "enemy.blood_wolf"]))
	# Catalog multipliers x placeholder bases; equal to the W0_KINDS trace input of sim_core.py.
	assert_eq(config.kinds, PackedInt64Array([
		3264, 24000, 12800, 6500, 36, 8,
		6144, 21600, 7800, 7600, 42, 2,
	]))
	assert_eq(config.hero_hp_mhp, 100000)
	assert_eq(config.spawn_min_distance_su, 384000)


func test_tuning_fails_closed_without_content() -> void:
	var tuning: P0Tuning = P0Tuning.new()
	assert_null(tuning.run_config(ContentRegistry.load_dir("res://does_not_exist"), "1"))
	assert_ne(tuning.error, "")
	assert_null(P0Tuning.new().run_config(ContentRegistry.load_dir(), "not-a-seed"))


func test_enemies_spawn_and_hurt_a_standing_hero() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("20261113")
	for _i: int in 50:
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_gt(view.driver.world.enemy_count(), 0, "first enemy after the spawn period")
	var guard: int = 0
	while not view.driver.world.is_over() and guard < 3000:
		view.advance_frame(TICK, Vector2i.ZERO)
		guard += 1
	assert_true(view.driver.world.is_over(), "a hero that never moves is caught")
	assert_eq(view.driver.world.hero_hp, 0)


func test_finished_run_restarts_after_delay() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("20261113")
	var guard: int = 0
	while not view.driver.world.is_over() and guard < 3000:
		view.advance_frame(TICK, Vector2i.ZERO)
		guard += 1
	var runs: int = view.runs_started
	var finished: FixedTickDriver = view.driver
	view.advance_frame(RunView.RESTART_DELAY * 0.5, Vector2i.ZERO)
	assert_eq(view.driver, finished, "the result stays on screen first")
	view.advance_frame(RunView.RESTART_DELAY, Vector2i.ZERO)
	assert_eq(view.runs_started, runs + 1)
	assert_false(view.driver.world.is_over())
	assert_eq(view.driver.world.tick, 0)
