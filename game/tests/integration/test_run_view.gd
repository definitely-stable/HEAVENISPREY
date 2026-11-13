extends GutTest
## P0-01 placeholder run scene: input quantization, fixed-tick driver, scene wiring, tuning
## from content, enemies, auto-attack and restart.

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
	assert_eq(tuning.skill_id, "skill.spirit_sword", "class.sword start skill")
	assert_eq(config.skill_period_mt, 50000, "base_cooldown_ticks 50 from content")
	# Equal to the P0_VALUES / P0_SKILL trace inputs of sim_core.py.
	assert_eq(config.to_ints().slice(8, 22), PackedInt64Array([
		100000, 90000, 10800, 2000, 48, 384000,
		50000, 384000, 10000, 12000, 10000, 40, 1, 64,
	]))


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
	for _i: int in 90:
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_eq(view.driver.world.enemy_alive, 1, "first enemy at tick 89")
	var guard: int = 0
	while not view.driver.world.is_over() and guard < 3000:
		view.advance_frame(TICK, Vector2i.ZERO)
		guard += 1
	assert_true(view.driver.world.is_over(), "a hero that never moves is caught")
	assert_eq(view.driver.world.hero_hp, 0)
	assert_gt(view.driver.world.kills, 0, "the auto-attack kills on its own")


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


func test_driver_reports_hits_and_kills_once() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), "20261113")
	var driver: FixedTickDriver = FixedTickDriver.create(config)
	var hits: int = 0
	var kills: Array = []
	for _i: int in 1200:
		driver.advance(TICK, Vector2i.ZERO)
		var events: Dictionary = driver.take_events()
		hits += (events["hit"] as PackedInt64Array).size()
		kills.append_array(events["killed"])
	assert_eq(kills.size(), driver.world.kills, "one death event per kill")
	assert_gt(hits, 0)
	assert_true((driver.take_events()["killed"] as Array).is_empty(), "events are cleared when taken")


func test_enemy_in_a_reused_slot_is_not_interpolated() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), "20261113")
	var driver: FixedTickDriver = FixedTickDriver.create(config)
	for _i: int in 101:
		driver.advance(TICK, Vector2i.ZERO)
	driver.previous.enemy_uid[0] = 999
	driver.previous.enemy_x[0] = 0
	var at: Vector2 = driver.enemy_position_px(0)
	assert_eq(at, Vector2(driver.world.enemy_x[0], driver.world.enemy_y[0]) / float(Fx.FX_ONE))


func test_bot_log_replays_through_the_scene() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/sim_bot_runs.json"))
	var row: Dictionary = (data["traces"] as Array)[1]
	assert_eq(str(row["id"]), "botrun.p0.circle.s101")
	var moves: Dictionary = {}
	for record: Variant in row["commands"]:
		var command: Array = record
		moves[str(command[0]).to_int()] = Vector2i(str(command[2]).to_int(), str(command[3]).to_int())
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("101")
	var held: Vector2i = Vector2i.ZERO
	while not view.driver.world.is_over() and view.driver.world.tick < 18000:
		held = moves.get(view.driver.world.tick, held)
		view.advance_frame(TICK, held)
	var checkpoints: Array = row["checkpoints"]
	assert_eq(view.driver.world.tick, int(row["death_tick"]), "same death tick")
	assert_eq(view.driver.world.digest(), str((checkpoints.back() as Dictionary)["digest"]), "same state")
	assert_eq(view.driver.commands.digest(), str(row["log_digest"]), "input recorded as the same log")


func test_scene_reports_gem_pickups_and_levels() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("101")
	var driver: FixedTickDriver = view.driver
	var picked: int = 0
	var levels: int = 0
	while not driver.world.is_over() and driver.world.tick < 3000:
		var east: bool = floori(driver.world.tick / 240.0) % 2 == 0
		driver.advance(TICK, Vector2i(1 if east else -1, 0))
		var events: Dictionary = driver.take_events()
		for gem: Array in events["collected"]:
			picked += int(gem[1])
		levels += int(events["levels"])
	assert_gt(picked, 0, "pickups of gems seen on the ground are reported")
	assert_lte(picked, driver.world.xp_collected_total, "never more than was credited")
	assert_gt(driver.world.level, 1)
	assert_eq(levels, driver.world.level - 1, "every level gained is reported once")
