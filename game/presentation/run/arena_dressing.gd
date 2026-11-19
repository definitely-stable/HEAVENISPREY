class_name ArenaDressing
extends RefCounted
## ADR-014 slice A3, ADR-015 A1: the things that stand in arena 07 of stage.jade_grove
## (REF-033 "Руины секты Юнхэ", REF-029 kit, REF-056, REF-023). The arena file lists the named
## props on their solid cells (the gate hall, the guardian lions, the columns, the braziers
## that carry the point lights, the old maple). The six fragments of the ruin ring around the seal
## are painted props on their cells (ADR-015 section 11), drawn in strips that sort by depth. The
## other low wall cells are a balustrade after REF-029 (section 10): posts on the cells, red
## rails between them. Every other solid cell stands as a placeholder stone block until the rest
## of the wall kit of slice A2. Far behind, rock spires and pagodas stand in the mist (BACKDROP).
## Presentation only.

const NATURE_ASSET: String = "asset.prop.courtyard_nature"
const WALLS_ASSET: String = "asset.prop.courtyard_walls"
const PEAKS_ASSET: String = "asset.prop.distant_peaks"
## The seal ring and the parapet after REF-068 (ADR-015 section 12): a pedestal brazier on one
## cell, a stone pagoda lantern on one cell, a broken pillar on two by two cells.
const RING_ASSET: String = "asset.prop.courtyard_ring"
## Guardian lions and the columns of the ruined sect after REF-033 and REF-029: monumental,
## the lion on its plinth about 2.25 hero heights, a column about 2.6.
const GUARDIANS_ASSET: String = "asset.prop.courtyard_guardians"
## The balustrade after REF-029: a stone post with a gold cap (0.8 hero heights), the post broken
## and the front elevation of one rail bay (0.5 hero heights).
const BALUSTRADE_ASSET: String = "asset.prop.courtyard_balustrade"
## The prop name of a rail bay: a vertical plane between two posts, textured with "rail".
const RAIL_PROP: String = "rail_span"
const COPING_PROP: String = "wall_coping"
const COPING_HEIGHT: float = 23.0
const COPING_HALF_WIDTH: float = 9.0
## Directions of a straight balustrade run on the grid and the cells between its posts: along a
## grid axis the run climbs the screen at 2:1 and posts every second cell keep the rail readable;
## along a cell diagonal it runs flat across the screen or straight up it, where the thin stone
## cap replaces the edge-on rail. Long flat runs alternate one and two bays between posts.
const RUN_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1)]
const RUN_STEPS: Array[int] = [2, 2, 1, 2]
## Half the side of a post's square base (world px, 0.4 of a cell): rails stop at the post faces.
const POST_HALF_PX: float = 9.6
## The ruin ring around the seal (ADR-015 section 11): each "seal_ruin" of the arena file is the
## painted fragment "ruin_<n>" of RUINS_ASSET, n its place on the ring (arena_layout.py step 5:
## fragment n starts RING_START_DEG + n RING_STEP_DEG around the seal). It covers the low and
## solid cells of its fragment and is drawn in vertical strips, one per half cell of screen
## width, each sorted at the nearest cell of the fragment under it.
const RUINS_ASSET: String = "asset.prop.seal_ruins"
const RUIN_PROP: String = "seal_ruin"
const RING_START_DEG: float = 15.0
const RING_STEP_DEG: float = 60.0
## The contact shadow of a fragment: its cells grown around their centres by this factor.
const RUIN_CONTACT_GROW: float = 1.15
## Each named prop of the arena file: [atlas, sprite of the first of a pair, of the second].
const PROP_SPRITES: Dictionary = {
	"gate": [WALLS_ASSET, "gate", "gate"],
	"lion": [GUARDIANS_ASSET, "lion_ball", "lion_cub"],
	"pillar": [GUARDIANS_ASSET, "pillar", "pillar"],
	"pillar_broken": [RING_ASSET, "pillar_stump", "pillar_stump"],
	"brazier": [RING_ASSET, "brazier_pedestal", "brazier_pedestal"],
	"lantern": [RING_ASSET, "lantern_stone", "lantern_stone"],
	"maple_large": [NATURE_ASSET, "maple_large", "maple_large"],
}
## Props that carry a warm point light, and the height of their flame above the base (px).
const LIGHT_PROPS: Dictionary = {"lantern_stone": 0.64, "brazier_pedestal": 0.66, "gate": 0.55}
## The prop name of a placeholder wall block.
const BLOCK_PROP: String = "block"
## Arena cells of tall walls (solid) and low walls (balustrades, ruins).
const SOLID_CHAR: String = "#"
const LOW_CHAR: String = "w"
## A group of solid cells (four neighbours) with a cell within this many cells (on both axes)
## of a named prop belongs to that prop.
const PROP_REACH_CELLS: float = 1.5
## Screen height of the placeholder blocks (px) and their stone tones (top, lit side, far side).
const BLOCK_SOLID_PX: float = 46.0
const BLOCK_LOW_PX: float = 16.0
const BLOCK_TOP: Color = Color(0.34, 0.3, 0.37)
const BLOCK_SIDE_X: Color = Color(0.23, 0.2, 0.26)
const BLOCK_SIDE_Y: Color = Color(0.17, 0.15, 0.2)
## Distant scenery in the mist (REF-033, REF-056: rock spires and pagodas behind the arena):
## [prop, base (px from the arena centre in the backdrop plane), scale, flip, nearness 0..1].
const BACKDROP: Array = [
	["spire", Vector2(-860.0, -72.0), 0.49, true, 0.16],
	["waterfall_rock", Vector2(-706.0, -138.0), 0.44, false, 0.12],
	["pagoda_rock", Vector2(-570.0, 47.0), 0.58, true, 0.40],
	["spire", Vector2(-432.0, -103.0), 0.55, false, 0.22],
	["gate_rock", Vector2(-285.0, -206.0), 0.46, false, 0.12],
	["waterfall_rock", Vector2(-252.0, 370.0), 0.50, true, 0.36],
	["spire", Vector2(69.0, 403.0), 0.5, false, 0.25],
	["spire", Vector2(108.0, -218.0), 0.39, true, 0.11],
	["waterfall_rock", Vector2(266.0, -61.0), 0.54, false, 0.29],
	["pagoda_rock", Vector2(441.0, 393.0), 0.51, false, 0.32],
	["spire", Vector2(543.0, -52.0), 0.55, true, 0.22],
	["gate_rock", Vector2(653.0, -133.0), 0.45, true, 0.13],
	["waterfall_rock", Vector2(835.0, 119.0), 0.49, false, 0.25],
	["spire", Vector2(-1418.0, 235.0), 0.68, false, 0.58],
	["waterfall_rock", Vector2(-1215.0, 354.0), 0.77, true, 0.75],
	["gate_rock", Vector2(-984.0, 247.0), 0.65, true, 0.65],
	["spire", Vector2(-822.0, 418.0), 0.66, true, 0.76],
	["pagoda_rock", Vector2(-529.0, 521.0), 0.72, false, 0.61],
	["waterfall_rock", Vector2(-160.0, 596.0), 0.66, false, 0.68],
	["spire", Vector2(143.0, 534.0), 0.69, true, 0.60],
	["waterfall_rock", Vector2(509.0, 558.0), 0.71, true, 0.72],
	["spire", Vector2(735.0, 395.0), 0.64, false, 0.60],
	["pagoda_rock", Vector2(971.0, 391.0), 0.71, false, 0.71],
	["gate_rock", Vector2(1213.0, 281.0), 0.66, false, 0.58],
]


