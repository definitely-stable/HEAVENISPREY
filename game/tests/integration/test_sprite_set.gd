extends GutTest
## ADR-013 (ART-01): SpriteSet reads the asset manifest, every listed texture imports with the
## manifest size, frame regions follow the atlas layout, and the run scene maps its enemy
## kinds to sprites. The digest is not touched: drawing reads simulation state only.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const IDS: Array[String] = [
	"asset.char.hero_sword", "asset.enemy.blood_wolf", "asset.enemy.cursed_spirit_lantern",
	"asset.enemy.fallen_sword_disciple", "asset.enemy.paper_puppet", "asset.enemy.sickle_mantis",
	"asset.enemy.venom_spirit_snake", "asset.enemy.wandering_spirit", "asset.enemy.yin_corpse",
	"asset.prop.cliff_growth", "asset.prop.courtyard_balustrade", "asset.prop.courtyard_guardians",
	"asset.prop.courtyard_lights",
	"asset.prop.courtyard_nature", "asset.prop.courtyard_ring", "asset.prop.courtyard_walls",
	"asset.prop.distant_peaks", "asset.prop.jade_grove_fence_modules", "asset.prop.jade_grove_masonry",
	"asset.prop.jade_grove_rail_details",
	"asset.prop.jade_grove_rail_finishes", "asset.prop.seal_ruins",
	"asset.tile.sect_cliff", "asset.tile.sect_courtyard_floor",
	"asset.tile.sect_courtyard_floor_worn", "asset.tile.sect_seal",
]
const FLOOR: String = "asset.tile.sect_courtyard_floor"
## Enemies with sprites (ADR-014 A5, A5c, A5d, section 27); the spirit's robe and the puppet's
## frame collapse into a heap where they stood instead of falling forward.
const HORDE: Array[String] = [
	"asset.enemy.yin_corpse", "asset.enemy.blood_wolf", "asset.enemy.wandering_spirit",
	"asset.enemy.venom_spirit_snake", "asset.enemy.sickle_mantis", "asset.enemy.fallen_sword_disciple",
	"asset.enemy.cursed_spirit_lantern", "asset.enemy.paper_puppet",
]
const HEAPS: Array[String] = ["asset.enemy.wandering_spirit", "asset.enemy.paper_puppet"]
## Kinds that never strike while alive (the puppet's seal opens after its death): no attack clip.
const UNARMED: Array[String] = ["asset.enemy.paper_puppet"]


func test_manifest_textures_load_with_their_size() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	var listed: Array = []
	for entry: Dictionary in manifest["assets"]:
		if entry["kind"] in ["ui_atlas", "vfx_atlas"]:
			continue  # Drawn through HudKit (test_run_hud.gd, test_combat_vfx.gd), not a scene sprite.
		listed.append(entry["asset_id"])
		assert_true(sprites.has(entry["asset_id"]), entry["asset_id"])
		var texture: Texture2D = sprites.texture(entry["asset_id"])
		var size: Array = entry["size"]
		assert_eq([texture.get_width(), texture.get_height()], [int(size[0]), int(size[1])], entry["asset_id"])
	assert_eq(listed, IDS)


## ADR-014 section 4: every asset is drawn through a CanvasTexture with its normal map.
func test_every_asset_has_a_normal_map_of_its_size() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for asset_id: String in IDS:
		assert_true(sprites.has_normals(asset_id), asset_id)
		var canvas: CanvasTexture = sprites.canvas_texture(asset_id) as CanvasTexture
		assert_not_null(canvas, asset_id)
		assert_eq(canvas.normal_texture.get_size(), canvas.diffuse_texture.get_size(), asset_id)
	assert_false(sprites.has_normals("asset.enemy.unknown"))
	assert_null(sprites.canvas_texture("asset.enemy.unknown"))


## Sprite atlases share one texture (skyline packed, never overlapping), so a mixed horde is
## one batch.
func test_sprite_atlases_are_packed_into_one_texture() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var shared: Texture2D = sprites.canvas_texture("asset.char.hero_sword")
	var placed: Array[Rect2] = []
	for asset_id: String in [
		"asset.char.hero_sword", "asset.enemy.blood_wolf", "asset.enemy.yin_corpse",
		"asset.prop.courtyard_guardians", "asset.prop.courtyard_lights", "asset.prop.courtyard_nature",
		"asset.prop.courtyard_ring", "asset.prop.courtyard_walls", "asset.prop.distant_peaks",
	]:
		assert_eq(sprites.canvas_texture(asset_id), shared, asset_id)
		var origin: Vector2 = sprites.atlas_origin(asset_id)
		var rect: Rect2 = Rect2(origin, sprites.texture(asset_id).get_size())
		for other: Rect2 in placed:
			assert_false(rect.grow(SpriteSet.PACK_GAP_PX * 0.5 - 0.5).intersects(other), asset_id + " overlaps")
		placed.append(rect)
		var packed: Image = (shared as CanvasTexture).diffuse_texture.get_image()
		var own: Image = sprites.texture(asset_id).get_image()
		var probe: Vector2i = Vector2i(96, 120)
		assert_eq(packed.get_pixelv(Vector2i(origin) + probe), own.get_pixelv(probe), asset_id + " pixels are copied")
	assert_ne(sprites.canvas_texture(FLOOR), shared, "the floor repeats on its own texture")
	assert_eq(sprites.atlas_origin(FLOOR), Vector2.ZERO)


