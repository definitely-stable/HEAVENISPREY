extends GutTest
## ADR-014 A5c: an attack with a telegraph plays its clip by the simulation's attack state, and
## an ethereal kind hovers. Presentation only. The snake bite is kind 0 of the arc table of
## test_enemy_attacks.gd (tell 20, active 6, recover 27 ticks).

const Attacks: GDScript = preload("res://tests/unit/test_enemy_attacks.gd")
const RunViewTests: GDScript = preload("res://tests/integration/test_run_view.gd")
const Shots: GDScript = preload("res://tests/unit/test_enemy_shots.gd")
const LANTERN: String = "asset.enemy.cursed_spirit_lantern"


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
	var signs: Vector2i = EnemyMotion.attack_signs(config, world, 0)
	assert_eq(signs, Vector2i(int(signf(expected.x)), int(signf(expected.y))))


## A charge aims at the hero until the end of `tell` (ADR-011 E3): the mantis faces the hero
## while it winds up, then the locked direction while it dashes.
func test_a_charge_faces_the_hero_while_it_winds_up() -> void:
	var config: SimConfig = Attacks._mantis()
	var world: WorldState = Attacks._mantis_world(config)
	SimKernel.run(config, world, CommandLog.new(), 1)
	assert_eq(world.enemy_state[0], EnemyAttackSystem.ST_TELL)
	world.player_y += 300 * Fx.FX_ONE
	var hero: Vector2 = Vector2(world.player_x - world.enemy_x[0], world.player_y - world.enemy_y[0])
	var toward: Vector2 = IsoProjection.to_screen(hero)
	var signs: Vector2i = EnemyMotion.attack_signs(config, world, 0)
	assert_eq(signs, Vector2i(int(signf(toward.x)), int(signf(toward.y))), "faces the hero, not the old direction")
	world.enemy_state[0] = EnemyAttackSystem.ST_ACTIVE
	var locked: Vector2 = IsoProjection.to_screen(Vector2(world.enemy_dir_x[0], world.enemy_dir_y[0]))
	signs = EnemyMotion.attack_signs(config, world, 0)
	assert_eq(signs, Vector2i(-1 if locked.x < 0.0 else 1, -1 if locked.y < 0.0 else 1), "dashes the locked way")


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


## ADR-014 section 27: a shot leaves in a single active tick. Its release frame shows on that tick
## and opens recover, which plays the rest of the clip; tell winds up as before.
func test_a_shot_shows_its_release_on_the_active_tick_and_through_recover() -> void:
	var config: SimConfig = Shots._lantern()
	var world: WorldState = Shots._lantern_world(config)
	var seen: Dictionary = {}
	var released: bool = false
	var last: int = -1
	for tick: int in 120:
		var before: int = world.enemy_state[0]
		Shots._run(config, world, 1)
		var state: int = world.enemy_state[0]
		var frame: int = EnemyMotion.attack_frame(config, world, 0, 6)
		if state == EnemyAttackSystem.ST_APPROACH:
			if before == EnemyAttackSystem.ST_RECOVER:
				break
			continue
		var phase: Array = seen.get(state, [])
		phase.append(frame)
		seen[state] = phase
		assert_true(frame >= last or state == EnemyAttackSystem.ST_TELL, "no step back after tell (tick %d)" % tick)
		last = frame
		if state == EnemyAttackSystem.ST_ACTIVE:
			released = Array(world.shot_damage).any(func(damage: int) -> bool: return damage != 0)
	assert_true(EnemyMotion.instant(config, 0), "a shot is released in one tick")
	assert_eq(_range(seen[EnemyAttackSystem.ST_TELL]), [0, 1], "tell winds up on frames 0-1")
	assert_eq(seen[EnemyAttackSystem.ST_ACTIVE], [2], "the release frame on the active tick")
	assert_true(released, "the shot is in the air on that tick")
	assert_eq(_range(seen[EnemyAttackSystem.ST_RECOVER]), [2, 5], "recover holds the release, then plays 3-5")
	assert_false(EnemyMotion.instant(Attacks._config(), 0), "an arc strikes over its active ticks")


## ADR-014 section 27: the lantern flies higher than a spirit; a fallen hovering body drops to the
## ground as its death clip starts, faster as it falls; a grounded body stays on the ground.
func test_a_fallen_hovering_body_drops_to_the_ground() -> void:
	var lift: float = float(EnemyMotion.HOVER[LANTERN][0])
	assert_gt(lift, float(EnemyMotion.HOVER["asset.enemy.wandering_spirit"][0]), "a lantern flies higher")
	assert_eq(EnemyMotion.fall_lift(LANTERN, 0.0), lift, "it starts at its lift")
	var half: float = EnemyMotion.fall_lift(LANTERN, EnemyMotion.FALL_TIME * 0.5)
	assert_almost_eq(half, lift * 0.75, 0.01, "slow at first")
	assert_gt(half, EnemyMotion.fall_lift(LANTERN, EnemyMotion.FALL_TIME * 0.9))
	assert_eq(EnemyMotion.fall_lift(LANTERN, EnemyMotion.FALL_TIME), 0.0, "on the ground at FALL_TIME")
	assert_eq(EnemyMotion.fall_lift(LANTERN, 2.0), 0.0)
	assert_eq(EnemyMotion.fall_lift("asset.enemy.yin_corpse", 0.0), 0.0, "a corpse falls where it stands")


static func _range(frames: Array) -> Array:
	return [frames.min(), frames.max()]
