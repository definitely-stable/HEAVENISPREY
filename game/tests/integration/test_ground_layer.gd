extends GutTest
## ADR-014 section 4, A3 and A3 polish, ADR-015 A1: the lit ground layer of the run scene on
## arena 07. Presentation only.

const CELL: int = 48
## A small arena: a 5 x 4 court with a void notch and a bridge cell.
const SMALL: Dictionary = {
	"cells": [6, 5], "centre": [2, 2],
	"rows": ["      ", " ..#. ", " .... ", " .wB  ", "      "],
}
const FLOOR: String = "asset.tile.sect_courtyard_floor"
const WORN: String = "asset.tile.sect_courtyard_floor_worn"
const SEAL: String = "asset.tile.sect_seal"
const CLIFF: String = "asset.tile.sect_cliff"


func _ground(
	sprites: SpriteSet, floor_asset: String, points: Array[Dictionary] = [], seal: String = "", cliff: String = "",
	worn: String = "", backdrop: Array[Dictionary] = []
) -> GroundLayer:
	var ground: GroundLayer = GroundLayer.new(sprites, floor_asset, _data(), CELL, points, seal, cliff, worn, backdrop)
	add_child_autofree(ground)
	return ground


func _data() -> Dictionary:
	return P0Tuning.arena_data()


func _arena() -> Vector2:
	return Vector2(GroundLayer.cells_of(_data()) * CELL)


func _centre() -> Vector2:
	return GroundLayer.centre_of(_data(), CELL)


## ADR-015 A1: the paving covers every cell that is not void, one rectangle per row run.
func test_footprint_covers_every_paved_cell_once() -> void:
	assert_eq(GroundLayer.footprint(SMALL, CELL), [
		Rect2(Vector2(1, 1) * CELL, Vector2(4, 1) * CELL),
		Rect2(Vector2(1, 2) * CELL, Vector2(4, 1) * CELL),
		Rect2(Vector2(1, 3) * CELL, Vector2(3, 1) * CELL),
	])
	var area: float = 0.0
	for rect: Rect2 in GroundLayer.footprint(_data(), CELL):
		area += rect.get_area()
	var paved: int = 0
	for row: String in _data()["rows"]:
		paved += row.length() - row.count(GroundLayer.VOID_CHAR)
	assert_eq(int(area), paved * CELL * CELL)


## The cliff shows under every near edge over the void: the +x and +y sides of paved cells.
func test_near_faces_hang_under_the_void_edges() -> void:
	var faces: Array[PackedVector2Array] = GroundLayer.near_faces(SMALL, CELL)
	assert_eq(faces.size(), 3 + 4, "a +x face on each paved row, +y faces under the notch and the last row")
	assert_has(faces, PackedVector2Array([Vector2(5, 1) * CELL, Vector2(5, 2) * CELL]))
	assert_has(faces, PackedVector2Array([Vector2(4, 3) * CELL, Vector2(5, 3) * CELL]), "the notch under (4, 2)")
	assert_has(faces, PackedVector2Array([Vector2(3, 4) * CELL, Vector2(4, 4) * CELL]), "under the bridge")
	for face: PackedVector2Array in GroundLayer.near_faces(_data(), CELL):
		assert_almost_eq(face[0].distance_to(face[1]), float(CELL), 0.01)


func test_paving_is_one_polygon_over_the_footprint() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN)
	var rects: Array[Rect2] = GroundLayer.footprint(_data(), CELL)
	assert_eq(ground.paving.polygons.size(), rects.size())
	assert_eq(ground.paving.polygon.size(), rects.size() * 4)
	assert_eq(ground.paving.polygon[0], rects[0].position)
	assert_true(ground.paving.texture is CanvasTexture, "the paving carries the normal map")
	var texels_per_px: float = float(ground.paving.texture.get_width()) / sprites.floor_repeat_px(FLOOR, CELL)
	for index: int in ground.paving.polygon.size():
		assert_almost_eq(ground.paving.uv[index], ground.paving.polygon[index] * texels_per_px, Vector2(0.01, 0.01))
	var wear: ShaderMaterial = ground.paving.material as ShaderMaterial
	assert_not_null(wear, "two floor textures are blended by the floor shader")
	assert_eq(wear.shader, GroundLayer.FLOOR_SHADER)
	assert_eq(wear.get_shader_parameter("worn_repeat_px"), sprites.floor_repeat_px(WORN, CELL))
	assert_eq(wear.get_shader_parameter("mask_origin"), Vector2.ZERO)
	assert_eq(wear.get_shader_parameter("mask_size"), _arena())
	var clean: float = sprites.floor_repeat_px(FLOOR, CELL)
	var periods: Array[float] = [
		clean, clean / float(wear.get_shader_parameter("alt_scale")), sprites.floor_repeat_px(WORN, CELL),
	]
	assert_almost_eq(periods[1], GroundLayer.ALT_REPEAT_CELLS * CELL, 0.01)
	assert_true(periods[0] < periods[1] and periods[1] < periods[2], "three layers, three periods: %s" % [periods])
	assert_null(_ground(sprites, FLOOR).paving.material, "one texture: no blend")


