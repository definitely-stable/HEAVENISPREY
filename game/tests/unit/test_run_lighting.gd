extends GutTest
## ADR-014 sections 4-5: the lighting model of the run scene. Presentation only.

const CELL: int = 48
const ARENA: Vector2 = Vector2(32 * 48, 20 * 48)


func test_falloff_is_linear_and_clamped() -> void:
	assert_eq(RunLighting.falloff(0.0, 200.0), 1.0)
	assert_almost_eq(RunLighting.falloff(50.0, 200.0), 0.75, 1e-6)
	assert_eq(RunLighting.falloff(200.0, 200.0), 0.0)
	assert_eq(RunLighting.falloff(500.0, 200.0), 0.0)


func test_upright_light_grows_towards_a_lantern() -> void:
	var lanterns: Array[Vector2] = [Vector2(5.5, 4.5) * CELL, Vector2(26.5, 15.5) * CELL]
	var far_hero: Vector2 = Vector2(-10000, -10000)
	var base: Color = RunLighting.light_at(ARENA * 0.5, far_hero, lanterns)
	assert_eq(base, Color(RunLighting.AMBIENT + RunLighting.MOON_COLOR * RunLighting.MOON_FLAT, 1.0),
		"away from every point light only ambient and the flat moon remain")
	var last: float = base.r
	for step: int in range(8, -1, -1):
		var at: Vector2 = lanterns[0] + Vector2(step * 30.0, 0.0)
		var light: Color = RunLighting.light_at(at, far_hero, lanterns)
		assert_gt(light.r, last - 1e-6, "closer is not darker (%d)" % step)
		last = light.r
	var peak: float = RunLighting.LANTERN_COLOR.r * RunLighting.LANTERN_ENERGY * RunLighting.UPRIGHT_SHARE
	assert_almost_eq(last - base.r, peak, 1e-4)
	assert_eq(RunLighting.light_at(ARENA * 0.5, far_hero, lanterns).a, 1.0)


func test_hero_aura_lights_the_hero() -> void:
	var lanterns: Array[Vector2] = []
	var hero: Vector2 = ARENA * 0.5
	var lit: Color = RunLighting.light_at(hero, hero, lanterns)
	var dark: Color = RunLighting.light_at(hero, hero + Vector2(RunLighting.AURA_RADIUS_PX, 0.0), lanterns)
	assert_gt(lit.r, dark.r)
	assert_gt(lit.get_luminance(), dark.get_luminance())


func test_shadows_fall_along_the_moon() -> void:
	var travel: Vector2 = RunLighting.moon_travel()
	assert_almost_eq(travel.length(), 1.0, 1e-6)
	assert_gt(travel.x, 0.0, "shadows fall to the right")
	assert_gt(travel.y, 0.0, "and down the screen")
	var feet: Vector2 = Vector2(100, 200)
	var shadow: Transform2D = RunLighting.shadow_transform(feet)
	assert_eq(shadow * Vector2.ZERO, feet, "the shadow starts at the feet")
	var head: Vector2 = shadow * Vector2(0.0, -100.0) - feet
	assert_almost_eq(head.normalized().dot(travel), 1.0, 1e-5, "the head falls along the moon")
	assert_almost_eq(head.y, 100.0 * RunLighting.SHADOW_SQUASH, 1e-4)
	var down_light: Vector2 = Vector2(0.0, 1.0).rotated(RunLighting.moon_rotation())
	assert_almost_eq(down_light.dot(travel), 1.0, 1e-5, "the directional moon shines the same way")
