extends GutTest
## ADR-014 section 4: the lit ground layer of the run scene. Presentation only.

const CELL: int = 48
const ARENA: Vector2 = Vector2(32 * 48, 20 * 48)
const FLOOR: String = "asset.tile.jade_grove_floor"


func _ground(sprites: SpriteSet, floor_asset: String) -> GroundLayer:
	var ground: GroundLayer = GroundLayer.new(sprites, floor_asset, ARENA, CELL)
	add_child_autofree(ground)
	return ground


func test_floor_chunks_cover_the_arena_and_apron() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR)
	var tile: float = sprites.floor_repeat_px(FLOOR, CELL)
	var span: Vector2 = ARENA + Vector2.ONE * 2.0 * GroundLayer.APRON_CELLS * CELL
	assert_eq(ground.floor_chunks, ceili(span.x / tile) * ceili(span.y / tile))
	var covered: Rect2 = Rect2()
	for chunk: Sprite2D in ground.find_children("*", "Sprite2D", true, false):
		assert_true(chunk.texture is CanvasTexture, "chunks carry the normal map")
		var rect: Rect2 = Rect2(chunk.position, chunk.region_rect.size * chunk.scale)
		covered = rect if covered.size == Vector2.ZERO else covered.merge(rect)
	assert_eq(covered, Rect2(-Vector2.ONE * GroundLayer.APRON_CELLS * CELL, span))


func test_without_a_floor_texture_one_flat_polygon() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	assert_eq(ground.floor_chunks, 1)
	assert_eq(ground.find_children("*", "Sprite2D", true, false).size(), 0)


func test_lights_reach_the_ground_layer_only() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	assert_eq(ground.layer, GroundLayer.LAYER)
	assert_eq(ground.lights.size(), 1 + RunLighting.LANTERN_CELLS.size() + 1, "moon, lanterns, aura")
	for light: Light2D in ground.lights:
		assert_eq([light.range_layer_min, light.range_layer_max], [GroundLayer.LAYER, GroundLayer.LAYER],
			"a light reaches only its own canvas layer")
	var lanterns: Array[Vector2] = RunLighting.lantern_positions(CELL)
	for index: int in lanterns.size():
		var light: Light2D = ground.lights[1 + index]
		assert_eq(light.position, IsoProjection.to_screen(lanterns[index]))
		assert_eq(light.scale, Vector2(1.0, 0.5), "a world circle is a 2:1 ellipse on screen")


func test_aura_follows_the_hero() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	ground.follow(Vector2(300, 200))
	assert_almost_eq(ground.aura_position().distance_to(Vector2(300, 200)), 0.0, 0.01)
