extends SceneTree
## Art acceptance screenshots (ADR-009 section 5, ADR-013). Needs a window, not --headless:
##   godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- out.png [seed] [mode] [count]
## Modes:
## - "horde" (default): `count` (48) enemies of the first two run kinds are placed on a ring
##   around the hero, which then stands still for 40 frames while they close in;
## - "circles": the P0 run with the hero walking circles and taking the first card of every
##   hand, saved once `count` enemies are alive or after 200 s;
## - "grid": light acceptance (ADR-014 section 7): the hero stands at the arena centre and at
##   each spawn point, one capture per point (out_<i>.png) and out.json with the screen points of the hero, the
##   lanterns and the arena corners in each capture;
## - "hero": a contact sheet of the animated hero (ADR-014 A4) in game light: four frames of the
##   run in each of the 8 directions (one row each, east first, clockwise), then idle, attacks
##   on a horde and the death, cropped around the hero;
## - "results" / "rewards": the end-of-run summaries with a reached milestone; final argument is en or ru.
## - "class-select": startup class cards over the empty arena; the last argument is locale (en or ru).
## - "choice": the P0 run with the hero walking circles until the first level-up, then the open
##   choice menu (ADR-014 section 16) after it has armed;
## - "fight": combat effects (ADR-014 section 18): `count` enemies with their real HP on rings
##   around the hero, which stands and fights and is kept at full HP; four captures out_<i>.png over FIGHT_SECONDS
##   (sword volleys, hits, numbers, falls, a level), the gems left on the ground included;
## - "perf": `count` enemies on rings around the hero walking left and right; prints the p50
##   and p95 frame time and the draw calls over 180 frames and writes them to out (JSON).
##   Run it with --disable-vsync (and at 1920x1080 for the ADR-014 A2 budget).
## - "reactions": a contact sheet of the hit and death reactions (ADR-014 A5b): enemies on each
##   side of the hero at the arena centre (rows: four diagonals), cropped around each while it
##   walks, recoils from a blow and falls and decays; `count` names the kinds in turn
##   ("yin_corpse,blood_wolf" by default, ids without "enemy.");
## - "strikes": the same four enemies start next to the hero and attack it for STRIKE_SECONDS
##   (ADR-014 A5c: a telegraphed attack plays its clip by the attack state), blows hidden;
## Placing enemies writes the world directly: a presentation check, not a gameplay trace.

const STEP: float = 1.0 / 60.0
const MAX_SECONDS: float = 200.0
const HORDE_FRAMES: int = 40
const RING_PX: float = 260.0
const FIGHT_SECONDS: Array[float] = [1.4, 2.6, 4.0, 6.5]
## Hero contact sheet: crop size (px) and frames run per direction.
const HERO_CROP: int = 200
const HERO_RUN_FRAMES: int = 40
## Reaction sheet: crop size (px), world offsets of the four enemies from the hero (each faces
## another diagonal) and the seconds after the blow and after the fall of each column.
const REACT_CROP: int = 150
const REACT_AT: Array[Vector2] = [Vector2(-230, 0), Vector2(0, 230), Vector2(0, -230), Vector2(230, 0)]
const REACT_HIT: Array[float] = [0.03, 0.1, 0.2, 0.32]
const REACT_FALL: Array[float] = [0.08, 0.25, 0.5, 0.75, 0.95, 1.1]
const REACT_KINDS: String = "yin_corpse,blood_wolf"
## Strike sheet: the enemies start this many px from the hero; a column every STRIKE_EVERY s.
const STRIKE_NEAR: float = 0.45
const STRIKE_EVERY: float = 0.1
const STRIKE_SECONDS: float = 1.6
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
	if mode == "class-select":
		TranslationServer.set_locale(args[3] if args.size() > 3 else "en")
		view._show_class_select()
		view.advance_frame(ClassSelect.ARM_DELAY, Vector2i.ZERO)
		await process_frame
		await RenderingServer.frame_post_draw
		var error: Error = root.get_texture().get_image().save_png(out)
		print("capture class selection: ", out, " error=", error)
		quit(0 if error == OK else 1)
		return
	if not view.start_run(seed_text):
		quit(1)
		return
	if mode == "results" or mode == "rewards":
		TranslationServer.set_locale(args[3] if args.size() > 3 else "en")
		# Leave the last tick to the sim so the live view creates the receipt normally.
		view.driver.world.tick = view.driver.config.run_ticks - 1
		view.driver.world.kills = 20
		view.advance_frame(STEP, Vector2i.ZERO)
		if mode == "rewards":
			view.advance_frame(RunResults.ARM_DELAY, Vector2i.ZERO)
			if not view.confirm_results():
				quit(1)
				return
			view.advance_frame(RunRewards.ARM_DELAY, Vector2i.ZERO)
		await process_frame
		await RenderingServer.frame_post_draw
		var error: Error = root.get_texture().get_image().save_png(out)
		print("capture terminal screen: ", out, " error=", error)
		quit(0 if error == OK else 1)
		return
	if mode == "grid":
		await _capture_grid(view, out)
		return
	if mode == "perf":
		await _measure_frames(view, out, count)
		return
	if mode == "hero":
		await _capture_hero(view, out)
		return
	if mode == "choice":
		await _capture_choice(view, out)
		return
	if mode == "fight":
		await _capture_fight(view, out, count)
		return
	if mode == "reactions" or mode == "strikes":
		var kinds: String = args[3] if args.size() > 3 else REACT_KINDS
		await _capture_reactions(view, out, kinds.split(","), mode == "strikes")
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


