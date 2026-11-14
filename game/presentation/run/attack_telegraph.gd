class_name AttackTelegraph
extends RefCounted
## Placeholder telegraphs of enemy attacks drawn with primitives (ADR-011 sections 2-3):
## a MELEE_ARC sector from the enemy in its fixed direction (E2); a CHARGE lane of the dash
## length and the enemy's width (E3), pointing at the hero during `tell` (the aim locks at its
## end) and along the locked direction while dashing; a PROJECTILE lane of the launch range
## and the shot's width (E4), following the hero the same way until the release. Zones (E5)
## are drawn from the zone pool, not from the enemy: a circle of the zone radius. During
## `tell` the outline shows the whole danger area and a fill grows with the time already spent
## in it; while active an attack shape or a death zone flashes and a ground zone stays a dark
## root circle. Presentation only: the simulation decides every hit.

const COLOR_TELL: Color = Color(0.95, 0.3, 0.22, 0.16)
const COLOR_TELL_EDGE: Color = Color(1.0, 0.42, 0.3, 0.85)
const COLOR_FILL: Color = Color(0.95, 0.3, 0.22, 0.32)
const COLOR_ACTIVE: Color = Color(1.0, 0.85, 0.6, 0.55)
const COLOR_ROOT: Color = Color(0.5, 0.1, 0.18, 0.34)
const COLOR_ROOT_EDGE: Color = Color(0.82, 0.2, 0.28, 0.9)
const ARC_POINTS: int = 24
const ZONE_POINTS: int = 48


