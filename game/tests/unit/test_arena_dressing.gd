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


func test_every_prop_of_the_file_has_its_sprites() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for item: Dictionary in _data()["props"]:
		var prop: String = item["prop"]
		assert_true(ArenaDressing.PROP_SPRITES.has(prop), prop)
		var sprite: Array = ArenaDressing.PROP_SPRITES[prop]
		assert_true(sprites.has_prop(sprite[0], sprite[1]) and sprites.has_prop(sprite[0], sprite[2]), prop)


## REF-033, REF-029: the guardian lions and the columns are monumental next to the hero
## (ADR-015 section 5: a column 2-3 hero heights; the lion figure itself about 1.3 on its plinth).
func test_guardians_tower_over_the_hero() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var hero: float = RunView.HERO_SPRITE_HEIGHT_PX
	for lion: String in ["lion_ball", "lion_cub"]:
		assert_between(sprites.prop_size(ArenaDressing.GUARDIANS_ASSET, lion).y / hero, 2.2, 2.7, lion)
	assert_between(sprites.prop_size(ArenaDressing.GUARDIANS_ASSET, "pillar").y / hero, 2.5, 3.0, "pillar")


## ADR-015 section 9: the square base of a lion or a column lies on the 2:1 floor, corner-on to
## the viewer: its lower edges rise 1 px per 2 px on both sides, and it covers its 2 x 2 solid cells
## (lions 0.85-1.05 of the cell diamond width, columns 0.65-1.0).
func test_guardian_bases_lie_on_the_floor() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	var entry: Dictionary = {}
	for asset: Dictionary in manifest["assets"]:
		if asset["asset_id"] == ArenaDressing.GUARDIANS_ASSET:
			entry = asset
	var image: Image = (load("res://" + (entry["path"] as String).trim_prefix("game/")) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var footprint: float = IsoProjection.to_screen(Vector2(2 * CELL, 0)).x * 2.0
	var cover: Dictionary = {"lion_ball": [0.85, 1.05], "lion_cub": [0.85, 1.05], "pillar": [0.65, 1.0]}
	for prop: Dictionary in entry["layout"]["props"]:
		var name: String = prop["name"]
		if not cover.has(name):
			continue
		var region: Array = prop["region"]
		var base: Array = _base_of(image, Rect2i(region[0], region[1], region[2], region[3]))
		assert_almost_eq(base[0], 0.5, 0.06, "%s left edge" % name)
		assert_almost_eq(base[1], -0.5, 0.06, "%s right edge" % name)
		assert_between(base[2] / float(entry["layout"]["density"]) / footprint, cover[name][0], cover[name][1], name)


## [slope left of the lowest point, slope right of it, base width] of the opaque shape in `rect`:
## slopes are medians over steps of a quarter of each side (a leaf or a chip does not move them);
## the base width is taken over the lowest 15 % of the rows, as the sprite builder anchors it.
func _base_of(image: Image, rect: Rect2i) -> Array:
	var bottom: PackedInt32Array = PackedInt32Array()
	var lowest: int = 0
	var first: int = -1
	var last: int = -1
	var top: int = rect.size.y
	for x: int in rect.size.x:
		var y_low: int = -1
		for y: int in rect.size.y:
			if image.get_pixel(rect.position.x + x, rect.position.y + y).a > 0.5:
				y_low = y
				top = mini(top, y)
		bottom.append(y_low)
		if y_low >= 0:
			last = x
			if first < 0:
				first = x
			if y_low > bottom[lowest]:
				lowest = x
	var band: int = maxi(2, roundi((bottom[lowest] + 1 - top) * 0.15))
	var left_x: int = -1
	var right_x: int = -1
	for x: int in rect.size.x:
		if bottom[x] > bottom[lowest] - band:
			right_x = x
			if left_x < 0:
				left_x = x
	var left_span: int = lowest - first
	var right_span: int = last - lowest
	return [
		_median_slope(bottom, first + left_span / 10, lowest - left_span / 10),
		_median_slope(bottom, lowest + right_span / 10, last - right_span / 10),
		float(right_x - left_x + 1),
	]


func _median_slope(bottom: PackedInt32Array, from: int, to: int) -> float:
	var step: int = maxi(4, (to - from) / 4)
	var slopes: Array[float] = []
	for x: int in range(from, to - step):
		if bottom[x] >= 0 and bottom[x + step] >= 0:
			slopes.append(float(bottom[x + step] - bottom[x]) / step)
	slopes.sort()
	return slopes[slopes.size() / 2] if not slopes.is_empty() else 0.0


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
	var lions: Array = []
	for item: Dictionary in _items():
		if item["asset"] == ArenaDressing.GUARDIANS_ASSET and (item["prop"] as String).begins_with("lion"):
			lions.append([item["prop"], item["flip"]])
	var pair: Array = [["lion_ball", false], ["lion_cub", true]]
	assert_eq(lions, pair + pair + pair)


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
