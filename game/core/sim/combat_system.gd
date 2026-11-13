class_name CombatSystem
extends RefCounted
## Hero skill phases of SimKernel (ADR-009 section 1, `skill.spirit_sword` damage part).
## Exact port of tools/content/sim_core.py.
##
## Cast (ADR-010 section 6): the cooldown accumulator gains the skill rate (1000 + haste)
## per tick; when it reaches the period, one projectile is fired at each of up to `count`
## distinct live enemies within range, nearest first (min distance^2, then lower slot), and
## the period is subtracted. With no target, or fewer free projectile slots than projectiles
## to fire, the whole cast is held: the tick does not advance the accumulator, no charges are
## stored, and the next cast after a hold comes exactly one period after it. A projectile
## keeps the damage and capacity (pierce + 1) of its cast. Projectiles fly in the direction
## locked at cast; leaving the arena removes them before they can hit. Hits: each projectile
## (slot order) repeatedly hits the nearest live overlapping enemy not in its own ledger,
## once per enemy, until it has used its capacity; an enemy at 0 HP is out of every later
## check.


static func cast(config: SimConfig, world: WorldState) -> void:
	var rate: int = UpgradeSystem.skill_rate(world)
	world.skill_acc += rate
	if world.skill_acc < config.skill_period_mt:
		return
	var targets: PackedInt64Array = _targets_in_range(config, world, UpgradeSystem.projectile_count(world))
	var room: int = world.proj_damage.count(0) + config.max_projectiles - world.projectile_slots()
	if targets.is_empty() or room < targets.size():
		world.skill_acc -= rate
		return
	world.skill_acc -= config.skill_period_mt
	var damage: int = UpgradeSystem.skill_damage(config, world)
	var capacity: int = UpgradeSystem.projectile_pierce(config, world) + 1
	for target: int in targets:
		var slot: int = world.proj_damage.find(0)
		if slot < 0:
			slot = world.projectile_slots()
			_append_projectile_slot(world)
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
		world.proj_damage[slot] = damage
		world.proj_hits[slot] = 0
		world.proj_capacity[slot] = capacity


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
		world.proj_ledger[base + world.proj_hits[slot]] = world.enemy_uid[best]
		world.proj_hits[slot] += 1
		if world.proj_hits[slot] >= world.proj_capacity[slot]:
			_free_projectile(world, slot)
			return


## Up to `count` distinct live enemies within the skill range, nearest first (distance^2,
## then the lower slot): a stable insertion into a list kept sorted by (d2, slot).
static func _targets_in_range(config: SimConfig, world: WorldState, count: int) -> PackedInt64Array:
	var slots: PackedInt64Array = PackedInt64Array()
	var dists: PackedInt64Array = PackedInt64Array()
	var range2: int = config.skill_range_su * config.skill_range_su
	for enemy: int in world.enemy_slots():
		if not world.is_enemy_live(enemy):
			continue
		var d2: int = EnemySystem.dist2(world.enemy_x[enemy], world.enemy_y[enemy], world.player_x, world.player_y)
		if d2 > range2:
			continue
		var at: int = dists.size()
		while at > 0 and dists[at - 1] > d2:
			at -= 1
		if at >= count:
			continue
		dists.insert(at, d2)
		slots.insert(at, enemy)
		if dists.size() > count:
			dists.resize(count)
			slots.resize(count)
	return slots


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
	world.proj_damage.append(0)
	world.proj_hits.append(0)
	world.proj_capacity.append(0)
	for _cell: int in world.ledger_stride:
		world.proj_ledger.append(0)


static func _free_projectile(world: WorldState, slot: int) -> void:
	world.proj_x[slot] = 0
	world.proj_y[slot] = 0
	world.proj_vx[slot] = 0
	world.proj_vy[slot] = 0
	world.proj_ttl[slot] = 0
	world.proj_damage[slot] = 0
	world.proj_hits[slot] = 0
	world.proj_capacity[slot] = 0
	for cell: int in world.ledger_stride:
		world.proj_ledger[slot * world.ledger_stride + cell] = 0
