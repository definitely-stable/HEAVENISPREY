class_name EnemyShotSystem
extends RefCounted
## Enemy shots (ADR-011 section 3, E4). Exact port of tools/content/sim_core.py.
##
## A PROJECTILE attack releases one shot from the enemy centre along the direction locked at
## the end of `tell`, speed shot_speed_su, lifetime active_ticks, the kind damage; it takes the
## lowest free slot, and with SimConfig.ENEMY_SHOTS_LIMIT slots taken it is not fired. After the
## hero's projectiles, in slot order, a shot moves, loses a tick of life and is freed past the
## arena edge, on touching the hero (the damage, once) or when its life runs out. Shots outlive
## the enemy that fired them. A projectile kind does not chase closer than keep_su.


static func keeps_distance(config: SimConfig, world: WorldState, slot: int) -> bool:
	var kind: int = world.enemy_kind[slot]
	if config.attack_value(kind, SimConfig.ATTACK_FORM) != SimConfig.FORM_PROJECTILE:
		return false
	var keep: int = config.attack_value(kind, SimConfig.ATTACK_KEEP)
	var d2: int = EnemySystem.dist2(world.enemy_x[slot], world.enemy_y[slot], world.player_x, world.player_y)
	return d2 <= keep * keep


static func release(config: SimConfig, world: WorldState, slot: int) -> void:
	var kind: int = world.enemy_kind[slot]
	var shot: int = -1
	for index: int in world.shot_slots():
		if world.shot_damage[index] == 0:
			shot = index
			break
	if shot < 0:
		if world.shot_slots() >= SimConfig.ENEMY_SHOTS_LIMIT:
			return
		shot = world.append_shot_slot()
	var speed: int = config.attack_value(kind, SimConfig.ATTACK_SHOT_SPEED)
	world.shot_x[shot] = world.enemy_x[slot]
	world.shot_y[shot] = world.enemy_y[slot]
	world.shot_vx[shot] = Fx.mul_q14(speed, world.enemy_dir_x[slot])
	world.shot_vy[shot] = Fx.mul_q14(speed, world.enemy_dir_y[slot])
	world.shot_ttl[shot] = config.attack_value(kind, SimConfig.ATTACK_ACTIVE)
	world.shot_damage[shot] = config.kind_value(kind, SimConfig.KIND_DAMAGE)
	world.shot_radius[shot] = config.attack_value(kind, SimConfig.ATTACK_SHOT_RADIUS)


static func fly(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] == 0:
			continue
		world.shot_x[slot] += world.shot_vx[slot]
		world.shot_y[slot] += world.shot_vy[slot]
		world.shot_ttl[slot] -= 1
		var x: int = world.shot_x[slot]
		var y: int = world.shot_y[slot]
		if x < config.arena_min_x or x > config.arena_max_x or y < config.arena_min_y or y > config.arena_max_y:
			_free(world, slot)
			continue
		var reach: int = config.player_radius_su + world.shot_radius[slot]
		if EnemySystem.dist2(x, y, world.player_x, world.player_y) <= reach * reach:
			world.hero_hp -= world.shot_damage[slot]
			_free(world, slot)
		elif world.shot_ttl[slot] <= 0:
			_free(world, slot)


static func _free(world: WorldState, slot: int) -> void:
	world.shot_x[slot] = 0
	world.shot_y[slot] = 0
	world.shot_vx[slot] = 0
	world.shot_vy[slot] = 0
	world.shot_ttl[slot] = 0
	world.shot_damage[slot] = 0
	world.shot_radius[slot] = 0