## Every placement: {asset, prop, at (world px), flip, light (bool), flame (screen px above the
## base)}; a placeholder block also carries its cell rectangle (world px) and screen height, a strip
## of a ruin its "base" (world px, where the whole prop stands and is lit), "clip" (screen x range)
## and, on the first strip, "footprint" (screen polygons of its contact shadow).
## The lions stand in pairs: the first with the ball, the second with the cub, mirrored to face
## the first.
static func placements(sprites: SpriteSet, data: Dictionary, cell_px: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var anchors: Array[Vector2] = []
	var ruin_at: Array[Vector2] = []
	var lions: int = 0
	for item: Dictionary in data.get("props", []):
		var prop: String = str(item.get("prop", ""))
		var at: Array = item.get("at", [0, 0])
		var cell: Vector2 = Vector2(float(at[0]), float(at[1]))
		anchors.append(cell)
		if prop == RUIN_PROP:
			ruin_at.append(cell)
		var second: bool = false
		if prop == "lion":
			second = lions % 2 == 1
			lions += 1
		if PROP_SPRITES.has(prop):
			var sprite: Array = PROP_SPRITES[prop]
			_add(out, sprites, sprite[0], sprite[2] if second else sprite[1], cell * cell_px, second)
	var rows: Array = data.get("rows", [])
	var propped: Dictionary = _propped(rows, anchors)
	var centre: Array = data.get("centre", [0, 0])
	for at: Vector2 in ruin_at:
		var index: int = ruin_index(at, Vector2i(int(centre[0]), int(centre[1])))
		if sprites.has_prop(RUINS_ASSET, "ruin_%d" % index):
			var cells: Array = ruin_cells(rows, at)
			for cell: Vector2i in cells:
				propped[cell] = true
			_add_ruin(out, "ruin_%d" % index, cells, at * cell_px, cell_px)
	var walls: bool = sprites.has_prop(BALUSTRADE_ASSET, "post") and sprites.has_prop(BALUSTRADE_ASSET, "rail")
	if walls:
		_add_balustrade(out, sprites, balustrade(rows, propped), cell_px)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if propped.has(Vector2i(x, y)):
				continue
			if (row[x] == LOW_CHAR and not walls) or row[x] == SOLID_CHAR:
				var rect: Rect2 = Rect2(Vector2(x, y) * cell_px, Vector2.ONE * cell_px)
				out.append({
					"asset": "", "prop": BLOCK_PROP, "at": rect.get_center(), "flip": false, "light": false,
					"flame": 0.0, "rect": rect, "height": BLOCK_LOW_PX if row[x] == LOW_CHAR else BLOCK_SOLID_PX,
				})
	return out


## The balustrade of the low wall cells of `rows` but those in `skip` (cells of the ruins):
## {"posts": cells, "broken": cells (dead ends of a line), "rails": [[cell, cell], ...] between
## neighbouring posts of a straight run, "edge_on": spans straight up the screen with a low
## stone course linking the bases}. Cells link to their neighbours
## along RUN_DIRS; a diagonal link is dropped where an axis link already joins the two cells
## through a corner cell, so a staircase on the grid is one run, not a zigzag.
static func balustrade(rows: Array, skip: Dictionary = {}) -> Dictionary:
	var lines: Dictionary = {}
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == LOW_CHAR and not skip.has(Vector2i(x, y)):
				lines[Vector2i(x, y)] = true
	var cells: Array = _sorted(lines.keys())
	var posts: Dictionary = {}
	var rails: Array = []
	var edge_on: Array = []
	var links: Dictionary = {}
	for index: int in RUN_DIRS.size():
		var dir: Vector2i = RUN_DIRS[index]
		for cell: Vector2i in cells:
			if not _linked(lines, cell, dir) or _linked(lines, cell - dir, dir):
				continue
			var run: Array[Vector2i] = [cell]
			while _linked(lines, run[-1], dir):
				run.append(run[-1] + dir)
			var last_post: int = 0
			for i: int in run.size():
				links[run[i]] = int(links.get(run[i], 0)) + (1 if i == 0 or i == run.size() - 1 else 2)
				if i % RUN_STEPS[index] != 0 and i != run.size() - 1:
					continue
				if dir == Vector2i(1, -1) and run.size() >= 7 and i % 3 == 2 and i != run.size() - 1 \
					and not _wall_junction(lines, run[i]):
					continue  # Combine two bays on long facades without a break in the rail.
				posts[run[i]] = true
				if i > 0:
					(edge_on if dir == Vector2i(1, 1) else rails).append([run[last_post], run[i]])
				last_post = i
	var broken: Array = []
	for cell: Vector2i in cells:
		if not links.has(cell):
			posts[cell] = true  # a lone post
		elif int(links[cell]) == 1:
			broken.append(cell)
	return {"posts": _sorted(posts.keys()), "broken": broken, "rails": rails, "edge_on": edge_on}


## Which fragment of the ruin ring a "seal_ruin" at `at` (cells) is: its turn around the seal.
static func ruin_index(at: Vector2, centre: Vector2i) -> int:
	var angle: float = rad_to_deg(atan2(at.y - centre.y - 0.5, at.x - centre.x - 0.5))
	return int(fposmod(angle - RING_START_DEG, 360.0) / RING_STEP_DEG)


## The wall cells ('w' and '#', eight neighbours) of the fragment nearest to `at` (cells), in row
## order: the cells its painted prop covers.
static func ruin_cells(rows: Array, at: Vector2) -> Array:
	var start: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] != LOW_CHAR and row[x] != SOLID_CHAR:
				continue
			var d: float = (Vector2(x, y) + Vector2(0.5, 0.5)).distance_squared_to(at)
			if d < best:
				best = d
				start = Vector2i(x, y)
	if start.x < 0:
		return []
	var seen: Dictionary = {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				var next: Vector2i = cell + Vector2i(dx, dy)
				if seen.has(next) or next.y < 0 or next.y >= rows.size() or next.x < 0:
					continue
				var row: String = rows[next.y]
				if next.x < row.length() and (row[next.x] == LOW_CHAR or row[next.x] == SOLID_CHAR):
					seen[next] = true
					todo.append(next)
	return _sorted(seen.keys())


## The screen strips of a fragment on `cells`: [{"clip": Vector2(from, to) screen x, "front": the
## nearest cell under it}], left to right. Strip m spans m to m + 1 half cells of screen width
## (cells with x - y = m or m + 1 lie under it); the outer strips reach to the ends of the sprite.
static func ruin_strips(cells: Array, cell_px: int) -> Array[Dictionary]:
	var half: float = IsoProjection.to_screen(Vector2(cell_px, 0.0)).x
	var front: Dictionary = {}
	for cell: Vector2i in cells:
		for m: int in [cell.x - cell.y - 1, cell.x - cell.y]:
			if not front.has(m) or _nearer(cell, front[m]):
				front[m] = cell
	var columns: Array = front.keys()
	columns.sort()
	var out: Array[Dictionary] = []
	for m: int in columns:
		var from: float = -INF if m == columns[0] else m * half
		var to: float = INF if m == columns[-1] else (m + 1) * half
		out.append({"clip": Vector2(from, to), "front": front[m]})
	return out


## Draws a rail bay on `canvas` (screen space): the "rail" elevation stretched on the vertical
## plane from `from` to `to` (world px, already stopped at the post faces), in whole bays.
static func draw_rail(canvas: CanvasItem, sprites: SpriteSet, item: Dictionary, light: Color) -> void:
	var quad: Dictionary = sprites.prop_quad(BALUSTRADE_ASSET, "rail", Vector2.ZERO)
	if quad.is_empty():
		return
	if item["prop"] == COPING_PROP:
		_draw_coping(canvas, quad, item, light)
		return
	var uv: Rect2 = quad["uv"]
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position,
	])
	var colors: PackedColorArray = PackedColorArray([light, light, light, light])
	for bay: PackedVector2Array in rail_quads(item, (quad["rect"] as Rect2).size):
		canvas.draw_polygon(bay, colors, uvs, quad["texture"])


