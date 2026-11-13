extends GutTest
## Level-up choice in the scene (ADR-010 sections 6 and 9, slice 5b): the menu over the paused
## run, the driver that neither spends time nor records MOVE in a pause, CHOOSE in the same
## log, RU/EN card texts and a bot log with choices replayed through the scene.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const UPGRADE_RUNS: String = "res://tests/fixtures/sim_bot_upgrade_runs.json"
const TICK: float = 1.0 / 60.0
const SEED: String = "20261113"

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


## Frames holding `move` until the run pauses for a choice (or `limit` frames).
static func _to_pause(view: RunView, move: Vector2i, limit: int = 20000) -> void:
	var guard: int = 0
	while not view.driver.world.is_paused() and not view.driver.world.is_over() and guard < limit:
		view.advance_frame(TICK, move)
		guard += 1


static func _driver_to_pause(driver: FixedTickDriver, delta: float, move: Vector2i) -> void:
	var guard: int = 0
	while not driver.world.is_paused() and not driver.world.is_over() and guard < 20000:
		driver.advance(delta, move)
		guard += 1


func test_game_runs_with_the_immediate_choice() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), SEED)
	assert_eq(config.choice_mode, SimConfig.CHOICE_IMMEDIATE)


func test_level_up_pauses_the_scene_under_the_menu() -> void:
	var view: RunView = _view()
	view.start_run(SEED)
	assert_false(view.is_menu_open())
	_to_pause(view, Vector2i.ZERO)
	var world: WorldState = view.driver.world
	assert_true(world.is_paused(), "a level is reached")
	assert_true(view.is_menu_open())
	var menu: ChoiceMenu = _menu(view)
	assert_eq(menu.revision, world.build_revision)
	var shown: int = 0
	for card: Button in menu.cards:
		shown += int(card.visible)
	assert_eq(shown, world.hand.size())
	var frozen: String = world.digest()
	var enemy_rng: int = world.enemy_rng_cursor
	var logged: int = view.driver.commands.size()
	for _i: int in 300:
		assert_eq(view.advance_frame(TICK, Vector2i(0, 1)), 0, "no tick in the menu")
	assert_eq(world.digest(), frozen, "five seconds of menu change nothing")
	assert_eq(world.enemy_rng_cursor, enemy_rng)
	assert_eq(view.driver.commands.size(), logged, "no MOVE recorded in a pause")


func test_menu_picks_only_once_armed_and_logs_choose() -> void:
	var view: RunView = _view()
	view.start_run(SEED)
	_to_pause(view, Vector2i.ZERO)
	var menu: ChoiceMenu = _menu(view)
	var world: WorldState = view.driver.world
	var revision: int = world.build_revision
	var card: int = world.hand[1]
	var rank: int = world.ranks[card] if card < UpgradeSystem.MAX_RANKS.size() else 0
	assert_false(menu.press(1), "a held button does not pick on the first frame")
	view.advance_frame(ChoiceMenu.ARM_DELAY * 0.5, Vector2i.ZERO)
	assert_false(menu.press(1))
	view.advance_frame(ChoiceMenu.ARM_DELAY, Vector2i.ZERO)
	assert_true(menu.press(1))
	assert_eq(world.choices_done, 1)
	assert_eq(world.build_revision, revision + 1)
	if card < UpgradeSystem.MAX_RANKS.size():
		assert_eq(world.ranks[card], rank + 1, "the second card was applied")
	var commands: CommandLog = view.driver.commands
	var last: int = commands.size() - 1
	assert_eq(commands.kind_at(last), PlayerCommand.CHOOSE)
	assert_eq([commands.tick_at(last), commands.a_at(last), commands.b_at(last)], [world.tick, 1, revision])
	assert_eq(view.is_menu_open(), world.is_paused(), "the menu follows the pause")


func test_driver_does_not_record_a_card_that_does_not_exist() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), SEED)
	var driver: FixedTickDriver = FixedTickDriver.create(config)
	assert_false(driver.choose(0), "no pause, no choice")
	_driver_to_pause(driver, TICK, Vector2i.ZERO)
	var logged: int = driver.commands.size()
	for index: int in [-1, driver.world.hand.size(), 7]:
		assert_false(driver.choose(index), str(index))
	assert_eq(driver.commands.size(), logged, "a rejected pick is not logged")
	assert_true(driver.choose(driver.world.hand.size() - 1))
	assert_eq(driver.commands.size(), logged + 1)


