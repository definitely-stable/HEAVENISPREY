class_name ArenaDressing
extends RefCounted
## ADR-014 slice A3, ADR-015 A1: the things that stand in arena 07 of stage.jade_grove
## (REF-033 "Руины секты Юнхэ", REF-029 kit, REF-056, REF-023). The arena file lists the named
## props on their solid cells (the gate hall, the guardian lions, the columns, the braziers
## that carry the point lights, the old maple). The low wall cells are a balustrade after REF-029
## (ADR-015 section 10): posts on the cells, red rails between them, heaps of ruin where the low
## walls fill whole squares. Every other solid cell stands as a placeholder stone block until
## the rest of the wall kit of slice A2. Far behind, rock spires and pagodas stand in the mist
## (BACKDROP). Presentation only.

const LIGHTS_ASSET: String = "asset.prop.courtyard_lights"
const NATURE_ASSET: String = "asset.prop.courtyard_nature"
const WALLS_ASSET: String = "asset.prop.courtyard_walls"
const PEAKS_ASSET: String = "asset.prop.distant_peaks"
## Guardian lions and the columns of the ruined sect after REF-033 and REF-029: monumental,
## the lion on its plinth about 2.25 hero heights, a column about 2.6.
const GUARDIANS_ASSET: String = "asset.prop.courtyard_guardians"
## The balustrade after REF-029: a stone post with a gold cap (0.8 hero heights), the post broken,
## a heap of ruin on one cell and the front elevation of one rail bay (0.5 hero heights).
const BALUSTRADE_ASSET: String = "asset.prop.courtyard_balustrade"
## The prop name of a rail bay: a vertical plane between two posts, textured with "rail".
const RAIL_PROP: String = "rail_span"
## Directions of a straight balustrade run on the grid and the cells between its posts: along a
## grid axis the run climbs the screen at 2:1 and posts every second cell keep the rail readable;
## along a cell diagonal it runs flat across the screen (a post on every cell, 68 px apart) or
## straight up it, where the rail is edge-on and posts on every second cell (68 px apart, as tall
## as their spacing) carry the line without stacking into a ladder.
const RUN_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1)]
const RUN_STEPS: Array[int] = [2, 2, 1, 2]
## Half the side of a post's square base (world px, 0.4 of a cell): rails stop at the post faces.
const POST_HALF_PX: float = 9.6
## Each named prop of the arena file: [atlas, sprite of the first of a pair, of the second].
const PROP_SPRITES: Dictionary = {
	"gate": [WALLS_ASSET, "gate", "gate"],
	"lion": [GUARDIANS_ASSET, "lion_ball", "lion_cub"],
	"pillar": [GUARDIANS_ASSET, "pillar", "pillar"],
	"brazier": [LIGHTS_ASSET, "brazier", "brazier"],
	"maple_large": [NATURE_ASSET, "maple_large", "maple_large"],
}
## Props that carry a warm point light, and the height of their flame above the base (px).
const LIGHT_PROPS: Dictionary = {"lantern_pagoda": 0.62, "brazier": 0.85, "gate": 0.55}
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
## [prop, base (px from the arena centre in the backdrop's own plane, which follows the view
## with GroundLayer.BACKDROP_PARALLAX), scale, flip, nearness 0..1 (less haze)].
const BACKDROP: Array = [
	["pagoda_rock", Vector2(-452.0, -119.0), 0.62, false, 0.3],
	["waterfall_rock", Vector2(228.0, -133.0), 0.6, false, 0.3],
	["spire", Vector2(455.0, -9.0), 0.5, false, 0.1],
	["spire", Vector2(90.0, -250.0), 0.38, true, 0.0],
	["gate_rock", Vector2(-230.0, -290.0), 0.36, false, 0.0],
	["gate_rock", Vector2(800.0, 215.0), 0.72, false, 0.7],
	["waterfall_rock", Vector2(-735.0, 109.0), 0.72, true, 0.7],
	["spire", Vector2(-318.0, 581.0), 0.7, true, 1.0],
	["pagoda_rock", Vector2(532.0, 561.0), 0.72, true, 1.0],
]