func _capture_choice(view: RunView, out: String) -> void:
	var seconds: float = 0.0
	while seconds < MAX_SECONDS and not view.driver.world.is_paused() and not view.driver.world.is_over():
		view.advance_frame(STEP, CIRCLE[int(seconds / 0.75) % CIRCLE.size()])
		seconds += STEP
	for index: int in HORDE_FRAMES:
		view.advance_frame(STEP, Vector2i.ZERO)
		await process_frame
	var error: Error = root.get_texture().get_image().save_png(out)
	print("capture choice: ", out, " open=", view.is_menu_open(), " level=", view.driver.world.level, " error=", error)
	quit(0 if error == OK else 1)


func _capture_fight(view: RunView, out: String, count: int) -> void:
	_place_horde(view, count, 3, 1.4, true)
	var seconds: float = 0.0
	for index: int in FIGHT_SECONDS.size():
		while seconds < FIGHT_SECONDS[index] and not view.driver.world.is_over():
			if view.driver.world.is_paused():
				view.choose(0)
			# The hero holds the ground: the capture is about the effects, not the outcome.
			view.driver.world.hero_hp = view.driver.world.hero_hp_max
			view.advance_frame(STEP, Vector2i.ZERO)
			seconds += STEP
			await process_frame
		var path: String = out.get_basename() + "_%d.png" % index
		var error: Error = root.get_texture().get_image().save_png(path)
		print("capture fight: ", path, " t=", snappedf(seconds, 0.1), " alive=", view.driver.world.enemy_alive,
			" kills=", view.driver.world.kills, " level=", view.driver.world.level, " error=", error)
	quit(0)


func _walk_circles(view: RunView, count: int) -> void:
	var seconds: float = 0.0
	while seconds < MAX_SECONDS and view.driver.world.enemy_alive < count and not view.driver.world.is_over():
		if view.driver.world.is_paused():
			view.choose(0)
		view.advance_frame(STEP, CIRCLE[int(seconds / 0.75) % CIRCLE.size()])
		seconds += STEP


## `count` enemies on `rings` rings around the hero, `near` times RING_PX away; with `real_hp`
## they have the HP of their kind (they fall), otherwise they are unkillable. The hero is moved
## to the seal first: at the west entry the outer rings would lie past the arena grid.
func _place_horde(view: RunView, count: int, rings: int = 3, near: float = 1.0, real_hp: bool = false) -> void:
	var world: WorldState = view.driver.world
	var centre: Vector2 = GroundLayer.centre_of(P0Tuning.arena_data(), RunView.CELL_PX)
	for state: WorldState in [world, view.driver.previous]:
		state.player_x = int(centre.x) * Fx.FX_ONE
		state.player_y = int(centre.y) * Fx.FX_ONE
	var hero: Vector2 = Vector2(world.player_x, world.player_y)
	for index: int in count:
		var angle: float = TAU * index / count
		var ring: float = RING_PX * near * (1.0 + 0.7 * (index % rings) / maxf(rings - 1, 1)) * Fx.FX_ONE
		var slot: int = world.append_enemy_slot()
		world.enemy_uid[slot] = world.next_enemy_uid
		world.enemy_kind[slot] = index % 2
		world.enemy_x[slot] = int(hero.x + cos(angle) * ring)
		world.enemy_y[slot] = int(hero.y + sin(angle) * ring * 0.6)
		world.enemy_hp[slot] = view.driver.config.kind_value(index % 2, SimConfig.KIND_HP) if real_hp else 1000000
		world.next_enemy_uid += 1
		world.enemy_alive += 1