func test_menu_open_five_seconds_at_60_and_15_fps_gives_the_same_run() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), SEED)
	var runs: Array[FixedTickDriver] = []
	for fps: float in [60.0, 15.0]:
		var driver: FixedTickDriver = FixedTickDriver.create(config)
		_driver_to_pause(driver, 1.0 / fps, Vector2i.ZERO)
		assert_true(driver.world.is_paused(), str(fps))
		var frozen: String = driver.world.digest()
		for _i: int in roundi(5.0 * fps):
			assert_eq(driver.advance(1.0 / fps, Vector2i(-1, 0)), 0)
		assert_eq(driver.world.digest(), frozen, str(fps) + " menu changes nothing")
		while driver.world.is_paused():
			assert_true(driver.choose(0))
		while driver.world.tick < 1800 and not driver.world.is_over():
			if driver.world.is_paused():
				driver.choose(0)
			else:
				driver.advance(1.0 / fps, Vector2i(1, 0))
		runs.append(driver)
	var fast: FixedTickDriver = runs[0]
	var slow: FixedTickDriver = runs[1]
	assert_gt(fast.world.choices_done, 0)
	assert_gt(fast.commands.size(), fast.world.choices_done, "MOVE after the pause is logged")
	assert_eq(slow.commands.digest(), fast.commands.digest(), "same log at 60 and 15 FPS")
	var tick: int = mini(fast.world.tick, slow.world.tick)
	var replay_fast: WorldState = _replay(config, fast.commands, tick)
	assert_eq(_replay(config, slow.commands, tick).digest(), replay_fast.digest())
	assert_eq(replay_fast.offers_rng_cursor, _replay(config, slow.commands, tick).offers_rng_cursor)
	assert_eq(_replay(config, fast.commands, fast.world.tick).digest(), fast.world.digest(), "replay == live")


func test_kiter_upgrades_log_replays_through_the_scene() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UPGRADE_RUNS))
	var row: Dictionary = (data["traces"] as Array)[0]
	assert_eq(str(row["id"]), "botrun.p0.kiter_upgrades.s101")
	var mark: Dictionary = {}
	for checkpoint: Variant in row["checkpoints"]:
		mark = checkpoint
		if int(mark["step"]) >= 3600:
			break
	assert_eq(int(mark["paused"]), 0, "a checkpoint outside the menu")
	var moves: Dictionary = {}
	var picks: Array[int] = []
	var records: Array = row["commands"]
	for record: Variant in records:
		var command: Array = record
		if str(command[2]).to_int() == PlayerCommand.MOVE:
			moves[str(command[0]).to_int()] = Vector2i(str(command[3]).to_int(), str(command[4]).to_int())
		else:
			picks.append(str(command[3]).to_int())
	var view: RunView = _view()
	view.start_run("101")
	var held: Vector2i = Vector2i.ZERO
	var picked: int = 0
	var target: int = int(mark["tick"])
	while view.driver.world.tick < target:
		if view.driver.world.is_paused():
			assert_true(view.choose(picks[picked]), "pick " + str(picked))
			picked += 1
			continue
		held = moves.get(view.driver.world.tick, held)
		view.advance_frame(TICK, held)
	var world: WorldState = view.driver.world
	assert_eq([world.tick, world.choices_done], [target, int(mark["choices"])])
	assert_eq(world.digest(), str(mark["digest"]), "the scene plays the bot run")
	var log: CommandLog = view.driver.commands
	assert_gt(log.size(), int(mark["choices"]))
	for index: int in log.size():
		var expected: Array = records[index]
		var got: PackedInt64Array = log.records().slice(index * CommandLog.STRIDE, (index + 1) * CommandLog.STRIDE)
		assert_eq(got, PackedInt64Array(expected.map(func(v: Variant) -> int: return str(v).to_int())))


