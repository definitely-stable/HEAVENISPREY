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
		if item["prop"] == ArenaDressing.BLOCK_PROP or item.has("wall"):
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
	var image: Image = _atlas_image(entry)
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


func _manifest_entry(asset_id: String) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	for asset: Dictionary in manifest["assets"]:
		if asset["asset_id"] == asset_id:
			return asset
	return {}


func _atlas_image(entry: Dictionary) -> Image:
	var image: Image = (load("res://" + (entry["path"] as String).trim_prefix("game/")) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	return image


## [slope left of the lowest point, slope right of it, base width] of the opaque shape in `rect`,
## as tools/art/measure_base.py measures a master: a median of local slopes seeds a line, the
## columns within 2.5 px of it are refitted by least squares (a leaf or a chip does not enter);
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
	var xs: Array[int] = []
	for x: int in range(from, to):
		if bottom[x] >= 0:
			xs.append(x)
		if x < to - step and bottom[x] >= 0 and bottom[x + step] >= 0:
			slopes.append(float(bottom[x + step] - bottom[x]) / step)
	var slope: float = _median(slopes)
	for _pass: int in 2:
		var offsets: Array[float] = []
		for x: int in xs:
			offsets.append(bottom[x] - slope * x)
		var offset: float = _median(offsets)
		var inliers: Array[int] = []
		for x: int in xs:
			if absf(bottom[x] - slope * x - offset) <= 2.5:
				inliers.append(x)
		if inliers.size() < 8:
			break
		var mean_x: float = 0.0
		var mean_y: float = 0.0
		for x: int in inliers:
			mean_x += x
			mean_y += bottom[x]
		mean_x /= inliers.size()
		mean_y /= inliers.size()
		var spread: float = 0.0
		var cross: float = 0.0
		for x: int in inliers:
			spread += (x - mean_x) * (x - mean_x)
			cross += (x - mean_x) * (bottom[x] - mean_y)
		if spread == 0.0:
			break
		slope = cross / spread
	return slope


func _median(values: Array[float]) -> float:
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else 0.0


## ADR-015 section 10: the low wall cells are a balustrade. Every cell of a line is a post or lies
## on a rail bay between two posts of its run; every cell of a 2 x 2 square of low walls is a heap
## of ruin; no low wall is left as a placeholder block.
func test_balustrade_covers_every_low_wall_cell() -> void:
	var rows: Array = _data()["rows"]
	var wall: Dictionary = ArenaDressing.balustrade(rows)
	var covered: Dictionary = {}
	for cell: Vector2i in wall["posts"]:
		covered[cell] = "post"
	for cell: Vector2i in wall["ruins"]:
		assert_false(covered.has(cell), "a heap is not a post: %s" % cell)
		covered[cell] = "ruin"
	for pair: Array in (wall["rails"] as Array) + (wall["edge_on"] as Array):
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var step: Vector2i = Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		assert_eq(step == Vector2i(1, 1), (wall["edge_on"] as Array).has(pair), "no rail edge-on")
		assert_true(covered.get(a) == "post" and covered.get(b) == "post", "a rail ends on posts")
		var cell: Vector2i = a + step
		while cell != b:
			covered[cell] = covered.get(cell, "rail")
			cell += step
	var low: int = 0
	for y: int in rows.size():
		for x: int in (rows[y] as String).length():
			if (rows[y] as String)[x] == ArenaDressing.LOW_CHAR:
				low += 1
				assert_true(covered.has(Vector2i(x, y)), "low wall %s is drawn" % Vector2i(x, y))
	assert_eq(covered.size(), low, "nothing outside the low walls")
	assert_gt((wall["ruins"] as Array).size(), 0, "the ruins inside the court")
	for item: Dictionary in _items():
		if item["prop"] == ArenaDressing.BLOCK_PROP:
			assert_ne(_char_at(item["at"]), ArenaDressing.LOW_CHAR, "no placeholder block on a low wall")


## A staircase of low walls on the grid is one straight run on the screen, not a zigzag: a
## diagonal neighbour is linked only when no axis neighbour joins the two cells.
func test_staircase_is_one_run() -> void:
	var stairs: Array = ["w   ", " w  ", "  w ", "   w"]
	var wall: Dictionary = ArenaDressing.balustrade(stairs)
	assert_eq(wall["posts"], [Vector2i(0, 0), Vector2i(2, 2), Vector2i(3, 3)], "every second cell, and the end")
	assert_eq(wall["rails"], [], "straight up the screen: posts only")
	assert_eq(wall["edge_on"], [[Vector2i(0, 0), Vector2i(2, 2)], [Vector2i(2, 2), Vector2i(3, 3)]])
	var flat: Dictionary = ArenaDressing.balustrade(["   w", "  w ", " w  ", "w   "])
	assert_eq((flat["rails"] as Array).size(), 3, "flat across the screen: a bay between every post")
	var axis: Dictionary = ArenaDressing.balustrade(["wwwww"])
	assert_eq(axis["posts"], [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)], "every second cell along an axis")
	assert_eq(axis["broken"], [Vector2i(0, 0), Vector2i(4, 0)], "the dead ends are broken posts")
	var corner: Dictionary = ArenaDressing.balustrade(["ww", "w "])
	assert_eq((corner["rails"] as Array).size(), 2, "an L joins through its corner, no diagonal")


