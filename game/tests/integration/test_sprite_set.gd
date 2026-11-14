extends GutTest
## ADR-013 (ART-01): SpriteSet reads the asset manifest, every listed texture imports with the
## manifest size, frame regions follow the atlas layout, and the run scene maps its enemy
## kinds to sprites. The digest is not touched: drawing reads simulation state only.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const IDS: Array[String] = [
	"asset.char.hero_sword", "asset.enemy.blood_wolf", "asset.enemy.yin_corpse", "asset.tile.jade_grove_floor",
]


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


func test_frame_regions_follow_the_layout() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	assert_eq(sprites.directions("asset.char.hero_sword"), PackedStringArray(["down", "left", "right", "up"]))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "down", 0), Rect2(0, 0, 192, 192))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "up", 3), Rect2(576, 576, 192, 192))
	assert_eq(sprites.frame_region("asset.char.hero_sword", "left", 5), Rect2(192, 192, 192, 192), "frames wrap")
	assert_eq(sprites.frame_region("asset.enemy.blood_wolf", "right", -1), Rect2(576, 192, 192, 192))
	assert_eq(sprites.frame_region("asset.enemy.blood_wolf", "down", 0), Rect2(), "no such direction")
	assert_eq(sprites.frame_region("asset.enemy.unknown", "left", 0), Rect2())
	assert_eq(sprites.floor_repeat_px("asset.tile.jade_grove_floor", 48), 384.0)


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
