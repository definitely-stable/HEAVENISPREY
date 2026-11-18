extends SceneTree
## Validate Python bridge journals or capture a four-fps Godot replay.
## godot --headless --path game -s res://tools/capture_opening.gd -- bridge.json
## godot --path game --resolution 1280x720 -s res://tools/capture_opening.gd -- bridge.json frames 101

const CAPTURE_EVERY: int = 15


func _initialize() -> void:
	_opening.call_deferred()


func _opening() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 and args.size() != 3:
		_fail("Expected bridge.json [frames seed]")
		return
	var package: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not package is Dictionary or int(package.get("schema_version", 0)) != 1:
		_fail("Unknown bridge journal schema")
		return
	if int(package["sim_schema_version"]) != RunRulesSnapshot.SIM_SCHEMA_VERSION:
		_fail("Bridge journals are for a different simulation")
		return
	var scene: PackedScene = load("res://presentation/run/run_view.tscn")
	var view: RunView = scene.instantiate()
	view.read_player_input = false
	root.add_child(view)
	await process_frame
	var tested: int = 0
	for trace: Dictionary in package["traces"]:
		if args.size() == 3 and args[2] != trace["seed"]:
			continue
		var ok: bool = await _replay(view, trace, args[1] if args.size() == 3 else "")
		if not ok:
			return
		tested += 1
	if tested == 0:
		_fail("No matching bridge journals")
		return
	print("PASS: opening replay parity for ", tested, " journals")
	quit(0)


func _replay(view: RunView, trace: Dictionary, output: String) -> bool:
	view.start_run(trace["seed"])
	var config: SimConfig = view.driver.config
	config.choice_mode = int(trace.get("choice_mode", 0))
	config.spawn_period_mt = int(trace["spawn_period_mt"])
	var pairs: PackedInt64Array = []
	for pair: Array in trace["spawns"]:
		pairs.append(int(pair[0]))
		pairs.append(int(pair[1]))
	var arena: ArenaTopology = config.arena
	config.arena = ArenaTopology.create(arena.width, arena.height, arena.cell, arena.body, arena.codes, pairs)
	var log: CommandLog = CommandLog.new()
	for record: Array in trace["commands"]:
		if log.append(PlayerCommand.from_ints(PackedInt64Array(record)), 0) != CommandLog.OK:
			_fail("Invalid bridge command")
			return false
	if log.digest() != trace["log_digest"]:
		_fail("Bridge command digest mismatch")
		return false
	view.driver = FixedTickDriver.create(config)
	var world: WorldState = view.driver.world
	var finish: int = int(trace["finish"])
	if output.is_empty():
		for step: int in finish:
			SimKernel.step(config, world, log)
	else:
		var folder: String = output.path_join(str(trace["variant"]))
		var error: Error = DirAccess.make_dir_recursive_absolute(folder)
		if error != OK:
			_fail("Could not create capture directory")
			return false
		view._hud.driver = view.driver
		view._camera.position_smoothing_enabled = false
		var held: Vector2i = Vector2i.ZERO
		var cursor: int = 0
		for tick: int in finish:
			if cursor < log.size() and log.tick_at(cursor) == tick:
				held = Vector2i(log.move_x_at(cursor), log.move_y_at(cursor))
				cursor += 1
			view.advance_frame(FixedTickDriver.TICK_SECONDS, held)
			if tick + 1 >= int(trace["start"]) - 60 and (tick + 1) % CAPTURE_EVERY == 0:
				view._camera.force_update_scroll()
				await RenderingServer.frame_post_draw
				var path: String = folder.path_join("%04d.png" % (tick + 1))
				if root.get_texture().get_image().save_png(path) != OK:
					_fail("Could not save a bridge frame")
					return false
	if world.tick != int(trace["end_tick"]) or world.digest() != trace["world_digest"]:
		_fail("Bridge world mismatch for %s/%s at tick %s" % [trace["variant"], trace["seed"], world.tick])
		return false
	print("Bridge ", trace["variant"], "/", trace["seed"], " tick ", world.tick, " ", world.digest())
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
