extends GutTest
## ADR-014 slice A3, ADR-015 A1: the things that stand in arena 07. Presentation only.

const CELL: int = 48
## The ring of ruin fragments the seal_ruins sheets were painted for (ADR-015 section 11); since
## section 12 the court is open and the atlas waits in reserve, checked against this grid.
const RING_LAYOUT: String = "res://tests/fixtures/seal_ring_layout.json"


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
	assert_eq(named, (_data()["props"] as Array).size(), "every prop has a sprite")


func test_every_prop_of_the_file_has_its_sprites() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for item: Dictionary in _data()["props"]:
		var prop: String = item["prop"]
		if prop == ArenaDressing.RUIN_PROP:
			continue
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


func _ring_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(RING_LAYOUT))


## The seal_ruin props of the ring layout: [{index, at (cells), cells}].
func _ruins() -> Array[Dictionary]:
	var data: Dictionary = _ring_data()
	var centre: Vector2i = Vector2i(int(data["centre"][0]), int(data["centre"][1]))
	var out: Array[Dictionary] = []
	for item: Dictionary in data["props"]:
		if item["prop"] == ArenaDressing.RUIN_PROP:
			var at: Vector2 = Vector2(float(item["at"][0]), float(item["at"][1]))
			out.append({
				"index": ArenaDressing.ruin_index(at, centre), "at": at,
				"cells": ArenaDressing.ruin_cells(data["rows"], at),
			})
	return out


## Every cell of the six ruin fragments.
func _ruin_cells() -> Dictionary:
	var out: Dictionary = {}
	for ruin: Dictionary in _ruins():
		for cell: Vector2i in ruin["cells"]:
			out[cell] = ruin["index"]
	return out


## ADR-015 section 10: the low wall cells are a balustrade (since section 12 the seal ring holds
## no ruins). Every cell of a line is a post or lies on a rail bay between two posts of its run;
## no low wall is left as a placeholder block.
func test_balustrade_covers_every_low_wall_cell() -> void:
	var rows: Array = _data()["rows"]
	var ruined: Dictionary = {}
	var wall: Dictionary = ArenaDressing.balustrade(rows, ruined)
	var covered: Dictionary = {}
	for cell: Vector2i in wall["posts"]:
		covered[cell] = "post"
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
			if (rows[y] as String)[x] == ArenaDressing.LOW_CHAR and not ruined.has(Vector2i(x, y)):
				low += 1
				assert_true(covered.has(Vector2i(x, y)), "low wall %s is drawn" % Vector2i(x, y))
	assert_eq(covered.size(), low, "nothing outside the low walls, nothing on the ruins")
	for item: Dictionary in _items():
		if item["prop"] == ArenaDressing.BLOCK_PROP:
			assert_ne(_char_at(item["at"]), ArenaDressing.LOW_CHAR, "no placeholder block on a low wall")


## A staircase of low walls on the grid is one straight run on the screen, not a zigzag: a
## diagonal neighbour is linked only when no axis neighbour joins the two cells.
func test_staircase_is_one_run() -> void:
	var stairs: Array = ["w   ", " w  ", "  w ", "   w"]
	var wall: Dictionary = ArenaDressing.balustrade(stairs)
	assert_eq(wall["posts"], [Vector2i(0, 0), Vector2i(2, 2), Vector2i(3, 3)], "every second cell, and the end")
	assert_eq(wall["rails"], [], "straight up the screen: a stone cap instead of a rail face")
	assert_eq(wall["edge_on"], [[Vector2i(0, 0), Vector2i(2, 2)], [Vector2i(2, 2), Vector2i(3, 3)]])
	var flat: Dictionary = ArenaDressing.balustrade(["   w", "  w ", " w  ", "w   "])
	assert_eq((flat["rails"] as Array).size(), 3, "flat across the screen: a bay between every post")
	var axis: Dictionary = ArenaDressing.balustrade(["wwwww"])
	assert_eq(axis["posts"], [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)], "every second cell along an axis")
	assert_eq(axis["broken"], [Vector2i(0, 0), Vector2i(4, 0)], "the dead ends are broken posts")
	var corner: Dictionary = ArenaDressing.balustrade(["ww", "w "])
	assert_eq((corner["rails"] as Array).size(), 2, "an L joins through its corner, no diagonal")


