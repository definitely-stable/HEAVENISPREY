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
		var side: bool = crossing == 1 or crossing == 2
		var previous: float = 0.0
		var count: int = 0
		for index: int in 45:
			var uv: Vector2 = COURT[crossing].lerp(LANDING[crossing], float(index) / 44.0)
			var point: Vector2 = origin + Vector2(uv.x + uv.y, uv.y - uv.x) * cell_px * 0.5
			var cell: Vector2i = Vector2i((point / float(cell_px)).floor())
			assert_true(ArenaTopology.WALK_CHARS.contains(data["rows"][cell.y][cell.x]))
			var lift: float = terrain.height_at(point)
			assert_gte((lift - previous) * signf(endpoint), -0.01)
			assert_lt(absf(lift - previous), 6.1 if side else 5.1, "one step or less between adjacent samples")
			assert_almost_eq(terrain.project(point), IsoProjection.to_screen(point) - Vector2(0.0, lift),
				Vector2(0.01, 0.01))
			count += int(not is_equal_approx(lift, previous))
			previous = lift
		assert_almost_eq(previous, endpoint, 0.01)
		assert_eq(count, JadeGroveTerrain.SIDE_RISES if side else 6 + int(crossing == 3))


func test_bridge_remains_at_court_height() -> void:
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(P0Tuning.arena_data(), RunView.CELL_PX)
	for cell: Vector2 in [Vector2(8.5, 63.5), Vector2(18.5, 54.5), Vector2(38.5, 33.5)]:
		var point: Vector2 = cell * RunView.CELL_PX
		assert_eq(terrain.project(point), IsoProjection.to_screen(point))


func test_walkable_paving_has_at_most_one_step_at_every_edge() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var cell_px: int = RunView.CELL_PX
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, cell_px)
	var rows: Array = data["rows"]
	var abrupt: Array[String] = []
	var samples: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, GroundLayer.cells_of(data))
	for y: int in bounds.size.y:
		for x: int in bounds.size.x:
			if not ArenaTopology.WALK_CHARS.contains(rows[y][x]):
				continue
			var centre: Vector2 = Vector2(x + 0.5, y + 0.5)
			for side: int in samples.size():
				var a: float = terrain.height_at((centre + samples[side] / 3.0) * cell_px)
				var b: float = terrain.height_at((centre + samples[(side + 1) % 4] / 3.0) * cell_px)
				if absf(a - b) > 6.01:
					abrupt.append("cell (%d, %d), tread %d" % [x, y, side])
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbour: Vector2i = Vector2i(x, y) + offset
				if not bounds.has_point(neighbour) or not ArenaTopology.WALK_CHARS.contains(rows[neighbour.y][neighbour.x]):
					continue
				var axis: Vector2 = Vector2(offset)
				var midpoint: Vector2 = centre + axis * 0.5
				for across: float in [-0.24, 0.0, 0.24]:
					var point: Vector2 = (midpoint + axis.orthogonal() * across) * cell_px
					if absf(terrain.height_at(point - axis * 0.01) - terrain.height_at(point + axis * 0.01)) > 6.01:
						abrupt.append("cell (%d, %d), edge to %s" % [x, y, neighbour])
						break
	assert_eq(abrupt, [], "no terrace wall interrupts a walkable edge")


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


func test_default_run_view_projects_raised_paving_shadows_and_warnings() -> void:
	var scene: PackedScene = load("res://presentation/run/run_view.tscn")
	var view: RunView = scene.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	var east: Vector2 = Vector2(67.5, 23.5) * RunView.CELL_PX
	assert_almost_eq(view.surface_at(east), IsoProjection.to_screen(east) - Vector2(0.0, 24.0), Vector2.ONE * 0.01)
	var bridge: Vector2 = Vector2(18.5, 54.5) * RunView.CELL_PX
	assert_eq(view.surface_at(bridge), IsoProjection.to_screen(bridge))
	var warnings: ShaderMaterial = view._danger.get_parent().material as ShaderMaterial
	var shadows: ShaderMaterial = view._shadow_canvas.get_parent().material as ShaderMaterial
	assert_not_null(warnings, "the normal scene projects attack outlines onto the raised paving")
	if warnings != null:
		assert_eq(warnings.get_shader_parameter("surface_mask"), shadows.get_shader_parameter("paving_mask"))


func test_masonry_contacts_reach_both_ends_of_a_raised_wall() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var sprites: SpriteSet = SpriteSet.load_default()
	var props: Array[Dictionary] = ArenaDressing.placements(sprites, data, RunView.CELL_PX)
	var footprints: Dictionary[int, PackedVector2Array] = {}
	for index: int in props.size():
		if props[index].has("footprint") and props[index].has("masonry_ends"):
			var polygon: PackedVector2Array = props[index]["footprint"][0]
			footprints[index] = polygon.duplicate()
	ArenaDressing.prepare_props(sprites, props, ArenaDressing.lights(props, terrain), terrain)
	var sloped: int = 0
	for index: int in footprints:
		var ends: PackedVector2Array = props[index]["masonry_ends"]
		var contact: PackedVector2Array = props[index]["footprint"][0]
		var left: float = terrain.height_at(ends[0])
		var right: float = terrain.height_at(ends[1])
		sloped += int(not is_equal_approx(left, right))
		for vertex: int in contact.size():
			var lift: float = left if vertex == 0 or vertex == contact.size() - 1 else right
			assert_almost_eq(footprints[index][vertex] - contact[vertex], Vector2(0.0, lift), Vector2.ONE * 0.01)
	assert_gt(sloped, 0)
