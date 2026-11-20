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


func test_regular_paving_is_flat_outside_the_authored_stair_cells() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var rows: Array = data["rows"]
	var uneven: Array[Vector2i] = []
	for y: int in rows.size():
		for x: int in (rows[y] as String).length():
			var tile: String = rows[y][x]
			if not ArenaTopology.WALK_CHARS.contains(tile) or tile == "^":
				continue
			var centre: Vector2 = Vector2(x + 0.5, y + 0.5) * RunView.CELL_PX
			var level: float = terrain.height_at(centre)
			if tile in [".", "B"] and level != 0.0:
				uneven.append(Vector2i(x, y))
			for axis: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
				if terrain.height_at(centre + axis * RunView.CELL_PX / 3.0) != level:
					uneven.append(Vector2i(x, y))
					break
	assert_eq(uneven, [], "steps belong only to their marked transitions")


func test_plinth_corners_and_sprite_pivots_share_the_same_floor_height() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var cell_px: int = RunView.CELL_PX
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, cell_px)
	for prop: Dictionary in data["props"]:
		if prop["prop"] not in ["lion", "pillar", "pillar_broken", "gate", "maple_large"]:
			continue
		var at: Array = prop["at"]
		var pivot: Vector2 = Vector2(at[0], at[1])
		for offset: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)]:
			assert_eq(terrain.height_at((pivot + offset) * cell_px), terrain.height_at(pivot * cell_px),
				"%s at %s has one supporting plane" % [prop["prop"], pivot])


func test_retaining_corner_has_a_split_foundation_and_preserves_open_rims() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var original: Array = data["rows"]
	var paving: Array = terrain.paving_data["rows"]
	var filled: Array[Vector2i] = []
	for y: int in original.size():
		for x: int in (original[y] as String).length():
			if original[y][x] != paving[y][x]:
				filled.append(Vector2i(x, y))
	var returns: Array[Vector2i] = [Vector2i(34, 8), Vector2i(60, 20), Vector2i(18, 22),
		Vector2i(14, 44), Vector2i(55, 47), Vector2i(42, 58)]
	var footings: Array[Vector2i] = [Vector2i(11, 35), Vector2i(10, 36)]
	assert_eq(filled, returns.slice(0, 3) + footings + returns.slice(3), "only masonry extends the silhouette")
	for cell: Vector2i in returns:
		assert_eq(original[cell.y][cell.x], " ", "the blocking topology retains the void cell")
		assert_eq(paving[cell.y][cell.x], "#")
		var floor: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * RunView.CELL_PX
		var lower: float = INF
		var lip: float = INF
		for side: Vector2i in JadeGroveTerrain.FACE_OFFSETS:
			var other: Vector2i = cell + side
			var along: Vector2 = Vector2(side) * RunView.CELL_PX
			var height: float = terrain.height_at(floor + along * 0.45)
			if original[other.y][other.x] == " ":
				lip = height
				continue
			assert_eq(height, terrain.height_at(floor + along * 0.55), "stone meets each adjoining wall")
			lower = minf(height, lower)
		if lip != INF:
			assert_eq(lip, lower, "the exposed stone face starts at the lower deck")
	for centre: Vector2 in [Vector2(19.5, 22.5), Vector2(34.5, 8.5)]:
		var rear: Vector2 = (centre - Vector2.ONE * 0.16) * RunView.CELL_PX
		var front: Vector2 = (centre + Vector2.ONE * 0.16) * RunView.CELL_PX
		assert_eq(terrain.height_at(rear), 30.0)
		assert_eq(terrain.height_at(front), 0.0)
	assert_eq(terrain.height_at(Vector2(19.5, 22.5) * RunView.CELL_PX), 30.0, "sockets sit on the upper cut")


func test_maple_parapets_follow_the_blocked_rim_and_reach_the_lower_foundation() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var sprites: SpriteSet = SpriteSet.load_default()
	var props: Array[Dictionary] = ArenaDressing.placements(sprites, data, RunView.CELL_PX)
	ArenaDressing.prepare_props(sprites, props, ArenaDressing.lights(props, terrain), terrain)
	var connections: Array[Vector4i] = []
	for prop: Dictionary in props:
		if prop["prop"] != ArenaDressing.MAPLE_PARAPET:
			continue
		var from: Vector2 = prop["from"]
		var to: Vector2 = prop["to"]
		var start: Vector2i = Vector2i((from / RunView.CELL_PX).floor())
		var end: Vector2i = Vector2i((to / RunView.CELL_PX).floor())
		connections.append(Vector4i(start.x, start.y, end.x, end.y))
		var lamp: Vector2 = ArenaDressing.MAPLE_LANTERN * RunView.CELL_PX
		assert_lt(minf(from.distance_to(lamp), to.distance_to(lamp)), ArenaDressing.POST_HALF_PX)
		for step: int in 33:
			var tile: Vector2i = Vector2i((from.lerp(to, step / 32.0) / RunView.CELL_PX).floor())
			assert_false(ArenaTopology.WALK_CHARS.contains(data["rows"][tile.y][tile.x]))
			assert_ne(terrain.paving_data["rows"][tile.y][tile.x], " ", "stone runs over the foundation")
		var mesh: ArrayMesh = prop["volume"]
		var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var across: Vector2 = (to - from).normalized().orthogonal() * float(prop["base_width"])
		assert_true(_contains_vertex(vertices, IsoProjection.to_screen(from + across)))
		assert_true(_contains_vertex(vertices, IsoProjection.to_screen(from - across)))
	assert_eq(connections, [Vector4i(9, 36, 12, 35), Vector4i(12, 35, 12, 36)],
		"the uphill pier and the approach pier both join the lantern's plinth")


