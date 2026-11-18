class_name RunEffectsPasses
extends RefCounted
## Render the combat overlays and additive light in the same order as the arena view.


static func prepare_danger(view: RunView) -> void:
	view._danger_marks.clear()
	if view.driver == null:
		return
	var world: WorldState = view.driver.world
	var config: SimConfig = view.driver.config
	for slot: int in world.zone_slots():
		var zone: Dictionary = AttackTelegraph.zone_shape(config, world, slot)
		if not zone.is_empty():
			view._danger_marks.append(zone)
	for slot: int in world.enemy_slots():
		var telegraph: Dictionary = AttackTelegraph.shape(config, world, slot)
		if not telegraph.is_empty():
			telegraph["center"] = view.driver.enemy_position_px(slot)
			view._danger_marks.append(telegraph)


static func draw_danger_fill(view: RunView) -> void:
	if view.driver == null:
		return
	var canvas: Node2D = view._danger
	canvas.draw_set_transform_matrix(IsoProjection.ground())
	for mark: Dictionary in view._danger_marks:
		AttackTelegraph.draw_fill(canvas, mark)
	var world: WorldState = view.driver.world
	if world.root_left > 0:
		canvas.draw_arc(view.driver.hero_position_px(), RunView.HERO_RADIUS_PX + 4.0, 0.0, TAU, 32, RunView.COLOR_ROOTED, 3.0)
	if world.is_over():
		for rect: Rect2 in GroundLayer.footprint(P0Tuning.arena_data(), RunView.CELL_PX):
			canvas.draw_rect(rect, RunView.COLOR_OVER)


static func draw_warning_edges(view: RunView) -> void:
	if view.driver == null:
		return
	var canvas: Node2D = view._warning_edges
	if view._chain_left > 0.0:
		var alpha: float = view._chain_left / 0.12
		canvas.draw_polyline(view._chain_line, Color(0.50, 0.49, 1.0, alpha), 5.0, true)
		canvas.draw_polyline(view._chain_line, Color(0.85, 0.92, 1.0, alpha), 2.0, true)
	canvas.draw_set_transform_matrix(IsoProjection.ground())
	for mark: Dictionary in view._danger_marks:
		AttackTelegraph.draw_edge(canvas, mark)