func test_card_texts_in_both_locales() -> void:
	assert_true(UiText.ensure_loaded())
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), SEED)
	var world: WorldState = WorldState.initial(config)
	TranslationServer.set_locale("en")
	var damage: Dictionary = UpgradeCard.describe(config, world, UpgradeSystem.DAMAGE)
	assert_eq(damage, {"name": "Honed Edge", "stat": "Sword damage 10 → 13", "rank": "Rank 1/2"})
	TranslationServer.set_locale("ru")
	damage = UpgradeCard.describe(config, world, UpgradeSystem.DAMAGE)
	assert_eq(damage, {"name": "Отточенный клинок", "stat": "Урон меча 10 → 13", "rank": "Ранг 1/2"})
	world.hero_hp = 50000
	var recover: Dictionary = UpgradeCard.describe(config, world, UpgradeSystem.RECOVER)
	assert_eq([recover["stat"], recover["rank"]], ["Здоровье 50 → 70", ""])


func test_card_stat_lines_follow_the_simulation() -> void:
	var config: SimConfig = P0Tuning.new().run_config(ContentRegistry.load_dir(), SEED)
	var world: WorldState = WorldState.initial(config)
	var expected: Dictionary = {
		UpgradeSystem.SPEED: ["288", "302"], UpgradeSystem.VITALITY: ["100", "120"],
		UpgradeSystem.PICKUP: ["48", "72"], UpgradeSystem.COUNT: ["1", "2"],
		UpgradeSystem.DAMAGE: ["10", "13"], UpgradeSystem.HASTE: ["1.20", "1.38"],
		UpgradeSystem.PIERCE: ["2", "3"], UpgradeSystem.RECOVER: ["100", "100"],
	}
	for code: int in expected:
		var after: WorldState = world.copy()
		UpgradeSystem.apply_upgrade(after, code)
		assert_eq([UpgradeCard.stat(config, world, code), UpgradeCard.stat(config, after, code)], expected[code])
	assert_eq(UpgradeCard.key_stem(UpgradeSystem.PICKUP), "UPGRADE_P0_PICKUP_RADIUS")
	assert_eq(UpgradeCard.key_stem(UpgradeSystem.RECOVER), "UPGRADE_P0_RECOVER")


func test_every_card_has_text_in_both_locales() -> void:
	assert_true(UiText.ensure_loaded())
	for locale: String in UiText.LOCALES:
		TranslationServer.set_locale(locale)
		for code: int in UpgradeSystem.MAX_RANKS.size() + 1:
			for suffix: String in ["_NAME", "_DESC"]:
				var key: String = UpgradeCard.key_stem(code) + suffix
				assert_ne(UiText.text(key), key, locale + " " + key)


func test_locale_choice() -> void:
	assert_eq(UiText.pick_locale("auto", "ru"), "ru")
	assert_eq(UiText.pick_locale("auto", "de"), "en")
	assert_eq(UiText.pick_locale("en", "ru"), "en")
	assert_eq(UiText.pick_locale("ru", "en"), "ru")
	assert_eq(UiText.pick_locale("xx", "ru"), "ru", "unknown preference -> auto")
	assert_false(UiText.ensure_loaded("res://does_not_exist.json"))
	assert_string_contains(UiText.error, "not found")
	assert_true(UiText.ensure_loaded(), "the real file still loads")
	assert_eq(UiText.text("NO_SUCH_KEY"), "NO_SUCH_KEY")


func test_restart_closes_the_menu() -> void:
	var view: RunView = _view()
	view.start_run(SEED)
	_to_pause(view, Vector2i.ZERO)
	assert_true(view.is_menu_open())
	view.start_run(SEED)
	assert_false(view.is_menu_open())
	assert_eq(view.driver.world.tick, 0)


static func _menu(view: RunView) -> ChoiceMenu:
	return view.get("_menu")


static func _replay(config: SimConfig, commands: CommandLog, tick: int) -> WorldState:
	var world: WorldState = WorldState.initial(config)
	var guard: int = 0
	while world.tick < tick and guard < tick * 2 + 100:
		SimKernel.step(config, world, commands)
		guard += 1
	return world
