class_name EnemySystem
extends RefCounted
## Enemy phases of SimKernel (ADR-008, ADR-009). Exact port of tools/content/sim_core.py.
##
## Spawn: the accumulator gains `spawn_rate(tick)` per tick; once it reaches the period and
## fewer than `max_enemies` are alive, one enemy spawns into the lowest free slot (at the cap
## the tick does not advance the accumulator). The `enemy` stream draws the kind (by weight),
## then up to SPAWN_ATTEMPTS points on the arena perimeter (inset by the enemy radius) until
## one is at least `spawn_min_distance_su` from the hero; else the inset corner farthest from
## the hero (first in corner order on ties).
## Chase and separation: SeparationSystem.
## Contact: per live enemy in slot order the cooldown counts down; a touching enemy with a
## ready cooldown hits the hero and restarts it. Deaths: per dead enemy in slot order its XP
## gem drops (XpSystem.drop), then its slot is freed and the kill counted.

const SPAWN_ATTEMPTS: int = 4
const RNG_STREAM: String = "enemy"


static func spawn(config: SimConfig, world: WorldState) -> void:
	var rate: int = config.spawn_rate(world.tick)
	world.spawn_acc += rate
	if world.spawn_acc < config.spawn_period_mt:
		return
	if world.enemy_alive >= config.max_enemies:
		world.spawn_acc -= rate
		return
	world.spawn_acc -= config.spawn_period_mt
	var rng: HipRng = HipRng.create(config.run_seed, RNG_STREAM, str(world.enemy_rng_cursor))
	var kind: int = _pick_kind(config, rng.below(config.total_weight()))
	var r: int = config.kind_value(kind, SimConfig.KIND_RADIUS)
	var x0: int = config.arena_min_x + r
	var y0: int = config.arena_min_y + r
	var x1: int = config.arena_max_x - r
	var y1: int = config.arena_max_y - r
	var w: int = x1 - x0
	var h: int = y1 - y0
	var min_d2: int = config.spawn_min_distance_su * config.spawn_min_distance_su
	var found: bool = false
	var sx: int = x0
	var sy: int = y0
	for _attempt: int in SPAWN_ATTEMPTS:
		var p: int = rng.below(2 * (w + h))
		if p < w:
			sx = x0 + p
			sy = y0
		elif p < w + h:
			sx = x1
			sy = y0 + p - w
		elif p < 2 * w + h:
			sx = x1 - (p - w - h)
			sy = y1
		else:
			sx = x0
			sy = y1 - (p - 2 * w - h)
		if dist2(sx, sy, world.player_x, world.player_y) >= min_d2:
			found = true
			break
	if not found:
		var best: int = -1
		for corner: PackedInt64Array in [
			PackedInt64Array([x0, y0]), PackedInt64Array([x1, y0]),
			PackedInt64Array([x1, y1]), PackedInt64Array([x0, y1]),
		]:
			var d2: int = dist2(corner[0], corner[1], world.player_x, world.player_y)
			if d2 > best:
				best = d2
				sx = corner[0]
				sy = corner[1]
	world.enemy_rng_cursor = rng.cursor()
	var slot: int = world.enemy_uid.find(0)
	if slot < 0:
		slot = world.enemy_slots()
		world.enemy_uid.append(0)
		world.enemy_kind.append(0)
		world.enemy_x.append(0)
		world.enemy_y.append(0)
		world.enemy_hp.append(0)
		world.enemy_cooldown.append(0)
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_kind[slot] = kind
	world.enemy_x[slot] = sx
	world.enemy_y[slot] = sy
	world.enemy_hp[slot] = config.kind_value(kind, SimConfig.KIND_HP)
	world.enemy_cooldown[slot] = 0
	world.next_enemy_uid += 1
	world.enemy_alive += 1


static func contact(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.enemy_slots():
		if not world.is_enemy_live(slot):
			continue
		if world.enemy_cooldown[slot] > 0:
			world.enemy_cooldown[slot] -= 1
		if world.enemy_cooldown[slot] == 0 and touching(config, world, slot):
			var kind: int = world.enemy_kind[slot]
			world.hero_hp -= config.kind_value(kind, SimConfig.KIND_DAMAGE)
			world.enemy_cooldown[slot] = config.kind_value(kind, SimConfig.KIND_INTERVAL)


## Death phase, enemies: every occupied slot with HP 0 is freed (all fields 0), in slot order.
static func clear_dead(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0 or world.enemy_hp[slot] > 0:
			continue
		if config.has_xp() and config.kind_xp[world.enemy_kind[slot]] > 0:
			var value: int = config.kind_xp[world.enemy_kind[slot]]
			XpSystem.drop(config, world, world.enemy_x[slot], world.enemy_y[slot], value)
		world.enemy_uid[slot] = 0
		world.enemy_kind[slot] = 0
		world.enemy_x[slot] = 0
		world.enemy_y[slot] = 0
		world.enemy_hp[slot] = 0
		world.enemy_cooldown[slot] = 0
		world.enemy_alive -= 1
		world.kills += 1


static func touching(config: SimConfig, world: WorldState, slot: int) -> bool:
	var reach: int = config.player_radius_su + config.kind_value(world.enemy_kind[slot], SimConfig.KIND_RADIUS)
	return dist2(world.enemy_x[slot], world.enemy_y[slot], world.player_x, world.player_y) <= reach * reach


static func dist2(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = ax - bx
	var dy: int = ay - by
	return dx * dx + dy * dy


static func _pick_kind(config: SimConfig, roll: int) -> int:
	for kind: int in config.kind_count():
		roll -= config.kind_value(kind, SimConfig.KIND_WEIGHT)
		if roll < 0:
			return kind
	return config.kind_count() - 1