func test_frame_regions_follow_the_layout() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	assert_eq(sprites.frame_region("asset.enemy.unknown", "left", 0), Rect2())
	assert_eq(sprites.floor_repeat_px(FLOOR, 48), 384.0)
	assert_eq(sprites.floor_repeat_px("asset.tile.sect_courtyard_floor_worn", 48), 480.0,
		"the worn paving repeats with another period")


func test_direction_and_walk_frame() -> void:
	assert_eq(SpriteSet.four_way(Vector2(0, 1)), "down")
	assert_eq(SpriteSet.four_way(Vector2(0, -1)), "up")
	assert_eq(SpriteSet.four_way(Vector2(-1, 0)), "left")
	assert_eq(SpriteSet.four_way(Vector2(0.7, 0.7)), "right", "diagonals use the side views")
	assert_eq(SpriteSet.four_way(Vector2(-0.6, 0.8)), "down")
	assert_eq(SpriteSet.walk_frame(0.0, 0), 0)
	assert_eq(SpriteSet.walk_frame(0.124, 0), 0)
	assert_eq(SpriteSet.walk_frame(0.125, 0), 1, "8 frames per second")
	assert_eq(SpriteSet.walk_frame(0.0, 3), 3, "phase offset")


func test_run_scene_draws_w0_kinds_as_sprites() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("101")
	var sprites: SpriteSet = SpriteSet.load_default()
	assert_eq(view.tuning.enemy_ids.slice(0, 2), PackedStringArray(["enemy.yin_corpse", "enemy.blood_wolf"]))
	for enemy_id: String in view.tuning.enemy_ids.slice(0, 2):
		assert_true(sprites.has(RunView.ENEMY_ASSETS[enemy_id]), enemy_id)
	assert_true(sprites.has(RunView.HERO_ASSET))
	assert_true(sprites.has(RunView.FLOOR_ASSET))
	for frame: int in 120:
		view.advance_frame(1.0 / 60.0, Vector2i(1, 0))
	assert_gt(view.driver.world.tick, 0, "the run advances with sprites drawn")


## ADR-014 slice A3: props are named regions of a prop atlas, drawn at density 2 from their base.
func test_props_are_named_regions_drawn_from_their_base() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var lights: String = "asset.prop.courtyard_lights"
	var names: PackedStringArray = PackedStringArray(["lantern_pagoda", "brazier", "banner", "incense", "lion", "stele"])
	assert_eq(sprites.prop_names(lights), names)
	assert_true(sprites.has_prop(lights, "brazier"))
	assert_false(sprites.has_prop(lights, "gate"), "the gate is on the walls sheet")
	assert_false(sprites.has_prop("asset.enemy.unknown", "brazier"))
	var size: Vector2 = sprites.prop_size(lights, "lantern_pagoda")
	assert_almost_eq(size.y, 118.0, 2.0, "drawn at its passport height")
	assert_eq(sprites.prop_size(lights, "gate"), Vector2.ZERO)
	var canvas: Node2D = Node2D.new()
	add_child_autofree(canvas)
	assert_false(sprites.draw_prop(canvas, lights, "gate", Vector2(10, 10), Color.WHITE), "nothing to draw")