## The ruins mix heaps, mirrored heaps and broken posts by a hash of the cell: no two neighbours
## in a row of the same kind in every row of a square, so a square of ruins does not tile.
func test_ruins_do_not_repeat_in_step() -> void:
	var kinds: Dictionary = {}
	for cell: Vector2i in ArenaDressing.balustrade(_data()["rows"])["ruins"]:
		kinds[ArenaDressing.ruin_pick(cell)] = int(kinds.get(ArenaDressing.ruin_pick(cell), 0)) + 1
	assert_eq(kinds.size(), 3, "all three kinds are used")
	for count: int in kinds.values():
		assert_gt(count, 5)


## Rail bays stand on the line between the post centres and stop at the post faces; the quads of
## a bay are vertical planes on that line, as tall as the rail elevation.
func test_rails_run_between_post_faces() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var bay: Vector2 = sprites.prop_size(ArenaDressing.BALUSTRADE_ASSET, "rail")
	var rails: int = 0
	for item: Dictionary in _items():
		if item["prop"] != ArenaDressing.RAIL_PROP:
			continue
		rails += 1
		var from: Vector2 = item["from"]
		var to: Vector2 = item["to"]
		var along: Vector2 = (to - from).normalized()
		var a: Vector2 = from - along * _reach(along)
		var b: Vector2 = to + along * _reach(along)
		for end: Vector2 in [a, b]:
			var centre: Vector2 = (end / CELL).floor() * CELL + Vector2.ONE * CELL * 0.5
			assert_almost_eq(end.distance_to(centre), 0.0, 0.01, "a rail runs from a post centre")
		for quad: PackedVector2Array in ArenaDressing.rail_quads(item, bay):
			assert_almost_eq(quad[3].y - quad[0].y, -bay.y, 0.01)
			assert_almost_eq(quad[0].x, quad[3].x, 0.01, "vertical plane")
			assert_almost_eq(_cross(IsoProjection.to_screen(a), IsoProjection.to_screen(b), quad[0]), 0.0, 0.5)
	assert_gt(rails, 50)


func _reach(along: Vector2) -> float:
	var diagonal: bool = absf(along.x) > 0.01 and absf(along.y) > 0.01
	return ArenaDressing.POST_HALF_PX * (sqrt(2.0) if diagonal else 1.0)


## Distance (px) of `point` from the line through `a` and `b`.
func _cross(a: Vector2, b: Vector2, point: Vector2) -> float:
	return (b - a).normalized().cross(point - a)


## REF-029: a post reaches the chest of the hero, the rail the waist, a heap of ruin stays low; the
## post's square base lies on the 2:1 floor and covers about 0.4 of a cell diamond. A base seen
## from the front (the slope of the first guardian sheet) fails the same measure.
func test_balustrade_heights_and_post_base() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var hero: float = RunView.HERO_SPRITE_HEIGHT_PX
	var asset: String = ArenaDressing.BALUSTRADE_ASSET
	assert_between(sprites.prop_size(asset, "post").y / hero, 0.7, 0.9, "post")
	assert_between(sprites.prop_size(asset, "rail").y / hero, 0.45, 0.55, "rail")
	assert_lt(sprites.prop_size(asset, "post_broken").y, sprites.prop_size(asset, "rail").y, "broken below the rail")
	assert_between(sprites.prop_size(asset, "rubble").y / hero, 0.35, 0.55, "rubble")
	var entry: Dictionary = _manifest_entry(asset)
	var image: Image = _atlas_image(entry)
	var cell_diamond: float = IsoProjection.to_screen(Vector2(CELL, 0)).x * 2.0
	for prop: Dictionary in entry["layout"]["props"]:
		if not (prop["name"] as String).begins_with("post"):
			continue
		var region: Array = prop["region"]
		var base: Array = _base_of(image, Rect2i(region[0], region[1], region[2], region[3]))
		assert_almost_eq(base[0], 0.5, 0.06, "%s left edge" % prop["name"])
		assert_almost_eq(base[1], -0.5, 0.06, "%s right edge" % prop["name"])
		assert_between(base[2] / float(entry["layout"]["density"]) / cell_diamond, 0.32, 0.5, prop["name"])
	var front: Image = Image.create_empty(120, 80, false, Image.FORMAT_RGBA8)
	for x: int in 120:
		var low: int = 70 - roundi(absf(x - 60) * (0.26 if x < 60 else 0.5))
		for y: int in range(10, low + 1):
			front.set_pixel(x, y, Color.WHITE)
	var wrong: Array = _base_of(front, Rect2i(0, 0, 120, 80))
	assert_gt(absf(wrong[0] - 0.5), 0.06, "a front-view base fails")


## Placeholder blocks without the balustrade atlas: one on every low wall cell, one on every solid
## cell that no named prop stands on, tall for solid and low for low walls; none on walkable cells.
func test_blocks_cover_the_walls_without_props() -> void:
	var rows: Array = _data()["rows"]
	var low: int = 0
	for row: String in rows:
		low += row.count(ArenaDressing.LOW_CHAR)
	var blocks: Dictionary = {}
	for item: Dictionary in ArenaDressing.placements(SpriteSet.new(), _data(), CELL):
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
