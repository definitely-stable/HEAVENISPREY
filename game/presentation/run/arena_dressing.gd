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
const HORIZON_ASSET: String = "asset.prop.jade_grove_horizon"
## The seal ring and the parapet after REF-068 (ADR-015 section 12): a pedestal brazier on one
## cell, a stone pagoda lantern on one cell, a broken pillar on two by two cells.
const RING_ASSET: String = "asset.prop.courtyard_ring"
## Guardian lions and the columns of the ruined sect after REF-033 and REF-029: monumental,
## the lion on its plinth about 2.25 hero heights, a column about 2.6.
const GUARDIANS_ASSET: String = "asset.prop.courtyard_guardians"
## The balustrade after REF-029: a stone post with a gold cap (0.8 hero heights), the post broken
## and the front elevation of one rail bay (0.5 hero heights).
const BALUSTRADE_ASSET: String = "asset.prop.courtyard_balustrade"
const MASONRY_ASSET: String = "asset.prop.jade_grove_masonry"
const RAIL_DETAILS_ASSET: String = "asset.prop.jade_grove_rail_details"
const RAIL_FINISHES_ASSET: String = "asset.prop.jade_grove_rail_finishes"
const FENCE_MODULES_ASSET: String = "asset.prop.jade_grove_fence_modules"
const STONE_PANEL: String = "stone_parapet"
const TEMPLE_PANEL: String = "temple_panel"
const CLIFF_PANEL: String = "cliff_parapet"
const BRIDGE_ARCH: String = "bridge_arch"
const TERRACE_RELIEF: String = "terrace_relief"
const LOW_LANTERNS: Array[Vector2] = [Vector2(32.5, 9.5), Vector2(59.5, 20.5), Vector2(64.5, 31.5)]
const TEMPLE_RAIL_REACH: float = 17.0
# This inside return is the apron of the east gate lantern. Tall rails on its two sides
# project on top of the outer rail. The walk-blocking stone apron shows the same footprint.
const GATE_LANTERN_APRON: Array[Vector2i] = [Vector2i(33, 8), Vector2i(34, 9)]
const TEMPLE_TURN: Array[Vector2i] = [Vector2i(33, 6), Vector2i(35, 8), Vector2i(38, 8), Vector2i(39, 7)]
const WALL_LIP_SHIFT: float = 0.29
## The prop name of a rail bay: a vertical plane between two posts, textured with "rail".
const RAIL_PROP: String = "rail_span"
const COPING_PROP: String = "wall_coping"
const COPING_HEIGHT: float = 6.0
const COPING_HALF_WIDTH: float = 8.0
## The atlas already paints the original stone foot below the railing.
const RAIL_STONE_SHARE: float = 0.19
## Directions of a straight balustrade run on the grid and the cells between its posts: along a
## grid axis the run climbs the screen at 2:1 and posts every second cell keep the rail readable;
## along a cell diagonal it runs flat across the screen or straight up it. All spans share the
## same stone base, with visible red infill where the rail presents a face.
const RUN_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1)]
const RUN_STEPS: Array[int] = [2, 2, 1, 2]
const MASONRY_RUN_STEPS: Array[int] = [3, 3, 2, 4]
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
const LIGHT_PROPS: Dictionary = {"lantern_stone": 0.64, "lantern_low": 0.52, "brazier_pedestal": 0.66, "gate": 0.55}
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
const BACKDROP: Dictionary = {
	HORIZON_ASSET: [
		["western_needles", Vector2(-748, -91), 0.79, false, 0.18],
		["split_ridge", Vector2(-40, -83), 0.86, false, 0.22],
		["eastern_rampart", Vector2(739, -111), 0.85, false, 0.17],
		["split_ridge", Vector2(-701, 263), 0.84, true, 0.35],
		["eastern_rampart", Vector2(70, 311), 0.89, false, 0.37],
		["western_needles", Vector2(806, 260), 0.88, true, 0.34],
	],
	PEAKS_ASSET: [
		["spire", Vector2(-652, -94), 0.40, true, 0.21],
		["pagoda_rock", Vector2(-398, 26), 0.50, false, 0.42],
		["gate_rock", Vector2(199, -105), 0.42, false, 0.24],
		["spire", Vector2(541, 38), 0.54, false, 0.29],
		["waterfall_rock", Vector2(823, 163), 0.56, true, 0.36],
		["spire", Vector2(-1354, 226), 0.71, false, 0.57],
		["waterfall_rock", Vector2(-1195, 354), 0.86, true, 0.77],
		["pagoda_rock", Vector2(-809, 393), 0.70, true, 0.70],
		["gate_rock", Vector2(-489, 515), 0.74, false, 0.62],
		["spire", Vector2(-90, 584), 0.61, true, 0.64],
		["waterfall_rock", Vector2(474, 542), 0.72, false, 0.72],
		["spire", Vector2(760, 415), 0.70, false, 0.61],
		["pagoda_rock", Vector2(1010, 406), 0.78, false, 0.73],
	],
}


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
	var gate: Vector2 = Vector2.INF
	for item: Dictionary in data.get("props", []):
		var prop: String = str(item.get("prop", ""))
		var at: Array = item.get("at", [0, 0])
		var cell: Vector2 = Vector2(float(at[0]), float(at[1]))
		anchors.append(cell)
		if prop == "gate":
			gate = cell
		if prop == "lantern" and LOW_LANTERNS.has(cell) and sprites.has_prop(RAIL_FINISHES_ASSET, "lantern_low"):
			_add(out, sprites, RAIL_FINISHES_ASSET, "lantern_low", cell * cell_px, false)
			continue
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
	var masonry: bool = walls and sprites.has_prop(MASONRY_ASSET, STONE_PANEL) \
		and sprites.has_prop(MASONRY_ASSET, TEMPLE_PANEL) and sprites.has_prop(MASONRY_ASSET, "corner_pier") \
		and sprites.has_prop(MASONRY_ASSET, "terminal_pier") and sprites.has_prop(RAIL_DETAILS_ASSET, CLIFF_PANEL) \
		and sprites.has_prop(RAIL_DETAILS_ASSET, "coping_top") and sprites.has_prop(RAIL_DETAILS_ASSET, "bridge_end") \
		and sprites.has_prop(RAIL_DETAILS_ASSET, "lantern_apron")
	if walls:
		var skip: Dictionary = propped.duplicate()
		if masonry and data.get("stage_id") == "stage.jade_grove":
			var plinth: bool = sprites.has_prop(FENCE_MODULES_ASSET, "lantern_base") \
				and GATE_LANTERN_APRON.all(func(cell: Vector2i) -> bool: return _tile(rows, cell) == LOW_CHAR)
			for index: int in GATE_LANTERN_APRON.size():
				var cell: Vector2i = GATE_LANTERN_APRON[index]
				if _tile(rows, cell) != LOW_CHAR:
					continue
				skip[cell] = true
				if plinth:
					continue
				var overlap: float = 0.18 if index == 0 else -0.18
				var anchor: Vector2 = (Vector2(cell) + Vector2.ONE * (0.5 + overlap)) * cell_px
				_add(out, sprites, RAIL_DETAILS_ASSET, "lantern_apron", anchor, false)
				out[-1]["wall"] = true
			if plinth:
				var a: Vector2 = (Vector2(GATE_LANTERN_APRON[0]) + Vector2(0.5, 0.5)) * cell_px
				var b: Vector2 = (Vector2(GATE_LANTERN_APRON[1]) + Vector2(0.5, 0.5)) * cell_px
				out.append(_fence_module("lantern_base", (a + b) * 0.5, b, [_footprint_between(a, b, 13.0)]))
		_add_balustrade(out, sprites, balustrade(rows, skip, masonry), cell_px, gate, masonry, rows)
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
static func balustrade(rows: Array, skip: Dictionary = {}, masonry: bool = false) -> Dictionary:
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
	var turns: Dictionary = {}
	var runs: Array[Dictionary] = []
	for index: int in RUN_DIRS.size():
		var dir: Vector2i = RUN_DIRS[index]
		var stride: int = (MASONRY_RUN_STEPS if masonry else RUN_STEPS)[index]
		for cell: Vector2i in cells:
			if not _linked(lines, cell, dir) or _linked(lines, cell - dir, dir):
				continue
			var run: Array[Vector2i] = [cell]
			while _linked(lines, run[-1], dir):
				run.append(run[-1] + dir)
			runs.append({"cells": run, "edge_on": dir == Vector2i.ONE})
			for i: int in run.size():
				if links.has(run[i]):
					turns[run[i]] = true
				links[run[i]] = int(links.get(run[i], 0)) + (1 if i == 0 or i == run.size() - 1 else 2)
				if i % stride != 0 and i != run.size() - 1:
					continue
				if not masonry and dir == Vector2i(1, -1) and run.size() >= 7 and i % 3 == 2 and i != run.size() - 1 \
					and not _wall_junction(lines, run[i]):
					continue  # Combine two bays on long facades without a break in the rail.
				posts[run[i]] = true
	posts.merge(turns)
	# Resolve spans after all directions have nominated their supports. A bay stops at a pier
	# shared with another direction even when that direction was encountered later.
	for run: Dictionary in runs:
		var last: Vector2i = run["cells"][0]
		var spans: Array = edge_on if run["edge_on"] else rails
		for cell: Vector2i in run["cells"]:
			if cell != last and posts.has(cell):
				spans.append([last, cell])
				last = cell
	var broken: Array = []
	for cell: Vector2i in cells:
		if not links.has(cell):
			posts[cell] = true  # a lone post
		elif int(links[cell]) == 1:
			broken.append(cell)
	return {"posts": _sorted(posts.keys()), "broken": broken, "rails": rails, "edge_on": edge_on, "turns": turns}


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
	if item.has("volume"):
		canvas.draw_mesh(item["volume"], item["surface"], Transform2D.IDENTITY, light)
		return
	var quad: Dictionary = sprites.prop_quad(BALUSTRADE_ASSET, "rail", Vector2.ZERO)
	if quad.is_empty():
		return
	var uv: Rect2 = quad["uv"]
	uv.size.y *= 1.0 - RAIL_STONE_SHARE
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position,
	])
	var colors: PackedColorArray = PackedColorArray([light, light, light, light])
	var bay_size: Vector2 = (quad["rect"] as Rect2).size
	bay_size.y *= 1.0 - RAIL_STONE_SHARE
	for bay: PackedVector2Array in rail_quads(item, bay_size, COPING_HEIGHT):
		canvas.draw_polygon(bay, colors, uvs, quad["texture"])


