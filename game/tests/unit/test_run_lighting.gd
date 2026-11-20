extends GutTest
## ADR-014 sections 4-5: the lighting model of the run scene. Presentation only.

const CELL: int = 48
const ARENA: Vector2 = Vector2(32 * 48, 20 * 48)


func _lantern(at: Vector2) -> Dictionary:
	return {"at": at, "radius": RunLighting.LANTERN_RADIUS_PX, "energy": RunLighting.LANTERN_ENERGY,
		"flame_at": IsoProjection.to_screen(at) - Vector2(0.0, 60.0)}


func test_falloff_is_linear_and_clamped() -> void:
	assert_eq(RunLighting.falloff(0.0, 200.0), 1.0)
	assert_almost_eq(RunLighting.falloff(50.0, 200.0), 0.75, 1e-6)
	assert_eq(RunLighting.falloff(200.0, 200.0), 0.0)
	assert_eq(RunLighting.falloff(500.0, 200.0), 0.0)


func test_upright_light_grows_towards_a_lantern() -> void:
	var first: Vector2 = Vector2(5.5, 4.5) * CELL
	var lanterns: Array[Dictionary] = [_lantern(first), _lantern(Vector2(26.5, 15.5) * CELL)]
	var far_hero: Vector2 = Vector2(-10000, -10000)
	var base: Color = RunLighting.light_at(ARENA * 0.5, far_hero, lanterns)
	assert_eq(base, Color(RunLighting.AMBIENT + RunLighting.MOON_COLOR * RunLighting.MOON_FLAT, 1.0),
		"away from every point light only ambient and the flat moon remain")
	var last: float = base.r
	for step: int in range(8, -1, -1):
		var at: Vector2 = first + Vector2(step * 30.0, 0.0)
		var light: Color = RunLighting.light_at(at, far_hero, lanterns)
		assert_gt(light.r, last - 1e-6, "closer is not darker (%d)" % step)
		last = light.r
	var peak: float = RunLighting.LANTERN_COLOR.r * RunLighting.LANTERN_ENERGY * RunLighting.UPRIGHT_SHARE
	assert_almost_eq(last - base.r, peak, 1e-4)
	assert_eq(RunLighting.light_at(ARENA * 0.5, far_hero, lanterns).a, 1.0)


## A3 polish: things that stand still keep the fixed part and add only the aura each frame.
func test_fixed_light_plus_aura_is_light_at() -> void:
	var first: Vector2 = Vector2(5.5, 4.5) * CELL
	var lanterns: Array[Dictionary] = [_lantern(first), _lantern(Vector2(26.5, 15.5) * CELL)]
	var feet: Vector2 = first + Vector2(60.0, 20.0)
	var hero: Vector2 = feet + Vector2(40.0, 0.0)
	var fixed: Color = RunLighting.fixed_light(feet, lanterns)
	assert_eq(fixed, RunLighting.light_at(feet, Vector2(-10000, -10000), lanterns), "no aura far from the hero")
	assert_eq(RunLighting.with_aura(fixed, feet, hero), RunLighting.light_at(feet, hero, lanterns))
	assert_gt(RunLighting.with_aura(fixed, feet, hero).r, fixed.r)


## A3 polish: a prop standing at its own lantern is not blown out by it (the sprite shader
## multiplies the painted colours by this light once).
func test_upright_light_at_a_lantern_stays_moderate() -> void:
	var lanterns: Array[Dictionary] = [_lantern(ARENA * 0.5)]
	var peak: Color = RunLighting.fixed_light(ARENA * 0.5, lanterns)
	assert_lt(peak.r, 1.6)
	assert_gt(peak.r, peak.b, "warm")


func test_hero_aura_lights_the_hero() -> void:
	var lanterns: Array[Dictionary] = []
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
	for elevation: float in [30.0, -28.0]:
		var on_terrace: Vector2 = feet - Vector2(0.0, elevation)
		var datum: Transform2D = RunLighting.shadow_transform(on_terrace, elevation)
		var expected: Vector2 = feet + head * (1.0 + elevation / 100.0)
		assert_almost_eq(datum * Vector2(0.0, -100.0), expected, Vector2.ONE * 0.001)


## ADR-014 section 26: the fires flicker around their energy, each out of step with the others,
## the same at the same time.
func test_fire_flickers_within_its_depth() -> void:
	var low: float = 2.0
	var high: float = 0.0
	var total: float = 0.0
	var samples: int = 600
	for step: int in samples:
		var value: float = RunLighting.flicker(step / 60.0, 3)
		low = minf(low, value)
		high = maxf(high, value)
		total += value
	assert_gte(low, 1.0 - RunLighting.FLICKER_DEPTH - 1e-5)
	assert_lte(high, 1.0 + RunLighting.FLICKER_DEPTH + 1e-5)
	assert_gt(high - low, RunLighting.FLICKER_DEPTH, "it visibly moves")
	assert_almost_eq(total / samples, 1.0, 0.02, "around the steady energy")
	assert_eq(RunLighting.flicker(2.5, 1), RunLighting.flicker(2.5, 1), "the same at the same time")
	assert_ne(RunLighting.flicker(2.5, 1), RunLighting.flicker(2.5, 2), "flames out of step")


func test_rim_material_carries_the_flames() -> void:
	var flames: Array[Dictionary] = []
	for index: int in RunLighting.MAX_FLAMES + 3:
		flames.append(_lantern(Vector2(index * 40.0, 0.0)))
	flames[0]["radius"] = 132.0
	flames[0]["energy"] = 1.7
	var rim: ShaderMaterial = RunLighting.rim_material(Color.WHITE, 0.5, flames)
	assert_eq(rim.get_shader_parameter("flame_count"), RunLighting.MAX_FLAMES, "at most the shader's array")
	var points: PackedVector4Array = rim.get_shader_parameter("flames")
	assert_eq(points.size(), RunLighting.MAX_FLAMES)
	assert_eq(points[0], Vector4(0.0, -60.0, 132.0, 0.5), "the rim uses local reach and energy")
	assert_eq(rim.get_shader_parameter("warm_strength"), RunLighting.WARM_RIM_STRENGTH)
	RunLighting.set_flicker(rim, 1.25, 4)
	var energy: PackedFloat32Array = rim.get_shader_parameter("flame_energy")
	assert_eq(energy.size(), 4)
	assert_almost_eq(energy[2], RunLighting.flicker(1.25, 2), 1e-6)
	var none: ShaderMaterial = RunLighting.rim_material(Color.WHITE, 0.5, [] as Array[Dictionary])
	assert_eq(none.get_shader_parameter("flame_count"), 0, "no fires, no warm rim")
