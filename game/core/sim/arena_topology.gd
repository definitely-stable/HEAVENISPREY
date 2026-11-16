class_name ArenaTopology
extends RefCounted
## The arena of a stage (ADR-015 A1). Exact port of tools/content/sim_core.py (Arena).
##
## A grid of `width` x `height` cells of `cell` su from (0, 0), the arena rectangle of the
## config. Cell codes: WALK (floor), LOW (low wall: blocks bodies, not shots), SOLID (blocks
## bodies and shots; the void counts as solid). Cells outside the grid are solid; the border
## cells are never walkable.
## - Bodies collide with walls as squares of half-size `body` (smaller than any combat
##   radius, so a body passes a one-cell gap): move() goes along x first, then along y from
##   the new x, and on each axis stops flush against the first blocked cell its leading edge
##   would enter, so the body slides along the wall on the other axis.
## - The chase follows a flow field: breadth-first distances in cells from the hero's cell
##   over walkable cells, four neighbours (-1 where unreachable). It is a pure function of
##   the hero's cell, cached for the last cell asked; not part of the world state.
## - Enemies spawn at `spawns` (cell pairs, row-major order of the S cells).

const WALK: int = 0
const LOW: int = 1
const SOLID: int = 2
const WALK_CHARS: String = ".HB^SE"
const LOW_CHARS: String = "w"
const SPAWN_CHARS: String = "S"

var width: int = 0
var height: int = 0
var cell: int = 0
var body: int = 0
var codes: PackedByteArray = PackedByteArray()
## Spawn cells as (x, y) pairs.
var spawns: PackedInt64Array = PackedInt64Array()
var _field_start: int = -1
var _field: PackedInt32Array = PackedInt32Array()
var _queue: PackedInt32Array = PackedInt32Array()


static func create(
	p_width: int, p_height: int, p_cell: int, p_body: int, p_codes: PackedByteArray, p_spawns: PackedInt64Array
) -> ArenaTopology:
	var arena: ArenaTopology = ArenaTopology.new()
	arena.width = p_width
	arena.height = p_height
	arena.cell = p_cell
	arena.body = p_body
	arena.codes = p_codes
	arena.spawns = p_spawns
	return arena


## Rows of the arena file (tools/content/arena_layout.py legend); null on ragged rows.
static func from_rows(rows: PackedStringArray, p_cell: int, p_body: int) -> ArenaTopology:
	if rows.is_empty():
		return null
	var w: int = rows[0].length()
	var p_codes: PackedByteArray = PackedByteArray()
	var p_spawns: PackedInt64Array = PackedInt64Array()
	for y: int in rows.size():
		var row: String = rows[y]
		if row.length() != w:
			return null
		for x: int in w:
			var ch: String = row[x]
			if WALK_CHARS.contains(ch):
				p_codes.append(WALK)
			elif LOW_CHARS.contains(ch):
				p_codes.append(LOW)
			else:
				p_codes.append(SOLID)
			if SPAWN_CHARS.contains(ch):
				p_spawns.append(x)
				p_spawns.append(y)
	return create(w, rows.size(), p_cell, p_body, p_codes, p_spawns)


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([width, height, cell, body])
	for code: int in codes:
		out.append(code)
	out.append(spawn_count())
	out.append_array(spawns)
	return out


func spawn_count() -> int:
	return spawns.size() >> 1


## The grid is the arena rectangle of `config`, every code is known, the border is not
## walkable, the body passes a cell, the start and every spawn point stand on walkable cells.
func fits(config: SimConfig) -> bool:
	if not (width > 0 and height > 0 and cell > 0 and body > 0 and 2 * body <= cell):
		return false
	if codes.size() != width * height or spawns.is_empty() or spawns.size() & 1 == 1:
		return false
	if config.arena_min_x != 0 or config.arena_min_y != 0:
		return false
	if config.arena_max_x != width * cell or config.arena_max_y != height * cell:
		return false
	for code: int in codes:
		if code > SOLID:
			return false
	for x: int in width:
		if code(x, 0) == WALK or code(x, height - 1) == WALK:
			return false
	for y: int in height:
		if code(0, y) == WALK or code(width - 1, y) == WALK:
			return false
	if code_at(config.start_x, config.start_y) != WALK:
		return false
	for index: int in spawn_count():
		var x: int = spawns[2 * index]
		var y: int = spawns[2 * index + 1]
		if x < 0 or x >= width or y < 0 or y >= height or codes[y * width + x] != WALK:
			return false
	return true


func code(cx: int, cy: int) -> int:
	if cx >= 0 and cx < width and cy >= 0 and cy < height:
		return codes[cy * width + cx]
	return SOLID


