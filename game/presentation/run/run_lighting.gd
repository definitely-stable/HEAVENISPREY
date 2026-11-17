class_name RunLighting
extends RefCounted
## ADR-014 sections 4-5: one lighting model for the run scene. The ground layer is lit by
## Godot 2D lights over normal maps (ambient = CanvasModulate, the moon, lanterns, the hero
## aura); upright sprites are not lit by Light2D (a spot on the floor would paint the head of
## an enemy standing in front of it) but take modulate = light_at(feet), the same model
## evaluated at their ground point. Shadows fall away from the moon. Presentation only.

## Night ambient on upright things (the base of light_at): bodies and props stand pale
## against the paving, as on REF-023 and REF-044.
const AMBIENT: Color = Color(0.79, 0.8, 0.9)
## Night ambient of the ground (CanvasModulate of GroundLayer): the paving of REF-023 is dark
## slate under a cold sky, so the lantern pools and the gold of the fight stand out of it
## (ADR-014 section 20).
const GROUND_AMBIENT: Color = Color(0.76, 0.77, 0.87)
## Moonlight: colour, energy and height for normal mapping (0..1). It travels from the upper
## left to the lower right of the screen, along the cast shadows (moon_travel()).
const MOON_COLOR: Color = Color(0.62, 0.72, 0.95)
const MOON_ENERGY: float = 0.18
const MOON_HEIGHT: float = 0.55
## Upright sprites get a flat share of the moon (no normal on the ground point).
const MOON_FLAT: float = 0.18
## Warm light of the lanterns and braziers of the courtyard (ArenaDressing.LIGHT_PROPS).
const LANTERN_COLOR: Color = Color(1.0, 0.68, 0.26)
const LANTERN_ENERGY: float = 3.4
const LANTERN_RADIUS_PX: float = 240.0
## Fire flickers: each flame's energy is 1 plus two slow waves of FLICKER_DEPTH in all, out of
## step from flame to flame (ADR-014 section 26).
const FLICKER_DEPTH: float = 0.09
const FLICKER_HZ: Vector2 = Vector2(1.3, 3.7)
## Warm rim a flame casts on the side of an upright sprite that faces it (sprite_rim.gdshader).
const WARM_RIM_STRENGTH: float = 0.9
const RIM_SHADER: Shader = preload("res://presentation/run/shaders/sprite_rim.gdshader")
## The shader's array of flames.
const MAX_FLAMES: int = 16
## Aura of the hero: a soft gold light that follows them.
const AURA_COLOR: Color = Color(1.0, 0.88, 0.62)
const AURA_ENERGY: float = 0.55
const AURA_RADIUS_PX: float = 150.0
## Share of a point light an upright sprite takes: its faces stand across the light that
## falls from above onto the floor, so they catch less of it than the ground below.
const UPRIGHT_SHARE: float = 0.14
## Height of point lights for normal mapping, px.
const LIGHT_HEIGHT_PX: float = 40.0
## Cast shadow of an upright sprite: squash of its height and horizontal shear per unit of
## height, both along the moon's travel (the shadow falls to the lower right).
const SHADOW_SQUASH: float = 0.34
const SHADOW_SHEAR: float = -0.62
## Darkening of the shadow layer, composited once (overlaps do not stack).
const SHADOW_ALPHA: float = 0.4


## Screen direction the moonlight travels: the direction cast shadows fall.
static func moon_travel() -> Vector2:
	return Vector2(-SHADOW_SHEAR, SHADOW_SQUASH).normalized()


## Rotation of a DirectionalLight2D whose light travels along moon_travel() (a rotation of 0
## shines down the screen).
static func moon_rotation() -> float:
	var travel: Vector2 = moon_travel()
	return atan2(-travel.x, travel.y)


## Linear fall-off of a radial light texture: 1 at the centre, 0 at `radius`.
static func falloff(distance: float, radius: float) -> float:
	return clampf(1.0 - distance / radius, 0.0, 1.0)


## Light on an upright sprite whose feet stand at `feet` (world px); `hero` (world px) carries
## the aura. Ambient plus the flat moon share plus UPRIGHT_SHARE of every point light there.
static func light_at(feet: Vector2, hero: Vector2, lanterns: Array[Vector2]) -> Color:
	return with_aura(fixed_light(feet, lanterns), feet, hero)


## The part of light_at() that does not move: ambient, the flat moon and the lanterns. Things
## that stand still (the courtyard props) keep it and add only the aura each frame.
static func fixed_light(feet: Vector2, lanterns: Array[Vector2]) -> Color:
	var light: Color = AMBIENT + MOON_COLOR * MOON_FLAT
	for lantern: Vector2 in lanterns:
		light += LANTERN_COLOR * (LANTERN_ENERGY * UPRIGHT_SHARE * falloff(feet.distance_to(lantern), LANTERN_RADIUS_PX))
	light.a = 1.0
	return light


## `fixed` (a fixed_light() at `feet`) plus the hero aura.
static func with_aura(fixed: Color, feet: Vector2, hero: Vector2) -> Color:
	var light: Color = fixed + AURA_COLOR * (AURA_ENERGY * UPRIGHT_SHARE * falloff(feet.distance_to(hero), AURA_RADIUS_PX))
	light.a = 1.0
	return light


## Screen transform that lays an upright sprite drawn at the origin (feet) down as its cast
## shadow at `feet_screen`: heights shrink by SHADOW_SQUASH and flip to fall down the screen,
## and lean to the right along the moon.
static func shadow_transform(feet_screen: Vector2) -> Transform2D:
	return Transform2D(Vector2(1.0, 0.0), Vector2(SHADOW_SHEAR, -SHADOW_SQUASH), feet_screen)


## Energy factor of flame `index` at `seconds` of the run: within 1 +- FLICKER_DEPTH, the same
## for the same time, different from flame to flame.
static func flicker(seconds: float, index: int) -> float:
	var phase: float = float(index) * 0.618
	var slow: float = sin(TAU * (FLICKER_HZ.x * seconds + phase))
	var quick: float = sin(TAU * (FLICKER_HZ.y * seconds + phase * 1.7))
	return 1.0 + FLICKER_DEPTH * (0.62 * slow + 0.38 * quick)


## The rim material of upright sprites: `color` on the moon side at `strength`, and the warm
## rim of every flame in `flames` (screen px, at most MAX_FLAMES).
static func rim_material(color: Color, strength: float, flames: Array[Vector2]) -> ShaderMaterial:
	var rim: ShaderMaterial = ShaderMaterial.new()
	rim.shader = RIM_SHADER
	rim.set_shader_parameter("to_moon", -moon_travel())
	rim.set_shader_parameter("rim_color", color)
	rim.set_shader_parameter("rim_strength", strength)
	var points: PackedVector2Array = PackedVector2Array(flames.slice(0, MAX_FLAMES))
	rim.set_shader_parameter("flames", points)
	rim.set_shader_parameter("flame_count", points.size())
	rim.set_shader_parameter("flame_radius", LANTERN_RADIUS_PX)
	rim.set_shader_parameter("warm_color", LANTERN_COLOR)
	rim.set_shader_parameter("warm_strength", WARM_RIM_STRENGTH)
	set_flicker(rim, 0.0, points.size())
	return rim


## Sets the flicker of `count` flames at `seconds` on a rim material.
static func set_flicker(rim: ShaderMaterial, seconds: float, count: int) -> void:
	var energy: PackedFloat32Array = PackedFloat32Array()
	for index: int in mini(count, MAX_FLAMES):
		energy.append(flicker(seconds, index))
	rim.set_shader_parameter("flame_energy", energy)
