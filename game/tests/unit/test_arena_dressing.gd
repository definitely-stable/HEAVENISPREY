extends GutTest
## ADR-014 slice A3, ADR-015 A1: the things that stand in arena 07. Presentation only.

const CELL: int = 48


func _data() -> Dictionary:
	return P0Tuning.arena_data()


func _items() -> Array[Dictionary]:
	return ArenaDressing.placements(SpriteSet.load_default(), _data(), CELL)


func _char_at(at: Vector2) -> String:
	var rows: Array = _data()["rows"]
	var cell: Vector2i = Vector2i((at / CELL).floor())
	return (rows[cell.y] as String)[cell.x]


## Every named prop of the arena file stands on its solid cells, with its atlas.
func test_named_props_stand_on_solid_cells() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var named: int = 0
	for item: Dictionary in _items():
		if item["prop"] == ArenaDressing.BLOCK_PROP:
			continue
		named += 1
		assert_true(sprites.has_prop(item["asset"], item["prop"]), "%s/%s" % [item["asset"], item["prop"]])
		assert_eq(_char_at(item["at"]), ArenaDressing.SOLID_CHAR, "%s at %s" % [item["prop"], item["at"] / CELL])
	assert_eq(named, (_data()["props"] as Array).size(), "every prop of the file has a sprite")


func test_every_prop_of_the_file_has_an_atlas() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for item: Dictionary in _data()["props"]:
		var prop: String = item["prop"]
		assert_true(ArenaDressing.PROP_ASSETS.has(prop), prop)
		assert_true(sprites.has_prop(ArenaDressing.PROP_ASSETS[prop], prop), prop)


## Placeholder blocks: one on every low wall cell, one on every solid cell that no named prop
## stands on, tall for solid and low for low walls; none on walkable cells.
func test_blocks_cover_the_walls_without_props() -> void:
	var rows: Array = _data()["rows"]
	var low: int = 0
	for row: String in rows:
		low += row.count(ArenaDressing.LOW_CHAR)
	var blocks: Dictionary = {}
	for item: Dictionary in _items():
		if item["prop"] != ArenaDressing.BLOCK_PROP:
			continue
		var rect: Rect2 = item["rect"]
		assert_eq(rect.size, Vector2.ONE * CELL)
		assert_eq(item["at"], rect.get_center())
		var code: String = _char_at(item["at"])
		assert_true(code == ArenaDressing.SOLID_CHAR or code == ArenaDressing.LOW_CHAR, code)
		var tall: bool = code == ArenaDressing.SOLID_CHAR
		assert_eq(item["height"], ArenaDressing.BLOCK_SOLID_PX if tall else ArenaDressing.BLOCK_LOW_PX)
		blocks[rect.position] = code
	var low_blocks: int = blocks.values().count(ArenaDressing.LOW_CHAR)
	assert_eq(low_blocks, low, "every low wall cell")
	assert_gt(blocks.values().count(ArenaDressing.SOLID_CHAR), 0, "ruin fragments of the seal ring")
	# The gate hall and the brazier columns are props, not blocks.
	for item: Dictionary in _data()["props"]:
		var at: Array = item["at"]
		var cell: Vector2 = (Vector2(float(at[0]), float(at[1])) - Vector2(0.5, 0.5)).floor() * CELL
		assert_false(blocks.has(cell), "%s stands on its own cells" % item["prop"])


func test_lions_face_each_other_in_pairs() -> void:
	var flips: Array = []
	for item: Dictionary in _items():
		if item["prop"] == "lion":
			flips.append(item["flip"])
	assert_eq(flips, [false, true, false, true, false, true])


func test_lights_come_from_lantern_props_with_their_flame_height() -> void:
	var items: Array[Dictionary] = _items()
	var lights: Array[Dictionary] = ArenaDressing.lights(items)
	var expected: int = 0
	for item: Dictionary in items:
		if ArenaDressing.LIGHT_PROPS.has(item["prop"]):
			expected += 1
	assert_eq(lights.size(), expected)
	assert_between(lights.size(), 6, RunView.MAX_SHADOW_POOLS, "within the shadow shader's pools")
	for light: Dictionary in lights:
		assert_gt(light["flame"], 20.0)


## A3 polish: the distant scenery is listed far to near and comes from its own atlas.
func test_backdrop_is_sorted_far_to_near() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var items: Array[Dictionary] = ArenaDressing.backdrop(sprites)
	assert_eq(items.size(), ArenaDressing.BACKDROP.size())
	var last: float = -INF
	for item: Dictionary in items:
		assert_true(sprites.has_prop(item["asset"], item["prop"]), item["prop"])
		assert_eq(item["asset"], ArenaDressing.PEAKS_ASSET)
		assert_gte(item["at"].y, last, "drawn back to front")
		last = item["at"].y
		assert_between(item["scale"], 0.2, 1.0, "smaller than the courtyard props: it is far away")
		assert_between(item["near"], 0.0, 1.0)


func test_without_assets_only_the_blocks_remain() -> void:
	for item: Dictionary in ArenaDressing.placements(SpriteSet.new(), _data(), CELL):
		assert_eq(item["prop"], ArenaDressing.BLOCK_PROP)
	assert_eq(ArenaDressing.backdrop(SpriteSet.new()).size(), 0)
