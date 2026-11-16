class_name SeparationSystem
extends RefCounted
## Enemy chase with separation (ADR-009 section 2, ADR-008 two-phase rule). Exact port of
## tools/content/sim_core.py.
##
## 1. Chase writes tentative positions (tx, ty) without clamping; an enemy touching the hero
##    stays where it is. In an arena the chase heads for ArenaTopology.chase_target (the hero,
##    or the next cell of the flow field around walls, ADR-015 A1). An enemy in an attack
##    (state other than approach, ADR-011 section 2) neither moves nor takes part in the
##    separation. A projectile kind within its keep
##    distance does not chase (it is still pushed apart, ADR-011 section 3).
## 2. A uniform grid (cell = 2 x the largest kind radius, index clamped to the grid) is built
##    from the positions of tick N: only the occupied cells, as keys cell x KEY_SPAN + slot
##    sorted (cell order, then slot order).
## 3. Pairs are visited cell by cell, row-major: the cell itself (later items only), then the
##    neighbours (+1,0), (-1,+1), (0,+1), (+1,+1). An overlapping pair pushes both enemies apart
##    by half the overlap each; coincident centres push along x, the larger slot towards +x.
##    Positions are not changed during the pass.
## 4. At most SEP_MAX_CHECKS pair checks per tick, counted between cells (a started cell is
##    always finished); the next tick resumes from the cell where the pass stopped
##    (world.sep_cursor, 0 once a pass completes). Empty cells add no pairs and no checks, so
##    the pass visits only occupied cells: one that runs out of checks after cell i stops at
##    i + 1, where a scan of every cell would test the budget next (0 after the last cell).
## 5. Per slot: move = (tx - x, ty - y) + push, capped at the kind speed, then through the
##    arena walls and clamped into the arena (move_enemy). An enemy never moves further than
##    its speed in one tick; the hero is not pushed.

const SEP_MAX_CHECKS: int = 4096
## Sort key span per grid cell: above every slot index (MAX_ENEMIES_LIMIT).
const KEY_SPAN: int = 8192
## Neighbour cells visited after the cell itself: (dx, dy) pairs.
const NEIGHBOURS: Array[int] = [1, 0, -1, 1, 0, 1, 1, 1]


static func chase_and_separate(config: SimConfig, world: WorldState) -> void:
	var slots: int = world.enemy_slots()
	var tx: PackedInt64Array = world.enemy_x.duplicate()
	var ty: PackedInt64Array = world.enemy_y.duplicate()
	for slot: int in slots:
		if world.enemy_uid[slot] == 0 or world.enemy_state[slot] != EnemyAttackSystem.ST_APPROACH:
			continue
		if EnemySystem.touching(config, world, slot) or EnemyShotSystem.keeps_distance(config, world, slot):
			continue
		var goal_x: int = world.player_x
		var goal_y: int = world.player_y
		if config.arena != null:
			var goal: PackedInt64Array = config.arena.chase_target(
				world.enemy_x[slot], world.enemy_y[slot], goal_x, goal_y
			)
			goal_x = goal[0]
			goal_y = goal[1]
		var direction: PackedInt64Array = Fx.normalize_q14(goal_x - world.enemy_x[slot], goal_y - world.enemy_y[slot])
		var speed: int = config.kind_value(world.enemy_kind[slot], SimConfig.KIND_SPEED)
		tx[slot] += Fx.mul_q14(speed, direction[0])
		ty[slot] += Fx.mul_q14(speed, direction[1])
	var push_x: PackedInt64Array = PackedInt64Array()
	var push_y: PackedInt64Array = PackedInt64Array()
	push_x.resize(slots)
	push_y.resize(slots)
	push_x.fill(0)
	push_y.fill(0)
	_separate(config, world, push_x, push_y)
	for slot: int in slots:
		if world.enemy_uid[slot] == 0 or world.enemy_state[slot] != EnemyAttackSystem.ST_APPROACH:
			continue
		var kind: int = world.enemy_kind[slot]
		var speed: int = config.kind_value(kind, SimConfig.KIND_SPEED)
		var mx: int = tx[slot] - world.enemy_x[slot] + push_x[slot]
		var my: int = ty[slot] - world.enemy_y[slot] + push_y[slot]
		if mx * mx + my * my > speed * speed:
			var unit: PackedInt64Array = Fx.normalize_q14(mx, my)
			mx = Fx.mul_q14(speed, unit[0])
			my = Fx.mul_q14(speed, unit[1])
		move_enemy(config, world, slot, mx, my)


## Moves the enemy in `slot` by (mx, my): through the arena walls (ADR-015 A1), then clamped
## into the arena rectangle inset by its radius.
static func move_enemy(config: SimConfig, world: WorldState, slot: int, mx: int, my: int) -> void:
	var r: int = config.kind_value(world.enemy_kind[slot], SimConfig.KIND_RADIUS)
	var x: int = world.enemy_x[slot] + mx
	var y: int = world.enemy_y[slot] + my
	if config.arena != null:
		var moved: PackedInt64Array = config.arena.move(world.enemy_x[slot], world.enemy_y[slot], mx, my)
		x = moved[0]
		y = moved[1]
	world.enemy_x[slot] = clampi(x, config.arena_min_x + r, config.arena_max_x - r)
	world.enemy_y[slot] = clampi(y, config.arena_min_y + r, config.arena_max_y - r)


