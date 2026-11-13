class_name EnemySystem
extends RefCounted
## P0-01d enemy phases of SimKernel (ADR-008, integers only). Exact port of
## tools/content/sim_core.py.
##
## Spawn: one enemy per `spawn_period_ticks` while below `max_enemies`. The `enemy` stream
## draws the kind (by spawn weight), then up to SPAWN_ATTEMPTS points on the arena perimeter
## (inset by the enemy radius) until one is at least `spawn_min_distance_su` from the hero;
## if none is, the inset corner farthest from the hero is used (first in corner order on ties).
## Chase: each enemy steps toward the hero (Q14 unit vector x speed) unless already touching.
## Contact: per enemy in slot order, the cooldown counts down; a touching enemy with a ready
## cooldown hits the hero for its contact damage and restarts the cooldown.

const SPAWN_ATTEMPTS: int = 4
const RNG_STREAM: String = "enemy"


static func spawn(config: SimConfig, world: WorldState) -> void:
	if world.tick < world.next_spawn_tick or world.enemy_count() >= config.max_enemies:
		return
	world.next_spawn_tick = world.tick + config.spawn_period_ticks
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
		if _dist2(sx, sy, world.player_x, world.player_y) >= min_d2:
			found = true
			break
	if not found:
		var best: int = -1
		for corner: PackedInt64Array in [
			PackedInt64Array([x0, y0]), PackedInt64Array([x1, y0]),
			PackedInt64Array([x1, y1]), PackedInt64Array([x0, y1]),
		]:
			var d2: int = _dist2(corner[0], corner[1], world.player_x, world.player_y)
			if d2 > best:
				best = d2
				sx = corner[0]
				sy = corner[1]
	world.enemy_rng_cursor = rng.cursor()
	world.enemy_kind.append(kind)
	world.enemy_x.append(sx)
	world.enemy_y.append(sy)
	world.enemy_hp.append(config.kind_value(kind, SimConfig.KIND_HP))
	world.enemy_cooldown.append(0)


static func chase(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.enemy_count():
		var kind: int = world.enemy_kind[slot]
		var r: int = config.kind_value(kind, SimConfig.KIND_RADIUS)
		var ex: int = world.enemy_x[slot]
		var ey: int = world.enemy_y[slot]
		if _touching(config, world, slot):
			continue
		var direction: PackedInt64Array = Fx.normalize_q14(world.player_x - ex, world.player_y - ey)
		var speed: int = config.kind_value(kind, SimConfig.KIND_SPEED)
		ex += Fx.mul_q14(speed, direction[0])
		ey += Fx.mul_q14(speed, direction[1])
		world.enemy_x[slot] = clampi(ex, config.arena_min_x + r, config.arena_max_x - r)
		world.enemy_y[slot] = clampi(ey, config.arena_min_y + r, config.arena_max_y - r)


static func contact(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.enemy_count():
		if world.enemy_cooldown[slot] > 0:
			world.enemy_cooldown[slot] -= 1
		if world.enemy_cooldown[slot] == 0 and _touching(config, world, slot):
			var kind: int = world.enemy_kind[slot]
			world.hero_hp -= config.kind_value(kind, SimConfig.KIND_DAMAGE)
			world.enemy_cooldown[slot] = config.kind_value(kind, SimConfig.KIND_INTERVAL)


static func _touching(config: SimConfig, world: WorldState, slot: int) -> bool:
	var reach: int = config.player_radius_su + config.kind_value(world.enemy_kind[slot], SimConfig.KIND_RADIUS)
	return _dist2(world.enemy_x[slot], world.enemy_y[slot], world.player_x, world.player_y) <= reach * reach


static func _pick_kind(config: SimConfig, roll: int) -> int:
	for kind: int in config.kind_count():
		roll -= config.kind_value(kind, SimConfig.KIND_WEIGHT)
		if roll < 0:
			return kind
	return config.kind_count() - 1


static func _dist2(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = ax - bx
	var dy: int = ay - by
	return dx * dx + dy * dy
