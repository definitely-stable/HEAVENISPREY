class_name JadeGroveTerrain
extends RefCounted
## Render elevation in screen pixels. Simulation coordinates remain on the arena grid.
## The regions use (x - y, x + y) relative to the seal cell, as in arena_layout.py.

const PLATEAUS: Array[Rect2i] = [
	Rect2i(-8, -42, 31, 13), Rect2i(-48, -26, 17, 13),
	Rect2i(33, 10, 16, 15), Rect2i(-20, 30, 23, 13),
]
const FLIGHTS: Array[Rect2i] = [
	Rect2i(2, -32, 11, 6), Rect2i(-37, -24, 8, 8),
	Rect2i(30, 13, 8, 8), Rect2i(-14, 27, 11, 7),
]
const LEVELS: Array[float] = [30.0, 24.0, 24.0, -28.0]
const VOID: int = 255
const SURFACE_MASK_SCALE: float = 0.5
## Terrace code is 1 through 4. Flight faces are clipped in projected grid axes.

var surface_mask: ImageTexture
var surface_bounds: Rect2
var _cell_px: float
var _size: Vector2i
var _origin: Vector2
var _tiles: PackedByteArray


func _init(data: Dictionary, cell_px: int) -> void:
	_cell_px = float(cell_px)
	var rows: Array = data["rows"]
	_size = Vector2i((rows[0] as String).length(), rows.size())
	var centre: Array = data["centre"]
	var seal: Vector2i = Vector2i(centre[0], centre[1])
	_origin = Vector2(seal) + Vector2(0.5, 0.5)
	_tiles.resize(_size.x * _size.y)
	for y: int in _size.y:
		for x: int in _size.x:
			var delta: Vector2i = Vector2i(x, y) - seal
			var uv: Vector2i = Vector2i(delta.x - delta.y, delta.x + delta.y)
			var tile: String = rows[y][x]
			if tile == " ":
				_tiles[y * _size.x + x] = VOID
				continue
			for index: int in PLATEAUS.size():
				if PLATEAUS[index].has_point(uv):
					_tiles[y * _size.x + x] = index + 1
					break


