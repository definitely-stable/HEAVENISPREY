class_name ArenaDressing
extends RefCounted
## ADR-014 slice A3: the courtyard of the ruined sect around the P0 arena (stage.jade_grove,
## REF-033 "Руины секты Юнхэ", REF-029 kit, REF-056, REF-023). Props stand outside the
## walkable field, on the terrace of GroundLayer.outline(), so the simulation (no prop
## collisions) and the picture agree: balustrades along the edges, the sect gate with guardian
## lions at the back, lanterns and braziers that carry the point lights, maples at the corners,
## the stairs down the cliff between two lions. Far behind, rock spires and pagodas stand in
## the mist (BACKDROP). Presentation only.

const LIGHTS_ASSET: String = "asset.prop.courtyard_lights"
const NATURE_ASSET: String = "asset.prop.courtyard_nature"
const WALLS_ASSET: String = "asset.prop.courtyard_walls"
const PEAKS_ASSET: String = "asset.prop.distant_peaks"
## Props that carry a warm point light, and the height of their flame above the base (px).
const LIGHT_PROPS: Dictionary = {"lantern_pagoda": 0.62, "brazier": 0.85, "gate": 0.55}
## The one prop that leaves the terrace: the stairs run down the cliff face.
const STAIRS_PROP: String = "stairs"
## Balustrades stand this many cells outside the wall line.
const RAIL_OUTSET: float = 0.45
## Fixed placements: [asset, prop, cell (x, y), flip]. Cells may lie outside 0..32 x 0..20.
const FIXED: Array = [
	# Back edge along y = 0 (upper right on screen): the sect gate between two lions.
	[WALLS_ASSET, "gate", Vector2(16.0, -1.8), false],
	[LIGHTS_ASSET, "lion", Vector2(12.6, -1.2), false],
	[LIGHTS_ASSET, "lion", Vector2(19.4, -1.2), true],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(4.5, -1.1), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(9.5, -1.1), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(22.5, -1.1), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(27.5, -1.1), false],
	[LIGHTS_ASSET, "banner", Vector2(7.0, -1.7), false],
	[LIGHTS_ASSET, "banner", Vector2(25.0, -1.7), false],
	[LIGHTS_ASSET, "incense", Vector2(14.3, -2.6), false],
	[LIGHTS_ASSET, "incense", Vector2(17.7, -2.6), false],
	# The back row of the far terrace: a stele, a pillar and rocks behind the lanterns.
	[LIGHTS_ASSET, "stele", Vector2(10.9, -2.7), false],
	[NATURE_ASSET, "pillar", Vector2(21.2, -2.8), false],
	[NATURE_ASSET, "tombstone", Vector2(23.8, -2.7), true],
	[NATURE_ASSET, "rocks", Vector2(29.6, -2.6), false],
	[NATURE_ASSET, "maple_small", Vector2(30.8, -2.0), false],
	[NATURE_ASSET, "pillar_broken", Vector2(2.4, -1.5), false],
	# Back edge along x = 0 (upper left on screen): banners, a stele, a shrine and bamboo.
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(-1.1, 4.5), true],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(-1.1, 15.5), true],
	[WALLS_ASSET, "banner_pair", Vector2(-1.7, 10.0), true],
	[LIGHTS_ASSET, "stele", Vector2(-1.5, 7.2), true],
	[WALLS_ASSET, "shrine", Vector2(-2.0, 12.8), true],
	[WALLS_ASSET, "bamboo", Vector2(-2.5, 18.2), false],
	[NATURE_ASSET, "pillar", Vector2(-1.4, 1.9), false],
	[NATURE_ASSET, "tombstone", Vector2(-2.6, 5.8), false],
	[NATURE_ASSET, "rocks", Vector2(-2.7, 8.8), true],
	[NATURE_ASSET, "maple_small", Vector2(-2.6, 15.2), false],
	# Corners: old maples, rocks.
	[NATURE_ASSET, "maple_large", Vector2(-1.7, -1.7), false],
	[NATURE_ASSET, "maple_small", Vector2(-2.2, 21.0), true],
	[NATURE_ASSET, "maple_large", Vector2(33.0, -2.0), false],
	[NATURE_ASSET, "maple_small", Vector2(33.0, 20.6), true],
	[NATURE_ASSET, "rocks", Vector2(-2.0, 20.0), false],
	[NATURE_ASSET, "rocks", Vector2(33.3, -0.4), true],
	[NATURE_ASSET, "rocks", Vector2(33.6, 19.2), true],
	# Front edges: stairs down the cliff in the middle of the left side (their head at the edge
	# of the terrace, STAIRS_PROP) between two lions and two braziers, a brazier at the middle of
	# the right side, lanterns and low ruins along both.
	[WALLS_ASSET, "stairs", Vector2(16.6, 24.4), false],
	[LIGHTS_ASSET, "lion", Vector2(13.9, 21.8), false],
	[LIGHTS_ASSET, "lion", Vector2(18.1, 21.8), true],
	[LIGHTS_ASSET, "brazier", Vector2(12.4, 21.1), false],
	[LIGHTS_ASSET, "brazier", Vector2(19.6, 21.1), false],
	[LIGHTS_ASSET, "brazier", Vector2(33.2, 10.0), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(33.2, 16.5), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(33.2, 3.8), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(26.5, 21.2), false],
	[LIGHTS_ASSET, "lantern_pagoda", Vector2(5.5, 21.2), false],
	[NATURE_ASSET, "pillar_broken", Vector2(23.0, 21.7), true],
	[NATURE_ASSET, "pillar_broken", Vector2(33.7, 13.4), false],
	[NATURE_ASSET, "rocks", Vector2(2.0, 21.7), false],
	[NATURE_ASSET, "tombstone", Vector2(9.2, 21.7), false],
]
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
