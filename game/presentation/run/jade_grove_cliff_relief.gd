class_name JadeGroveCliffRelief
extends MeshInstance2D
## Projections of the exposed rock under the terrace coping, drawn in front of the cliff mesh.

const ASSET: String = "asset.prop.jade_grove_cliff_relief"
## [Attachment in cells, piece, scale, mirror, distance below the attachment in screen pixels].
const SECTIONS: Array = [
	[Vector2(4.5, 47), "maple_roots", 1.15, false, 36.0],
	[Vector2(11.5, 47), "gorge_split", 0.89, false, 61.0],
	[Vector2(5.5, 64), "terrace_shelves", 0.96, true, 63.0],
	[Vector2(14.5, 67), "gorge_split", 1.04, true, 60.0],
	[Vector2(46.25, 61), "terrace_shelves", 1.18, false, 48.0],
	[Vector2(50, 64.5), "south_spur", 1.22, true, 67.0],
	[Vector2(55.5, 59), "gorge_split", 0.93, false, 55.0],
	[Vector2(69.5, 27), "south_spur", 0.98, false, 47.0],
]
const ACROSS: Array[float] = [0.0, 0.17, 0.83, 1.0]
const DOWN: Array[float] = [0.0, 0.14, 0.43, 0.68, 1.0]
const ALPHA: Array[float] = [0.06, 0.89, 0.97, 0.68, 0.0]


func _init(sprites: SpriteSet, cell_px: int) -> void:
	name = "JadeGroveCliffRelief"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var vertices: PackedVector2Array = PackedVector2Array()
	var colours: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for section: Array in SECTIONS:
		var at: Vector2 = IsoProjection.to_screen(section[0] * cell_px) + Vector2(0.0, section[4])
		var quad: Dictionary = sprites.prop_quad(ASSET, section[1], at, section[2], section[3])
		if quad.is_empty():
			continue
		texture = quad["texture"]
		var rect: Rect2 = quad["rect"]
		var uv: Rect2 = quad["uv"]
		var base: int = vertices.size()
		for row: int in DOWN.size():
			for col: int in ACROSS.size():
				var fraction: Vector2 = Vector2(ACROSS[col], DOWN[row])
				var tint: Color = Color(0.86, 0.81, 0.89).lerp(Color(0.57, 0.59, 0.74), fraction.y)
				# Soften both cut ends into the parent rock and let the foot dissolve in mist.
				var flank: float = 0.0 if col == 0 or col == ACROSS.size() - 1 else 1.0
				tint.a = ALPHA[row] * flank
				colours.append(tint)
				vertices.append(rect.position + rect.size * fraction)
				uvs.append(uv.position + uv.size * fraction)
				if col + 1 < ACROSS.size() and row + 1 < DOWN.size():
					var index: int = base + row * ACROSS.size() + col
					var below: int = index + ACROSS.size()
					indices.append_array(PackedInt32Array([index, index + 1, below, below, index + 1, below + 1]))
	if indices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface: ArrayMesh = ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = surface


## Both faces of an end-on corner share this contour, including the shallow overhang.
static func return_offset(seam: Vector2, centre_x: float, depth: float) -> Vector2:
	var inward: float = clampf((centre_x - seam.x) / 800.0, -1.0, 1.0)
	var taper: float = smoothstep(0.08, 0.45, depth)
	var shelf: float = smoothstep(0.06, 0.27, depth) * (1.0 - smoothstep(0.38, 0.95, depth))
	var fracture: float = sin(seam.y * 0.042 + seam.x * 0.008)
	var shoulder: float = (30.0 + fracture * 22.0) * shelf
	return Vector2(inward * (49.0 * taper - shoulder), fracture * shelf * 11.0)