func _capture_grid(view: RunView, out: String) -> void:
	var world: WorldState = view.driver.world
	var arena: Vector2 = Vector2(P0Tuning.arena_cells() * RunView.CELL_PX)
	var lanterns: Array[Vector2] = view.lantern_positions()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(arena.x, 0.0), arena, Vector2(0.0, arena.y)]
	var shots: Array = []
	for at: Vector2 in _grid_points():
		var index: int = shots.size()
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


## The arena centre and its spawn points (world px): walkable spots across the courtyard.
func _grid_points() -> Array[Vector2]:
	var data: Dictionary = P0Tuning.arena_data()
	var centre: Array = data.get("centre", [0, 0])
	var out: Array[Vector2] = [(Vector2(float(centre[0]), float(centre[1])) + Vector2(0.5, 0.5)) * RunView.CELL_PX]
	var rows: Array = data.get("rows", [])
	for y: int in rows.size():
		for x: int in (rows[y] as String).length():
			if (rows[y] as String)[x] == ArenaTopology.SPAWN_CHARS:
				out.append((Vector2(x, y) + Vector2(0.5, 0.5)) * RunView.CELL_PX)
	return out


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


func _capture_hero(view: RunView, out: String) -> void:
	var world: WorldState = view.driver.world
	var rows: Array = []
	for direction: Vector2i in CIRCLE:
		var row: Array[Image] = []
		for frame: int in HERO_RUN_FRAMES:
			await _hero_step(view, direction)
			if frame >= HERO_RUN_FRAMES - 16 and frame % 4 == 0:
				row.append(_hero_crop(view))
		rows.append(row)
	var idle: Array[Image] = []
	for frame: int in 24:
		await _hero_step(view, Vector2i.ZERO)
		if frame % 6 == 5:
			idle.append(_hero_crop(view))
	rows.append(idle)
	_place_horde(view, 24)
	var attack: Array[Image] = []
	var guard: int = 0
	while attack.size() < 4 and guard < 600:
		await _hero_step(view, Vector2i.ZERO)
		if view._hero_pose()[1] == "attack" and guard % 3 == 0:
			attack.append(_hero_crop(view))
		guard += 1
	rows.append(attack)
	world.hero_hp = mini(world.hero_hp, 1)
	guard = 0
	while not world.is_over() and guard < 1200:
		await _hero_step(view, Vector2i.ZERO)
		guard += 1
	var death: Array[Image] = []
	for frame: int in 60:
		await _hero_step(view, Vector2i.ZERO)
		if frame in [2, 14, 26, 58]:
			death.append(_hero_crop(view))
	rows.append(death)
	var sheet: Image = Image.create_empty(HERO_CROP * 4, HERO_CROP * rows.size(), false, Image.FORMAT_RGBA8)
	for y: int in rows.size():
		for x: int in (rows[y] as Array).size():
			var crop: Image = rows[y][x]
			sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(x, y) * HERO_CROP)
	var error: Error = sheet.save_png(out)
	print("capture hero: ", out, " rows=", rows.size(), " error=", error)
	quit(0 if error == OK else 1)


func _hero_step(view: RunView, direction: Vector2i) -> void:
	if view.driver.world.is_paused():
		view.choose(0)
	view.advance_frame(STEP, direction)
	await process_frame


## HERO_CROP px around the hero (its feet low in the crop) from the last drawn frame.
func _hero_crop(view: RunView) -> Image:
	var camera: Camera2D = root.get_viewport().get_camera_2d()
	var feet: Vector2 = IsoProjection.to_screen(view.driver.hero_position_px())
	var pixel: Vector2 = (feet - camera.get_screen_center_position()) * camera.zoom
	pixel += Vector2(root.get_visible_rect().size) * 0.5
	var image: Image = root.get_texture().get_image()
	var corner: Vector2i = Vector2i(pixel) - Vector2i(HERO_CROP / 2, HERO_CROP * 3 / 4)
	corner = corner.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE * HERO_CROP)
	return image.get_region(Rect2i(corner, Vector2i.ONE * HERO_CROP))


