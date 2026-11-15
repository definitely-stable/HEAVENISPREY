extends GutTest
## ADR-014 section 4, A3 and A3 polish: the lit ground layer of the run scene. Presentation only.

const CELL: int = 48
const ARENA: Vector2 = Vector2(32 * 48, 20 * 48)
const FLOOR: String = "asset.tile.sect_courtyard_floor"
const WORN: String = "asset.tile.sect_courtyard_floor_worn"
const SEAL: String = "asset.tile.sect_seal"
const CLIFF: String = "asset.tile.sect_cliff"


func _ground(
	sprites: SpriteSet, floor_asset: String, points: Array[Dictionary] = [], seal: String = "", cliff: String = "",
	worn: String = "", backdrop: Array[Dictionary] = []
) -> GroundLayer:
	var ground: GroundLayer = GroundLayer.new(sprites, floor_asset, ARENA, CELL, points, seal, cliff, worn, backdrop)
	add_child_autofree(ground)
	return ground


## A3 polish: the terrace is the field plus its aprons with the far and near corners cut.
func test_outline_holds_the_field_and_cuts_two_corners() -> void:
	var outline: PackedVector2Array = GroundLayer.outline(ARENA, CELL)
	assert_eq(outline.size(), 6)
	var far: float = GroundLayer.FAR_APRON_CELLS * CELL
	var near: float = GroundLayer.NEAR_APRON_CELLS * CELL
	for corner: Vector2 in [Vector2.ZERO, Vector2(ARENA.x, 0.0), ARENA, Vector2(0.0, ARENA.y)]:
		assert_true(Geometry2D.is_point_in_polygon(corner, outline), "field corner %s" % corner)
	assert_true(Geometry2D.is_point_in_polygon(Vector2(ARENA.x + near - 4.0, -far + 4.0), outline), "right tip stays")
	assert_true(Geometry2D.is_point_in_polygon(Vector2(-far + 4.0, ARENA.y + near - 4.0), outline), "left tip stays")
	assert_false(Geometry2D.is_point_in_polygon(Vector2(-far + 4.0, -far + 4.0), outline), "far corner is cut")
	assert_false(Geometry2D.is_point_in_polygon(ARENA + Vector2.ONE * (near - 4.0), outline), "near corner is cut")
	# The balustrades (ArenaDressing.RAIL_OUTSET) stay on the terrace at every corner.
	var rail: float = ArenaDressing.RAIL_OUTSET * CELL
	for corner: Vector2 in [Vector2(-rail, -rail), ARENA + Vector2(rail, rail)]:
		assert_true(Geometry2D.is_point_in_polygon(corner, outline), "rail corner %s" % corner)


## The cliff shows under the three near edges, left to right on screen, joined end to end.
func test_near_edges_run_left_to_right() -> void:
	var edges: Array[PackedVector2Array] = GroundLayer.near_edges(ARENA, CELL)
	assert_eq(edges.size(), 3)
	var last: Vector2 = edges[0][0]
	for edge: PackedVector2Array in edges:
		assert_eq(edge[0], last, "faces share their corners")
		assert_gt(IsoProjection.to_screen(edge[1]).x, IsoProjection.to_screen(edge[0]).x)
		last = edge[1]
	var front: PackedVector2Array = edges[1]
	assert_almost_eq(IsoProjection.to_screen(front[0]).y, IsoProjection.to_screen(front[1]).y, 0.01,
		"the cut corner faces the viewer")


