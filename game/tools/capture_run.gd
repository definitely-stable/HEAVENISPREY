extends SceneTree
## Art acceptance screenshots (ADR-009 section 5, ADR-013). Needs a window, not --headless:
##   godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- out.png [seed] [mode] [count]
## Modes:
## - "horde" (default): `count` (48) enemies of the first two run kinds are placed on a ring
##   around the hero, which then stands still for 40 frames while they close in;
## - "circles": the P0 run with the hero walking circles and taking the first card of every
##   hand, saved once `count` enemies are alive or after 200 s.
## Placing enemies writes the world directly: a presentation check, not a gameplay trace.

const STEP: float = 1.0 / 60.0
const MAX_SECONDS: float = 200.0
const HORDE_FRAMES: int = 40
const RING_PX: float = 260.0
const CIRCLE: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://capture.png"
	var seed_text: String = args[1] if args.size() > 1 else "101"
	var mode: String = args[2] if args.size() > 2 else "horde"
	var count: int = int(args[3]) if args.size() > 3 else 48
	var view: RunView = (load("res://presentation/run/run_view.tscn") as PackedScene).instantiate() as RunView
	view.read_player_input = false
	root.add_child(view)
	await process_frame
	view.start_run(seed_text)
	if mode == "circles":
		_walk_circles(view, count)
	else:
		_place_horde(view, count)
	for index: int in HORDE_FRAMES:
		if view.driver.world.is_paused():
			view.choose(0)
		view.advance_frame(STEP, Vector2i.ZERO)
		await process_frame
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(out)
	print("capture: ", out, " ", image.get_size(), " alive=", view.driver.world.enemy_alive,
		" tick=", view.driver.world.tick, " error=", error)
	quit(0 if error == OK else 1)


func _walk_circles(view: RunView, count: int) -> void:
	var seconds: float = 0.0
	while seconds < MAX_SECONDS and view.driver.world.enemy_alive < count and not view.driver.world.is_over():
		if view.driver.world.is_paused():
			view.choose(0)
		view.advance_frame(STEP, CIRCLE[int(seconds / 0.75) % CIRCLE.size()])
		seconds += STEP


func _place_horde(view: RunView, count: int) -> void:
	var world: WorldState = view.driver.world
	var hero: Vector2 = Vector2(world.player_x, world.player_y)
	for index: int in count:
		var angle: float = TAU * index / count
		var ring: float = RING_PX * (1.0 + 0.35 * (index % 3)) * Fx.FX_ONE
		var slot: int = world.append_enemy_slot()
		world.enemy_uid[slot] = world.next_enemy_uid
		world.enemy_kind[slot] = index % 2
		world.enemy_x[slot] = int(hero.x + cos(angle) * ring)
		world.enemy_y[slot] = int(hero.y + sin(angle) * ring * 0.6)
		world.enemy_hp[slot] = 1000000
		world.next_enemy_uid += 1
		world.enemy_alive += 1
