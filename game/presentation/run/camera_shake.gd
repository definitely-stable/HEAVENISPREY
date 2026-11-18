class_name CameraShake
extends RefCounted
## QUALITY-2026-11 Q2 trauma shake: how far the camera is pushed after a blow on the hero and
## after its death. View only: it reads nothing of the simulation and is deterministic (no random
## numbers); the offset is written into Camera2D.offset, so Camera2D.position and everything that
## follows it stay untouched.

## Trauma of a blow on the hero and of its death.
const TRAUMA_HIT: float = 0.30
const TRAUMA_DEATH: float = 0.60
## Seconds inside which a second blow does not stack on the first (the same instant).
const MERGE_TIME: float = 0.05
## Trauma lost per second.
const DECAY_PER_SECOND: float = 1.6
## Screen px of a shake at full trauma and full strength.
const MAX_OFFSET_PX: float = 8.0
## Frequencies of the two axes and the phase that keeps them apart.
const FREQ_X_HZ: float = 17.0
const FREQ_Y_HZ: float = 23.0
const PHASE_Y: float = 1.3

var trauma: float = 0.0
var _time: float = 0.0
var _since_add: float = INF


func clear() -> void:
	trauma = 0.0
	_time = 0.0
	_since_add = INF


## Adds the trauma of one blow; a second blow inside MERGE_TIME keeps the larger of the two
## instead of stacking them.
func add(amount: float) -> void:
	if amount <= 0.0:
		return
	if _since_add < MERGE_TIME:
		trauma = maxf(trauma, minf(amount, 1.0))
		return
	trauma = minf(trauma + amount, 1.0)
	_since_add = 0.0


## Ages the shake: the trauma decays and the wave clock runs.
func age(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	trauma = maxf(trauma - DECAY_PER_SECOND * step, 0.0)
	_time += step
	_since_add += step


## Screen px of the camera at `strength` (the settings multiplier): the squared trauma scales the
## wave, so a blow reads as a nudge and a death as a jolt.
func offset(strength: float) -> Vector2:
	if strength <= 0.0 or trauma <= 0.0:
		return Vector2.ZERO
	var amplitude: float = MAX_OFFSET_PX * clampf(strength, 0.0, 1.0) * trauma * trauma
	return Vector2(
		sin(_time * TAU * FREQ_X_HZ),
		sin(_time * TAU * FREQ_Y_HZ + PHASE_Y),
	) * amplitude