## A thick stone sill, projected from the same plane as the post feet and the adjacent paving.
static func sill_mesh(sprites: SpriteSet, props: Array[Dictionary]) -> MeshInstance2D:
	var sill: MeshInstance2D = MeshInstance2D.new()
	var quad: Dictionary = sprites.prop_quad(BALUSTRADE_ASSET, "rail", Vector2.ZERO)
	if quad.is_empty():
		return sill
	sill.texture = quad["texture"]
	sill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var source: Rect2 = quad["uv"]
	var lift: Vector2 = Vector2(0.0, -COPING_HEIGHT)
	var band: PackedVector2Array = PackedVector2Array([
		Vector2(source.position.x, source.position.y + source.size.y * 0.86),
		Vector2(source.end.x, source.position.y + source.size.y * 0.86),
		source.end, Vector2(source.position.x, source.end.y),
	])
	var vertices: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for item: Dictionary in props:
		if not item.has("rail_bounds") or item.has("panel"):
			continue
		var from: Vector2 = item["from"]
		var to: Vector2 = item["to"]
		var offset: Vector2 = (to - from).normalized().orthogonal() * COPING_HALF_WIDTH
		if IsoProjection.to_screen(offset).y < 0.0:
			offset = -offset
		var a: Vector2 = IsoProjection.to_screen(from - offset)
		var b: Vector2 = IsoProjection.to_screen(to - offset)
		var c: Vector2 = IsoProjection.to_screen(to + offset)
		var d: Vector2 = IsoProjection.to_screen(from + offset)
		var base: int = vertices.size()
		vertices.append_array(PackedVector2Array([d + lift, c + lift, c, d, a + lift, b + lift, c + lift, d + lift]))
		uvs.append_array(band)
		uvs.append_array(band)
		var side: Color = Color(0.68, 0.64, 0.73)
		colors.append_array(PackedColorArray([side, side, side, side, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3,
			base + 4, base + 5, base + 6, base + 4, base + 6, base + 7]))
	sill.mesh = GroundLayer._surface_mesh(vertices, colors, uvs, indices)
	return sill


