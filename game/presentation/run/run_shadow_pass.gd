class_name RunShadowPass
extends RefCounted
## The shadow layer of the arena view: one buffer, composited once (ADR-014 section 5).
## Silhouettes of the bodies and props laid away from the moon, then the soft contacts.


static func draw(view: RunView) -> void:
	var canvas: Node2D = view._shadow_canvas
	var world: WorldState = view.driver.world if view.driver != null else null
	# Draw silhouettes first. White contacts on top preserve their coverage in lit areas.
	if world != null:
		for slot: int in world.enemy_slots():
			if world.enemy_uid[slot] != 0:
				var pose: Array = view._frame_pose(slot)
				var lift: float = EnemyMotion.lift(pose[0], world.enemy_uid[slot], view._anim_time)
				_cast_shadow(view, canvas, pose, view._enemy_feet(slot), lift)
		_cast_shadow(view, canvas, view._hero_pose(), view.driver.hero_position_px())
	for prop: Dictionary in view._props:
		if prop["prop"] == ArenaDressing.BLOCK_PROP or prop["prop"] == ArenaDressing.RAIL_PROP or prop.has("clip"):
			continue
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(prop["screen"]))
		view._sprites.draw_prop(canvas, prop["asset"], prop["prop"], Vector2.ZERO, Color.BLACK, prop["flip"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	# A ruin as wide as several cells has no single base point to lay its silhouette from: its
	# cells darken the ground around its foot instead.
	for prop: Dictionary in view._props:
		for polygon: PackedVector2Array in prop.get("footprint", []):
			canvas.draw_colored_polygon(polygon, Color.WHITE)
	for lantern: Vector2 in view._lanterns:
		RunLighting.contact(canvas, view._disc_texture, IsoProjection.to_screen(lantern), RunView.CELL_PX * 0.65)
	if world == null:
		return
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] != 0:
			var radius: float = view._kind_radius_px(world.enemy_kind[slot]) * 0.95
			RunLighting.contact(canvas, view._disc_texture, IsoProjection.to_screen(view._enemy_feet(slot)), radius)
	if view._vfx != null:
		for death: Array in view._vfx.deaths:
			var left: float = 1.0 - CombatVfx.decay(death)
			var radius: float = RunView.HERO_RADIUS_PX * 0.9 * left
			RunLighting.contact(canvas, view._disc_texture, IsoProjection.to_screen(death[0]), radius)
	var hero: Vector2 = IsoProjection.to_screen(view.driver.hero_position_px())
	RunLighting.contact(canvas, view._disc_texture, hero, RunView.HERO_RADIUS_PX * 0.95)
	for slot: int in world.gem_slots():
		if world.gem_uid[slot] != 0:
			var at: Vector2 = IsoProjection.to_screen(view.driver.gem_position_px(slot))
			RunLighting.contact(canvas, view._disc_texture, at, 3.5)
	for slot: int in world.projectile_slots():
		if world.proj_damage[slot] != 0:
			var at: Vector2 = IsoProjection.to_screen(view.driver.projectile_position_px(slot))
			RunLighting.contact(canvas, view._disc_texture, at, 3.0)
	for slot: int in world.shot_slots():
		if world.shot_damage[slot] != 0:
			var at: Vector2 = IsoProjection.to_screen(view.driver.shot_position_px(slot))
			RunLighting.contact(canvas, view._disc_texture, at, 4.0)


## The silhouette laid down away from the moon.
static func _cast_shadow(view: RunView, canvas: Node2D, pose: Array, feet_world: Vector2, lift: float = 0.0) -> void:
	if pose[0] != "":
		canvas.draw_set_transform_matrix(RunLighting.shadow_transform(IsoProjection.to_screen(feet_world)))
		view._draw_pose(canvas, pose, Vector2(0.0, -lift), Color.BLACK)
