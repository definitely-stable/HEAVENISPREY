extends GutTest
## ADR-014 A5c: an attack with a telegraph plays its clip by the simulation's attack state, and
## an ethereal kind hovers. Presentation only. The snake bite is kind 0 of the arc table of
## test_enemy_attacks.gd (tell 20, active 6, recover 27 ticks).

const Attacks: GDScript = preload("res://tests/unit/test_enemy_attacks.gd")
const RunViewTests: GDScript = preload("res://tests/integration/test_run_view.gd")


func test_a_telegraphed_attack_plays_wind_up_strike_and_recovery_by_its_state() -> void:
	var config: SimConfig = Attacks._config()
	var world: WorldState = Attacks._world(config, 0)
	var commands: CommandLog = CommandLog.new()
	var seen: Dictionary = {}
	var last: int = -1
	var struck_on_first_active: bool = false
	for tick: int in 90:
		var before: int = world.enemy_state[0]
		SimKernel.run(config, world, commands, 1)
		var state: int = world.enemy_state[0]
		var frame: int = EnemyMotion.attack_frame(config, world, 0, 6)
		if state == EnemyAttackSystem.ST_APPROACH:
			assert_eq(frame, -1, "no attack frame while it approaches (tick %d)" % tick)
			last = -1
			continue
		var phase: Array = seen.get(state, [])
		phase.append(frame)
		seen[state] = phase
		assert_true(frame >= last or before != state, "frames never step back within a phase (tick %d)" % tick)
		last = frame
		if state == EnemyAttackSystem.ST_ACTIVE and before == EnemyAttackSystem.ST_TELL:
			struck_on_first_active = frame == 2
	assert_eq(_range(seen[EnemyAttackSystem.ST_TELL]), [0, 1], "tell winds up on frames 0-1")
	assert_eq(_range(seen[EnemyAttackSystem.ST_ACTIVE]), [2, 3], "active strikes on frames 2-3")
	assert_eq(_range(seen[EnemyAttackSystem.ST_RECOVER]), [4, 5], "recover pulls back on frames 4-5")
	assert_true(struck_on_first_active, "the strike frame is the first active tick, when the hit lands")


func test_the_attack_faces_the_locked_direction() -> void:
	var config: SimConfig = Attacks._config()
	var world: WorldState = Attacks._world(config, 0)
	SimKernel.run(config, world, CommandLog.new(), 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_TELL)
	# The hero is on the enemy's -x side: the attack points to -x, up-left on the screen.
	var expected: Vector2 = IsoProjection.to_screen(Vector2(-1.0, 0.0))
	var signs: Vector2i = EnemyMotion.attack_signs(world, 0)
	assert_eq(signs, Vector2i(int(signf(expected.x)), int(signf(expected.y))))


func test_a_short_clip_or_a_contact_kind_keeps_its_loop() -> void:
	var config: SimConfig = Attacks._config()
	var world: WorldState = Attacks._world(config, 0)
	SimKernel.run(config, world, CommandLog.new(), 1)
	assert_eq(EnemyMotion.attack_frame(config, world, 0, 2), -1, "too short to split into three phases")
	world.enemy_state[0] = EnemyAttackSystem.ST_APPROACH
	assert_eq(EnemyMotion.attack_frame(config, world, 0, 6), -1)


func test_a_spirit_hovers_and_bobs_and_the_rest_stand() -> void:
	var spirit: String = "asset.enemy.wandering_spirit"
	var hover: Array = EnemyMotion.HOVER[spirit]
	var lifts: Array[float] = []
	for step: int in 40:
		lifts.append(EnemyMotion.lift(spirit, 9, step * 0.05))
	assert_almost_eq(lifts.min(), float(hover[0]) - float(hover[1]), 0.1, "it sinks to lift - bob")
	assert_almost_eq(lifts.max(), float(hover[0]) + float(hover[1]), 0.1, "and rises to lift + bob")
	assert_ne(EnemyMotion.lift(spirit, 9, 0.0), EnemyMotion.lift(spirit, 10, 0.0), "each spirit at its own phase")
	assert_eq(EnemyMotion.lift("asset.enemy.yin_corpse", 9, 0.3), 0.0, "a corpse stands on the ground")
	assert_lt(EnemyMotion.opacity(spirit), 1.0, "a spirit is a little see-through")
	assert_eq(EnemyMotion.opacity("asset.enemy.venom_spirit_snake"), 1.0)


## ADR-014 A5c: the snake bite (MELEE_ARC) plays its clip by the attack state, toward the
## locked direction; a spirit hovers above its feet.
func test_a_snake_winds_up_and_strikes_by_its_attack_state() -> void:
	var view: RunView = (load(RunViewTests.RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("20261113")
	RunViewTests._to_centre(view)
	var world: WorldState = view.driver.world
	var snake: int = view.tuning.enemy_ids.find("enemy.venom_spirit_snake")
	assert_gt(snake, -1)
	assert_eq(view._kind_assets[snake], "asset.enemy.venom_spirit_snake")
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_kind[slot] = snake
	world.enemy_x[slot] = world.player_x + 30 * Fx.FX_ONE
	world.enemy_y[slot] = world.player_y
	world.enemy_hp[slot] = 1000000
	world.next_enemy_uid += 1
	world.enemy_alive += 1
	var states: Dictionary = {}
	for step: int in 90:
		view.advance_frame(RunViewTests.TICK, Vector2i.ZERO)
		view._reactions.clear()
		if world.is_paused():
			view.choose(0)
		if world.enemy_uid[slot] == 0:
			break
		var pose: Array = view._enemy_pose(slot)
		var state: int = world.enemy_state[slot]
		if state == EnemyAttackSystem.ST_APPROACH:
			continue
		assert_eq(pose[1], "attack", "an attacking snake shows its attack clip")
		assert_eq(pose[2], "nw", "it bites toward the hero on its -x side (up-left)")
		states[state] = maxi(states.get(state, -1), pose[3])
	assert_eq(states.get(EnemyAttackSystem.ST_TELL, -1), 1, "the wind-up ends on frame 1")
	assert_eq(states.get(EnemyAttackSystem.ST_ACTIVE, -1), 3, "the strike plays frames 2-3")
	var spirit: String = "asset.enemy.wandering_spirit"
	assert_gt(EnemyMotion.lift(spirit, 1, 0.0), 0.0, "a spirit floats above its feet")


static func _range(frames: Array) -> Array:
	return [frames.min(), frames.max()]