func code_at(x: int, y: int) -> int:
	return code(Fx.floor_div(x, cell), Fx.floor_div(y, cell))


## The centre of spawn point `index` (su).
func spawn_point(index: int) -> PackedInt64Array:
	var half: int = cell >> 1
	return PackedInt64Array([spawns[2 * index] * cell + half, spawns[2 * index + 1] * cell + half])


## A body at (x, y) moved by (mx, my); returns the new (x, y).
func move(x: int, y: int, mx: int, my: int) -> PackedInt64Array:
	if mx != 0:
		var nx: int = x + mx
		var cy0: int = Fx.floor_div(y - body, cell)
		var cy1: int = Fx.floor_div(y + body - 1, cell)
		if mx > 0:
			for cx: int in range(Fx.floor_div(x + body - 1, cell) + 1, Fx.floor_div(nx + body - 1, cell) + 1):
				if _column_blocked(cx, cy0, cy1):
					nx = cx * cell - body
					break
		else:
			for cx: int in range(Fx.floor_div(x - body, cell) - 1, Fx.floor_div(nx - body, cell) - 1, -1):
				if _column_blocked(cx, cy0, cy1):
					nx = (cx + 1) * cell + body
					break
		x = nx
	if my != 0:
		var ny: int = y + my
		var cx0: int = Fx.floor_div(x - body, cell)
		var cx1: int = Fx.floor_div(x + body - 1, cell)
		if my > 0:
			for cy: int in range(Fx.floor_div(y + body - 1, cell) + 1, Fx.floor_div(ny + body - 1, cell) + 1):
				if _row_blocked(cy, cx0, cx1):
					ny = cy * cell - body
					break
		else:
			for cy: int in range(Fx.floor_div(y - body, cell) - 1, Fx.floor_div(ny - body, cell) - 1, -1):
				if _row_blocked(cy, cx0, cx1):
					ny = (cy + 1) * cell + body
					break
		y = ny
	return PackedInt64Array([x, y])


func _column_blocked(cx: int, cy0: int, cy1: int) -> bool:
	for cy: int in range(cy0, cy1 + 1):
		if code(cx, cy) != WALK:
			return true
	return false


func _row_blocked(cy: int, cx0: int, cx1: int) -> bool:
	for cx: int in range(cx0, cx1 + 1):
		if code(cx, cy) != WALK:
			return true
	return false


## Breadth-first distances (cells) to cell (cx, cy); -1 where unreachable or blocked. The
## border is never walkable, so the neighbours of a walkable cell are inside the grid.
func field(cx: int, cy: int) -> PackedInt32Array:
	var start: int = cy * width + cx
	if start == _field_start:
		return _field
	var size: int = width * height
	_field.resize(size)
	_field.fill(-1)
	_queue.resize(size)
	_field[start] = 0
	_queue[0] = start
	var head: int = 0
	var tail: int = 1
	var steps: PackedInt32Array = PackedInt32Array([1, -1, width, -width])
	while head < tail:
		var at: int = _queue[head]
		head += 1
		var d: int = _field[at] + 1
		for k: int in 4:
			var n: int = at + steps[k]
			if _field[n] < 0 and codes[n] == WALK:
				_field[n] = d
				_queue[tail] = n
				tail += 1
	_field_start = start
	return _field


## Where an enemy at (ex, ey) heads for the hero at (hx, hy): the hero itself when it shares
## the cell, is unreachable, or when the field descends towards it on each axis they are
## apart on and on no other; else the centre of the next cell of the field (x neighbour +1
## before -1, y the same; the diagonal one when both axes descend).
func chase_target(ex: int, ey: int, hx: int, hy: int) -> PackedInt64Array:
	var ecx: int = Fx.floor_div(ex, cell)
	var ecy: int = Fx.floor_div(ey, cell)
	var hcx: int = Fx.floor_div(hx, cell)
	var hcy: int = Fx.floor_div(hy, cell)
	var dist: PackedInt32Array = field(hcx, hcy)
	var e: int = ecy * width + ecx
	var d: int = dist[e]
	if d <= 0:
		return PackedInt64Array([hx, hy])
	var sx: int = 0
	var sy: int = 0
	if dist[e + 1] == d - 1:
		sx = 1
	elif dist[e - 1] == d - 1:
		sx = -1
	if dist[e + width] == d - 1:
		sy = 1
	elif dist[e - width] == d - 1:
		sy = -1
	if sx == signi(hcx - ecx) and sy == signi(hcy - ecy):
		return PackedInt64Array([hx, hy])
	var half: int = cell >> 1
	return PackedInt64Array([(ecx + sx) * cell + half, (ecy + sy) * cell + half])