## From this angle the rail face has zero width. Only the stone cap and its near end are visible.
static func _draw_coping(canvas: CanvasItem, quad: Dictionary, item: Dictionary, light: Color) -> void:
	var source: Rect2 = quad["uv"]
	var from: Vector2 = IsoProjection.to_screen(item["from"])
	var to: Vector2 = IsoProjection.to_screen(item["to"])
	var lift: Vector2 = Vector2(0.0, -COPING_HEIGHT)
	var left: Vector2 = Vector2(-COPING_HALF_WIDTH, 0.0)
	var right: Vector2 = -left
	var cap: PackedVector2Array = PackedVector2Array([from + left + lift, from + right + lift,
		to + right + lift, to + left + lift])
	var band: Rect2 = Rect2(source.position + Vector2(0.0, source.size.y * 0.83),
		Vector2(source.size.x, source.size.y * 0.13))
	var cap_uv: PackedVector2Array = PackedVector2Array([band.position,
		Vector2(band.position.x, band.end.y), band.end, Vector2(band.end.x, band.position.y)])
	canvas.draw_polygon(cap, PackedColorArray([light.lightened(0.11)]), cap_uv, quad["texture"])
	var end: PackedVector2Array = PackedVector2Array([cap[3], cap[2], to + right, to + left])
	canvas.draw_colored_polygon(end, Color(0.28, 0.25, 0.32) * light)