## The face disappears end-on, but the upper edge of the handrail still catches the light.
static func edge_handrail_mesh(sprites: SpriteSet, props: Array[Dictionary]) -> MeshInstance2D:
	var mesh: MeshInstance2D = MeshInstance2D.new()
	if props.any(func(item: Dictionary) -> bool: return item.has("panel")):
		return mesh
	var quad: Dictionary = sprites.prop_quad(BALUSTRADE_ASSET, "rail", Vector2.ZERO)
	if quad.is_empty():
		return mesh
	mesh.texture = quad["texture"]
	var height: float = COPING_HEIGHT + (quad["rect"] as Rect2).size.y * (1.0 - RAIL_STONE_SHARE)
	var lift: Vector2 = Vector2(0.0, -height)
	var half: Vector2 = Vector2(2.4, 0.0)
	var uv: Rect2 = quad["uv"]
	var top: float = uv.position.y + uv.size.y * 0.02
	var bottom: float = uv.position.y + uv.size.y * 0.13
	var band: PackedVector2Array = PackedVector2Array([
		Vector2(uv.position.x, top), Vector2(uv.end.x, top),
		Vector2(uv.position.x, bottom), Vector2(uv.end.x, bottom),
	])
	var vertices: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for item: Dictionary in props:
		if item["prop"] != COPING_PROP:
			continue
		var from: Vector2 = IsoProjection.to_screen(item["from"]) + lift
		var to: Vector2 = IsoProjection.to_screen(item["to"]) + lift
		var base: int = vertices.size()
		vertices.append_array(PackedVector2Array([from - half, to - half, to + half, from + half]))
		uvs.append_array(band)
		var light: Color = wall_light(item["fixed_light"]).darkened(0.22)
		colors.append_array(PackedColorArray([light, light, light, light]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	mesh.mesh = GroundLayer._surface_mesh(vertices, colors, uvs, indices)
	return mesh


## A tapered stone course retains a visible body even when viewed straight along its length.
## The lacquered version uses a slimmer section and the keyed openings in the painted elevations.
static func _build_masonry_volume(sprites: SpriteSet, item: Dictionary, from: Vector2, to: Vector2) -> void:
	var piece: Dictionary = sprites.prop_quad(item["asset"], item["panel"], Vector2.ZERO)
	var uv: Rect2 = piece["uv"]
	var wooden: bool = item["panel"] == TEMPLE_PANEL
	var open: bool = wooden or item["panel"] == BRIDGE_ARCH
	var across: Vector2 = (to - from).normalized().orthogonal()
	if IsoProjection.to_screen(across).y < 0.0:
		across = -across
	var bottom: Vector2 = across * (4.0 if wooden else 14.0)
	var crown: Vector2 = across * (4.0 if wooden else 7.0)
	var lift: Vector2 = Vector2(0.0, -float(item["panel_height"]))
	var bevel: float = 0.0 if open else 3.0
	var floor: PackedVector2Array = PackedVector2Array()
	var top: PackedVector2Array = PackedVector2Array()
	var crown_lip: PackedVector2Array = PackedVector2Array()
	for at: Vector2 in [from, to]:
		floor.append(IsoProjection.to_screen(at - bottom))
		floor.append(IsoProjection.to_screen(at + bottom))
		top.append(IsoProjection.to_screen(at - crown) + lift + Vector2(0.0, bevel))
		top.append(IsoProjection.to_screen(at + crown) + lift + Vector2(0.0, bevel))
		crown_lip.append(IsoProjection.to_screen(at - crown - across * bevel) + lift)
		crown_lip.append(IsoProjection.to_screen(at + crown + across * bevel) + lift)
	var cap: Rect2 = uv
	cap.position.y += uv.size.y * 0.015
	cap.size.y *= 0.13
	if item["asset"] == RAIL_DETAILS_ASSET:
		cap = sprites.prop_quad(RAIL_DETAILS_ASSET, "coping_top", Vector2.ZERO)["uv"]
	# Each quad has independent material coordinates. Ends sample the frame, away from cutouts.
	var end: Rect2 = Rect2(uv.position + Vector2(uv.size.x * 0.02, 0.0), uv.size * Vector2(0.045, 1.0))
	var vertices: PackedVector2Array = PackedVector2Array([
		floor[0], floor[2], top[2], top[0],
		floor[0], floor[1], top[1], top[0],
		floor[2], floor[3], top[3], top[2],
		floor[1], floor[3], top[3], top[1],
		crown_lip[0], crown_lip[2], crown_lip[3], crown_lip[1],
	])
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var rects: Array[Rect2] = [uv, end, end, uv, cap]
	var tones: Array[float] = [0.66, 0.63, 0.73, 0.85, 0.94]
	if wooden:
		# Use solid crosspieces behind the keyed elevation. A second full elevation in the back
		# would appear through the apertures and visually fill them at the game camera angle.
		for level: float in [0.20, 0.57]:
			var drop: Vector2 = -lift * level
			vertices.append_array([top[0] + drop, top[2] + drop, top[3] + drop, top[1] + drop])
			rects.append(Rect2(uv.position + Vector2(0.0, uv.size.y * level), uv.size * Vector2(1.0, 0.045)))
			tones.append(0.70)
	elif not open:
		vertices.append_array([top[0], top[2], crown_lip[2], crown_lip[0]])
		vertices.append_array([top[1], top[3], crown_lip[3], crown_lip[1]])
		var moulding: Rect2 = Rect2(uv.position, Vector2(uv.size.x, uv.size.y * 0.16))
		rects.append_array([moulding, moulding])
		tones.append_array([0.68, 0.94])
	for face: int in rects.size():
		var rect: Rect2 = rects[face]
		var base: int = face * 4
		if face == 4 or (wooden and face > 4):
			uvs.append_array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
				Vector2(rect.position.x, rect.end.y)])
		else:
			uvs.append_array([Vector2(rect.position.x, rect.end.y), rect.end,
				Vector2(rect.end.x, rect.position.y), rect.position])
		var shade: Color = Color.WHITE * tones[face]
		shade.a = 1.0
		colors.append_array([shade, shade, shade, shade])
		if not open or face != 0:
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	item["surface"] = piece["texture"]
	item["volume"] = GroundLayer._surface_mesh(vertices, colors, uvs, indices)


