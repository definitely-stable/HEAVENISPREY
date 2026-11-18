extends GutTest

const SKILL: PackedInt64Array = [65000, 384000, 8000, 0, 0, 0, 0, 0]
const CHAIN: PackedInt64Array = [SimConfig.SKILL_CHAIN, 4, 144000]
const SWORD: PackedInt64Array = [50000, 384000, 10000, 12000, 10000, 40, 1, 64]
const MOVE: PackedInt64Array = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const TICK: float = FixedTickDriver.TICK_SECONDS


static func _config(skill: PackedInt64Array, shape: PackedInt64Array, hp: int = 100000) -> SimConfig:
	return SimConfig.create(MOVE).with_enemies(
		PackedInt64Array([500000000, 268435456, 0, 1000, 32, 0]),
		PackedInt64Array([0, 12000, hp, 0, 36, 1]), "101"
	).with_skill(skill, shape)


static func _enemy(world: WorldState, uid: int, dx: int, dy: int, hp: int) -> void:
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = uid
	world.enemy_x[slot] = world.player_x + dx
	world.enemy_y[slot] = world.player_y + dy
	world.enemy_hp[slot] = hp
	world.enemy_alive += 1


func test_chain_first_target_inclusive_and_cast_held_if_no_target() -> void:
	var config: SimConfig = _config(SKILL, CHAIN)
	var world: WorldState = WorldState.initial(config)
	world.tick = 100
	world.skill_acc = config.skill_period_mt - SimConfig.RATE_ONE
	_enemy(world, 16, config.skill_range_su + 1, 0, 100000)
	CombatSystem.cast(config, world)
	assert_eq(world.skill_acc, 64000)
	assert_eq(world.chain_len, 0)
	world.enemy_x[0] -= 1
	CombatSystem.cast(config, world)
	assert_eq(world.skill_acc, 0)
	assert_eq(world.chain_tick, 100)
	assert_eq(world.chain_uids, PackedInt64Array([16, 0, 0, 0, 0, 0, 0, 0]))


func test_chain_uses_killed_previous_target_and_inclusive_jump_and_lower_slot() -> void:
	var config: SimConfig = _config(SKILL, CHAIN)
	var world: WorldState = WorldState.initial(config)
	world.tick = 100
	world.skill_acc = 64000
	_enemy(world, 20, 200000, 0, 1000)
	_enemy(world, 99, 344000, 0, 100000)
	_enemy(world, 1, 200000, 144000, 100000)
	_enemy(world, 40, 488001, 0, 100000)
	CombatSystem.cast(config, world)
	assert_eq(world.enemy_hp, PackedInt64Array([0, 92000, 100000, 100000]))
	assert_eq(world.chain_uids, PackedInt64Array([20, 99, 0, 0, 0, 0, 0, 0]))
	assert_eq(world.copy().to_ints().slice(44, 54), PackedInt64Array([100, 2, 20, 99, 0, 0, 0, 0, 0, 0]))


func test_chain_does_not_repeat_a_surviving_target() -> void:
	var config: SimConfig = _config(SKILL, CHAIN)
	var world: WorldState = WorldState.initial(config)
	world.skill_acc = 64000
	for index: int in 3:
		_enemy(world, 20 + index, 24000 * (index + 1), 0, 100000)
	CombatSystem.cast(config, world)
	assert_eq(world.chain_uids, PackedInt64Array([20, 21, 22, 0, 0, 0, 0, 0]))
	assert_eq(world.enemy_hp, PackedInt64Array([92000, 92000, 92000]))


