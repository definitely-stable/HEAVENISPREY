extends SceneTree
## Fixed eye-level comparisons of the 2.5D paving. The simulation stays at tick zero.
## godot --path game --resolution 1280x720 -s res://tools/capture_terraces.gd -- <directory> [raised]

const VIEWS: Dictionary[String, Vector2i] = {
	"temple-court": Vector2i(28, 18), "temple-flight": Vector2i(27, 15), "temple-landing": Vector2i(25, 10),
	"maple-court": Vector2i(15, 37), "maple-flight": Vector2i(11, 41), "maple-landing": Vector2i(7, 45),
	"east-court": Vector2i(58, 26), "east-flight": Vector2i(63, 25), "east-landing": Vector2i(67, 23),
	"south-court": Vector2i(44, 48), "south-flight": Vector2i(48, 54), "south-landing": Vector2i(53, 57),
}


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or not DirAccess.dir_exists_absolute(args[0]):
		push_error("Specify an existing directory for terrace captures.")
		quit(1)
		return
	var scene: PackedScene = load("res://presentation/run/run_view.tscn")
	var view: RunView = scene.instantiate()
	view.read_player_input = false
	var arena: Dictionary = P0Tuning.arena_data()
	if args.has("raised"):
		view.terrain = JadeGroveTerrain.new(arena, RunView.CELL_PX)
	root.add_child(view)
	await process_frame
	if not view.start_run("101"):
		push_error("The fixed capture scene did not initialize.")
		quit(1)
		return
	view.set_process(false)
	view.set_physics_process(false)
	var camera: Camera2D = root.get_camera_2d()
	var heights: Dictionary[String, float] = {}
	for name: String in VIEWS:
		var cell: Vector2i = VIEWS[name]
		if not ArenaTopology.WALK_CHARS.contains(arena["rows"][cell.y][cell.x]):
			push_error("The capture cell is blocked: %s" % name)
			quit(1)
			return
		var at: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * RunView.CELL_PX
		heights[name] = IsoProjection.to_screen(at).y - view.surface_at(at).y
		view.driver.world.player_x = roundi(at.x * Fx.FX_ONE)
		view.driver.world.player_y = roundi(at.y * Fx.FX_ONE)
		view.driver.previous = view.driver.world.copy()
		view.advance_frame(0.0, Vector2i.ZERO)
		# Match camera coordinates between the two geometries.
		camera.position = IsoProjection.to_screen(at)
		view._ground.follow(at, camera.position, RunView.CAMERA_ZOOM)
		camera.reset_smoothing()
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(args[0].path_join(name + ".png")) != OK:
			push_error("Could not write the terrace capture: %s" % name)
			quit(1)
			return
	if view.driver.world.tick != 0:
		push_error("The scene advanced during the fixed capture.")
		quit(1)
		return
	print("Captured %d fixed cameras and sampled these floor heights: %s" % [VIEWS.size(), JSON.stringify(heights)])
	quit(0)