## ADR-014 A3 polish: a prop as a quad for draw_polygon (the distant scenery fades at its base).
func test_prop_quad_follows_scale_and_flip() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var peaks: String = "asset.prop.distant_peaks"
	assert_eq(sprites.prop_names(peaks), PackedStringArray(["spire", "pagoda_rock", "waterfall_rock", "gate_rock"]))
	var size: Vector2 = sprites.prop_size(peaks, "spire")
	var quad: Dictionary = sprites.prop_quad(peaks, "spire", Vector2(100, 200), 0.5)
	var rect: Rect2 = quad["rect"]
	assert_almost_eq(rect.size, size * 0.5, Vector2(0.01, 0.01), "half size")
	assert_between(100.0, rect.position.x, rect.end.x, "the base centre lies under the quad")
	assert_almost_eq(rect.end.y, 200.0, size.y * 0.5 * 0.2, "the base is at its foot")
	var uv: Rect2 = quad["uv"]
	assert_true(uv.position.x >= 0.0 and uv.end.x <= 1.0 and uv.position.y >= 0.0 and uv.end.y <= 1.0, "normalised")
	assert_eq(quad["texture"], sprites.canvas_texture(peaks))
	var mirrored: Rect2 = sprites.prop_quad(peaks, "spire", Vector2(100, 200), 0.5, true)["uv"]
	assert_almost_eq(mirrored.position.x, uv.end.x, 1e-6, "mirrored: u runs right to left")
	assert_almost_eq(mirrored.end.x, uv.position.x, 1e-6)
	assert_true(sprites.prop_quad(peaks, "gate", Vector2.ZERO).is_empty())


func test_floor_decal_and_strip_spans() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	assert_eq(sprites.decal_world_px("asset.tile.sect_seal"), 672.0)
	assert_eq(sprites.decal_world_px("asset.tile.sect_cliff"), 520.0)
	assert_eq(sprites.decal_world_px("asset.tile.unknown"), 0.0)


## ADR-014 A4: the hero is an animated atlas: clips loop or hold, west-facing directions are the
## east-facing rows mirrored, a one-direction clip serves every direction.
func test_hero_clips_loop_hold_and_mirror() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var hero: String = "asset.char.hero_sword"
	for clip: String in ["idle", "run", "attack", "death"]:
		assert_true(sprites.has_clip(hero, clip), clip)
	assert_false(sprites.has_clip(hero, "fly"))
	assert_false(sprites.has_clip("asset.prop.courtyard_lights", "run"), "a prop atlas has no clips")
	var run: float = sprites.clip_length(hero, "run")
	assert_almost_eq(run, 8.0 / 14.0, 1e-6)
	assert_eq(sprites.clip_frame(hero, "run", 0.0), 0)
	assert_eq(sprites.clip_frame(hero, "run", run * 1.5 + 1e-4), 4, "a loop wraps")
	assert_eq(sprites.clip_frame(hero, "attack", 10.0), 5, "a one-shot holds its last frame")
	assert_eq(sprites.clip_frame(hero, "fly", 1.0), 0)
	var east: Array = sprites.clip_region(hero, "run", "e", 2)
	var west: Array = sprites.clip_region(hero, "run", "w", 2)
	assert_eq(west[0], east[0], "west is east mirrored")
	assert_true(west[1])
	assert_false(east[1])
	assert_ne(sprites.clip_region(hero, "run", "se", 2)[0], east[0])
	var south: Array = sprites.clip_region(hero, "death", "s", 3)
	for direction: String in SpriteSet.EIGHT_WAY:
		assert_eq(sprites.clip_region(hero, "death", direction, 3), [south[0], false], direction)
	assert_eq(sprites.clip_region(hero, "fly", "s", 0)[0], Rect2())


func test_eight_way_screen_directions() -> void:
	var expected: Dictionary = {
		Vector2(1, 0): "e", Vector2(1, 1): "se", Vector2(0, 1): "s", Vector2(-1, 1): "sw",
		Vector2(-1, 0): "w", Vector2(-1, -1): "nw", Vector2(0, -1): "n", Vector2(1, -1): "ne",
		Vector2(1, 0.3): "e", Vector2(0.3, 1): "s", Vector2.ZERO: "s",
	}
	for facing: Vector2 in expected:
		assert_eq(SpriteSet.eight_way(facing), expected[facing], str(facing))


func test_skyline_packing_stays_inside_and_apart() -> void:
	var sizes: Array[Vector2i] = [
		Vector2i(300, 400), Vector2i(500, 100), Vector2i(200, 200), Vector2i(700, 50), Vector2i(100, 300),
		Vector2i(256, 256), Vector2i(1000, 120),
	]
	var places: Array[Vector2i] = SpriteSet.skyline_pack(sizes, 1000)
	assert_eq(places.size(), sizes.size())
	for index: int in sizes.size():
		var rect: Rect2i = Rect2i(places[index], sizes[index])
		assert_true(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1000, str(rect))
		for other: int in index:
			assert_false(rect.intersects(Rect2i(places[other], sizes[other])), "%d overlaps %d" % [index, other])
	assert_eq(places[0], Vector2i.ZERO)
	assert_eq(places[1], Vector2i(300, 0), "the next rect rests beside the first")


