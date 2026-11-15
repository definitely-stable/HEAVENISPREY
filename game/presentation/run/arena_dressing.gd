class_name ArenaDressing
extends RefCounted
## ADR-014 slice A3: the courtyard of the ruined sect around the P0 arena (stage.jade_grove,
## REF-033 "Руины секты Юнхэ", REF-029 kit, REF-056, REF-023). Props stand outside the
## walkable field, so the simulation (no prop collisions) and the picture agree: balustrades
## along the edges, the sect gate with guardian lions at the back, lanterns and braziers that
## carry the point lights, maples at the corners. Presentation only.

const LIGHTS_ASSET: String = "asset.prop.courtyard_lights"
const NATURE_ASSET: String = "asset.prop.courtyard_nature"
const WALLS_ASSET: String = "asset.prop.courtyard_walls"
## Props that carry a warm point light, and the height of their flame above the base (px).
const LIGHT_PROPS: Dictionary = {"lantern_pagoda": 0.62, "brazier": 0.85, "gate": 0.55}
## Balustrades stand this many cells outside the wall line.
const RAIL_OUTSET: float = 0.45
## Fixed placements: [asset, prop, cell (x, y), flip]. Cells may lie outside 0..32 x 0..20.
const FIXED: Array = [
	# Back edge along y = 0 (upper right on screen): the sect gate between two lions.
	[WALLS_ASSET, "gate", Vector2(16.0, -1.6), false],
	[LIGHTS_ASSET, "lion", Vector2(12.6, -1.0), false],
	[LIGHTS_ASSET, "lion", Vector2(19.4, -1.0), true],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(4.5, -1.0), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(9.5, -1.0), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(22.5, -1.0), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(27.5, -1.0), false],
	[LIGHTS_ASSET, "banner", Vector2(7.0, -1.3), false],
	[LIGHTS_ASSET, "banner", Vector2(25.0, -1.3), false],
	[LIGHTS_ASSET, "incense", Vector2(14.3, -2.4), false],
	[LIGHTS_ASSET, "incense", Vector2(17.7, -2.4), false],
	# Back edge along x = 0 (upper left on screen): banners, a stele, a shrine and bamboo.
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(-1.0, 4.5), true],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(-1.0, 15.5), true],
	[WALLS_ASSET, "banner_pair", Vector2(-1.4, 10.0), true],
	[LIGHTS_ASSET, "stele", Vector2(-1.3, 7.2), true],
	[WALLS_ASSET, "shrine", Vector2(-1.6, 12.8), true],
	[WALLS_ASSET, "bamboo", Vector2(-2.2, 18.2), false],
	[NATURE_ASSET, "pillar", Vector2(-1.2, 1.6), false],
	[NATURE_ASSET, "pillar_broken", Vector2(1.6, -1.2), false],
	# Corners: old maples, rocks.
	[NATURE_ASSET, "maple_large", Vector2(-2.6, -2.4), false],
	[NATURE_ASSET, "maple_small", Vector2(-2.0, 21.6), true],
	[NATURE_ASSET, "maple_large", Vector2(33.8, -2.2), false],
	[NATURE_ASSET, "maple_small", Vector2(33.4, 21.2), true],
	[NATURE_ASSET, "rocks", Vector2(-1.8, 20.6), false],
	[NATURE_ASSET, "rocks", Vector2(32.8, -0.8), true],
	[NATURE_ASSET, "tombstone", Vector2(-2.3, 6.0), false],
	# Front edges: stairs down the cliff in the middle of the left side between two braziers, a
	# brazier at the middle of the right side, lanterns near the near corner.
	[WALLS_ASSET, "stairs", Vector2(16.0, 21.5), false],
	[LIGHTS_ASSET, "brazier", Vector2(13.4, 21.0), false],
	[LIGHTS_ASSET, "brazier", Vector2(18.6, 21.0), false],
	[LIGHTS_ASSET, "brazier", Vector2(33.0, 10.0), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(33.0, 16.5), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(26.5, 21.0), false],
]


## Every placement: {asset, prop, at (world px), flip, light (bool), flame (screen px above the
## base)}; balustrades are laid along all four edges between the fixed props.
static func placements(sprites: SpriteSet, arena_cells: Vector2i, cell_px: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Array in FIXED:
		_add(out, sprites, item[0], item[1], (item[2] as Vector2) * cell_px, item[3])
	var arena: Vector2 = Vector2(arena_cells * cell_px)
	var outset: float = RAIL_OUTSET * cell_px
	_rail(out, sprites, Vector2(0.0, -outset), Vector2(arena.x, -outset), false, [12.0, 20.0], cell_px)
	_rail(out, sprites, Vector2(-outset, 0.0), Vector2(-outset, arena.y), true, [], cell_px)
	_rail(out, sprites, Vector2(0.0, arena.y + outset), Vector2(arena.x, arena.y + outset), false, [14.0, 18.0], cell_px)
	_rail(out, sprites, Vector2(arena.x + outset, 0.0), Vector2(arena.x + outset, arena.y), true, [], cell_px)
	return out


## World points (px) of every light-carrying prop, with its flame height (screen px).
static func lights(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in items:
		if item["light"]:
			out.append({"at": item["at"], "flame": item["flame"]})
	return out


static func _add(
	out: Array[Dictionary], sprites: SpriteSet, asset: String, prop: String, at: Vector2, flip: bool
) -> void:
	if not sprites.has_prop(asset, prop):
		return
	var flame: float = sprites.prop_size(asset, prop).y * float(LIGHT_PROPS.get(prop, 0.0))
	out.append({"asset": asset, "prop": prop, "at": at, "flip": flip, "light": LIGHT_PROPS.has(prop), "flame": flame})


## Balustrade segments end to end from `from` to `to` (world px), leaving gaps (cells along the
## edge) for the gate. A segment's world length is its screen width over the projection's K
## (it runs along one world axis).
static func _rail(
	out: Array[Dictionary], sprites: SpriteSet, from: Vector2, to: Vector2, flip: bool, gap: Array, cell_px: int
) -> void:
	if not sprites.has_prop(WALLS_ASSET, "balustrade"):
		return
	var length: float = sprites.prop_size(WALLS_ASSET, "balustrade").x / IsoProjection.K
	var edge: float = from.distance_to(to)
	var direction: Vector2 = (to - from) / edge
	var count: int = maxi(1, roundi(edge / length))
	var step: float = edge / count
	for index: int in count:
		var along: float = (index + 0.5) * step
		if gap.size() == 2 and along > float(gap[0]) * cell_px and along < float(gap[1]) * cell_px:
			continue
		_add(out, sprites, WALLS_ASSET, "balustrade", from + direction * along, flip)