func test_without_a_floor_texture_one_flat_polygon() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	assert_null(ground.paving.texture)
	assert_eq(ground.paving.color, GroundLayer.COLOR_FLOOR_FLAT)
	assert_eq(ground.find_children("*", "Sprite2D", true, false).size(), 0)
	assert_eq(ground.inlay.size(), 0, "no seal, no inlay")


## A3 polish: the wear mask is the same on every run, clean at the seal, more worn at the walls.
func test_wear_mask_is_fixed_clean_at_the_seal_and_worn_at_the_walls() -> void:
	var clear: float = 336.0
	var mask: Image = GroundLayer.wear_mask(_data(), CELL, clear)
	assert_eq(mask.get_size(), GroundLayer.cells_of(_data()) * GroundLayer.MASK_TEXELS_PER_CELL)
	assert_eq(mask.get_data(), GroundLayer.wear_mask(_data(), CELL, clear).get_data(), "fixed seed")
	var texel: float = float(CELL) / GroundLayer.MASK_TEXELS_PER_CELL
	assert_eq(mask.get_pixelv(Vector2i(_centre() / texel)).r, 0.0, "the seal lies on clean stone")
	var walls: PackedInt32Array = GroundLayer.wall_distance(_data())
	var cells: Vector2i = GroundLayer.cells_of(_data())
	var inner: float = 0.0
	var inner_count: int = 0
	var edge: float = 0.0
	var edge_count: int = 0
	var worn: int = 0
	var second: int = 0
	var field: int = 0
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			var cell: int = (y / GroundLayer.MASK_TEXELS_PER_CELL) * cells.x + x / GroundLayer.MASK_TEXELS_PER_CELL
			if walls[cell] == 0:
				continue
			var at: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			if at.distance_to(_centre()) < clear + GroundLayer.WEAR_EDGE_CELLS * CELL:
				continue
			var wear: float = mask.get_pixel(x, y).r
			field += 1
			worn += int(wear > 0.5)
			second += int(mask.get_pixel(x, y).b > 0.5)
			if walls[cell] == 1:
				edge += wear
				edge_count += 1
			elif walls[cell] > 4:
				inner += wear
				inner_count += 1
	assert_gt(edge_count, 0)
	assert_gt(inner_count, 0)
	assert_between(float(worn) / field, 0.1, 0.6, "worn patches are accents, not the whole field")
	assert_between(float(second) / field, 0.3, 0.7, "both layers of the clean paving show")
	var damp: int = 0
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			damp += int(mask.get_pixel(x, y).a > 0.5)
	assert_between(float(damp) / (mask.get_width() * mask.get_height()), 0.05, 0.5, "damp patches, not a wet floor")
	assert_gt(edge / edge_count, inner / inner_count, "more wear along the walls")


func test_wall_distance_counts_cells_from_walls_and_void() -> void:
	var dist: PackedInt32Array = GroundLayer.wall_distance(SMALL)
	assert_eq(dist[1 * 6 + 1], 1, "a corner of the court")
	assert_eq(dist[1 * 6 + 3], 0, "the solid cell")
	assert_eq(dist[2 * 6 + 2], 1, "next to the low wall")
	var data: Dictionary = _data()
	var centre: Array = data["centre"]
	var seal: int = int(centre[1]) * GroundLayer.cells_of(data).x + int(centre[0])
	assert_gt(GroundLayer.wall_distance(data)[seal], 5, "the seal lies far from the walls")
	assert_eq(dist[3 * 6 + 3], 1, "the bridge is walkable")


func test_lights_reach_the_ground_layer_only() -> void:
	var points: Array[Dictionary] = [{"at": Vector2(-48, 200), "flame": 70.0}, {"at": Vector2(800, -48), "flame": 50.0}]
	var ground: GroundLayer = _ground(SpriteSet.new(), "none", points)
	assert_eq(ground.layer, GroundLayer.LAYER)
	assert_eq(ground.lights.size(), 1 + points.size() + 1, "moon, lanterns, aura")
	for light: Light2D in ground.lights:
		assert_eq([light.range_layer_min, light.range_layer_max], [GroundLayer.LAYER, GroundLayer.LAYER],
			"a light reaches only its own canvas layer")
	for index: int in points.size():
		var light: Light2D = ground.lights[1 + index]
		assert_eq(light.position, IsoProjection.to_screen(points[index]["at"]))
		assert_eq(light.scale, Vector2(1.0, 0.5), "a world circle is a 2:1 ellipse on screen")