func height_at(at: Vector2) -> float:
	var cell: Vector2i = Vector2i((at / _cell_px).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
		return 0.0
	var code: int = _tiles[cell.y * _size.x + cell.x]
	if code == VOID:
		return 0.0
	var uv: Vector2 = _layout_point(at)
	var index: int = _flight_index(uv)
	if index >= 0:
		var flight: Rect2i = FLIGHTS[index]
		var axis: int = _flight_axis(index)
		var width: float = flight.size[axis]
		var step: float = floorf(uv[axis]) - flight.position[axis] + 1.0
		if index < 2:
			step = width - step
		return LEVELS[index] * clampf(step / width, 0.0, 1.0)
	return LEVELS[code - 1] if code > 0 else 0.0


func _layout_point(at: Vector2) -> Vector2:
	var delta: Vector2 = at / _cell_px - _origin
	return Vector2(delta.x - delta.y, delta.x + delta.y)


static func _flight_index(uv: Vector2) -> int:
	for index: int in FLIGHTS.size():
		if Rect2(FLIGHTS[index]).has_point(uv):
			return index
	return -1


static func _flight_axis(index: int) -> int:
	return 1 if index == 0 or index == 3 else 0


func project(at: Vector2) -> Vector2:
	return IsoProjection.to_screen(at) - Vector2(0.0, height_at(at))


## A concave bevel extends into an empty cell. Its height comes from the adjacent paving.
func rim_height(at: Vector2) -> float:
	for offset: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var sample: Vector2 = at + offset * 0.05
		var cell: Vector2i = Vector2i((sample / _cell_px).floor())
		if Rect2i(Vector2i.ZERO, _size).has_point(cell) and _tiles[cell.y * _size.x + cell.x] != VOID:
			return height_at(sample)
	return 0.0


## Both ends of a cliff segment share the elevation of the inside of that edge.
func rim_edge_height(a: Vector2, b: Vector2) -> float:
	var middle: Vector2 = (a + b) * 0.5
	var normal: Vector2 = (b - a).normalized().orthogonal() * 0.05
	for point: Vector2 in [middle + normal, middle - normal]:
		var cell: Vector2i = Vector2i((point / _cell_px).floor())
		if Rect2i(Vector2i.ZERO, _size).has_point(cell) and _tiles[cell.y * _size.x + cell.x] != VOID:
			return height_at(point)
	return 0.0


## Each cell is four triangles split along the two screen axes. This puts treads on the flight
## axis instead of alternating the diamonds of the pathfinding grid.
func build_paving(
	data: Dictionary, texels_per_px: float, bevels: Array[PackedVector2Array] = []
) -> Polygon2D:
	var rows: Array = data["rows"]
	var edges: Dictionary[Vector4i, Vector2] = {}
	var faces: Array[Dictionary] = []
	for y: int in _size.y:
		for x: int in _size.x:
			if rows[y][x] == " ":
				continue
			var corner: Vector2i = Vector2i(x, y) * 2
			var corners: Array[Vector2i] = [
				corner, corner + Vector2i(2, 0), corner + Vector2i(2, 2), corner + Vector2i(0, 2),
			]
			var middle: Vector2i = corner + Vector2i.ONE
			for side: int in 4:
				var a: Vector2i = corners[side]
				var b: Vector2i = corners[(side + 1) % 4]
				var depth: float = (a.x + a.y + b.x + b.y + middle.x + middle.y) / 3.0
				var points: PackedVector2Array = PackedVector2Array([
					Vector2(a) * _cell_px * 0.5, Vector2(b) * _cell_px * 0.5,
					Vector2(middle) * _cell_px * 0.5,
				])
				var level: float = height_at((points[0] + points[1] + points[2]) / 3.0)
				_append_face(faces, points, PackedFloat32Array([level, level, level]), depth, 1.0)
				_join_edge(faces, edges, a, b, level, depth)
				_join_edge(faces, edges, b, middle, level, depth)
				_join_edge(faces, edges, middle, a, level, depth)
	for bevel: PackedVector2Array in bevels:
		var tip: Vector2 = (bevel[1] + bevel[2]) * 0.5
		for side: int in [1, 2]:
			var level: float = rim_edge_height(bevel[0], bevel[side])
			var depth: float = IsoProjection.depth((bevel[0] + bevel[side] + tip) / 3.0) * 2.0 / _cell_px
			var half: PackedVector2Array = PackedVector2Array([bevel[0], bevel[side], tip])
			_append_face(faces, half, PackedFloat32Array([level, level, level]), depth, 1.0)
	faces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])
	var vertices: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var parts: Array[PackedInt32Array] = []
	for face: Dictionary in faces:
		var polygon: PackedVector2Array = face["points"]
		var heights: PackedFloat32Array = face["levels"]
		var part: PackedInt32Array = PackedInt32Array()
		var uv_centre: Vector2 = _layout_point((polygon[0] + polygon[1] + polygon[2]) / 3.0)
		var flight: int = _flight_index(uv_centre) if polygon.size() == 3 and heights[0] != 0.0 else -1
		for index: int in polygon.size():
			part.append(vertices.size())
			vertices.append(polygon[index] - Vector2.ONE * heights[index] / IsoProjection.K)
			# The riser shares the texture scale of the treads, continuing down the exposed face.
			var sample: Vector2 = polygon[index]
			if face["shade"] < 1.0:
				sample += Vector2.ONE * (heights[0] - heights[index]) / IsoProjection.K
			uvs.append(sample * texels_per_px)
			var shade: float = face["shade"]
			var tint: float = shade if index < 2 or shade == 1.0 else shade * 0.86
			var edge: float = 0.0
			if flight >= 0:
				var axis: int = _flight_axis(flight)
				var across: float = clampf(_layout_point(polygon[index])[axis] - floorf(uv_centre[axis]), 0.0, 1.0)
				edge = 1.0 - across if flight == 2 else across
			colors.append(Color(tint, edge, 0.0))
		parts.append(part)
	var paving: Polygon2D = Polygon2D.new()
	paving.polygon = vertices
	paving.uv = uvs
	paving.polygons = parts
	paving.vertex_colors = colors
	_build_surface_mask(paving, texels_per_px)
	return paving