func test_paving_is_one_polygon_over_the_outline() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN)
	assert_eq(ground.paving.polygon, GroundLayer.outline(ARENA, CELL))
	assert_true(ground.paving.texture is CanvasTexture, "the paving carries the normal map")
	var texels_per_px: float = float(ground.paving.texture.get_width()) / sprites.floor_repeat_px(FLOOR, CELL)
	for index: int in ground.paving.polygon.size():
		assert_almost_eq(ground.paving.uv[index], ground.paving.polygon[index] * texels_per_px, Vector2(0.01, 0.01))
	var wear: ShaderMaterial = ground.paving.material as ShaderMaterial
	assert_not_null(wear, "two floor textures are blended by the floor shader")
	assert_eq(wear.shader, GroundLayer.FLOOR_SHADER)
	assert_eq(wear.get_shader_parameter("worn_repeat_px"), sprites.floor_repeat_px(WORN, CELL))
	assert_eq(wear.get_shader_parameter("mask_origin"), -Vector2.ONE * GroundLayer.FAR_APRON_CELLS * CELL)
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
	var mask: Image = GroundLayer.wear_mask(ARENA, CELL, clear)
	var cells: Vector2 = Vector2(32, 20) + Vector2.ONE * (GroundLayer.FAR_APRON_CELLS + GroundLayer.NEAR_APRON_CELLS)
	assert_eq(mask.get_size(), Vector2i((cells * GroundLayer.MASK_TEXELS_PER_CELL).ceil()))
	assert_eq(mask.get_data(), GroundLayer.wear_mask(ARENA, CELL, clear).get_data(), "fixed seed")
	var texel: float = float(CELL) / GroundLayer.MASK_TEXELS_PER_CELL
	var origin: Vector2 = -Vector2.ONE * GroundLayer.FAR_APRON_CELLS * CELL
	var centre: Vector2i = Vector2i((ARENA * 0.5 - origin) / texel)
	assert_eq(mask.get_pixelv(centre).r, 0.0, "the seal lies on clean stone")
	var inner: float = 0.0
	var inner_count: int = 0
	var edge: float = 0.0
	var edge_count: int = 0
	var worn: int = 0
	var second: int = 0
	var field: int = 0
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			var at: Vector2 = origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			if at.x < 0.0 or at.y < 0.0 or at.x > ARENA.x or at.y > ARENA.y:
				continue
			var wear: float = mask.get_pixel(x, y).r
			field += 1
			worn += int(wear > 0.5)
			second += int(mask.get_pixel(x, y).b > 0.5)
			var inside: float = minf(minf(at.x, at.y), minf(ARENA.x - at.x, ARENA.y - at.y))
			if inside < CELL:
				edge += wear
				edge_count += 1
			elif inside > 5.0 * CELL:
				inner += wear
				inner_count += 1
	assert_gt(edge_count, 0)
	assert_gt(inner_count, 0)
	assert_between(float(worn) / field, 0.1, 0.5, "worn patches are accents, not the whole field")
	assert_between(float(second) / field, 0.3, 0.7, "both layers of the clean paving show")
	assert_gt(edge / edge_count, inner / inner_count, "more wear along the walls")


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
## it and gold lines to the four walls; the mist sits on its own canvas layer behind the ground.
func test_seal_inlay_and_mist() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN)
	var seals: Array = ground.find_children("*", "Sprite2D", true, false)
	assert_eq(seals.size(), 2, "the seal and its glow")
	for seal: Sprite2D in seals:
		assert_eq(seal.position, ARENA * 0.5)
		assert_almost_eq(seal.scale.x * seal.texture.get_width(), sprites.decal_world_px(SEAL), 0.01)
	var glow: Sprite2D = seals[1]
	assert_eq((glow.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_eq(ground.inlay.size(), 4 * 3, "two lines and a knot to each wall")
	var field: Rect2 = Rect2(Vector2.ZERO, ARENA)
	var radius: float = sprites.decal_world_px(SEAL) * 0.5
	for line: PackedVector2Array in ground.inlay:
		for point: Vector2 in line:
			assert_true(field.has_point(point), "the inlay stays inside the walls: %s" % point)
			assert_gt(point.distance_to(ARENA * 0.5), radius * 0.9, "and outside the seal")
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


## A3 polish: waterfalls hang on the near cliff faces, under the edge of the terrace.
func test_waterfalls_start_under_the_near_edges() -> void:
	var ground: GroundLayer = _ground(SpriteSet.load_default(), FLOOR, [], SEAL, CLIFF, WORN)
	var edges: Array[PackedVector2Array] = GroundLayer.near_edges(ARENA, CELL)
	assert_eq(ground.waterfalls.size(), GroundLayer.WATERFALLS.size())
	for index: int in ground.waterfalls.size():
		var rect: ColorRect = ground.waterfalls[index]
		var fall: Array = GroundLayer.WATERFALLS[index]
		var edge: PackedVector2Array = edges[fall[0]]
		var top: Vector2 = IsoProjection.to_screen(edge[0]).lerp(IsoProjection.to_screen(edge[1]), fall[1])
		assert_almost_eq(rect.position.x + rect.size.x * 0.5, top.x, 0.01)
		assert_almost_eq(rect.position.y, top.y + GroundLayer.WATERFALL_TOP_PX, 0.01)
		assert_eq((rect.material as ShaderMaterial).shader, GroundLayer.WATERFALL_SHADER)
		assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)


## A3 polish: the distant scenery follows the view at BACKDROP_PARALLAX of its travel.
func test_backdrop_slides_slower_than_the_view() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF, WORN, ArenaDressing.backdrop(sprites))
	var size: Vector2 = Vector2(1280, 720)
	var centre: Vector2 = IsoProjection.to_screen(ARENA * 0.5)
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
