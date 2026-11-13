class_name CombatSystem
extends RefCounted
## Hero skill phases of SimKernel (ADR-009 section 1, `skill.spirit_sword` damage part).
## Exact port of tools/content/sim_core.py.
##
## Cast: the cooldown accumulator gains 1000 per tick; when it reaches the period and a live
## enemy is within range, one projectile is fired at the nearest one (min distance^2, then
## lower slot) and the period is subtracted. With no target, or no free projectile slot, the
## tick does not advance the accumulator: it stays ready, no charges are stored, and the next
## cast after a hold comes exactly one period after it. Projectiles fly in the direction
## locked at cast; leaving the arena removes them before they can hit. Hits: each projectile
## (slot order) repeatedly hits the nearest live overlapping enemy not in its ledger, once
## per enemy, until its pierce is used up; an enemy at 0 HP is out of every later check.


static func cast(config: SimConfig, world: WorldState) -> void:
	world.skill_acc += SimConfig.RATE_ONE
	if world.skill_acc < config.skill_period_mt:
		return
	var target: int = _nearest_in_range(config, world)
	var slot: int = world.proj_damage.find(0)
	if target < 0 or (slot < 0 and world.projectile_slots() >= config.max_projectiles):
		world.skill_acc -= SimConfig.RATE_ONE
		return
	if slot < 0:
		slot = world.projectile_slots()
		_append_projectile_slot(world)
	world.skill_acc -= config.skill_period_mt
	var direction: PackedInt64Array = Fx.normalize_q14(
		world.enemy_x[target] - world.player_x, world.enemy_y[target] - world.player_y
	)
	if direction[0] == 0 and direction[1] == 0:
		direction = PackedInt64Array([Fx.Q14, 0])
	world.proj_x[slot] = world.player_x
	world.proj_y[slot] = world.player_y
	world.proj_vx[slot] = Fx.mul_q14(config.projectile_speed_su, direction[0])
	world.proj_vy[slot] = Fx.mul_q14(config.projectile_speed_su, direction[1])
	world.proj_ttl[slot] = config.projectile_ttl_ticks
	world.proj_pierce_left[slot] = config.projectile_pierce
	world.proj_damage[slot] = maxi(1, config.skill_damage_mhp)


## Steps every live projectile and resolves its hits (phases 6 and 7a; enemies do not move
## in between, so stepping and hitting slot by slot equals two separate passes).
static func fly_and_hit(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var x: int = world.proj_x[slot] + world.proj_vx[slot]
		var y: int = world.proj_y[slot] + world.proj_vy[slot]
		world.proj_ttl[slot] -= 1
		if x < config.arena_min_x or x > config.arena_max_x or y < config.arena_min_y or y > config.arena_max_y:
			_free_projectile(world, slot)
			continue
		world.proj_x[slot] = x
		world.proj_y[slot] = y
		_resolve_hits(config, world, slot)


## Death phase, projectiles: the ones whose lifetime ran out are freed.
static func clear_expired(world: WorldState) -> void:
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] != 0 and world.proj_ttl[slot] <= 0:
			_free_projectile(world, slot)


static func _resolve_hits(config: SimConfig, world: WorldState, slot: int) -> void:
	var base: int = slot * world.ledger_stride
	while true:
		var best: int = -1
		var best_d2: int = 0
		for enemy: int in world.enemy_slots():
			if not world.is_enemy_live(enemy) or _in_ledger(world, base, world.enemy_uid[enemy]):
				continue
			var reach: int = config.projectile_radius_su + config.kind_value(world.enemy_kind[enemy], SimConfig.KIND_RADIUS)
			var d2: int = EnemySystem.dist2(world.enemy_x[enemy], world.enemy_y[enemy], world.proj_x[slot], world.proj_y[slot])
			if d2 <= reach * reach and (best < 0 or d2 < best_d2):
				best = enemy
				best_d2 = d2
		if best < 0:
			return
		world.enemy_hp[best] = maxi(0, world.enemy_hp[best] - world.proj_damage[slot])
		world.proj_ledger[base + config.projectile_pierce - world.proj_pierce_left[slot]] = world.enemy_uid[best]
		if world.proj_pierce_left[slot] == 0:
			_free_projectile(world, slot)
			return
		world.proj_pierce_left[slot] -= 1


static func _nearest_in_range(config: SimConfig, world: WorldState) -> int:
	var best: int = -1
	var best_d2: int = 0
	var range2: int = config.skill_range_su * config.skill_range_su
	for enemy: int in world.enemy_slots():
		if not world.is_enemy_live(enemy):
			continue
		var d2: int = EnemySystem.dist2(world.enemy_x[enemy], world.enemy_y[enemy], world.player_x, world.player_y)
		if d2 <= range2 and (best < 0 or d2 < best_d2):
			best = enemy
			best_d2 = d2
	return best


static func _in_ledger(world: WorldState, base: int, uid: int) -> bool:
	for cell: int in world.ledger_stride:
		if world.proj_ledger[base + cell] == uid:
			return true
	return false


static func _append_projectile_slot(world: WorldState) -> void:
	world.proj_x.append(0)
	world.proj_y.append(0)
	world.proj_vx.append(0)
	world.proj_vy.append(0)
	world.proj_ttl.append(0)
	world.proj_pierce_left.append(0)
	world.proj_damage.append(0)
	for _cell: int in world.ledger_stride:
		world.proj_ledger.append(0)


static func _free_projectile(world: WorldState, slot: int) -> void:
	world.proj_x[slot] = 0
	world.proj_y[slot] = 0
	world.proj_vx[slot] = 0
	world.proj_vy[slot] = 0
	world.proj_ttl[slot] = 0
	world.proj_pierce_left[slot] = 0
	world.proj_damage[slot] = 0
	for cell: int in world.ledger_stride:
		world.proj_ledger[slot * world.ledger_stride + cell] = 0
