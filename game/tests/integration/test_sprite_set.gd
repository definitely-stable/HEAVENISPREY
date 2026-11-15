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


## Sprite atlases share one texture, side by side, so a mixed horde is one batch.
func test_sprite_atlases_are_packed_into_one_texture() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var shared: Texture2D = sprites.canvas_texture("asset.char.hero_sword")
	var right: float = -1.0
	for asset_id: String in [
		"asset.char.hero_sword", "asset.enemy.blood_wolf", "asset.enemy.yin_corpse",
		"asset.prop.courtyard_lights", "asset.prop.courtyard_nature", "asset.prop.courtyard_walls",
		"asset.prop.distant_peaks",
	]:
		assert_eq(sprites.canvas_texture(asset_id), shared, asset_id)
		var origin: Vector2 = sprites.atlas_origin(asset_id)
		assert_gt(origin.x, right, asset_id + " does not overlap the atlas before it")
		right = origin.x + sprites.texture(asset_id).get_width() + SpriteSet.PACK_GAP_PX - 1
		var packed: Image = (shared as CanvasTexture).diffuse_texture.get_image()
		var own: Image = sprites.texture(asset_id).get_image()
		var probe: Vector2i = Vector2i(96, 120)
		assert_eq(packed.get_pixelv(Vector2i(origin) + probe), own.get_pixelv(probe), asset_id + " pixels are copied")
	assert_ne(sprites.canvas_texture(FLOOR), shared, "the floor repeats on its own texture")
	assert_eq(sprites.atlas_origin(FLOOR), Vector2.ZERO)


func test_frame_regions_follow_the_layout() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	assert_eq(sprites.directions("asset.char.hero_sword"), PackedStringArray(["down", "left", "right", "up"]))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "down", 0), Rect2(0, 0, 192, 192))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "up", 3), Rect2(576, 576, 192, 192))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "left", 5), Rect2(192, 192, 192, 192), "frames wrap")
	assert_eq(sprites.frame_region("asset.enemy.blood_wolf", "right", -1), Rect2(576, 192, 192, 192))
	assert_eq(sprites.frame_region("asset.enemy.blood_wolf", "down", 0), Rect2(), "no such direction")
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