static func wall_light(light: Color) -> Color:
	return light.darkened(0.17 * (1.0 - smoothstep(0.91, 1.26, light.r)))


## A strip of a large prop sorts at its own cell but is drawn and lit at the sprite anchor.
static func prepare_props(sprites: SpriteSet, props: Array[Dictionary], lanterns: Array[Vector2]) -> void:
	for index: int in props.size():
		var prop: Dictionary = props[index]
		var base: Vector2 = prop.get("base", prop["at"])
		var screen: Vector2 = IsoProjection.to_screen(base)
		prop["screen"] = screen
		prop["order"] = Vector2i(roundi(IsoProjection.depth(prop["at"]) * 16.0), -1 - index)
		prop["fixed_light"] = RunLighting.fixed_light(base, lanterns)
		if prop.has("rail_bounds"):
			continue
		var quad: Dictionary = sprites.prop_quad(prop["asset"], prop["prop"], Vector2.ZERO, 1.0, prop["flip"])
		if quad.is_empty():
			continue
		var local: Rect2 = quad["rect"]
		var bounds: Rect2 = Rect2(local.position + screen, local.size)
		prop["draw_bounds"] = bounds
		prop["shadow_bounds"] = (RunLighting.shadow_transform(screen) * local).merge(bounds).grow(18.0)


