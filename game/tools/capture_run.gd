extends SceneTree
## Art acceptance screenshots (ADR-009 section 5, ADR-013). Needs a window, not --headless:
##   godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- out.png [seed] [mode] [count]
## Modes:
## - "horde" (default): `count` (48) enemies of the first two run kinds are placed on a ring
##   around the hero, which then stands still for 40 frames while they close in;
## - "circles": the P0 run with the hero walking circles and taking the first card of every
##   hand, saved once `count` enemies are alive or after 200 s;
## - "grid": light acceptance (ADR-014 section 7): the hero stands on a 3x3 grid of the arena,
##   one capture per point (out_<i>.png) and out.json with the screen points of the hero, the
##   lanterns and the arena corners in each capture;
## - "perf": `count` enemies on rings around the hero walking left and right; prints the p50
##   and p95 frame time and the draw calls over 180 frames and writes them to out (JSON).
##   Run it with --disable-vsync (and at 1920x1080 for the ADR-014 A2 budget).
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
	if mode == "grid":
		await _capture_grid(view, out)
		return
	if mode == "perf":
		await _measure_frames(view, out, count)
		return
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


func _place_horde(view: RunView, count: int, rings: int = 3) -> void:
	var world: WorldState = view.driver.world
	var hero: Vector2 = Vector2(world.player_x, world.player_y)
	for index: int in count:
		var angle: float = TAU * index / count
		var ring: float = RING_PX * (1.0 + 0.7 * (index % rings) / maxf(rings - 1, 1)) * Fx.FX_ONE
		var slot: int = world.append_enemy_slot()
		world.enemy_uid[slot] = world.next_enemy_uid
		world.enemy_kind[slot] = index % 2
		world.enemy_x[slot] = int(hero.x + cos(angle) * ring)
		world.enemy_y[slot] = int(hero.y + sin(angle) * ring * 0.6)
		world.enemy_hp[slot] = 1000000
		world.next_enemy_uid += 1
		world.enemy_alive += 1


func _capture_grid(view: RunView, out: String) -> void:
	var world: WorldState = view.driver.world
	var arena: Vector2 = Vector2(RunView.ARENA_CELLS * RunView.CELL_PX)
	var lanterns: Array[Vector2] = RunLighting.lantern_positions(RunView.CELL_PX)
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(arena.x, 0.0), arena, Vector2(0.0, arena.y)]
	var shots: Array = []
	for index: int in 9:
		var at: Vector2 = arena * Vector2(0.15 + 0.35 * (index % 3), 0.15 + 0.35 * (index / 3))
		world.player_x = int(at.x * Fx.FX_ONE)
		world.player_y = int(at.y * Fx.FX_ONE)
		for frame: int in HORDE_FRAMES:
			if world.is_paused():
				view.choose(0)
			view.advance_frame(STEP, Vector2i.ZERO)
			await process_frame
		var path: String = out.get_basename() + "_%d.png" % index
		var error: Error = root.get_texture().get_image().save_png(path)
		var camera: Camera2D = root.get_viewport().get_camera_2d()
		var to_pixel: Callable = func(point: Vector2) -> Array:
			var pixel: Vector2 = (IsoProjection.to_screen(point) - camera.get_screen_center_position()) * camera.zoom
			pixel += Vector2(root.get_visible_rect().size) * 0.5
			return [pixel.x, pixel.y]
		shots.append({
			"path": path, "error": error, "hero": to_pixel.call(view.driver.hero_position_px()),
			"lanterns": lanterns.map(to_pixel), "corners": corners.map(to_pixel),
			"zoom": camera.zoom.x, "radius": RunLighting.LANTERN_RADIUS_PX, "aura": RunLighting.AURA_RADIUS_PX,
		})
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(shots, "  "))
	file.close()
	print("capture grid: ", out, " shots=", shots.size())
	quit(0)


func _measure_frames(view: RunView, out: String, count: int) -> void:
	_place_horde(view, count, 7)
	var world: WorldState = view.driver.world
	var frames: Array[float] = []
	var calls: Array[int] = []
	for frame: int in 240:
		var start: int = Time.get_ticks_usec()
		if world.is_paused():
			view.choose(0)
		view.advance_frame(STEP, Vector2i(1, 0) if (frame / 60) % 2 == 0 else Vector2i(-1, 0))
		await process_frame
		if frame >= 60:
			frames.append((Time.get_ticks_usec() - start) / 1000.0)
			calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	frames.sort()
	calls.sort()
	var result: Dictionary = {
		"enemies": world.enemy_alive, "window_px": root.size,
		"frame_ms_p50": frames[frames.size() / 2], "frame_ms_p95": frames[int(frames.size() * 0.95)],
		"draw_calls_p50": calls[calls.size() / 2], "draw_calls_max": calls[-1],
	}
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("perf: ", result)
	quit(0)