## ADR-014 A5: the horde walks and strikes in four diagonals, SE and NE drawn, SW and NW mirrored.
func test_horde_walks_and_strikes_in_four_diagonals() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	for enemy: String in HORDE:
		for clip: String in ["walk", "attack"]:
			if enemy in UNARMED and clip == "attack":
				assert_false(sprites.has_clip(enemy, clip), enemy + " strikes only after death")
				continue
			assert_true(sprites.has_clip(enemy, clip), enemy + " " + clip)
			assert_eq(sprites.clip_frames(enemy, clip), 6)
			var se: Array = sprites.clip_region(enemy, clip, "se", 1)
			var ne: Array = sprites.clip_region(enemy, clip, "ne", 1)
			assert_ne(se[0], ne[0], "two drawn diagonals")
			assert_eq(sprites.clip_region(enemy, clip, "sw", 1), [se[0], true], "sw mirrors se")
			assert_eq(sprites.clip_region(enemy, clip, "nw", 1), [ne[0], true], "nw mirrors ne")
	assert_eq(sprites.clip_frames("asset.enemy.yin_corpse", "fly"), 0)
	assert_eq(SpriteSet.diagonal(Vector2i(1, 1)), "se")
	assert_eq(SpriteSet.diagonal(Vector2i(-1, 1)), "sw")
	assert_eq(SpriteSet.diagonal(Vector2i(1, -1)), "ne")
	assert_eq(SpriteSet.diagonal(Vector2i(-1, -1)), "nw")


## ADR-014 A5b: an enemy recoils and falls in one-shot clips (REF-010, REF-034); the fall ends
## lying on the ground line and reaches forward, its back where the standing body stood.
func test_horde_recoils_and_falls_forward_onto_the_ground() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	for enemy: String in HORDE:
		for clip: String in ["hit", "death"]:
			assert_eq(sprites.clip_frames(enemy, clip), 6, enemy + " " + clip)
			assert_eq(sprites.clip_frame(enemy, clip, 10.0), 5, "a one-shot holds its last frame")
			assert_eq(sprites.clip_region(enemy, clip, "sw", 1)[1], true, "sw mirrors se")
		var layout: Dictionary = {}
		for entry: Dictionary in manifest["assets"]:
			if entry["asset_id"] == enemy:
				layout = entry["layout"]
		var frame: int = int(layout["frame_size"])
		var anchor: Vector2i = Vector2i(int(layout["feet_anchor"][0]), int(layout["feet_anchor"][1]))
		var image: Image = sprites.texture(enemy).get_image()
		if image.is_compressed():
			image.decompress()
		var row: int = int(layout["clips"]["death"]["row"])
		for offset: int in 2:
			var standing: Rect2i = _extent(image, Rect2i(0, (row + offset) * frame, frame, frame))
			var lying: Rect2i = _extent(image, Rect2i(5 * frame, (row + offset) * frame, frame, frame))
			var label: String = "%s death row %d" % [enemy, offset]
			assert_almost_eq(float(lying.end.y), float(anchor.y), 3.0, label + ": lies on the ground line")
			assert_lt(lying.size.y, standing.size.y * 0.6, label + ": lies down")
			if enemy in HEAPS:
				continue
			assert_gt(lying.end.x - anchor.x, standing.end.x - anchor.x, label + ": falls forward")
			assert_lt(absi(lying.position.x - standing.position.x), frame / 6, label + ": its back stays")


## Bounding box (cell px) of the solid pixels of a cell.
static func _extent(image: Image, cell: Rect2i) -> Rect2i:
	var low: Vector2i = cell.size
	var high: Vector2i = Vector2i(-1, -1)
	for y: int in cell.size.y:
		for x: int in cell.size.x:
			if image.get_pixel(cell.position.x + x, cell.position.y + y).a8 > 200:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	return Rect2i(low, high - low + Vector2i.ONE)