## ADR-015 section 11: the ring of ruins around the seal is six painted fragments, each on all
## its low and solid cells (a broken wall between two pillar stumps) and each its own picture;
## nothing else (no post, rail or block) stands on those cells.
func test_ruin_ring_is_six_painted_fragments() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var rows: Array = _ring_data()["rows"]
	var ruins: Array[Dictionary] = _ruins()
	assert_eq(ruins.size(), 6)
	var indices: Dictionary = {}
	for ruin: Dictionary in ruins:
		indices[ruin["index"]] = true
		assert_true(sprites.has_prop(ArenaDressing.RUINS_ASSET, "ruin_%d" % ruin["index"]), str(ruin["index"]))
		var codes: Dictionary = {}
		for cell: Vector2i in ruin["cells"]:
			codes[(rows[cell.y] as String)[cell.x]] = true
		assert_eq(codes.keys().size(), 2, "low wall and pillar cells")
		assert_between((ruin["cells"] as Array).size(), 10, 16)
	assert_eq(indices.keys().size(), 6, "six different fragments")
	var ruined: Dictionary = _ruin_cells()
	var centre: Vector2 = Vector2(float(_ring_data()["centre"][0]), float(_ring_data()["centre"][1]))
	for y: int in rows.size():
		for x: int in (rows[y] as String).length():
			var code: String = (rows[y] as String)[x]
			var ring: float = Vector2(x, y).distance_to(centre)
			if (code == ArenaDressing.LOW_CHAR or code == ArenaDressing.SOLID_CHAR) and ring > 9.5 and ring < 12.3:
				assert_true(ruined.has(Vector2i(x, y)), "ring cell %s belongs to a fragment" % Vector2i(x, y))
	var strips: int = 0
	for item: Dictionary in ArenaDressing.placements(sprites, _ring_data(), CELL):
		if item.has("clip"):
			strips += 1
			continue
		var cell: Vector2i = Vector2i((item["at"] / CELL).floor())
		if item["prop"] == ArenaDressing.RAIL_PROP:
			cell = Vector2i(-1, -1)
		assert_false(ruined.has(cell), "%s stands on a ruin cell %s" % [item["prop"], cell])
	assert_gt(strips, 6 * 4)


## A fragment is drawn in strips half a cell wide on the screen, edge to edge; each sorts at the
## nearest cell under it, so a body in front of that cell is drawn over the strip and a body
## behind it under the strip.
func test_ruin_strips_sort_at_their_nearest_cell() -> void:
	var half: float = IsoProjection.to_screen(Vector2(CELL, 0)).x
	for ruin: Dictionary in _ruins():
		var strips: Array[Dictionary] = ArenaDressing.ruin_strips(ruin["cells"], CELL)
		assert_eq((strips[0]["clip"] as Vector2).x, -INF)
		assert_eq((strips[-1]["clip"] as Vector2).y, INF)
		for i: int in strips.size():
			var clip: Vector2 = strips[i]["clip"]
			if i > 0:
				assert_eq(clip.x, (strips[i - 1]["clip"] as Vector2).y, "strips meet")
			if i > 0 and i < strips.size() - 1:
				assert_almost_eq(clip.y - clip.x, half, 0.001)
			var m: int = roundi(clip.x / half) if i > 0 else roundi(clip.y / half) - 1
			var front: Vector2i = strips[i]["front"]
			for cell: Vector2i in ruin["cells"]:
				if cell.x - cell.y == m or cell.x - cell.y == m + 1:
					assert_true(cell.x + cell.y <= front.x + front.y, "%s is the nearest" % front)
			var strip: float = IsoProjection.depth((Vector2(front) + Vector2(0.5, 0.5)) * CELL)
			var ahead: float = IsoProjection.depth((Vector2(front) + Vector2(1.3, 1.3)) * CELL)
			var behind: float = IsoProjection.depth((Vector2(front) + Vector2(-0.3, -0.3)) * CELL)
			assert_true(ahead > strip and behind < strip)


## A fragment stands on its cells, it does not float: the lowest painted stones of the sprite end
## on the nearest corner of its cells, its sides at the outer corners of its cells (leaves and
## chips may stick out a little), and its pillars stand about 1.3 hero heights tall.
func test_ruins_stand_on_their_cells() -> void:
	var entry: Dictionary = _manifest_entry(ArenaDressing.RUINS_ASSET)
	var image: Image = _atlas_image(entry)
	var density: float = float(entry["layout"]["density"])
	var regions: Dictionary = {}
	for prop: Dictionary in entry["layout"]["props"]:
		regions[prop["name"]] = prop
	var hero: float = RunView.HERO_SPRITE_HEIGHT_PX
	for ruin: Dictionary in _ruins():
		var prop: Dictionary = regions["ruin_%d" % ruin["index"]]
		var region: Array = prop["region"]
		var feet: Vector2 = Vector2(float(prop["feet"][0]), float(prop["feet"][1]))
		var base: Vector2 = IsoProjection.to_screen(ruin["at"] * CELL)
		var low: float = -INF
		var far: float = INF
		var left: float = INF
		var right: float = -INF
		for cell: Vector2i in ruin["cells"]:
			low = maxf(low, IsoProjection.to_screen(Vector2(cell + Vector2i.ONE) * CELL).y - base.y)
			far = minf(far, IsoProjection.to_screen(Vector2(cell) * CELL).y - base.y)
			left = minf(left, IsoProjection.to_screen(Vector2(cell + Vector2i(0, 1)) * CELL).x - base.x)
			right = maxf(right, IsoProjection.to_screen(Vector2(cell + Vector2i(1, 0)) * CELL).x - base.x)
		var box: Rect2i = image.get_region(Rect2i(region[0], region[1], region[2], region[3])).get_used_rect()
		var painted_low: float = (region[1] + box.end.y - feet.y) / density
		var painted_top: float = (region[1] + box.position.y - feet.y) / density
		var painted_left: float = (region[0] + box.position.x - feet.x) / density
		var painted_right: float = (region[0] + box.end.x - feet.x) / density
		var name: String = "ruin_%d" % ruin["index"]
		assert_almost_eq(painted_low, low, 4.0, "%s rests on its nearest corner" % name)
		assert_almost_eq(painted_left, left, 12.0, "%s left end" % name)
		assert_almost_eq(painted_right, right, 12.0, "%s right end" % name)
		# The pillars (1.3 hero heights) rise over the farthest corner of the cells; the whole ruin
		# with the depth of its cells stays within three hero heights.
		assert_gt((far - painted_top) / hero, 0.75, "%s pillars over its farthest corner" % name)
		assert_lt((low - painted_top) / hero, 3.0, "%s height over its nearest corner" % name)


