class_name IsoProjection
extends RefCounted
## ADR-014 section 1: the fixed 2:1 isometric matrix between the world XY plane of the
## simulation (px) and the screen. screen = K * (x - y, (x + y) / 2) with K = sqrt(2) / 2, so a
## world step along the screen horizontal keeps its length and a step along the screen
## vertical is halved. Ground items are drawn in world coordinates under ground(); upright
## sprites are drawn unprojected at to_screen(feet). Presentation only: the simulation, its
## inputs and replays stay in world axes.

const K: float = 0.7071067811865476


static func to_screen(world: Vector2) -> Vector2:
	return Vector2(world.x - world.y, (world.x + world.y) * 0.5) * K


static func to_world(screen: Vector2) -> Vector2:
	var diff: float = screen.x / K
	var total: float = 2.0 * screen.y / K
	return Vector2((total + diff) * 0.5, (total - diff) * 0.5)


## The canvas transform that draws world coordinates onto the ground plane.
static func ground() -> Transform2D:
	return Transform2D(Vector2(K, 0.5 * K), Vector2(-K, 0.5 * K), Vector2.ZERO)


## A held move in screen axes (up = screen up) -> the world move that looks like it on screen.
## Screen up is the world diagonal (-1, -1), screen right is (1, -1).
static func screen_move_to_world(move: Vector2i) -> Vector2i:
	return Vector2i(signi(move.x + move.y), signi(move.y - move.x))


## Depth of a ground point: larger is nearer the viewer (lower on screen).
static func depth(world: Vector2) -> float:
	return world.x + world.y


## Screen bounding box of a world rectangle anchored at the origin (the arena diamond).
static func bounds(size: Vector2) -> Rect2:
	var corners: Array[Vector2] = [
		to_screen(Vector2.ZERO), to_screen(Vector2(size.x, 0)), to_screen(Vector2(0, size.y)), to_screen(size),
	]
	var box: Rect2 = Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		box = box.expand(corner)
	return box
