class_name SeparationSystem
extends RefCounted
## Enemy chase with separation (ADR-009 section 2, ADR-008 two-phase rule). Exact port of
## tools/content/sim_core.py.
##
## 1. Chase writes tentative positions (tx, ty) without clamping; an enemy touching the hero
##    stays where it is.
## 2. A uniform grid (cell = 2 x the largest kind radius, index clamped to the grid) is built
##    from the positions of tick N by counting sort over slots (cell_start, cell_items).
## 3. Pairs are visited cell by cell, row-major: the cell itself (later items only), then the
##    neighbours (+1,0), (-1,+1), (0,+1), (+1,+1). An overlapping pair pushes both enemies apart
##    by half the overlap each; coincident centres push along x, the larger slot towards +x.
##    Positions are not changed during the pass.
## 4. At most SEP_MAX_CHECKS pair checks per tick, counted between cells (a started cell is
##    always finished); the next tick resumes from the cell where the pass stopped
##    (world.sep_cursor, 0 once a pass completes).
## 5. Per slot: move = (tx - x, ty - y) + push, capped at the kind speed, then clamped into
##    the arena. An enemy never moves further than its speed in one tick; the hero is not
##    pushed.

const SEP_MAX_CHECKS: int = 4096
## Neighbour cells visited after the cell itself: (dx, dy) pairs.
const NEIGHBOURS: Array[int] = [1, 0, -1, 1, 0, 1, 1, 1]


static func chase_and_separate(config: SimConfig, world: WorldState) -> void:
	var slots: int = world.enemy_slots()
	var tx: PackedInt64Array = world.enemy_x.duplicate()
	var ty: PackedInt64Array = world.enemy_y.duplicate()
	for slot: int in slots:
		if world.enemy_uid[slot] == 0 or EnemySystem.touching(config, world, slot):
			continue
		var direction: PackedInt64Array = Fx.normalize_q14(
			world.player_x - world.enemy_x[slot], world.player_y - world.enemy_y[slot]
		)
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
		if world.enemy_uid[slot] == 0:
			continue
		var kind: int = world.enemy_kind[slot]
		var speed: int = config.kind_value(kind, SimConfig.KIND_SPEED)
		var mx: int = tx[slot] - world.enemy_x[slot] + push_x[slot]
		var my: int = ty[slot] - world.enemy_y[slot] + push_y[slot]
		if mx * mx + my * my > speed * speed:
			var unit: PackedInt64Array = Fx.normalize_q14(mx, my)
			mx = Fx.mul_q14(speed, unit[0])
			my = Fx.mul_q14(speed, unit[1])
		var r: int = config.kind_value(kind, SimConfig.KIND_RADIUS)
		world.enemy_x[slot] = clampi(world.enemy_x[slot] + mx, config.arena_min_x + r, config.arena_max_x - r)
		world.enemy_y[slot] = clampi(world.enemy_y[slot] + my, config.arena_min_y + r, config.arena_max_y - r)


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
	var home: PackedInt64Array = PackedInt64Array()
	home.resize(world.enemy_slots())
	var cell_start: PackedInt64Array = PackedInt64Array()
	cell_start.resize(cells + 1)
	cell_start.fill(0)
	var live: int = 0
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0:
			continue
		var cx: int = clampi(Fx.floor_div(world.enemy_x[slot] - config.arena_min_x, cell), 0, cols - 1)
		var cy: int = clampi(Fx.floor_div(world.enemy_y[slot] - config.arena_min_y, cell), 0, rows - 1)
		home[slot] = cy * cols + cx
		cell_start[home[slot] + 1] += 1
		live += 1
	for index: int in cells:
		cell_start[index + 1] += cell_start[index]
	# Items in cell order with their positions and radii side by side (structure of arrays).
	var cell_items: PackedInt64Array = PackedInt64Array()
	var item_x: PackedInt64Array = PackedInt64Array()
	var item_y: PackedInt64Array = PackedInt64Array()
	var item_r: PackedInt64Array = PackedInt64Array()
	cell_items.resize(live)
	item_x.resize(live)
	item_y.resize(live)
	item_r.resize(live)
	var fill: PackedInt64Array = cell_start.slice(0, cells)
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0:
			continue
		var at: int = fill[home[slot]]
		cell_items[at] = slot
		item_x[at] = world.enemy_x[slot]
		item_y[at] = world.enemy_y[slot]
		item_r[at] = config.kind_value(world.enemy_kind[slot], SimConfig.KIND_RADIUS)
		fill[home[slot]] = at + 1
	var checks: int = 0
	var index: int = world.sep_cursor if world.sep_cursor < cells else 0
	while index < cells:
		if checks >= SEP_MAX_CHECKS:
			world.sep_cursor = index
			return
		var cy: int = Fx.floor_div(index, cols)
		var cx: int = index - cy * cols
		var first: int = cell_start[index]
		var last: int = cell_start[index + 1]
		for a: int in range(first, last):
			var xi: int = item_x[a]
			var yi: int = item_y[a]
			var ri: int = item_r[a]
			checks += last - a - 1
			for b: int in range(a + 1, last):
				var dx: int = xi - item_x[b]
				var dy: int = yi - item_y[b]
				var reach: int = ri + item_r[b]
				if dx * dx + dy * dy < reach * reach:
					_push(cell_items[a], cell_items[b], dx, dy, reach, push_x, push_y)
			for n: int in 4:
				var nx: int = cx + NEIGHBOURS[2 * n]
				var ny: int = cy + NEIGHBOURS[2 * n + 1]
				if nx < 0 or nx >= cols or ny >= rows:
					continue
				var other: int = ny * cols + nx
				checks += cell_start[other + 1] - cell_start[other]
				for b: int in range(cell_start[other], cell_start[other + 1]):
					var dx: int = xi - item_x[b]
					var dy: int = yi - item_y[b]
					var reach: int = ri + item_r[b]
					if dx * dx + dy * dy < reach * reach:
						_push(cell_items[a], cell_items[b], dx, dy, reach, push_x, push_y)
		index += 1
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