static func cell_size(config: SimConfig) -> int:
	var largest: int = 0
	for kind: int in config.kind_count():
		largest = maxi(largest, config.kind_value(kind, SimConfig.KIND_RADIUS))
	return 2 * largest


static func _separate(
	config: SimConfig, world: WorldState, push_x: PackedInt64Array, push_y: PackedInt64Array
) -> void:
	var cell: int = cell_size(config)
	var cols: int = Fx.floor_div(config.arena_max_x - config.arena_min_x, cell) + 1
	var rows: int = Fx.floor_div(config.arena_max_y - config.arena_min_y, cell) + 1
	var cells: int = cols * rows
	var keys: PackedInt64Array = PackedInt64Array()
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0 or world.enemy_state[slot] != EnemyAttackSystem.ST_APPROACH:
			continue
		var cx: int = clampi(Fx.floor_div(world.enemy_x[slot] - config.arena_min_x, cell), 0, cols - 1)
		var cy: int = clampi(Fx.floor_div(world.enemy_y[slot] - config.arena_min_y, cell), 0, rows - 1)
		keys.append((cy * cols + cx) * KEY_SPAN + slot)
	keys.sort()
	# Items in cell order, then slot order, with their positions and radii side by side.
	var live: int = keys.size()
	var cell_items: PackedInt64Array = PackedInt64Array()
	var item_home: PackedInt64Array = PackedInt64Array()
	var item_x: PackedInt64Array = PackedInt64Array()
	var item_y: PackedInt64Array = PackedInt64Array()
	var item_r: PackedInt64Array = PackedInt64Array()
	cell_items.resize(live)
	item_home.resize(live)
	item_x.resize(live)
	item_y.resize(live)
	item_r.resize(live)
	for at: int in live:
		var home: int = Fx.floor_div(keys[at], KEY_SPAN)
		var slot: int = keys[at] - home * KEY_SPAN
		cell_items[at] = slot
		item_home[at] = home
		item_x[at] = world.enemy_x[slot]
		item_y[at] = world.enemy_y[slot]
		item_r[at] = config.kind_value(world.enemy_kind[slot], SimConfig.KIND_RADIUS)
	var checks: int = 0
	var start: int = world.sep_cursor if world.sep_cursor < cells else 0
	var first: int = keys.bsearch(start * KEY_SPAN)
	var near_first: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	var near_last: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	while first < live:
		var index: int = item_home[first]
		var last: int = keys.bsearch((index + 1) * KEY_SPAN)
		var cy: int = Fx.floor_div(index, cols)
		var cx: int = index - cy * cols
		var near_count: int = 0
		for n: int in 4:
			var nx: int = cx + NEIGHBOURS[2 * n]
			var ny: int = cy + NEIGHBOURS[2 * n + 1]
			near_first[n] = 0
			near_last[n] = 0
			if nx < 0 or nx >= cols or ny >= rows:
				continue
			var other: int = ny * cols + nx
			near_first[n] = keys.bsearch(other * KEY_SPAN)
			near_last[n] = keys.bsearch((other + 1) * KEY_SPAN)
			near_count += near_last[n] - near_first[n]
		for a: int in range(first, last):
			var xi: int = item_x[a]
			var yi: int = item_y[a]
			var ri: int = item_r[a]
			checks += last - a - 1 + near_count
			for b: int in range(a + 1, last):
				var dx: int = xi - item_x[b]
				var dy: int = yi - item_y[b]
				var reach: int = ri + item_r[b]
				if dx * dx + dy * dy < reach * reach:
					_push(cell_items[a], cell_items[b], dx, dy, reach, push_x, push_y)
			for n: int in 4:
				for b: int in range(near_first[n], near_last[n]):
					var dx: int = xi - item_x[b]
					var dy: int = yi - item_y[b]
					var reach: int = ri + item_r[b]
					if dx * dx + dy * dy < reach * reach:
						_push(cell_items[a], cell_items[b], dx, dy, reach, push_x, push_y)
		if checks >= SEP_MAX_CHECKS:
			world.sep_cursor = index + 1 if index + 1 < cells else 0
			return
		first = last
	world.sep_cursor = 0


## Overlapping pair (i, j) with dx = x_i - x_j: each is pushed apart by half the overlap.
static func _push(
	i: int, j: int, dx: int, dy: int, reach: int, push_x: PackedInt64Array, push_y: PackedInt64Array
) -> void:
	var d2: int = dx * dx + dy * dy
	if d2 == 0:
		var h: int = reach >> 1
		push_x[maxi(i, j)] += h
		push_x[mini(i, j)] -= h
		return
	var d: int = Fx.isqrt(d2)
	var half: int = (reach - d) >> 1
	var hx: int = signi(dx) * Fx.floor_div(absi(dx) * half, d)
	var hy: int = signi(dy) * Fx.floor_div(absi(dy) * half, d)
	push_x[i] += hx
	push_y[i] += hy
	push_x[j] -= hx
	push_y[j] -= hy