## ADR-014 section 19: the horde at the height of its boards, measured on the atlases as the
## build measures it (lowest solid pixel to the first row 12 % as wide as the widest): the Yin
## Corpse nearly as tall as the hero (REF-044), the wolf at the hero's chest (REF-034).
func test_horde_stands_at_the_height_of_its_boards() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	var hero: float = _clip_height(sprites, manifest, "asset.char.hero_sword", "idle")
	assert_gt(hero, 0.0)
	var corpse: float = _clip_height(sprites, manifest, "asset.enemy.yin_corpse", "walk") / hero
	var wolf: float = _clip_height(sprites, manifest, "asset.enemy.blood_wolf", "walk") / hero
	assert_between(corpse, 0.9, 1.0, "Yin Corpse / hero")
	assert_between(wolf, 0.6, 0.75, "wolf / hero")
	# A5c, no boards: the spirit a little shorter than the corpse, the raised snake below the wolf.
	var spirit: float = _clip_height(sprites, manifest, "asset.enemy.wandering_spirit", "walk") / hero
	var snake: float = _clip_height(sprites, manifest, "asset.enemy.venom_spirit_snake", "walk") / hero
	assert_between(spirit, 0.82, corpse, "spirit / hero")
	assert_between(snake, 0.5, wolf, "snake / hero")
	# A5d: the disciple stands upright about as tall as the hero, the mantis below the wolf's back.
	var disciple: float = _clip_height(sprites, manifest, "asset.enemy.fallen_sword_disciple", "walk") / hero
	var mantis: float = _clip_height(sprites, manifest, "asset.enemy.sickle_mantis", "walk") / hero
	assert_between(disciple, corpse, 1.05, "disciple / hero")
	assert_between(mantis, 0.5, wolf, "mantis / hero")
	# Section 27: the lantern from its ring to its tassel at three quarters of the corpse, the
	# puppet a little shorter than the corpse.
	var lantern: float = _clip_height(sprites, manifest, "asset.enemy.cursed_spirit_lantern", "walk") / hero
	var puppet: float = _clip_height(sprites, manifest, "asset.enemy.paper_puppet", "walk") / hero
	assert_between(lantern, 0.65, 0.78, "lantern / hero")
	assert_between(puppet, 0.82, corpse, "puppet / hero")


## ADR-014 section 27: an enemy shot leaves the lantern's eye. The pale eye of the walk SE frames
## stands, above the feet and lifted by the hover, at the height the shots fly.
func test_lantern_shots_leave_its_eye() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var image: Image = sprites.texture("asset.enemy.cursed_spirit_lantern").get_image()
	if image.is_compressed():
		image.decompress()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpriteSet.MANIFEST_PATH))
	var layout: Dictionary = {}
	for entry: Dictionary in manifest["assets"]:
		if entry["asset_id"] == "asset.enemy.cursed_spirit_lantern":
			layout = entry["layout"]
	var frame: int = int(layout["frame_size"])
	var row: int = int(layout["clips"]["walk"]["row"])
	var total: float = 0.0
	var count: int = 0
	for column: int in 6:
		for y: int in frame:
			for x: int in frame:
				var pixel: Color = image.get_pixel(column * frame + x, row * frame + y)
				if pixel.a8 > 200 and pixel.r8 > 200 and pixel.g8 > 190 and pixel.b8 > 180:
					total += y
					count += 1
	assert_gt(count, 60, "the pale eye shows in the walk frames")
	var eye: float = (float(layout["feet_anchor"][1]) - total / count) / SpriteSet.DENSITY
	var lift: float = float(EnemyMotion.HOVER["asset.enemy.cursed_spirit_lantern"][0])
	assert_almost_eq(RunView.SHOT_LIFT_PX, lift + eye, 4.0, "the shot flies at the height of the eye")
	assert_gt(RunView.SHOT_LIFT_PX, RunView.FLIGHT_LIFT_PX, "above the hero's swords")


## Median body height (atlas px) of a clip over its frames and generated directions.
static func _clip_height(sprites: SpriteSet, manifest: Dictionary, asset_id: String, clip: String) -> float:
	var layout: Dictionary = {}
	for entry: Dictionary in manifest["assets"]:
		if entry["asset_id"] == asset_id:
			layout = entry["layout"]
	var frame: int = int(layout["frame_size"])
	var info: Dictionary = layout["clips"][clip]
	var image: Image = sprites.texture(asset_id).get_image()
	if image.is_compressed():
		image.decompress()
	var heights: Array[float] = []
	for offset: int in (info["directions"] as Array).size():
		for index: int in int(info["frames"]):
			heights.append(_body_height(image, Rect2i(index * frame, (int(info["row"]) + offset) * frame, frame, frame)))
	heights.sort()
	return heights[heights.size() / 2]


static func _body_height(image: Image, cell: Rect2i) -> float:
	var widths: Array[int] = []
	var widest: int = 0
	for y: int in cell.size.y:
		var width: int = 0
		for x: int in cell.size.x:
			if image.get_pixel(cell.position.x + x, cell.position.y + y).a8 > 200:
				width += 1
		widths.append(width)
		widest = maxi(widest, width)
	var top: int = -1
	var bottom: int = -1
	for y: int in widths.size():
		if top < 0 and widths[y] >= widest * 0.12:
			top = y
		if widths[y] > 0:
			bottom = y
	return 0.0 if top < 0 else float(bottom + 1 - top)