func _capture_reactions(view: RunView, out: String, kinds: PackedStringArray, strikes: bool) -> void:
	var world: WorldState = view.driver.world
	var centre: Vector2 = GroundLayer.centre_of(P0Tuning.arena_data(), RunView.CELL_PX)
	for state: WorldState in [world, view.driver.previous]:
		state.player_x = int(centre.x) * Fx.FX_ONE
		state.player_y = int(centre.y) * Fx.FX_ONE
	var slots: Array[int] = []
	for index: int in REACT_AT.size():
		var slot: int = world.append_enemy_slot()
		world.enemy_uid[slot] = world.next_enemy_uid
		world.enemy_kind[slot] = maxi(view.tuning.enemy_ids.find("enemy." + kinds[index % kinds.size()]), 0)
		var offset: Vector2 = REACT_AT[index] * (STRIKE_NEAR if strikes else 1.0)
		world.enemy_x[slot] = int((centre.x + offset.x) * Fx.FX_ONE)
		world.enemy_y[slot] = int((centre.y + offset.y) * Fx.FX_ONE)
		world.enemy_hp[slot] = 1000000
		world.next_enemy_uid += 1
		world.enemy_alive += 1
		slots.append(slot)
	var rows: Array = [[], [], [], []]
	if strikes:
		await _capture_strikes(view, slots, rows)
		_save_sheet(rows, out)
		return
	for _frame: int in 8:
		await _hero_step(view, Vector2i.ZERO)
	for index: int in slots.size():
		rows[index].append(_crop_at(view.driver.enemy_position_px(slots[index]), REACT_CROP))
		view._reactions.hit(world.enemy_uid[slots[index]], view._hit_keep)
	var seconds: float = 0.0
	for at: float in REACT_HIT:
		while seconds < at:
			await _hero_step(view, Vector2i.ZERO)
			seconds += STEP
		for index: int in slots.size():
			rows[index].append(_crop_at(view.driver.enemy_position_px(slots[index]), REACT_CROP))
	var fallen: Array[Vector2] = []
	for slot: int in slots:
		var feet: Vector2 = view.driver.enemy_position_px(slot)
		var fell: Array = EnemyReactions.death_pose(view._sprites, view._frame_pose(slot))
		view._vfx.add_death(feet, fell[0], fell[1])
		fallen.append(feet)
		world.enemy_uid[slot] = 0
		world.enemy_alive -= 1
	seconds = 0.0
	for at: float in REACT_FALL:
		while seconds < at:
			await _hero_step(view, Vector2i.ZERO)
			seconds += STEP
		for index: int in fallen.size():
			rows[index].append(_crop_at(fallen[index], REACT_CROP))
	_save_sheet(rows, out)


## Crops around each enemy every STRIKE_EVERY s while it attacks the hero; blows on it are
## hidden (no recoil over the attack) and the hero is kept alive.
func _capture_strikes(view: RunView, slots: Array[int], rows: Array) -> void:
	var seconds: float = 0.0
	var next: float = STRIKE_EVERY
	while seconds < STRIKE_SECONDS:
		await _hero_step(view, Vector2i.ZERO)
		seconds += STEP
		view._reactions.clear()
		view.driver.world.hero_hp = view.driver.world.hero_hp_max
		if seconds >= next:
			next += STRIKE_EVERY
			for index: int in slots.size():
				rows[index].append(_crop_at(view.driver.enemy_position_px(slots[index]), REACT_CROP))


func _save_sheet(rows: Array, out: String) -> void:
	var columns: int = (rows[0] as Array).size()
	var sheet: Image = Image.create_empty(REACT_CROP * columns, REACT_CROP * rows.size(), false, Image.FORMAT_RGBA8)
	for y: int in rows.size():
		for x: int in columns:
			var crop: Image = rows[y][x]
			sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(x, y) * REACT_CROP)
	var error: Error = sheet.save_png(out)
	print("capture reactions: ", out, " columns=", columns, " error=", error)
	quit(0 if error == OK else 1)


## `size` px around a world point (its feet low in the crop) from the last drawn frame.
func _crop_at(world_point: Vector2, size: int) -> Image:
	var camera: Camera2D = root.get_viewport().get_camera_2d()
	var pixel: Vector2 = (IsoProjection.to_screen(world_point) - camera.get_screen_center_position()) * camera.zoom
	pixel += Vector2(root.get_visible_rect().size) * 0.5
	var image: Image = root.get_texture().get_image()
	var corner: Vector2i = Vector2i(pixel) - Vector2i(size / 2, size * 3 / 4)
	corner = corner.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE * size)
	return image.get_region(Rect2i(corner, Vector2i.ONE * size))