## ADR-014 slice A3: the seal lies at the centre of the arena at its world size with a glow over
## it and gold lines towards the walls; the mist sits on its own canvas layer behind the ground.
func test_seal_inlay_and_mist() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN)
	var seals: Array = ground.find_children("*", "Sprite2D", true, false)
	assert_eq(seals.size(), 2, "the seal and its glow")
	for seal: Sprite2D in seals:
		assert_eq(seal.position, _centre())
		assert_almost_eq(seal.scale.x * seal.texture.get_width(), sprites.decal_world_px(SEAL), 0.01)
	var glow: Sprite2D = seals[1]
	assert_eq((glow.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_eq(ground.inlay.size(), 4 * 3, "two lines and a knot to each side")
	var radius: float = sprites.decal_world_px(SEAL) * 0.5
	var rows: Array = _data()["rows"]
	for line: PackedVector2Array in ground.inlay:
		for point: Vector2 in line:
			var cell: Vector2i = Vector2i((point / CELL).floor())
			assert_true(GroundLayer.FLOOR_CHARS.contains((rows[cell.y] as String)[cell.x]), "on open floor: %s" % point)
			assert_gt(point.distance_to(_centre()), radius * 0.9, "and outside the seal")
	var mist: Array = ground.find_children("*", "CanvasLayer", true, false)
	assert_eq(mist.size(), 1)
	var back: CanvasLayer = mist[0]
	assert_eq(back.layer, GroundLayer.MIST_LAYER)
	assert_lt(GroundLayer.MIST_LAYER, GroundLayer.LAYER)
	var kinds: Array = []
	for child: Node in back.get_children():
		kinds.append(child.get_class())
	assert_eq(kinds, ["ColorRect", "Node2D", "ColorRect"], "sky, distant scenery, mist veil")
	assert_false((back.get_child(0) as ColorRect).material.get_shader_parameter("veil"))
	assert_true((back.get_child(2) as ColorRect).material.get_shader_parameter("veil"))


## A3 polish: waterfalls hang on the near cliff faces, under the edge of the paving.
func test_waterfalls_start_under_the_near_faces() -> void:
	var ground: GroundLayer = _ground(SpriteSet.load_default(), FLOOR, [], SEAL, CLIFF, WORN)
	assert_eq(ground.waterfalls.size(), GroundLayer.WATERFALLS.size())
	var tops: Array[Vector2] = []
	for face: PackedVector2Array in GroundLayer.near_faces(_data(), CELL):
		tops.append(IsoProjection.to_screen((face[0] + face[1]) * 0.5))
	var last: float = -INF
	for index: int in ground.waterfalls.size():
		var rect: ColorRect = ground.waterfalls[index]
		var fall: Array = GroundLayer.WATERFALLS[index]
		var top: Vector2 = GroundLayer.waterfall_top(_data(), CELL, fall[0])
		assert_has(tops, top, "the top of a near face")
		assert_gt(top.x, last, "left to right")
		last = top.x
		assert_almost_eq(rect.position.x + rect.size.x * 0.5, top.x, 0.01)
		assert_almost_eq(rect.position.y, top.y + GroundLayer.WATERFALL_TOP_PX, 0.01)
		assert_eq((rect.material as ShaderMaterial).shader, GroundLayer.WATERFALL_SHADER)
		assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)


## A3 polish: the distant scenery follows the view at BACKDROP_PARALLAX of its travel.
func test_backdrop_slides_slower_than_the_view() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN, ArenaDressing.backdrop(sprites))
	var size: Vector2 = Vector2(1280, 720)
	var centre: Vector2 = IsoProjection.to_screen(_centre())
	assert_eq(ground.backdrop_origin(centre, 1.3, size), size * 0.5, "centred view: the scenery is centred")
	var moved: Vector2 = ground.backdrop_origin(centre + Vector2(200, -100), 1.3, size)
	assert_almost_eq(moved, size * 0.5 - Vector2(200, -100) * GroundLayer.BACKDROP_PARALLAX * 1.3, Vector2(0.01, 0.01))
	assert_lt(GroundLayer.BACKDROP_PARALLAX, 1.0)


func test_aura_follows_the_hero() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	ground.follow(Vector2(300, 200))
	assert_almost_eq(ground.aura_position().distance_to(Vector2(300, 200)), 0.0, 0.01)
	ground.follow(Vector2(500, 100), IsoProjection.to_screen(Vector2(400, 300)), 1.3)
	assert_almost_eq(ground.aura_position().distance_to(Vector2(500, 100)), 0.0, 0.01, "the aura stays on the hero")


## ADR-014 section 26: the fire lights flicker with RunLighting.flicker; the aura stays steady.
func test_fire_lights_flicker() -> void:
	var points: Array[Dictionary] = [{"at": Vector2(-48, 200), "flame": 70.0}, {"at": Vector2(800, -48), "flame": 50.0}]
	var ground: GroundLayer = _ground(SpriteSet.new(), "none", points)
	for energy: float in ground.fire_energies():
		assert_almost_eq(energy, RunLighting.LANTERN_ENERGY, 1e-5, "steady before the run")
	ground.flicker(0.8)
	var energies: Array[float] = ground.fire_energies()
	for index: int in points.size():
		assert_almost_eq(energies[index], RunLighting.LANTERN_ENERGY * RunLighting.flicker(0.8, index), 1e-5)
	assert_ne(energies[0], energies[1], "out of step")
	assert_almost_eq((ground.lights[ground.lights.size() - 1] as PointLight2D).energy, RunLighting.AURA_ENERGY, 1e-5,
		"aura steady")
