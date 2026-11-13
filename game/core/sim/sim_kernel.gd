class_name SimKernel
extends RefCounted
## Fixed 60 Hz simulation step (s04, ADR-008, ADR-009 section 1, ADR-010). Exact port of
## tools/content/sim_core.py.
##
## A paused run (a level-up hand is offered, ADR-010 section 6) only reads the log: records
## with tick <= world.tick in sequence order up to and including the first accepted CHOOSE (a
## MOVE only sets the held direction, a rejected CHOOSE is skipped); the tick does not advance
## and nothing else changes. One step resolves at most one choice, live and in replay alike.
##
## Phase order inside one tick (P0-01 subset of s04):
##   0. a finished run (hero dead) does not step;
##   1. apply every logged command whose tick <= world.tick, in log order (last MOVE wins; a
##      CHOOSE outside a pause is skipped);
##   2. move the hero by the held direction (Q14 unit vector x speed with upgrades, symmetric
##      rounding) and clamp inside the arena rectangle (radius-aware);
##   3. spawn at most one enemy into the lowest free slot (EnemySystem.spawn);
##   4. move enemies toward the hero with separation, capped at their speed
##      (SeparationSystem.chase_and_separate);
##   5. hero skill: cooldown, target, cast (CombatSystem.cast);
##   6-7a. projectiles fly and hit enemies, slot order (CombatSystem.fly_and_hit);
##   7b. enemy contact hits, slot order, enemies at 0 HP do not hit (EnemySystem.contact);
##   8. deaths: enemies in slot order (XP gem drop, slot freed, kill counted), expired
##      projectiles, then the hero (pending level choices are voided when the run ends);
##   9. XP pickup within the pickup radius (XpSystem.pickup), not in the tick the hero dies;
##   10. level progression from the XP bank (XpSystem.progress), same condition; with
##       choice_mode Immediate and choices pending the first hand is built (the run pauses);
##   11. advance the tick.
## No float, no Input, no delta: the same log and config give the same state everywhere.

const AXIS_Q14: int = 16384
## round(16384 / sqrt(2)): diagonal component of a unit vector, equal to FxTables sin(45 deg).
const DIAG_Q14: int = 11585


static func direction_q14(move_x: int, move_y: int) -> PackedInt64Array:
	if move_x != 0 and move_y != 0:
		return PackedInt64Array([signi(move_x) * DIAG_Q14, signi(move_y) * DIAG_Q14])
	return PackedInt64Array([signi(move_x) * AXIS_Q14, signi(move_y) * AXIS_Q14])


static func step(config: SimConfig, world: WorldState, commands: CommandLog) -> void:
	if world.is_over():
		return
	if world.is_paused():
		var accepted: bool = false
		while not accepted and _has_due_command(world, commands):
			accepted = _apply_command(config, world, commands, world.command_cursor)
			world.command_cursor += 1
		return
	while _has_due_command(world, commands):
		_apply_command(config, world, commands, world.command_cursor)
		world.command_cursor += 1
	var direction: PackedInt64Array = direction_q14(world.move_x, world.move_y)
	var r: int = config.player_radius_su
	var speed: int = UpgradeSystem.hero_speed(config, world)
	var next_x: int = world.player_x + Fx.mul_q14(speed, direction[0])
	var next_y: int = world.player_y + Fx.mul_q14(speed, direction[1])
	world.player_x = clampi(next_x, config.arena_min_x + r, config.arena_max_x - r)
	world.player_y = clampi(next_y, config.arena_min_y + r, config.arena_max_y - r)
	if config.has_enemies():
		EnemySystem.spawn(config, world)
		SeparationSystem.chase_and_separate(config, world)
		if config.has_skill():
			CombatSystem.cast(config, world)
			CombatSystem.fly_and_hit(config, world)
		EnemySystem.contact(config, world)
		EnemySystem.clear_dead(config, world)
		if config.has_skill():
			CombatSystem.clear_expired(world)
	# Terminal checks (ADR-009 section 4, ADR-011 section 1): victory beats defeat; a terminal
	# tick runs neither pickup nor progression and voids the pending choices.
	if config.run_ticks > 0 and world.tick + 1 == config.run_ticks:
		world.won = 1
		world.hero_hp = maxi(world.hero_hp, 0)
		_void_choices(world)
	elif config.has_enemies() and world.hero_hp <= 0:
		world.hero_hp = 0
		world.hero_dead = 1
		_void_choices(world)
	elif config.has_enemies() and config.has_xp():
		XpSystem.pickup(config, world)
		XpSystem.progress(config, world)
		if config.choice_mode == SimConfig.CHOICE_IMMEDIATE and world.pending_level_choices > 0:
			UpgradeSystem.build_hand(config, world)
	world.tick += 1


## A terminal tick cancels the pending choices without drawing offers (ADR-009 section 4).
static func _void_choices(world: WorldState) -> void:
	world.choices_voided += world.pending_level_choices
	world.pending_level_choices = 0


## The next unread log record is for this tick or an earlier one.
static func _has_due_command(world: WorldState, commands: CommandLog) -> bool:
	return world.command_cursor < commands.size() and commands.tick_at(world.command_cursor) <= world.tick


## Applies one log record; true only for an accepted CHOOSE.
static func _apply_command(config: SimConfig, world: WorldState, commands: CommandLog, index: int) -> bool:
	if commands.kind_at(index) == PlayerCommand.MOVE:
		world.move_x = commands.move_x_at(index)
		world.move_y = commands.move_y_at(index)
		return false
	return UpgradeSystem.choose(config, world, commands.a_at(index), commands.b_at(index))


static func run(config: SimConfig, world: WorldState, commands: CommandLog, ticks: int) -> void:
	for _i: int in ticks:
		step(config, world, commands)