func test_chain_config_bounds_and_catalog_effects() -> void:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
		registry, PackedStringArray(["unlock.thunder"]), "class.thunder", P0Tuning.STAGE_ID,
		"difficulty.standard", PackedStringArray(["mode.normal"]), "101"
	)
	var tuning: P0Tuning = P0Tuning.new()
	var config: SimConfig = tuning.run_config(registry, snapshot)
	assert_not_null(config, tuning.error)
	assert_eq(tuning.skill_id, "skill.thunder_chain")
	assert_eq(config.to_ints().slice(14, 22), SKILL)
	assert_eq(config.skill_form, SimConfig.SKILL_CHAIN)
	assert_true(config.is_valid())
	config.chain_hits = 7
	assert_false(config.is_valid())
	config.choice_mode = SimConfig.CHOICE_NONE
	config.chain_hits = 8
	assert_true(config.is_valid())
	config.chain_hits += 1
	assert_false(config.is_valid())
	config.chain_hits = 8
	config.projectile_pierce = 1
	assert_false(config.is_valid())
	assert_false(P0Tuning._start_effects_supported([{"op": "damage"}, {"op": "summon"}]))
	assert_false(P0Tuning._start_effects_supported([{"op": "apply_status", "status_id": "status.venom"}]))
	assert_true(P0Tuning._start_effects_supported([{"op": "damage"}, {"op": "apply_status", "status_id": "status.shock"}]))


static func _fight(skill: PackedInt64Array, shape: PackedInt64Array, enemies: int, hp: int) -> Vector2i:
	var config: SimConfig = _config(skill, shape, hp)
	var world: WorldState = WorldState.initial(config)
	for index: int in enemies:
		var x: int = 72000 + Fx.floor_div(index, 5) * 27500
		var y: int = (index % 5 - 2) * 27500
		_enemy(world, index + 1, x, y, hp)
	var log: CommandLog = CommandLog.new()
	for _i: int in 600:
		SimKernel.step(config, world, log)
		if world.kills == enemies:
			return Vector2i(world.tick, enemies * hp)
	var remaining: int = 0
	for health: int in world.enemy_hp:
		remaining += health
	return Vector2i(world.tick, enemies * hp - remaining)


func test_chain_and_sword_class_roles() -> void:
	var projectile: PackedInt64Array = PackedInt64Array([0, 0, 0])
	assert_gt(_fight(SKILL, CHAIN, 20, 100000).y, _fight(SWORD, projectile, 20, 100000).y)
	assert_gt(_fight(SKILL, CHAIN, 1, 10000).x, _fight(SWORD, projectile, 1, 10000).x)


func test_scene_shows_chain_to_live_and_fallen_targets_for_120_ms() -> void:
	var scene: PackedScene = load("res://presentation/run/run_view.tscn")
	var view: RunView = scene.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	assert_true(view.start_run("101"))
	view.driver = FixedTickDriver.create(_config(SKILL, CHAIN))
	var world: WorldState = view.driver.world
	world.skill_acc = 64000
	_enemy(world, 2, 120000, 0, 1000)
	_enemy(world, 1, 180000, 0, 100000)
	var origin: Vector2 = Vector2(world.player_x, world.player_y) / Fx.FX_ONE
	view.advance_frame(TICK, Vector2i.ZERO)
	assert_eq(world.kills, 1)
	assert_eq(view._chain_left, 0.12)
	var expected: PackedVector2Array = PackedVector2Array()
	for dx: int in [0, 120, 180]:
		expected.append(IsoProjection.to_screen(origin + Vector2(dx, 0)) - Vector2(0, 18))
	assert_eq(view._chain_line, expected)
	view.advance_frame(0.121, Vector2i.ZERO)
	assert_eq(view._chain_left, 0.0)


func test_thunder_card_localization_displays_its_own_stat() -> void:
	var config: SimConfig = _config(SKILL, CHAIN)
	var world: WorldState = WorldState.initial(config)
	UiText.apply_locale("en")
	var card: Dictionary = UpgradeCard.describe(config, world, UpgradeSystem.THUNDER_DAMAGE)
	assert_eq(card["name"], "Storm Wrath")
	assert_eq(card["change"], "8 → 10")
	UiText.apply_locale("ru")
	card = UpgradeCard.describe(config, world, UpgradeSystem.THUNDER_JUMPS)
	assert_eq(card["name"], "Ветвистый разряд")
	assert_eq(card["change"], "4 → 5")
	UiText.apply_locale()
