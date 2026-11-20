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