func test_sloped_temple_rail_reaches_the_court_with_its_stone_sill() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var sprites: SpriteSet = SpriteSet.load_default()
	var props: Array[Dictionary] = ArenaDressing.placements(sprites, data, RunView.CELL_PX)
	ArenaDressing.prepare_props(sprites, props, ArenaDressing.lights(props, terrain), terrain)
	var supported: int = 0
	for item: Dictionary in props:
		if item.get("panel") != ArenaDressing.TEMPLE_PANEL:
			continue
		var ends: PackedVector2Array = item["masonry_ends"]
		var low: float = minf(terrain.height_at(ends[0]), terrain.height_at(ends[1]))
		if absf(terrain.height_at(ends[0]) - terrain.height_at(ends[1])) <= JadeGroveTerrain.MAX_STEP:
			continue
		var across: Vector2 = (ends[1] - ends[0]).normalized().orthogonal()
		if IsoProjection.to_screen(across).y < 0.0:
			across = -across
		var mesh: ArrayMesh = item["volume"]
		var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for at: Vector2 in ends:
			var lower_foot: Vector2 = IsoProjection.to_screen(at + across * 11.0) - Vector2(0.0, low)
			assert_true(_contains_vertex(vertices, lower_foot))
		supported += 1
	assert_eq(supported, 1, "the angled temple connection has a stone footing")


func _contains_vertex(vertices: PackedVector2Array, point: Vector2) -> bool:
	for vertex: Vector2 in vertices:
		if vertex.distance_to(point) < 0.01:
			return true
	return false


func test_surface_mask_follows_the_visible_floor_in_screen_space() -> void:
	var data: Dictionary = P0Tuning.arena_data()
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(data, RunView.CELL_PX)
	var polygon: Polygon2D = terrain.build_paving(1.0)
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


func test_raised_rim_bevel_covers_the_gap_between_its_two_heights() -> void:
	var terrain: JadeGroveTerrain = JadeGroveTerrain.new(P0Tuning.arena_data(), RunView.CELL_PX)
	var cell: int = RunView.CELL_PX
	var boundary: Array[PackedVector2Array] = GroundLayer.perimeter(terrain.paving_data, cell)
	var offsets: Dictionary = GroundLayer.rim_offsets(terrain.paving_data, cell, boundary)
	var corner: Vector2 = Vector2(35, 8) * cell
	var offset: Vector2 = offsets[corner]
	var bevel: PackedVector2Array = PackedVector2Array([corner, corner + Vector2(2.0 * offset.x, 0.0),
		corner + Vector2(0.0, 2.0 * offset.y)])
	var paving: Polygon2D = terrain.build_paving(1.0, [bevel])
	add_child_autofree(paving)
	var seam: Vector2 = IsoProjection.to_screen(corner + offset * 0.5) - Vector2(0.0, 15.0)
	var texel: Vector2i = Vector2i((seam - terrain.surface_bounds.position) * JadeGroveTerrain.SURFACE_MASK_SCALE)
	var mark: Color = terrain.surface_mask.get_image().get_pixelv(texel)
	assert_almost_eq(mark.g, 0.5, 0.01, "the temple bevel has a visible retaining face")
	assert_almost_eq(mark.r * 127.5 - 64.0, 15.0, 1.0)


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


func test_windup_cover_requires_opaque_body_samples_and_foreground_depth() -> void:
	var image: Image = Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	var bounds: Rect2 = Rect2(100, 200, 40, 40)
	var mask: BitMap = BitMap.new()
	var cover: Dictionary = {"bounds": bounds, "order": 20, "mask": mask, "region": Rect2(0, 0, 40, 40)}
	var feet: Vector2 = Vector2(120, 228)
	image.set_pixel(20, 22, Color.WHITE)
	image.set_pixel(20, 13, Color(1.0, 1.0, 1.0, 0.3))
	mask.create_from_image_alpha(image, 0.65)
	assert_false(RunThreatSilhouettes.covers_body(cover, feet, 10.0, 19), "a grazing overlap is transparent")
	image.set_pixel(20, 13, Color.WHITE)
	mask.create_from_image_alpha(image, 0.65)
	assert_true(RunThreatSilhouettes.covers_body(cover, feet, 10.0, 19))
	assert_false(RunThreatSilhouettes.covers_body(cover, feet, 10.0, 20), "draw order shows an enemy at the same depth")
	assert_false(RunThreatSilhouettes.covers_body(cover, feet, 10.0, 21), "the enemy stands in front of the prop")
	assert_false(RunThreatSilhouettes.covers_body(cover, feet + Vector2(45, 0), 10.0, 19))
