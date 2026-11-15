extends GutTest
## ADR-014 section 4: the lit ground layer of the run scene. Presentation only.

const CELL: int = 48
const ARENA: Vector2 = Vector2(32 * 48, 20 * 48)
const FLOOR: String = "asset.tile.sect_courtyard_floor"
const SEAL: String = "asset.tile.sect_seal"
const CLIFF: String = "asset.tile.sect_cliff"


func _ground(
	sprites: SpriteSet, floor_asset: String, points: Array[Dictionary] = [], seal: String = "", cliff: String = ""
) -> GroundLayer:
	var ground: GroundLayer = GroundLayer.new(sprites, floor_asset, ARENA, CELL, points, seal, cliff)
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
		if not chunk.region_enabled:
			continue
		assert_true(chunk.texture is CanvasTexture, "chunks carry the normal map")
		var rect: Rect2 = Rect2(chunk.position, chunk.region_rect.size * chunk.scale)
		covered = rect if covered.size == Vector2.ZERO else covered.merge(rect)
	assert_eq(covered, Rect2(-Vector2.ONE * GroundLayer.APRON_CELLS * CELL, span))


func test_without_a_floor_texture_one_flat_polygon() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	assert_eq(ground.floor_chunks, 1)
	assert_eq(ground.find_children("*", "Sprite2D", true, false).size(), 0)


func test_lights_reach_the_ground_layer_only() -> void:
	var points: Array[Dictionary] = [{"at": Vector2(-48, 200), "flame": 70.0}, {"at": Vector2(800, -48), "flame": 50.0}]
	var ground: GroundLayer = _ground(SpriteSet.new(), "none", points)
	assert_eq(ground.layer, GroundLayer.LAYER)
	assert_eq(ground.lights.size(), 1 + points.size() + 1, "moon, lanterns, aura")
	for light: Light2D in ground.lights:
		assert_eq([light.range_layer_min, light.range_layer_max], [GroundLayer.LAYER, GroundLayer.LAYER],
			"a light reaches only its own canvas layer")
	for index: int in points.size():
		var light: Light2D = ground.lights[1 + index]
		assert_eq(light.position, IsoProjection.to_screen(points[index]["at"]))
		assert_eq(light.scale, Vector2(1.0, 0.5), "a world circle is a 2:1 ellipse on screen")


## ADR-014 slice A3: the seal lies at the centre of the arena at its world size; the mist sits on
## its own canvas layer behind the ground.
func test_seal_and_mist() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var ground: GroundLayer = _ground(sprites, FLOOR, [], SEAL, CLIFF)
	var seals: Array = ground.find_children("*", "Sprite2D", true, false).filter(
		func(node: Sprite2D) -> bool: return not node.region_enabled)
	assert_eq(seals.size(), 1)
	var seal: Sprite2D = seals[0]
	assert_eq(seal.position, ARENA * 0.5)
	assert_almost_eq(seal.scale.x * seal.texture.get_width(), sprites.decal_world_px(SEAL), 0.01)
	var mist: Array = ground.find_children("*", "CanvasLayer", true, false)
	assert_eq(mist.size(), 1)
	assert_eq((mist[0] as CanvasLayer).layer, GroundLayer.MIST_LAYER)
	assert_lt(GroundLayer.MIST_LAYER, GroundLayer.LAYER)


func test_aura_follows_the_hero() -> void:
	var ground: GroundLayer = _ground(SpriteSet.new(), "none")
	ground.follow(Vector2(300, 200))
	assert_almost_eq(ground.aura_position().distance_to(Vector2(300, 200)), 0.0, 0.01)
