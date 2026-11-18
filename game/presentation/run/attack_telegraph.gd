class_name AttackTelegraph
extends RefCounted
## Enemy attack telegraphs drawn with primitives (ADR-011 sections 2-3):
## a MELEE_ARC sector from the enemy in its fixed direction (E2); a CHARGE lane of the dash
## length and the enemy's width (E3), pointing at the hero during `tell` (the aim locks at its
## end) and along the locked direction while dashing; a PROJECTILE lane of the launch range
## and the shot's width (E4), following the hero the same way until the release. Zones (E5)
## are drawn from the zone pool, not from the enemy: a circle of the zone radius. During
## `tell` the charge has an outlined lane and a forward chevron, and the shot has a thin axis
## with a crossbar at its source. The fill grows with elapsed time. While active an attack
## shape or a death zone flashes and a ground zone stays a dark root circle.

const COLOR_TELL: Color = Color(0.95, 0.3, 0.22, 0.16)
const COLOR_TELL_EDGE: Color = Color(1.0, 0.42, 0.3, 0.85)
const COLOR_FILL: Color = Color(0.95, 0.3, 0.22, 0.32)
const COLOR_CHARGE_BASE: Color = Color(0.08, 0.035, 0.045, 0.64)
const COLOR_CHARGE_EDGE: Color = Color(1.0, 0.73, 0.54)
const COLOR_CHARGE_FILL: Color = Color(0.95, 0.33, 0.19, 0.53)
const COLOR_SHOT_BASE: Color = Color(0.07, 0.12, 0.16, 0.48)
const COLOR_SHOT_EDGE: Color = Color(0.84, 0.97, 1.0)
const COLOR_SHOT_FILL: Color = Color(0.36, 0.68, 0.78, 0.25)
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


## Zone and attack marks share the same draw passes and keep their original footprints.
static func _is_zone(form: int) -> bool:
	return form == SimConfig.FORM_GROUND_ZONE or form == SimConfig.FORM_DEATH_ZONE


## The telegraph ticks of the first kind whose attack has `form` (one kind per zone form in P0).
static func _form_telegraph(config: SimConfig, form: int) -> int:
	for kind: int in config.kind_count():
		if config.attack_value(kind, SimConfig.ATTACK_FORM) == form:
			return config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
	return 0


## Draws the area and its timing fill on the arena floor.
static func draw_fill(canvas: CanvasItem, telegraph: Dictionary) -> void:
	var center: Vector2 = telegraph["center"]
	var radius: float = telegraph["radius"]
	var form: int = telegraph["form"]
	var grown: float = radius * float(telegraph["progress"])
	if _is_zone(form):
		if telegraph["active"]:
			canvas.draw_circle(center, radius, COLOR_ROOT if form == SimConfig.FORM_GROUND_ZONE else COLOR_ACTIVE)
		else:
			canvas.draw_circle(center, radius, COLOR_TELL)
			if grown > 1.0:
				canvas.draw_circle(center, grown, COLOR_FILL)
		return
	var outline: PackedVector2Array = _shape(telegraph, radius)
	if telegraph["active"]:
		canvas.draw_colored_polygon(outline, COLOR_ACTIVE)
		return
	var base: Color = COLOR_TELL
	var fill: Color = COLOR_FILL
	if form == SimConfig.FORM_CHARGE:
		base = COLOR_CHARGE_BASE
		fill = COLOR_CHARGE_FILL
	elif form == SimConfig.FORM_PROJECTILE:
		base = COLOR_SHOT_BASE
		fill = COLOR_SHOT_FILL
	canvas.draw_colored_polygon(outline, base)
	if grown > 1.0:
		canvas.draw_colored_polygon(_shape(telegraph, grown), fill)


## Keeps the same outline, axis and direction cues legible over bodies and light.
static func draw_edge(canvas: CanvasItem, telegraph: Dictionary) -> void:
	var form: int = telegraph["form"]
	var center: Vector2 = telegraph["center"]
	var radius: float = telegraph["radius"]
	var active: bool = telegraph["active"]
	if _is_zone(form):
		if not active or form == SimConfig.FORM_GROUND_ZONE:
			var edge: Color = COLOR_ROOT_EDGE if active else COLOR_TELL_EDGE
			canvas.draw_arc(center, radius, 0.0, TAU, ZONE_POINTS, edge, 2.0)
		return
	if active:
		return
	var outline: PackedVector2Array = _shape(telegraph, radius)
	if form == SimConfig.FORM_CHARGE:
		canvas.draw_polyline(outline + PackedVector2Array([outline[0]]), COLOR_CHARGE_EDGE, 4.0, true)
		var travel: Vector2 = (outline[1] + outline[2]) * 0.5 - center
		var wing: Vector2 = (outline[0] - center) * 0.56
		var tail: Vector2 = center + travel * 0.43
		canvas.draw_polyline(
			PackedVector2Array([tail + wing, center + travel * 0.57, tail - wing]),
			COLOR_CHARGE_EDGE, 3.0, true
		)
	elif form == SimConfig.FORM_PROJECTILE:
		var tip: Vector2 = (outline[1] + outline[2]) * 0.5
		canvas.draw_multiline(PackedVector2Array([center, tip, outline[0], outline[3]]), COLOR_SHOT_EDGE, 2.0, true)
	else:
		canvas.draw_polyline(outline + PackedVector2Array([outline[0]]), COLOR_TELL_EDGE, 2.0)


static func _shape(telegraph: Dictionary, radius: float) -> PackedVector2Array:
	var center: Vector2 = telegraph["center"]
	var angle: float = telegraph["angle"]
	if telegraph["form"] != SimConfig.FORM_ARC:
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
