extends GutTest
## ADR-014 section 1: the isometric matrix of the presentation layer. World -> screen ->
## world is exact to 0.01 px, the ground transform draws exactly to_screen, screen-axis keys
## map to the world diagonals that look like them, and depth follows the screen y.

const POINTS: Array[Vector2] = [
	Vector2.ZERO, Vector2(768, 480), Vector2(1536, 960), Vector2(13.25, 900.5), Vector2(-40, 77),
]


func test_round_trip_is_exact() -> void:
	for point: Vector2 in POINTS:
		var back: Vector2 = IsoProjection.to_world(IsoProjection.to_screen(point))
		assert_lt(back.distance_to(point), 0.01, str(point))


func test_ground_transform_matches_to_screen() -> void:
	var ground: Transform2D = IsoProjection.ground()
	for point: Vector2 in POINTS:
		assert_lt((ground * point).distance_to(IsoProjection.to_screen(point)), 0.001, str(point))


func test_two_to_one_and_horizontal_scale() -> void:
	var right: Vector2 = IsoProjection.to_screen(Vector2(1, -1).normalized() * 100.0)
	assert_almost_eq(right.x, 100.0, 0.001, "a step along the screen horizontal keeps its length")
	assert_almost_eq(right.y, 0.0, 0.001)
	var down: Vector2 = IsoProjection.to_screen(Vector2(1, 1).normalized() * 100.0)
	assert_almost_eq(down.y, 50.0, 0.001, "a step along the screen vertical is halved")
	var cell: Vector2 = IsoProjection.to_screen(Vector2(48, 0))
	assert_almost_eq(cell.x / cell.y, 2.0, 0.001, "a world axis runs at 2:1 on screen")


func test_screen_keys_map_to_world_diagonals() -> void:
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(0, -1)), Vector2i(-1, -1), "up")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(0, 1)), Vector2i(1, 1), "down")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(1, 0)), Vector2i(1, -1), "right")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(-1, 0)), Vector2i(-1, 1), "left")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(1, -1)), Vector2i(0, -1), "up-right")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i(-1, 1)), Vector2i(0, 1), "down-left")
	assert_eq(IsoProjection.screen_move_to_world(Vector2i.ZERO), Vector2i.ZERO)
	for x: int in [-1, 0, 1]:
		for y: int in [-1, 0, 1]:
			var move: Vector2i = Vector2i(x, y)
			if move == Vector2i.ZERO:
				continue
			var on_screen: Vector2 = IsoProjection.to_screen(Vector2(IsoProjection.screen_move_to_world(move)))
			# Straight keys are exact; a diagonal key runs along a world axis, 26.6 deg off the
			# horizontal instead of 45 (the 2:1 slope), which is the closest of the 8 moves.
			var exact: bool = move.x == 0 or move.y == 0
			var limit: float = 0.999 if exact else 0.948
			assert_gt(on_screen.normalized().dot(Vector2(move).normalized()), limit, "key %s looks like itself" % move)


func test_depth_follows_screen_y() -> void:
	var near: Vector2 = Vector2(500, 600)
	var far: Vector2 = Vector2(600, 400)
	assert_gt(IsoProjection.depth(near), IsoProjection.depth(far))
	assert_gt(IsoProjection.to_screen(near).y, IsoProjection.to_screen(far).y)


func test_bounds_hold_the_arena_diamond() -> void:
	var box: Rect2 = IsoProjection.bounds(Vector2(1536, 960))
	for corner: Vector2 in [Vector2.ZERO, Vector2(1536, 0), Vector2(0, 960), Vector2(1536, 960)]:
		assert_true(box.grow(0.01).has_point(IsoProjection.to_screen(corner)), str(corner))
	assert_almost_eq(box.size.x, (1536.0 + 960.0) * IsoProjection.K, 0.01)
	assert_almost_eq(box.size.y, (1536.0 + 960.0) * IsoProjection.K * 0.5, 0.01)
