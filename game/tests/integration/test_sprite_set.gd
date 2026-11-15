extends GutTest
## ADR-013 (ART-01): SpriteSet reads the asset manifest, every listed texture imports with the
## manifest size, frame regions follow the atlas layout, and the run scene maps its enemy
## kinds to sprites. The digest is not touched: drawing reads simulation state only.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const IDS: Array[String] = [
	"asset.char.hero_sword", "asset.enemy.blood_wolf", "asset.enemy.yin_corpse",
	"asset.prop.courtyard_lights", "asset.prop.courtyard_nature", "asset.prop.courtyard_walls",
	"asset.prop.distant_peaks", "asset.tile.sect_cliff", "asset.tile.sect_courtyard_floor",
	"asset.tile.sect_courtyard_floor_worn", "asset.tile.sect_seal",
]
const FLOOR: String = "asset.tile.sect_courtyard_floor"


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
		"asset.prop.courtyard_lights", "asset.prop.courtyard_nature", "asset.prop.courtyard_walls",
		"asset.prop.distant_peaks",
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
	for enemy: String in ["asset.enemy.yin_corpse", "asset.enemy.blood_wolf"]:
		for clip: String in ["walk", "attack"]:
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
