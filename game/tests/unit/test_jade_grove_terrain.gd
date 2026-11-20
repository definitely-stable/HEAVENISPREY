extends GutTest

const COURT: Array[Vector2] = [Vector2(7, -25), Vector2(-28, -20), Vector2(28, 16), Vector2(-9, 25)]
const LANDING: Array[Vector2] = [Vector2(7, -35), Vector2(-39, -20), Vector2(39, 16), Vector2(-9, 35)]


func test_four_profiles_keep_the_walkable_crossings() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var cell_px: int = RunView.CELL_PX
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, cell_px)
	var origin: Vector2 = GroundLayer.centre_of(data, cell_px)
	for crossing: int in COURT.size():
		var endpoint: float = JadeGroveTerrain.LEVELS[crossing]
		var previous: float = 0.0
		var count: int = 0
		for index: int in 45:
			var uv: Vector2 = COURT[crossing].lerp(LANDING[crossing], float(index) / 44.0)
			var point: Vector2 = origin + Vector2(uv.x + uv.y, uv.y - uv.x) * cell_px * 0.5
			var cell: Vector2i = Vector2i((point / float(cell_px)).floor())
			assert_true(ArenaTopology.WALK_CHARS.contains(data["rows"][cell.y][cell.x]))
			var lift: float = terrain.height_at(point)
			assert_gte((lift - previous) * signf(endpoint), -0.01)
			assert_lt(absf(lift - previous), 5.1, "one step or less between adjacent samples")
			assert_almost_eq(terrain.project(point), IsoProjection.to_screen(point) - Vector2(0.0, lift),
				Vector2(0.01, 0.01))
			count += int(not is_equal_approx(lift, previous))
			previous = lift
		assert_almost_eq(previous, endpoint, 0.01)
		assert_gte(count, 6)


func test_bridge_remains_at_court_height() -> void:
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(P0Tuning.arena_data(), RunView.CELL_PX)
	for cell: Vector2 in [Vector2(8.5, 63.5), Vector2(18.5, 54.5), Vector2(38.5, 33.5)]:
		var point: Vector2 = cell * RunView.CELL_PX
		assert_eq(terrain.project(point), IsoProjection.to_screen(point))


func test_surface_mask_follows_the_visible_floor_in_screen_space() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var polygon: Polygon2D = terrain.build_paving(data, 1.0)
	add_child_autofree(polygon)
	var image: Image = terrain.surface_mask.get_image()
	for cell: Vector2 in [Vector2(25.5, 10.5), Vector2(9.5, 44.5),
			Vector2(67.5, 23.5), Vector2(53.5, 57.5), Vector2(38.5, 33.5)]:
		var world: Vector2 = cell * RunView.CELL_PX
		var texel: Vector2i = Vector2i((terrain.project(world) - terrain.surface_bounds.position)
			* JadeGroveTerrain.SURFACE_MASK_SCALE)
		var encoded: Color = image.get_pixelv(texel)
		assert_almost_eq(encoded.r * 127.5 - 64.0, terrain.height_at(world), 0.26)
		assert_eq(encoded.g, 1.0, "the marked point is on a visible tread")
	var empty: Vector2 = IsoProjection.to_screen(Vector2(20.5, 60.5) * RunView.CELL_PX)
	var sky_texel: Vector2i = Vector2i((empty - terrain.surface_bounds.position) * JadeGroveTerrain.SURFACE_MASK_SCALE)
	assert_eq(image.get_pixelv(sky_texel).g, 0.0, "the gorge does not receive floor marks")