## Rasterize the same projected pieces, in their paint order. Red stores the height in
## half pixels, green identifies an exposed stair face or a horizontal surface.
func _build_surface_mask(paving: Polygon2D, texels_per_px: float) -> void:
	var vertices: PackedVector2Array = paving.polygon
	var screen: PackedVector2Array = PackedVector2Array()
	var bounds: Rect2 = Rect2(IsoProjection.to_screen(vertices[0]), Vector2.ZERO)
	for point: Vector2 in vertices:
		var projected: Vector2 = IsoProjection.to_screen(point)
		bounds = bounds.expand(projected)
		screen.append(projected)
	var origin: Vector2 = bounds.position.floor()
	var size: Vector2i = Vector2i(((bounds.end - origin) * SURFACE_MASK_SCALE).ceil())
	surface_bounds = Rect2(origin, Vector2(size) / SURFACE_MASK_SCALE)
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RG8)
	var samples: PackedVector2Array = paving.uv
	var colors: PackedColorArray = paving.vertex_colors
	for part: PackedInt32Array in paving.polygons:
		var polygon: PackedVector2Array = PackedVector2Array()
		for index: int in part:
			polygon.append((screen[index] - origin) * SURFACE_MASK_SCALE)
		var first: int = part[0]
		var source: Vector2 = IsoProjection.to_screen(samples[first] / texels_per_px)
		var level: float = source.y - screen[first].y
		var riser: bool = colors[first].r < 1.0
		var gradient: Vector3 = Vector3.ZERO
		if riser:
			var end: Vector2 = IsoProjection.to_screen(samples[part[1]] / texels_per_px)
			var slope: float = (end.y - source.y) / (end.x - source.x)
			gradient = Vector3(slope, -1.0, (source.y - origin.y) + (origin.x - source.x) * slope)
		_rasterize_polygon(image, polygon, Color(_encode_lift(level), 0.5 if riser else 1.0, 0.0), gradient)
	surface_mask = ImageTexture.create_from_image(image)


static func _encode_lift(level: float) -> float:
	return roundf((level + 64.0) * 2.0) / 255.0


static func _rasterize_polygon(image: Image, points: PackedVector2Array, color: Color, gradient: Vector3) -> void:
	var top: float = INF
	var bottom: float = -INF
	for point: Vector2 in points:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	for row: int in range(ceili(top - 0.5), ceili(bottom - 0.5)):
		var y: float = float(row) + 0.5
		var left: float = INF
		var right: float = -INF
		for index: int in points.size():
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			if (a.y > y) != (b.y > y):
				var x: float = lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
				left = minf(left, x)
				right = maxf(right, x)
		if right > left:
			var start: int = ceili(left - 0.5)
			var end: int = ceili(right - 0.5)
			if end <= start:
				continue
			if gradient == Vector3.ZERO:
				image.fill_rect(Rect2i(start, row, end - start, 1), color)
				continue
			var lift: float = gradient.z + gradient.y * y / SURFACE_MASK_SCALE
			if gradient.x == 0.0:
				image.fill_rect(Rect2i(start, row, end - start, 1), Color(_encode_lift(lift), color.g, 0.0))
				continue
			for column: int in range(start, end):
				var sample: float = lift + (float(column) + 0.5) * gradient.x / SURFACE_MASK_SCALE
				image.set_pixel(column, row, Color(_encode_lift(sample), color.g, 0.0))


func _join_edge(
	faces: Array[Dictionary], edges: Dictionary[Vector4i, Vector2],
	a: Vector2i, b: Vector2i, level: float, depth: float
) -> void:
	var left: Vector2i = a
	var right: Vector2i = b
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		left = b
		right = a
	var key: Vector4i = Vector4i(left.x, left.y, right.x, right.y)
	if not edges.has(key):
		edges[key] = Vector2(level, depth)
		return
	var other: Vector2 = edges[key]
	edges.erase(key)
	if is_equal_approx(level, other.x) or a.x - a.y == b.x - b.y:
		return
	var farther: float = level if depth < other.y else other.x
	var nearer: float = other.x if depth < other.y else level
	if farther <= nearer:
		return
	var from: Vector2 = Vector2(left) * _cell_px * 0.5
	var to: Vector2 = Vector2(right) * _cell_px * 0.5
	_append_face(faces, PackedVector2Array([from, to, to, from]),
		PackedFloat32Array([farther, farther, nearer, nearer]), (depth + other.y) * 0.5, 0.76)


static func _append_face(
	faces: Array[Dictionary], points: PackedVector2Array, levels: PackedFloat32Array, depth: float, shade: float
) -> void:
	faces.append({"points": points, "levels": levels, "depth": depth, "shade": shade})