static func wall_light(light: Color) -> Color:
	return light.darkened(0.17 * (1.0 - smoothstep(0.91, 1.26, light.r)))


## Lay the silhouettes first; the white contacts keep their coverage near a lantern.
static func draw_shadows(canvas: Node2D, sprites: SpriteSet, props: Array[Dictionary], disc: Texture2D) -> void:
	for prop: Dictionary in props:
		if prop["prop"] == BLOCK_PROP or prop.has("rail_bounds") or prop.has("clip"):
			continue
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(prop["screen"]))
		var shadow: Color = Color(0.0, 0.0, 0.0, 0.72) if prop.get("wall", false) else Color.BLACK
		sprites.draw_prop(canvas, prop["asset"], prop["prop"], Vector2.ZERO, shadow, prop["flip"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	for prop: Dictionary in props:
		for polygon: PackedVector2Array in prop.get("footprint", []):
			canvas.draw_colored_polygon(polygon, Color.WHITE)
		if prop.get("wall", false) and not prop.has("rail_bounds"):
			RunLighting.contact(canvas, disc, prop["screen"], POST_HALF_PX * 1.55)


## The screen quads [base from, base to, top to, top from] of the bays of a rail: as many whole
## bays as fit the run at the elevation's own width (`bay`, screen px of a front view).
static func rail_quads(item: Dictionary, bay: Vector2) -> Array[PackedVector2Array]:
	var from: Vector2 = item["from"]
	var to: Vector2 = item["to"]
	var count: int = maxi(1, roundi(from.distance_to(to) / bay.x))
	var lift: Vector2 = Vector2(0.0, -bay.y)
	var out: Array[PackedVector2Array] = []
	for i: int in count:
		var a: Vector2 = IsoProjection.to_screen(from.lerp(to, float(i) / count))
		var b: Vector2 = IsoProjection.to_screen(from.lerp(to, float(i + 1) / count))
		out.append(PackedVector2Array([a, b, b + lift, a + lift]))
	return out


## Draws a placeholder block on `canvas` (screen space): its two near faces and its top.
static func draw_block(canvas: CanvasItem, item: Dictionary, light: Color) -> void:
	var rect: Rect2 = item["rect"]
	var lift: Vector2 = Vector2(0.0, -float(item["height"]))
	var a: Vector2 = IsoProjection.to_screen(rect.position)
	var b: Vector2 = IsoProjection.to_screen(Vector2(rect.end.x, rect.position.y))
	var c: Vector2 = IsoProjection.to_screen(rect.end)
	var d: Vector2 = IsoProjection.to_screen(Vector2(rect.position.x, rect.end.y))
	canvas.draw_colored_polygon(PackedVector2Array([b, c, c + lift, b + lift]), BLOCK_SIDE_X * light)
	canvas.draw_colored_polygon(PackedVector2Array([d, c, c + lift, d + lift]), BLOCK_SIDE_Y * light)
	canvas.draw_colored_polygon(PackedVector2Array([a + lift, b + lift, c + lift, d + lift]), BLOCK_TOP * light)


## The distant scenery, far to near: {asset, prop, at (px in the backdrop plane), scale, flip,
## near}.
static func backdrop(sprites: SpriteSet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Array in BACKDROP:
		if sprites.has_prop(PEAKS_ASSET, item[0]):
			out.append({
				"asset": PEAKS_ASSET, "prop": item[0], "at": item[1], "scale": item[2], "flip": item[3], "near": item[4],
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"].y < b["at"].y)
	return out


## World points (px) of every light-carrying prop, with its flame height (screen px).
static func lights(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in items:
		if item["light"]:
			out.append({"at": item["at"], "flame": item["flame"]})
	return out


static func _wall_junction(lines: Dictionary, cell: Vector2i) -> bool:
	for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		if _linked(lines, cell, dir) or _linked(lines, cell - dir, dir):
			return true
	return false


static func _linked(lines: Dictionary, cell: Vector2i, dir: Vector2i) -> bool:
	if not lines.has(cell) or not lines.has(cell + dir):
		return false
	if dir.x == 0 or dir.y == 0:
		return true
	return not lines.has(cell + Vector2i(dir.x, 0)) and not lines.has(cell + Vector2i(0, dir.y))


## Cells in row order (y, then x), so the placements do not depend on dictionary order.
static func _sorted(cells: Array) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return cells


static func _nearer(a: Vector2i, b: Vector2i) -> bool:
	return a.x + a.y > b.x + b.y or (a.x + a.y == b.x + b.y and a.x > b.x)


## The strips of a ruin fragment as placements; the first carries the contact shadow.
static func _add_ruin(out: Array[Dictionary], prop: String, cells: Array, base: Vector2, cell_px: int) -> void:
	var half: Vector2 = Vector2(0.5, 0.5)
	var footprint: Array[PackedVector2Array] = []
	for cell: Vector2i in cells:
		var centre: Vector2 = (Vector2(cell) + half) * cell_px
		var diamond: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			diamond.append(IsoProjection.to_screen(centre + corner * cell_px * RUIN_CONTACT_GROW))
		footprint.append(diamond)
	for strip: Dictionary in ruin_strips(cells, cell_px):
		var item: Dictionary = {
			"asset": RUINS_ASSET, "prop": prop, "at": (Vector2(strip["front"]) + half) * cell_px, "base": base,
			"clip": strip["clip"], "flip": false, "light": false, "flame": 0.0, "wall": true,
		}
		if not footprint.is_empty():
			item["footprint"] = footprint
			footprint = []
		out.append(item)


## Posts, broken posts and rail bays of `wall` (balustrade()) as placements.
static func _add_balustrade(out: Array[Dictionary], sprites: SpriteSet, wall: Dictionary, cell_px: int) -> void:
	var half: Vector2 = Vector2(0.5, 0.5)
	var rail_height: float = sprites.prop_size(BALUSTRADE_ASSET, "rail").y
	for pair: Array in wall["rails"]:
		var a: Vector2 = (Vector2(pair[0]) + half) * cell_px
		var b: Vector2 = (Vector2(pair[1]) + half) * cell_px
		var along: Vector2 = (b - a).normalized()
		var diagonal: bool = absf(along.x) > 0.01 and absf(along.y) > 0.01
		var reach: float = POST_HALF_PX * (sqrt(2.0) if diagonal else 1.0)
		var from: Vector2 = a + along * reach
		var to: Vector2 = b - along * reach
		var bounds: Rect2 = Rect2(IsoProjection.to_screen(from), Vector2.ZERO)
		bounds = bounds.expand(IsoProjection.to_screen(to)).grow_side(SIDE_TOP, rail_height)
		out.append({
			"asset": BALUSTRADE_ASSET, "prop": RAIL_PROP, "at": (a + b) * 0.5, "flip": false, "light": false,
			"flame": 0.0, "from": from, "to": to, "rail_bounds": bounds, "wall": true,
		})
	for pair: Array in wall["edge_on"]:
		var a: Vector2 = (Vector2(pair[0]) + half) * cell_px
		var b: Vector2 = (Vector2(pair[1]) + half) * cell_px
		var bounds: Rect2 = Rect2(IsoProjection.to_screen(a), Vector2.ZERO).expand(IsoProjection.to_screen(b))
		var inset: Vector2 = Vector2.ONE * (POST_HALF_PX * 0.52)
		out.append({
			"asset": BALUSTRADE_ASSET, "prop": COPING_PROP, "at": (a + b) * 0.5, "flip": false, "light": false,
			"flame": 0.0, "from": a + inset, "to": b - inset, "rail_bounds": bounds.grow(COPING_HEIGHT), "wall": true,
		})
	for cell: Vector2i in wall["posts"]:
		var prop: String = "post_broken" if (wall["broken"] as Array).has(cell) else "post"
		_add(out, sprites, BALUSTRADE_ASSET, prop, (Vector2(cell) + half) * cell_px, false)
		out[-1]["wall"] = true


## Keep rails that the camera can reveal while smoothing finishes after a redraw.
static func rail_draw_window(canvas: CanvasItem, target: Vector2) -> Rect2:
	var current: Rect2 = canvas.get_canvas_transform().affine_inverse() * canvas.get_viewport_rect()
	var settled: Rect2 = Rect2(target - current.size * 0.5, current.size)
	return current.merge(settled).grow(2.0)


## The solid cells (keys Vector2i) of every group of solid cells that a named prop stands on.
static func _propped(rows: Array, anchors: Array[Vector2]) -> Dictionary:
	var out: Dictionary = {}
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] != SOLID_CHAR or out.has(Vector2i(x, y)) or not _near(anchors, Vector2(x, y)):
				continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			out[Vector2i(x, y)] = true
			while not queue.is_empty():
				var at: Vector2i = queue.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = at + step
					if next.y < 0 or next.y >= rows.size() or next.x < 0 or next.x >= (rows[next.y] as String).length():
						continue
					if (rows[next.y] as String)[next.x] == SOLID_CHAR and not out.has(next):
						out[next] = true
						queue.append(next)
	return out


## Whether the cell at (x, y) lies within PROP_REACH_CELLS of a named prop (cell units).
static func _near(anchors: Array[Vector2], cell: Vector2) -> bool:
	var centre: Vector2 = cell + Vector2(0.5, 0.5)
	for anchor: Vector2 in anchors:
		if absf(anchor.x - centre.x) <= PROP_REACH_CELLS and absf(anchor.y - centre.y) <= PROP_REACH_CELLS:
			return true
	return false


static func _add(
	out: Array[Dictionary], sprites: SpriteSet, asset: String, prop: String, at: Vector2, flip: bool
) -> void:
	if not sprites.has_prop(asset, prop):
		return
	var flame: float = sprites.prop_size(asset, prop).y * float(LIGHT_PROPS.get(prop, 0.0))
	out.append({"asset": asset, "prop": prop, "at": at, "flip": flip, "light": LIGHT_PROPS.has(prop), "flame": flame})
