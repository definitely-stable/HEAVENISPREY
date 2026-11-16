class_name ArenaDressing
extends RefCounted
## ADR-014 slice A3, ADR-015 A1: the things that stand in arena 07 of stage.jade_grove
## (REF-033 "Руины секты Юнхэ", REF-029 kit, REF-056, REF-023). The arena file lists the named
## props on their solid cells (the gate hall, the guardian lions, the columns, the braziers
## that carry the point lights, the old maple); every other wall cell stands as a placeholder
## stone block until the wall kit of slice A2: tall for solid cells, low for balustrades and
## ruins. Far behind, rock spires and pagodas stand in the mist (BACKDROP). Presentation only.

const LIGHTS_ASSET: String = "asset.prop.courtyard_lights"
const NATURE_ASSET: String = "asset.prop.courtyard_nature"
const WALLS_ASSET: String = "asset.prop.courtyard_walls"
const PEAKS_ASSET: String = "asset.prop.distant_peaks"
## The atlas of each named prop of the arena file.
const PROP_ASSETS: Dictionary = {
	"gate": WALLS_ASSET, "lion": LIGHTS_ASSET, "pillar": NATURE_ASSET, "brazier": LIGHTS_ASSET,
	"maple_large": NATURE_ASSET,
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
## The second lion of each pair is mirrored to face the first.
static func placements(sprites: SpriteSet, data: Dictionary, cell_px: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var anchors: Array[Vector2] = []
	var lions: int = 0
	for item: Dictionary in data.get("props", []):
		var prop: String = str(item.get("prop", ""))
		var at: Array = item.get("at", [0, 0])
		var cell: Vector2 = Vector2(float(at[0]), float(at[1]))
		anchors.append(cell)
		var flip: bool = false
		if prop == "lion":
			flip = lions % 2 == 1
			lions += 1
		if PROP_ASSETS.has(prop):
			_add(out, sprites, PROP_ASSETS[prop], prop, cell * cell_px, flip)
	var rows: Array = data.get("rows", [])
	var propped: Dictionary = _propped(rows, anchors)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == LOW_CHAR or (row[x] == SOLID_CHAR and not propped.has(Vector2i(x, y))):
				var rect: Rect2 = Rect2(Vector2(x, y) * cell_px, Vector2.ONE * cell_px)
				out.append({
					"asset": "", "prop": BLOCK_PROP, "at": rect.get_center(), "flip": false, "light": false,
					"flame": 0.0, "rect": rect, "height": BLOCK_LOW_PX if row[x] == LOW_CHAR else BLOCK_SOLID_PX,
				})
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