static func draw_over_pass(view: RunView) -> void:
	if view.driver == null:
		return
	var canvas: Node2D = view._over
	var hero: Vector2 = IsoProjection.to_screen(view.driver.hero_position_px())
	if view._flash > 0.0:
		_draw_hero_hit(canvas, hero, view._flash / RunView.HIT_FLASH)
	var stacks: int = view.driver.world.venom_stacks
	var top: float = -view._hero_height() - 8.0
	for pip: int in stacks:
		canvas.draw_circle(hero + Vector2(-8.0 + 8.0 * pip, top - 6.0), 3.0, RunView.COLOR_VENOM)
	var max_hp: int = view.driver.world.hero_hp_max
	if max_hp > 0:
		var bar: Rect2 = Rect2(hero + Vector2(-RunView.HERO_RADIUS_PX, top), Vector2(RunView.HERO_RADIUS_PX * 2, 5))
		canvas.draw_rect(bar, RunView.COLOR_HP_BACK)
		var share: float = clampf(float(view.driver.world.hero_hp) / float(max_hp), 0.0, 1.0)
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), RunView.COLOR_HP)
	var world: WorldState = view.driver.world
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] == 0:
			continue
		var at: Vector2 = IsoProjection.to_screen(view.driver.shot_position_px(slot)) - Vector2(0, RunView.SHOT_LIFT_PX)
		canvas.draw_circle(at, float(world.shot_radius[slot]) / Fx.FX_ONE, RunView.COLOR_WISP)
	var font: Font = view._hud.kit.font if view._hud != null and view._hud.kit != null else ThemeDB.fallback_font
	var gem_light: bool = view._vfx != null and view._vfx.kit.has("qi_wisp")
	for pickup: Array in view._pickups:
		var age: float = pickup[2]
		if age < RunView.PICKUP_FLY:
			if not gem_light:
				CombatVfx.draw_gem_primitive(
					canvas, _pickup_flight(view, pickup), pickup[1], 1.0, RunView.GEM_REST_SCALE, RunView.COLOR_GEM
				)
			continue
		var fade: float = (age - RunView.PICKUP_FLY) / RunView.PICKUP_TEXT
		var color: Color = RunView.COLOR_GEM
		color.a = 1.0 - fade
		var at: Vector2 = hero + Vector2(RunView.HERO_RADIUS_PX * 0.6, -view._hero_height() - 6 - 24 * fade)
		canvas.draw_string_outline(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3,
			Color(0.02, 0.06, 0.08, 0.8 * color.a))
		canvas.draw_string(font, at, "+" + str(pickup[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if view._vfx != null:
		view._vfx.draw_numbers(canvas)


## A short cue at the feet keeps the character's face and clothing readable on impact.
static func _draw_hero_hit(canvas: CanvasItem, feet: Vector2, remaining: float) -> void:
	var spread: float = 23.0 + (1.0 - remaining) * 8.0
	var left: Vector2 = feet + Vector2(-spread, 4.0)
	var right: Vector2 = feet + Vector2(spread, 4.0)
	var lines: PackedVector2Array = PackedVector2Array([
		left + Vector2(6, -5), left, left, left + Vector2(6, 5),
		right + Vector2(-6, -5), right, right, right + Vector2(-6, 5),
	])
	canvas.draw_multiline(lines, Color(0.13, 0.08, 0.08, 0.95 * remaining), 5.0, true)
	canvas.draw_multiline(lines, Color(1.0, 0.87, 0.60, remaining), 2.5, true)


## Where the collected gem is on its short flight to the hero.
static func _pickup_flight(view: RunView, pickup: Array) -> Vector2:
	var hero: Vector2 = IsoProjection.to_screen(view.driver.hero_position_px()) - Vector2(0, RunView.GEM_LIFT_PX)
	var from: Vector2 = IsoProjection.to_screen(pickup[0]) - Vector2(0, RunView.GEM_LIFT_PX)
	return from.lerp(hero, clampf(pickup[2] / RunView.PICKUP_FLY, 0.0, 1.0))


# --- glow item (additive): flames, blades and trails, wisps, gems near the hero ---

static func draw_glow_pass(view: RunView) -> void:
	var canvas: Node2D = view._glow
	for index: int in view._flames.size():
		var radius: float = 26.0 * RunLighting.flicker(view._anim_time, index)
		RunLighting.halo(
			canvas, view._halo_texture, view._flames[index], radius, RunView.COLOR_LANTERN_GLOW
		)
	if view.driver == null:
		return
	var world: WorldState = view.driver.world
	var radius: float = float(view.driver.config.projectile_radius_su) / Fx.FX_ONE
	var light: bool = view._vfx != null and view._vfx.kit.has("sword")
	if light:
		_draw_vfx_light(view, canvas)
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] == 0:
			continue
		var ground: Vector2 = view.driver.projectile_position_px(slot)
		var at: Vector2 = IsoProjection.to_screen(ground) - Vector2(0, RunView.FLIGHT_LIFT_PX)
		var heading: Vector2 = view._projectile_heading(slot)
		if light:
			view._vfx.draw_sword(canvas, at, heading)
			continue
		canvas.draw_line(at - heading * radius * 6.0, at, RunView.COLOR_SWORD_TRAIL, radius * 0.9)
		RunLighting.halo(canvas, view._halo_texture, at, radius * 2.6, RunView.COLOR_SWORD_GLOW)
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] != 0:
			var at: Vector2 = IsoProjection.to_screen(view.driver.shot_position_px(slot)) - Vector2(0, RunView.SHOT_LIFT_PX)
			RunLighting.halo(
				canvas, view._halo_texture, at, float(world.shot_radius[slot]) / Fx.FX_ONE * 3.2, RunView.COLOR_WISP_GLOW
			)
	var hero: Vector2 = view.driver.hero_position_px()
	var near_px: float = float(UpgradeSystem.pickup_radius(view.driver.config, world)) / Fx.FX_ONE * RunView.GEM_NEAR_RADII
	for slot: int in world.gem_slots():
		if world.gem_uid[slot] != 0 and view.driver.gem_position_px(slot).distance_to(hero) <= near_px:
			var at: Vector2 = IsoProjection.to_screen(view.driver.gem_position_px(slot)) - Vector2(0, RunView.GEM_LIFT_PX)
			RunLighting.halo(canvas, view._halo_texture, at, 14.0, RunView.COLOR_GEM_GLOW)


## Effects light of the atlas: bursts and circles, the gems (a qi wisp brighter near the hero, as
## it is about to be drawn in) and the gems flying in.
static func _draw_vfx_light(view: RunView, canvas: Node2D) -> void:
	view._vfx.draw_light(canvas)
	var world: WorldState = view.driver.world
	var hero: Vector2 = view.driver.hero_position_px()
	var near_px: float = float(UpgradeSystem.pickup_radius(view.driver.config, world)) / Fx.FX_ONE * RunView.GEM_NEAR_RADII
	for slot: int in world.gem_slots():
		var uid: int = world.gem_uid[slot]
		if uid == 0:
			continue
		var ground: Vector2 = view.driver.gem_position_px(slot)
		var bob: float = sin(view._anim_time * RunView.GEM_BOB_HZ * TAU + float(uid)) * RunView.GEM_BOB_PX
		var at: Vector2 = IsoProjection.to_screen(ground) - Vector2(0, RunView.GEM_LIFT_PX + bob)
		var near: bool = ground.distance_to(hero) <= near_px
		view._vfx.draw_gem(
			canvas, at, world.gem_value[slot], 1.0 if near else RunView.GEM_REST_ALPHA, 1.0 if near else RunView.GEM_REST_SCALE
		)
	for pickup: Array in view._pickups:
		if pickup[2] < RunView.PICKUP_FLY:
			view._vfx.draw_gem(canvas, _pickup_flight(view, pickup), pickup[1], 1.0)
