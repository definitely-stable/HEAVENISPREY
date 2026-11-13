class_name AttackTelegraph
extends RefCounted
## Placeholder telegraphs of enemy attacks drawn with primitives (ADR-011 sections 2-3):
## a MELEE_ARC sector from the enemy in its fixed direction (E2); a CHARGE lane of the dash
## length and the enemy's width (E3), pointing at the hero during `tell` (the aim locks at its
## end) and along the locked direction while dashing. During `tell` the outline shows the
## whole danger area and a fill grows with the time already spent in it; while active the
## shape flashes. Presentation only: the simulation decides every hit.

const COLOR_TELL: Color = Color(0.95, 0.3, 0.22, 0.16)
const COLOR_TELL_EDGE: Color = Color(1.0, 0.42, 0.3, 0.85)
const COLOR_FILL: Color = Color(0.95, 0.3, 0.22, 0.32)
const COLOR_ACTIVE: Color = Color(1.0, 0.85, 0.6, 0.55)
const ARC_POINTS: int = 24


## The telegraph of the attack in `slot`, empty when the enemy is not in tell or active:
## {form, center, radius (px: arc radius or dash length), angle (rad), half_arc (rad, arc) or
## width (px, charge), progress (0..1 of the tell), active}.
static func shape(config: SimConfig, world: WorldState, slot: int) -> Dictionary:
	if slot >= world.enemy_slots() or world.enemy_uid[slot] == 0:
		return {}
	var state: int = world.enemy_state[slot]
	if state != EnemyAttackSystem.ST_TELL and state != EnemyAttackSystem.ST_ACTIVE:
		return {}
	var kind: int = world.enemy_kind[slot]
	var form: int = config.attack_value(kind, SimConfig.ATTACK_FORM)
	if form != SimConfig.FORM_ARC and form != SimConfig.FORM_CHARGE:
		return {}
	var telegraph: int = config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
	var progress: float = 1.0
	if state == EnemyAttackSystem.ST_TELL:
		progress = clampf(float(telegraph - world.enemy_left[slot]) / float(telegraph), 0.0, 1.0)
	var center: Vector2 = Vector2(world.enemy_x[slot], world.enemy_y[slot]) / Fx.FX_ONE
	var angle: float = atan2(float(world.enemy_dir_y[slot]), float(world.enemy_dir_x[slot]))
	if form == SimConfig.FORM_CHARGE and state == EnemyAttackSystem.ST_TELL:
		# The aim is not locked yet: the lane follows the hero.
		var hero: Vector2 = Vector2(world.player_x, world.player_y) / Fx.FX_ONE
		if not hero.is_equal_approx(center):
			angle = center.angle_to_point(hero)
	return {
		"form": form,
		"center": center,
		"radius": float(config.attack_value(kind, SimConfig.ATTACK_REACH)) / Fx.FX_ONE,
		"angle": angle,
		"half_arc": deg_to_rad(config.attack_value(kind, SimConfig.ATTACK_ARC) * 0.5),
		"width": 2.0 * float(config.kind_value(kind, SimConfig.KIND_RADIUS)) / Fx.FX_ONE,
		"progress": progress,
		"active": state == EnemyAttackSystem.ST_ACTIVE,
	}


## Draws `telegraph` (from shape) at `center` (the interpolated enemy position in px).
static func draw(canvas: CanvasItem, telegraph: Dictionary, center: Vector2) -> void:
	var radius: float = telegraph["radius"]
	var angle: float = telegraph["angle"]
	var charge: bool = telegraph["form"] == SimConfig.FORM_CHARGE
	var outline: PackedVector2Array = _shape(telegraph, center, radius, angle, charge)
	if telegraph["active"]:
		canvas.draw_colored_polygon(outline, COLOR_ACTIVE)
		return
	canvas.draw_colored_polygon(outline, COLOR_TELL)
	var grown: float = radius * float(telegraph["progress"])
	if grown > 1.0:
		canvas.draw_colored_polygon(_shape(telegraph, center, grown, angle, charge), COLOR_FILL)
	canvas.draw_polyline(outline + PackedVector2Array([outline[0]]), COLOR_TELL_EDGE, 2.0)


static func _shape(
	telegraph: Dictionary, center: Vector2, radius: float, angle: float, charge: bool
) -> PackedVector2Array:
	if charge:
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