## Lay the silhouettes first; the white contacts keep their coverage near a lantern.
static func draw_shadows(
	canvas: Node2D, sprites: SpriteSet, props: Array[Dictionary], disc: Texture2D, window: Rect2
) -> void:
	for prop: Dictionary in props:
		if prop["prop"] == BLOCK_PROP or prop.has("rail_bounds") or prop.has("clip") or prop.has("footprint"):
			continue
		if prop.has("shadow_bounds") and not window.intersects(prop["shadow_bounds"]):
			continue
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(prop["screen"]))
		var shadow: Color = Color(0.0, 0.0, 0.0, 0.72) if prop.get("wall", false) else Color.BLACK
		sprites.draw_prop(canvas, prop["asset"], prop["prop"], Vector2.ZERO, shadow, prop["flip"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	for prop: Dictionary in props:
		if prop.has("shadow_bounds") and not window.intersects(prop["shadow_bounds"]):
			continue
		for polygon: PackedVector2Array in prop.get("footprint", []):
			canvas.draw_colored_polygon(polygon, Color.WHITE)
		if prop.get("wall", false) and not prop.has("rail_bounds") and not prop.has("footprint"):
			RunLighting.contact(canvas, disc, prop["screen"], POST_HALF_PX * 1.55)


## The screen quads [base from, base to, top to, top from] of the bays of a rail: as many whole
## bays as fit the run at the elevation's own width (`bay`, screen px of a front view).
static func rail_quads(item: Dictionary, bay: Vector2, elevation: float) -> Array[PackedVector2Array]:
	var from: Vector2 = item["from"]
	var to: Vector2 = item["to"]
	var count: int = maxi(1, roundi(from.distance_to(to) / bay.x))
	var lift: Vector2 = Vector2(0.0, -bay.y)
	var out: Array[PackedVector2Array] = []
	for i: int in count:
		var a: Vector2 = IsoProjection.to_screen(from.lerp(to, float(i) / count)) - Vector2(0.0, elevation)
		var b: Vector2 = IsoProjection.to_screen(from.lerp(to, float(i + 1) / count)) - Vector2(0.0, elevation)
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
	for asset: String in BACKDROP:
		for item: Array in BACKDROP[asset]:
			if sprites.has_prop(asset, item[0]):
				out.append({
					"asset": asset, "prop": item[0], "at": item[1], "scale": item[2], "flip": item[3], "near": item[4],
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
static func _add_balustrade(
	out: Array[Dictionary], sprites: SpriteSet, wall: Dictionary, cell_px: int, gate: Vector2, masonry: bool, rows: Array
) -> void:
	var half: Vector2 = Vector2(0.5, 0.5)
	var rail_height: float = sprites.prop_size(BALUSTRADE_ASSET, "rail").y
	var painted_posts: Dictionary = {}
	var temple_spans: Array = []
	if masonry and sprites.has_prop(FENCE_MODULES_ASSET, "temple_turn"):
		temple_spans = _temple_spans(wall)
		if not temple_spans.is_empty():
			_add_temple_turn(out, temple_spans, painted_posts, rows, cell_px)
	var first_span: int = out.size()
	for pair: Array in wall["rails"]:
		if temple_spans.has(pair):
			continue
		var a: Vector2 = (Vector2(pair[0]) + half) * cell_px
		var b: Vector2 = (Vector2(pair[1]) + half) * cell_px
		var along: Vector2 = (b - a).normalized()
		var diagonal: bool = absf(along.x) > 0.01 and absf(along.y) > 0.01
		var reach: float = POST_HALF_PX * (sqrt(2.0) if diagonal else 1.0)
		var from: Vector2 = a + along * reach
		var to: Vector2 = b - along * reach
		var bounds: Rect2 = Rect2(IsoProjection.to_screen(from), Vector2.ZERO).expand(IsoProjection.to_screen(to))
		bounds = bounds.grow(COPING_HALF_WIDTH + COPING_HEIGHT).grow_side(SIDE_TOP, rail_height)
		out.append({
			"asset": BALUSTRADE_ASSET, "prop": RAIL_PROP, "at": (a + b) * 0.5, "flip": false, "light": false,
			"flame": 0.0, "from": from, "to": to, "rail_bounds": bounds, "wall": true,
		})
	for pair: Array in wall["edge_on"]:
		if temple_spans.has(pair):
			continue
		var a: Vector2 = (Vector2(pair[0]) + half) * cell_px
		var b: Vector2 = (Vector2(pair[1]) + half) * cell_px
		var bounds: Rect2 = Rect2(IsoProjection.to_screen(a), Vector2.ZERO).expand(IsoProjection.to_screen(b))
		var inset: Vector2 = Vector2.ONE * (POST_HALF_PX * 0.52)
		out.append({
			"asset": BALUSTRADE_ASSET, "prop": COPING_PROP, "at": (a + b) * 0.5, "flip": false, "light": false,
			"flame": 0.0, "from": a + inset, "to": b - inset, "wall": true,
			"rail_bounds": bounds.grow(COPING_HALF_WIDTH).grow_side(SIDE_TOP, rail_height + COPING_HEIGHT),
		})
	var temple_piers: Dictionary = {}
	var bridge_piers: Dictionary = {}
	var copy_end_on: Array[Dictionary] = []
	var bridge_arches: bool = sprites.has_prop(RAIL_FINISHES_ASSET, BRIDGE_ARCH) \
		and sprites.has_prop(RAIL_FINISHES_ASSET, "bridge_pier")
	if masonry:
		for index: int in range(first_span, out.size()):
			var item: Dictionary = out[index]
			var centre: Vector2 = item["at"] / float(cell_px)
			var from: Vector2 = item["from"]
			var to: Vector2 = item["to"]
			# Narrow returns take masonry. The central brass disc needs a genuinely wide bay.
			var width: float = absf(IsoProjection.to_screen(to - from).x)
			var temple: bool = width >= cell_px and centre.distance_to(gate) <= TEMPLE_RAIL_REACH
			var bridge: bool = _bridge_wall(rows, Vector2i(centre.floor()))
			var panel: String = TEMPLE_PANEL if temple else (STONE_PANEL if bridge else CLIFF_PANEL)
			var asset: String = RAIL_DETAILS_ASSET if panel == CLIFF_PANEL else MASONRY_ASSET
			if bridge and not temple and bridge_arches and width >= cell_px * 1.35:
				panel = BRIDGE_ARCH
				asset = RAIL_FINISHES_ASSET
			elif panel == CLIFF_PANEL and centre.x >= 42.0 and width >= cell_px * 1.5 \
					and _near_tile(rows, Vector2i(centre.floor()), "H") and sprites.has_prop(RAIL_FINISHES_ASSET, TERRACE_RELIEF):
				panel = TERRACE_RELIEF
				asset = RAIL_FINISHES_ASSET
			item["asset"] = asset
			item["panel"] = panel
			item["panel_height"] = 29.0 if temple or panel == BRIDGE_ARCH else 22.0
			if item["prop"] == COPING_PROP:
				item["panel_height"] = 18.0
			var start: Vector2i = Vector2i((from / cell_px).floor())
			var finish: Vector2i = Vector2i((to / cell_px).floor())
			if temple:
				temple_piers[start] = true
				temple_piers[finish] = true
			if panel == BRIDGE_ARCH:
				bridge_piers[start] = true
				bridge_piers[finish] = true
			var start_shift: Vector2 = _lip_offset(rows, start, cell_px)
			var end_shift: Vector2 = _lip_offset(rows, finish, cell_px)
			var start_at: Vector2 = (Vector2(start) + half) * cell_px + start_shift
			var end_at: Vector2 = (Vector2(finish) + half) * cell_px + end_shift
			var delta: Vector2i = finish - start
			# The midpoint of the two lip offsets retains the module's full shape and keeps both
			# sockets inside their wall cells. The end fittings are wider than the offset change.
			var adjustment: Vector2 = (end_shift - start_shift) * 0.5
			var module_start: Vector2 = start_at + adjustment
			var module_end: Vector2 = end_at - adjustment
			if panel == BRIDGE_ARCH and delta == Vector2i(2, -2) and sprites.has_prop(FENCE_MODULES_ASSET, "bridge_bay"):
				out[index] = _fence_segment("bridge_bay", module_start, module_end, 12.0)
				painted_posts[start] = true
				continue
			var adjoining_turn: bool = not temple_spans.is_empty() and finish == TEMPLE_TURN[0]
			if item["prop"] == COPING_PROP and delta.x == delta.y and delta.x in [2, 4] \
					and (centre.x >= 42.0 or adjoining_turn) \
					and sprites.has_prop(FENCE_MODULES_ASSET, "cliff_coping"):
				var flip: bool = IsoProjection.to_screen(start_shift + end_shift).x < 0.0
				var midpoint: Vector2 = module_start.lerp(module_end, 0.5) if delta.x == 4 else module_end
				out[index] = _fence_segment("cliff_coping", module_start, midpoint, 13.0, flip)
				if delta.x == 4:
					copy_end_on.append(_fence_segment("cliff_coping", midpoint, module_end, 13.0, flip))
				continue
			var along: Vector2 = (to - from).normalized() * 4.5
			_build_masonry_volume(sprites, item, start_at + along, end_at - along)
			item["rail_bounds"] = (item["rail_bounds"] as Rect2).grow(22.0)
	out.append_array(copy_end_on)
	for cell: Vector2i in wall["posts"]:
		if painted_posts.has(cell):
			continue
		var prop: String = "post_broken" if (wall["broken"] as Array).has(cell) else "post"
		var asset: String = BALUSTRADE_ASSET
		var anchor: Vector2 = (Vector2(cell) + half) * cell_px
		if masonry:
			asset = MASONRY_ASSET
			var turn: bool = (wall["turns"] as Dictionary).has(cell)
			if temple_piers.has(cell):
				prop = "corner_pier"
			elif turn:
				asset = RAIL_DETAILS_ASSET
				prop = "bridge_end"
			elif bridge_piers.has(cell):
				asset = RAIL_FINISHES_ASSET
				prop = "bridge_pier"
			else:
				prop = "terminal_pier"
			anchor += _lip_offset(rows, cell, cell_px)
		_add(out, sprites, asset, prop, anchor, false)
		out[-1]["wall"] = true


## The painted L fits these shared sockets only. Keep the assembled wall on other layouts.
static func _temple_spans(wall: Dictionary) -> Array:
	var spans: Array = (wall["rails"] as Array) + (wall["edge_on"] as Array)
	var matched: Array = []
	for index: int in range(1, TEMPLE_TURN.size()):
		var pair: Array = [TEMPLE_TURN[index - 1], TEMPLE_TURN[index]]
		if not spans.has(pair):
			return []
		matched.append(pair)
	return matched


static func _add_temple_turn(
	out: Array[Dictionary], spans: Array, painted_posts: Dictionary, rows: Array, cell_px: int
) -> void:
	var cells: Array[Vector2i] = []
	var footprint: Array[PackedVector2Array] = []
	var pivot: Vector2i = TEMPLE_TURN[1]
	var anchor: Vector2 = (Vector2(pivot) + Vector2(0.5, 0.5)) * cell_px + _lip_offset(rows, pivot, cell_px)
	for cell: Vector2i in TEMPLE_TURN:
		painted_posts[cell] = true
	for pair: Array in spans:
		var start: Vector2i = pair[0]
		var finish: Vector2i = pair[1]
		var a: Vector2 = (Vector2(start) + Vector2(0.5, 0.5)) * cell_px + _lip_offset(rows, start, cell_px)
		var b: Vector2 = (Vector2(finish) + Vector2(0.5, 0.5)) * cell_px + _lip_offset(rows, finish, cell_px)
		footprint.append(_footprint_between(a, b, 13.0))
		var delta: Vector2i = finish - start
		var count: int = maxi(absi(delta.x), absi(delta.y))
		for index: int in count:
			cells.append(start + delta.sign() * index)
	cells.append(TEMPLE_TURN[-1])
	for strip: Dictionary in ruin_strips(cells, cell_px):
		var sort_feet: Vector2 = (Vector2(strip["front"]) + Vector2(0.5, 0.5)) * cell_px
		var module: Dictionary = _fence_module("temple_turn", anchor, sort_feet, footprint)
		module["clip"] = strip["clip"]
		out.append(module)
		footprint = []


static func _fence_module(
	prop: String, anchor: Vector2, sort_feet: Vector2, footprint: Array[PackedVector2Array]
) -> Dictionary:
	return {"asset": FENCE_MODULES_ASSET, "prop": prop, "at": sort_feet, "base": anchor, "flip": false,
		"light": false, "flame": 0.0, "wall": true, "footprint": footprint}


static func _fence_segment(prop: String, a: Vector2, b: Vector2, half_width: float, flip: bool = false) -> Dictionary:
	var segment: Dictionary = _fence_module(prop, a, b, [_footprint_between(a, b, half_width)])
	segment["flip"] = flip
	return segment


static func _footprint_between(from: Vector2, to: Vector2, half_width: float) -> PackedVector2Array:
	var offset: Vector2 = (to - from).normalized().orthogonal() * half_width
	return PackedVector2Array([IsoProjection.to_screen(from - offset), IsoProjection.to_screen(to - offset),
		IsoProjection.to_screen(to + offset), IsoProjection.to_screen(from + offset)])


static func _tile(rows: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= rows.size():
		return " "
	var row: String = rows[cell.y]
	return row[cell.x] if cell.x >= 0 and cell.x < row.length() else " "


static func _bridge_wall(rows: Array, cell: Vector2i) -> bool:
	return _near_tile(rows, cell, "B")


static func _near_tile(rows: Array, cell: Vector2i, tile: String) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _tile(rows, cell + Vector2i(dx, dy)) == tile:
				return true
	return false


## Align exterior stonework nearer the lip while retaining its position inside the same wall tile.
static func _lip_offset(rows: Array, cell: Vector2i, cell_px: int) -> Vector2:
	var outward: Vector2 = Vector2.ZERO
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		if _tile(rows, cell + offset) == " ":
			outward += Vector2(offset)
	return outward.normalized() * cell_px * WALL_LIP_SHIFT


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
