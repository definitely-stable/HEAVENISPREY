class_name EnemyReactions
extends RefCounted
## ADR-014 A5b: how an enemy takes a blow and how it falls, after the hit and death rows of
## REF-010 and REF-034. Presentation only: the simulation positions stay as they are.
## - A blow plays the enemy's "hit" clip (recoil and back to its stance), flashes it white for
##   a moment and pushes its sprite a few px away from the hero, which then eases back onto its
##   simulation point. A blow inside the first half of a running recoil does not restart it, so
##   a body under a stream of blows still reads as recoiling, not frozen on frame 1.
## - A fallen enemy plays its "death" clip where it stood, in the direction it faced, then
##   decays (CombatVfx.DECAY_TIME): shaders/sprite_dissolve.gdshader eats the body in an ink
##   noise with a crimson edge while the yin burst rises (CombatVfx.draw_light).

const FLASH_TIME: float = 0.1
## Seconds at full white before the flash fades.
const FLASH_PEAK: float = 0.035
## World px the sprite is pushed back at most, when, and when it is back on its point.
const KNOCK_PX: float = 5.0
const KNOCK_PEAK: float = 0.05
const KNOCK_TIME: float = 0.24
## Share of the hit clip after which a new blow restarts it.
const RESTART_SHARE: float = 0.5
const DISSOLVE_SHADER: Shader = preload("res://presentation/run/shaders/sprite_dissolve.gdshader")
## Texels of the dissolve noise tile and its seed.
const NOISE_SIZE: int = 128
const NOISE_SEED: int = 7
## Crimson of the decaying edge (the yin burst, REF-010 "decay") and the ink the body darkens to.
const COLOR_EMBER: Color = Color(0.95, 0.16, 0.2)
const COLOR_INK: Color = Color(0.05, 0.02, 0.05)

## Enemy uid -> seconds since its last counted blow.
var _ages: Dictionary = {}


func clear() -> void:
	_ages.clear()


## A blow on `uid`; `clip_length` is its hit clip (0 without one).
func hit(uid: int, clip_length: float) -> void:
	var restart: float = clip_length * RESTART_SHARE if clip_length > 0.0 else FLASH_TIME
	if not _ages.has(uid) or float(_ages[uid]) >= restart:
		_ages[uid] = 0.0


## Ages every reaction; one is dropped `keep` seconds after its blow (the longest hit clip).
func age(delta: float, keep: float) -> void:
	var limit: float = maxf(keep, KNOCK_TIME)
	for uid: Variant in _ages.keys():
		var since: float = float(_ages[uid]) + maxf(delta, 0.0)
		if since >= limit:
			_ages.erase(uid)
		else:
			_ages[uid] = since


func fallen(uid: int) -> void:
	_ages.erase(uid)


## Seconds since the last counted blow on `uid`, INF without one.
func since(uid: int) -> float:
	return float(_ages[uid]) if _ages.has(uid) else INF


## 0-1 white of the hit flash: full for FLASH_PEAK, then it fades out by FLASH_TIME.
func flash(uid: int) -> float:
	var t: float = since(uid)
	if t >= FLASH_TIME:
		return 0.0
	return 1.0 if t <= FLASH_PEAK else 1.0 - (t - FLASH_PEAK) / (FLASH_TIME - FLASH_PEAK)


## World px offset of the sprite of `uid`, pushed along `away` (from the hero to the enemy):
## out by KNOCK_PEAK, eased back by KNOCK_TIME.
func knock(uid: int, away: Vector2) -> Vector2:
	var t: float = since(uid)
	if t >= KNOCK_TIME or away == Vector2.ZERO:
		return Vector2.ZERO
	var share: float = t / KNOCK_PEAK if t < KNOCK_PEAK else 1.0 - (t - KNOCK_PEAK) / (KNOCK_TIME - KNOCK_PEAK)
	return away.normalized() * KNOCK_PX * smoothstep(0.0, 1.0, share)


## [death pose, seconds of the fall] for an enemy that fell in `pose` ([asset, clip, direction,
## frame]): its death clip from frame 0 in the same direction, or the pose as it was.
static func death_pose(sprites: SpriteSet, pose: Array) -> Array:
	if pose[0] != "" and sprites.has_clip(pose[0], "death"):
		return [[pose[0], "death", pose[2], 0], sprites.clip_length(pose[0], "death")]
	return [pose, 0.0]


## The material of the fallen bodies: modulate alpha carries the decay (1 whole, 0 gone).
static func dissolve_material() -> ShaderMaterial:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var image: Image = noise.get_seamless_image(NOISE_SIZE, NOISE_SIZE)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("noise", ImageTexture.create_from_image(image))
	material.set_shader_parameter("noise_texels", float(NOISE_SIZE))
	material.set_shader_parameter("ember", COLOR_EMBER)
	material.set_shader_parameter("ink", COLOR_INK)
	return material


## Draws every fallen body of `deaths` (CombatVfx entries [at, age, pose, fall]): the death
## clip frame of its age, then the decay. `light` maps world feet to their light.
static func draw_fallen(canvas: CanvasItem, sprites: SpriteSet, deaths: Array[Array], light: Callable) -> void:
	for death: Array in deaths:
		var pose: Array = death[2]
		if pose[0] == "":
			continue
		var frame: int = pose[3]
		if pose[1] == "death":
			frame = sprites.clip_frame(pose[0], "death", death[1])
		var tint: Color = light.call(death[0])
		tint.a = 1.0 - CombatVfx.decay(death)
		var at: Vector2 = IsoProjection.to_screen(death[0])
		if pose[1] != "":
			sprites.draw_clip(canvas, pose[0], pose[1], pose[2], frame, at, tint)
		else:
			sprites.draw_frame(canvas, pose[0], pose[2], frame, at, tint)
