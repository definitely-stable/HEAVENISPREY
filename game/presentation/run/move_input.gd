class_name MoveInput
extends RefCounted
## Presentation-side input boundary (ADR-008): the only place where float input becomes the
## integer 8-direction move of a PlayerCommand. Simulation never reads Input.

const DEADZONE: float = 0.25
## Sector k (k * 45 deg, +x = east, +y = south in screen space) -> held move per axis.
const SECTORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]


## Snap an analog or digital vector to the nearest of 8 directions; inside the deadzone -> (0, 0).
static func quantize(vector: Vector2) -> Vector2i:
	if vector.length() < DEADZONE:
		return Vector2i.ZERO
	var sector: int = wrapi(roundi(vector.angle() / (PI / 4.0)), 0, 8)
	return SECTORS[sector]


## Current held move from the InputMap actions (keyboard, d-pad and left stick).
static func read() -> Vector2i:
	return quantize(Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.0))