## Every placement: {asset, prop, at (world px), flip, light (bool), flame (screen px above the
## base)}; a placeholder block also carries its cell rectangle (world px) and screen height.
## The lions stand in pairs: the first with the ball, the second with the cub, mirrored to face
## the first.
static func placements(sprites: SpriteSet, data: Dictionary, cell_px: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var anchors: Array[Vector2] = []
	var lions: int = 0
	for item: Dictionary in data.get("props", []):
		var prop: String = str(item.get("prop", ""))
		var at: Array = item.get("at", [0, 0])
		var cell: Vector2 = Vector2(float(at[0]), float(at[1]))
		anchors.append(cell)
		var second: bool = false
		if prop == "lion":
			second = lions % 2 == 1
			lions += 1
		if PROP_SPRITES.has(prop):
			var sprite: Array = PROP_SPRITES[prop]
			_add(out, sprites, sprite[0], sprite[2] if second else sprite[1], cell * cell_px, second)
	var rows: Array = data.get("rows", [])
	var propped: Dictionary = _propped(rows, anchors)
	var walls: bool = sprites.has_prop(BALUSTRADE_ASSET, "post") and sprites.has_prop(BALUSTRADE_ASSET, "rail")
	if walls:
		_add_balustrade(out, sprites, balustrade(rows), cell_px)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if (row[x] == LOW_CHAR and not walls) or (row[x] == SOLID_CHAR and not propped.has(Vector2i(x, y))):
				var rect: Rect2 = Rect2(Vector2(x, y) * cell_px, Vector2.ONE * cell_px)
				out.append({
					"asset": "", "prop": BLOCK_PROP, "at": rect.get_center(), "flip": false, "light": false,
					"flame": 0.0, "rect": rect, "height": BLOCK_LOW_PX if row[x] == LOW_CHAR else BLOCK_SOLID_PX,
				})
	return out


## The balustrade of the low wall cells of `rows`: {"posts": cells, "broken": cells (dead ends of
## a line: posts of a ruin), "rails": [[cell, cell], ...] between neighbouring posts of a straight
## run, "edge_on": the same for runs straight up the screen (no rail is drawn: it is edge-on and
## the posts carry the line), "ruins": cells inside a 2 x 2 square of low walls (a heap each)}. Cells link to
## their neighbours along RUN_DIRS; a diagonal link is dropped where an axis link already joins
## the two cells through a corner cell, so a staircase on the grid is one run, not a zigzag.
static func balustrade(rows: Array) -> Dictionary:
	var low: Dictionary = {}
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == LOW_CHAR:
				low[Vector2i(x, y)] = true
	var ruins: Dictionary = {}
	for cell: Vector2i in low:
		if low.has(cell + Vector2i(1, 0)) and low.has(cell + Vector2i(0, 1)) and low.has(cell + Vector2i(1, 1)):
			for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				ruins[cell + step] = true
	var lines: Dictionary = {}
	for cell: Vector2i in low:
		if not ruins.has(cell):
			lines[cell] = true
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
	return {
		"posts": _sorted(posts.keys()), "broken": broken, "rails": rails, "edge_on": edge_on,
		"ruins": _sorted(ruins.keys()),
	}


## Draws a rail bay on `canvas` (screen space): the "rail" elevation stretched on the vertical
## plane from `from` to `to` (world px, already stopped at the post faces), in whole bays.
static func draw_rail(canvas: CanvasItem, sprites: SpriteSet, item: Dictionary, light: Color) -> void:
	var quad: Dictionary = sprites.prop_quad(BALUSTRADE_ASSET, "rail", Vector2.ZERO)
	if quad.is_empty():
		return
	var uv: Rect2 = quad["uv"]
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position,
	])
	var colors: PackedColorArray = PackedColorArray([light, light, light, light])
	for bay: PackedVector2Array in rail_quads(item, (quad["rect"] as Rect2).size):
		canvas.draw_polygon(bay, colors, uvs, quad["texture"])


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


## Posts, broken posts, rail bays and heaps of ruin of `wall` (balustrade()) as placements.
static func _add_balustrade(out: Array[Dictionary], sprites: SpriteSet, wall: Dictionary, cell_px: int) -> void:
	var half: Vector2 = Vector2(0.5, 0.5)
	for pair: Array in wall["rails"]:
		var a: Vector2 = (Vector2(pair[0]) + half) * cell_px
		var b: Vector2 = (Vector2(pair[1]) + half) * cell_px
		var along: Vector2 = (b - a).normalized()
		var diagonal: bool = absf(along.x) > 0.01 and absf(along.y) > 0.01
		var reach: float = POST_HALF_PX * (sqrt(2.0) if diagonal else 1.0)
		out.append({
			"asset": BALUSTRADE_ASSET, "prop": RAIL_PROP, "at": (a + b) * 0.5, "flip": false, "light": false,
			"flame": 0.0, "from": a + along * reach, "to": b - along * reach, "wall": true,
		})
	for cell: Vector2i in wall["posts"]:
		var prop: String = "post_broken" if (wall["broken"] as Array).has(cell) else "post"
		_add(out, sprites, BALUSTRADE_ASSET, prop, (Vector2(cell) + half) * cell_px, false)
		out[-1]["wall"] = true
	for cell: Vector2i in wall["ruins"]:
		var pick: int = ruin_pick(cell)
		var prop: String = "post_broken" if pick == 2 else "rubble"
		_add(out, sprites, BALUSTRADE_ASSET, prop, (Vector2(cell) + half) * cell_px, pick == 1)
		out[-1]["wall"] = true


## What stands on a ruin cell, fixed by the cell: 0 a heap, 1 the heap mirrored, 2 a broken post.
## A hash of the cell, not its parity, so a square of ruins does not repeat in step; half are broken
## posts (a fallen colonnade), as the one heap of the atlas repeats visibly when it fills a square.
static func ruin_pick(cell: Vector2i) -> int:
	var hash: int = posmod(cell.x * 73856093 ^ cell.y * 19349663, 8)
	return 2 if hash >= 4 else hash % 2


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