## The telegraph of the attack in `slot`, empty when the enemy is not in tell or active:
## {form, center, radius (px: arc radius or dash length), angle (rad), half_arc (rad, arc) or
## width (px, charge or projectile lane), progress (0..1 of the tell), active}.
static func shape(config: SimConfig, world: WorldState, slot: int) -> Dictionary:
	if slot >= world.enemy_slots() or world.enemy_uid[slot] == 0:
		return {}
	var state: int = world.enemy_state[slot]
	if state != EnemyAttackSystem.ST_TELL and state != EnemyAttackSystem.ST_ACTIVE:
		return {}
	var kind: int = world.enemy_kind[slot]
	var form: int = config.attack_value(kind, SimConfig.ATTACK_FORM)
	if form == SimConfig.FORM_CONTACT or form == SimConfig.FORM_DEATH_ZONE or form == SimConfig.FORM_GROUND_ZONE:
		return {}
	var telegraph: int = config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
	var progress: float = 1.0
	if state == EnemyAttackSystem.ST_TELL:
		progress = clampf(float(telegraph - world.enemy_left[slot]) / float(telegraph), 0.0, 1.0)
	var center: Vector2 = Vector2(world.enemy_x[slot], world.enemy_y[slot]) / Fx.FX_ONE
	var angle: float = atan2(float(world.enemy_dir_y[slot]), float(world.enemy_dir_x[slot]))
	if form != SimConfig.FORM_ARC and state == EnemyAttackSystem.ST_TELL:
		# The aim is not locked yet: the lane follows the hero.
		var hero: Vector2 = Vector2(world.player_x, world.player_y) / Fx.FX_ONE
		if not hero.is_equal_approx(center):
			angle = center.angle_to_point(hero)
	var width: float = 2.0 * float(config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE
	if form == SimConfig.FORM_PROJECTILE:
		width = 2.0 * float(config.attack_value(kind, SimConfig.ATTACK_RADIUS)) / Fx.FX_ONE
	return {
		"form": form,
		"center": center,
		"radius": float(config.attack_value(kind, SimConfig.ATTACK_REACH)) / Fx.FX_ONE,
		"angle": angle,
		"half_arc": deg_to_rad(config.attack_value(kind, SimConfig.ATTACK_ARC) * 0.5),
		"width": width,
		"progress": progress,
		"active": state == EnemyAttackSystem.ST_ACTIVE,
	}


## The zone in pool `slot`, empty when the slot is free: {form, center (px), radius (px),
## progress (0..1 of the telegraph), active}.
static func zone_shape(config: SimConfig, world: WorldState, slot: int) -> Dictionary:
	if slot >= world.zone_slots() or world.zone_form[slot] == 0:
		return {}
	var form: int = world.zone_form[slot]
	var telegraph: int = _form_telegraph(config, form)
	var tell: int = world.zone_tell[slot]
	var progress: float = 1.0
	if tell > 0 and telegraph > 0:
		progress = clampf(float(telegraph - tell) / float(telegraph), 0.0, 1.0)
	return {
		"form": form,
		"center": Vector2(world.zone_x[slot], world.zone_y[slot]) / Fx.FX_ONE,
		"radius": float(world.zone_radius[slot]) / Fx.FX_ONE,
		"progress": progress,
		"active": tell == 0,
	}


## Draws `zone` (from zone_shape).
static func draw_zone(canvas: CanvasItem, zone: Dictionary) -> void:
	var center: Vector2 = zone["center"]
	var radius: float = zone["radius"]
	if zone["active"]:
		if zone["form"] == SimConfig.FORM_GROUND_ZONE:
			canvas.draw_circle(center, radius, COLOR_ROOT)
			canvas.draw_arc(center, radius, 0.0, TAU, ZONE_POINTS, COLOR_ROOT_EDGE, 2.0)
		else:
			canvas.draw_circle(center, radius, COLOR_ACTIVE)
		return
	canvas.draw_circle(center, radius, COLOR_TELL)
	var grown: float = radius * float(zone["progress"])
	if grown > 1.0:
		canvas.draw_circle(center, grown, COLOR_FILL)
	canvas.draw_arc(center, radius, 0.0, TAU, ZONE_POINTS, COLOR_TELL_EDGE, 2.0)


## The telegraph ticks of the first kind whose attack has `form` (one kind per zone form in P0).
static func _form_telegraph(config: SimConfig, form: int) -> int:
	for kind: int in config.kind_count():
		if config.attack_value(kind, SimConfig.ATTACK_FORM) == form:
			return config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
	return 0


## Draws `telegraph` (from shape) at `center` (the interpolated enemy position in px).
static func draw(canvas: CanvasItem, telegraph: Dictionary, center: Vector2) -> void:
	var radius: float = telegraph["radius"]
	var angle: float = telegraph["angle"]
	var lane_form: bool = telegraph["form"] != SimConfig.FORM_ARC
	var outline: PackedVector2Array = _shape(telegraph, center, radius, angle, lane_form)
	if telegraph["active"]:
		canvas.draw_colored_polygon(outline, COLOR_ACTIVE)
		return
	canvas.draw_colored_polygon(outline, COLOR_TELL)
	var grown: float = radius * float(telegraph["progress"])
	if grown > 1.0:
		canvas.draw_colored_polygon(_shape(telegraph, center, grown, angle, lane_form), COLOR_FILL)
	canvas.draw_polyline(outline + PackedVector2Array([outline[0]]), COLOR_TELL_EDGE, 2.0)


static func _shape(
	telegraph: Dictionary, center: Vector2, radius: float, angle: float, lane_form: bool
) -> PackedVector2Array:
	if lane_form:
		return lane(center, radius, angle, telegraph["width"])
	return sector(center, radius, angle, telegraph["half_arc"])


## Rectangle of `length` along `angle` from `center`, `width` across.
static func lane(center: Vector2, length: float, angle: float, width: float) -> PackedVector2Array:
	var along: Vector2 = Vector2(cos(angle), sin(angle))
	var side: Vector2 = along.orthogonal() * (width * 0.5)
	var tip: Vector2 = center + along * length
	return PackedVector2Array([center + side, tip + side, tip - side, center - side])


## Points of a sector polygon: the centre, then the arc from angle - half to angle + half.
static func sector(center: Vector2, radius: float, angle: float, half: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([center])
	for i: int in ARC_POINTS + 1:
		var a: float = angle - half + 2.0 * half * float(i) / ARC_POINTS
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points
