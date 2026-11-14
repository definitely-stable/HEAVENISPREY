extends GutTest
## ADR-014 slice A3: the courtyard props around the P0 arena. Presentation only.

const CELL: int = 48
const ARENA_CELLS: Vector2i = Vector2i(32, 20)


func _items() -> Array[Dictionary]:
	return ArenaDressing.placements(SpriteSet.load_default(), ARENA_CELLS, CELL)


func test_props_stand_outside_the_walkable_field() -> void:
	var field: Rect2 = Rect2(Vector2.ZERO, Vector2(ARENA_CELLS * CELL))
	var items: Array[Dictionary] = _items()
	assert_gt(items.size(), ArenaDressing.FIXED.size(), "fixed props and balustrades")
	for item: Dictionary in items:
		assert_false(field.grow(-1.0).has_point(item["at"]), "%s at %s" % [item["prop"], item["at"]])


func test_every_fixed_prop_exists_in_its_atlas() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for item: Array in ArenaDressing.FIXED:
		assert_true(sprites.has_prop(item[0], item[1]), "%s/%s" % [item[0], item[1]])


func test_balustrades_leave_gaps_for_the_gate_and_the_stairs() -> void:
	var gate: Rect2 = Rect2(Vector2(12.5, -2.0) * CELL, Vector2(7.0, 2.0) * CELL)
	var stairs: Rect2 = Rect2(Vector2(14.5, 20.0) * CELL, Vector2(3.0, 2.0) * CELL)
	var rails: int = 0
	for item: Dictionary in _items():
		if item["prop"] == "balustrade":
			rails += 1
			assert_false(gate.has_point(item["at"]), "gate gap at %s" % item["at"])
			assert_false(stairs.has_point(item["at"]), "stairs gap at %s" % item["at"])
	assert_gt(rails, 20, "four edges of balustrades")


func test_lights_come_from_lantern_props_with_their_flame_height() -> void:
	var items: Array[Dictionary] = _items()
	var lights: Array[Dictionary] = ArenaDressing.lights(items)
	var expected: int = 0
	for item: Dictionary in items:
		if ArenaDressing.LIGHT_PROPS.has(item["prop"]):
			expected += 1
	assert_eq(lights.size(), expected)
	assert_between(lights.size(), 8, RunView.MAX_SHADOW_POOLS, "within the shadow shader's pools")
	for light: Dictionary in lights:
		assert_gt(light["flame"], 20.0)


func test_without_assets_there_is_no_dressing() -> void:
	assert_eq(ArenaDressing.placements(SpriteSet.new(), ARENA_CELLS, CELL).size(), 0)