## Rail bays stand on the line between the post centres and stop at the post faces; the quads of
## a bay are vertical planes on that line, as tall as the rail elevation.
func test_edge_on_coping_joins_only_the_existing_low_wall() -> void:
	var caps: int = 0
	for item: Dictionary in _items():
		if item["prop"] != ArenaDressing.COPING_PROP:
			continue
		caps += 1
		var from: Vector2 = item["from"]
		var to: Vector2 = item["to"]
		assert_almost_eq(IsoProjection.to_screen(from).x, IsoProjection.to_screen(to).x, 0.01)
		var at: Vector2 = from
		while at.x < to.x:
			assert_eq(_char_at(at), ArenaDressing.LOW_CHAR, "cap never covers the walkable floor")
			at += Vector2.ONE * CELL
		assert_eq(_char_at(to), ArenaDressing.LOW_CHAR, "the cap meets the final post")
	assert_gt(caps, 0, "the real arena has visible stone caps")
	var split: Dictionary = ArenaDressing.balustrade(["w  ", " . ", "  w"])
	assert_eq(split["edge_on"], [], "do not bridge a gap")


func test_long_fence_keeps_posts_at_turns_and_runs_continuously() -> void:
	var rows: Array = ["      w", "     w ", "    w  ", "   w   ", "  w    ", " w     ", "w      "]
	var flat: Dictionary = ArenaDressing.balustrade(rows)
	assert_false(flat["posts"].has(Vector2i(2, 4)), "two consecutive bays share the end posts")
	assert_has(flat["rails"], [Vector2i(1, 5), Vector2i(3, 3)])
	rows[5] = " w w   "
	var corner: Dictionary = ArenaDressing.balustrade(rows)
	assert_has(corner["posts"], Vector2i(2, 4), "the turn into the other run keeps its post")


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
		var infill: Vector2 = Vector2(bay.x, bay.y * (1.0 - ArenaDressing.RAIL_STONE_SHARE))
		for quad: PackedVector2Array in ArenaDressing.rail_quads(item, infill, ArenaDressing.COPING_HEIGHT):
			assert_almost_eq(quad[3].y - quad[0].y, -infill.y, 0.01)
			assert_almost_eq(quad[0].x, quad[3].x, 0.01, "vertical plane")
			var on_floor: Vector2 = quad[0] + Vector2(0.0, ArenaDressing.COPING_HEIGHT)
			assert_almost_eq(_cross(IsoProjection.to_screen(a), IsoProjection.to_screen(b), on_floor), 0.0, 0.5)
	assert_gt(rails, 50)


func _reach(along: Vector2) -> float:
	var diagonal: bool = absf(along.x) > 0.01 and absf(along.y) > 0.01
	return ArenaDressing.POST_HALF_PX * (sqrt(2.0) if diagonal else 1.0)


## Distance (px) of `point` from the line through `a` and `b`.
func _cross(a: Vector2, b: Vector2, point: Vector2) -> float:
	return (b - a).normalized().cross(point - a)


## REF-029: a post reaches the chest of the hero, the rail the waist; the
## post's square base lies on the 2:1 floor and covers about 0.4 of a cell diamond. A base seen
## from the front (the slope of the first guardian sheet) fails the same measure.
func test_balustrade_heights_and_post_base() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var hero: float = RunView.HERO_SPRITE_HEIGHT_PX
	var asset: String = ArenaDressing.BALUSTRADE_ASSET
	assert_between(sprites.prop_size(asset, "post").y / hero, 0.7, 0.9, "post")
	assert_between(sprites.prop_size(asset, "rail").y / hero, 0.45, 0.55, "rail")
	assert_lt(sprites.prop_size(asset, "post_broken").y, sprites.prop_size(asset, "rail").y, "broken below the rail")
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
	# The gate hall, the braziers, broken pillars and lanterns are props, not blocks.
	for item: Dictionary in _data()["props"]:
		if item["prop"] == ArenaDressing.RUIN_PROP:
			continue
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
