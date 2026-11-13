class_name EnemyAttackSystem
extends RefCounted
## Enemy attack machine (ADR-011 sections 2-3: MELEE_ARC in E2, CHARGE in E3, PROJECTILE in
## E4). Exact port of tools/content/sim_core.py.
##
## Per live enemy whose kind has an attack record (not contact), in slot order: the cooldown
## counts down; an enemy in an attack counts down its state (tell -> active, the hit lands in
## the first active tick only -> recover -> approach); an approaching enemy with a ready
## cooldown and the hero centre within 3R/4 starts `tell`: the direction to the hero is fixed,
## the cooldown (kind interval) restarts and the attack instance takes the next attack uid.
## The tell starts in that tick and lasts telegraph_ticks ticks. An attacking enemy does not
## chase and takes no part in the separation (SeparationSystem). No float: the half arc test
## uses the golden COS_Q14 table.
## MELEE_ARC launches within 3R/4 and keeps its direction; the sector hits in the first active
## tick. CHARGE launches within its dash length L, aims again at the end of `tell` and never
## after; each active tick it dashes L // active_ticks su (clamped by the walls) and its first
## touch of the hero hits. PROJECTILE launches within its reach, aims again at the end of
## `tell` and releases one shot (EnemyShotSystem.release); the enemy is active for one tick and
## the shot lives active_ticks ticks.

const ST_APPROACH: int = 0
const ST_TELL: int = 1
const ST_ACTIVE: int = 2
const ST_RECOVER: int = 3
## round(16384 * cos(k degrees)) for k = 0..180, half away from zero (= sim_core.COS_Q14).
const COS_Q14: Array[int] = [
	16384, 16382, 16374, 16362, 16344, 16322, 16294, 16262, 16225, 16182, 16135, 16083, 16026,
	15964, 15897, 15826, 15749, 15668, 15582, 15491, 15396, 15296, 15191, 15082, 14968, 14849,
	14726, 14598, 14466, 14330, 14189, 14044, 13894, 13741, 13583, 13421, 13255, 13085, 12911,
	12733, 12551, 12365, 12176, 11982, 11786, 11585, 11381, 11174, 10963, 10749, 10531, 10311,
	10087, 9860, 9630, 9397, 9162, 8923, 8682, 8438, 8192, 7943, 7692, 7438, 7182, 6924, 6664,
	6402, 6138, 5872, 5604, 5334, 5063, 4790, 4516, 4240, 3964, 3686, 3406, 3126, 2845, 2563,
	2280, 1997, 1713, 1428, 1143, 857, 572, 286, 0, -286, -572, -857, -1143, -1428, -1713,
	-1997, -2280, -2563, -2845, -3126, -3406, -3686, -3964, -4240, -4516, -4790, -5063, -5334,
	-5604, -5872, -6138, -6402, -6664, -6924, -7182, -7438, -7692, -7943, -8192, -8438, -8682,
	-8923, -9162, -9397, -9630, -9860, -10087, -10311, -10531, -10749, -10963, -11174, -11381,
	-11585, -11786, -11982, -12176, -12365, -12551, -12733, -12911, -13085, -13255, -13421,
	-13583, -13741, -13894, -14044, -14189, -14330, -14466, -14598, -14726, -14849, -14968,
	-15082, -15191, -15296, -15396, -15491, -15582, -15668, -15749, -15826, -15897, -15964,
	-16026, -16083, -16135, -16182, -16225, -16262, -16294, -16322, -16344, -16362, -16374,
	-16382, -16384
]


static func run(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.enemy_slots():
		if not world.is_enemy_live(slot):
			continue
		var kind: int = world.enemy_kind[slot]
		if config.attack_value(kind, SimConfig.ATTACK_FORM) == SimConfig.FORM_CONTACT:
			continue
		if world.enemy_cooldown[slot] > 0:
			world.enemy_cooldown[slot] -= 1
		if world.enemy_state[slot] != ST_APPROACH:
			world.enemy_left[slot] -= 1
			if world.enemy_left[slot] == 0:
				_next_state(config, world, slot, kind)
		var form: int = config.attack_value(kind, SimConfig.ATTACK_FORM)
		var reach: int = config.attack_value(kind, SimConfig.ATTACK_REACH)
		if form == SimConfig.FORM_CHARGE and world.enemy_state[slot] == ST_ACTIVE:
			_dash(config, world, slot, Fx.floor_div(reach, config.attack_value(kind, SimConfig.ATTACK_ACTIVE)))
		var dx: int = world.player_x - world.enemy_x[slot]
		var dy: int = world.player_y - world.enemy_y[slot]
		var in_range: bool = in_launch_range(reach, dx, dy)
		if form == SimConfig.FORM_CHARGE or form == SimConfig.FORM_PROJECTILE:
			in_range = dx * dx + dy * dy <= reach * reach
		if world.enemy_state[slot] == ST_APPROACH and world.enemy_cooldown[slot] == 0 and in_range:
			var unit: PackedInt64Array = aim(world, slot)
			world.enemy_state[slot] = ST_TELL
			world.enemy_left[slot] = config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
			world.enemy_cooldown[slot] = config.kind_value(kind, SimConfig.KIND_INTERVAL)
			world.enemy_dir_x[slot] = unit[0]
			world.enemy_dir_y[slot] = unit[1]
			world.enemy_attack_uid[slot] = world.next_attack_uid
			world.next_attack_uid += 1


static func _next_state(config: SimConfig, world: WorldState, slot: int, kind: int) -> void:
	var state: int = world.enemy_state[slot]
	var recovery: int = config.attack_value(kind, SimConfig.ATTACK_RECOVERY)
	if state == ST_TELL:
		var form: int = config.attack_value(kind, SimConfig.ATTACK_FORM)
		world.enemy_state[slot] = ST_ACTIVE
		world.enemy_left[slot] = config.attack_value(kind, SimConfig.ATTACK_ACTIVE)
		if form == SimConfig.FORM_PROJECTILE:
			world.enemy_left[slot] = 1
		if form == SimConfig.FORM_CHARGE or form == SimConfig.FORM_PROJECTILE:
			var unit: PackedInt64Array = aim(world, slot)
			world.enemy_dir_x[slot] = unit[0]
			world.enemy_dir_y[slot] = unit[1]
			if form == SimConfig.FORM_PROJECTILE:
				EnemyShotSystem.release(config, world, slot)
			return
		var hit: bool = in_sector(
			config.attack_value(kind, SimConfig.ATTACK_REACH), config.attack_value(kind, SimConfig.ATTACK_ARC),
			world.enemy_dir_x[slot], world.enemy_dir_y[slot],
			world.player_x - world.enemy_x[slot], world.player_y - world.enemy_y[slot]
		)
		if hit:
			world.hero_hp -= config.kind_value(kind, SimConfig.KIND_DAMAGE)
			if config.attack_value(kind, SimConfig.ATTACK_VENOM) != 0:
				StatusSystem.add_venom(config, world)
	elif state == ST_ACTIVE and recovery > 0:
		world.enemy_state[slot] = ST_RECOVER
		world.enemy_left[slot] = recovery
	else:
		world.enemy_state[slot] = ST_APPROACH
		world.enemy_dir_x[slot] = 0
		world.enemy_dir_y[slot] = 0
		world.enemy_attack_uid[slot] = 0
		world.enemy_hit[slot] = 0


## Q14 direction from the enemy in `slot` to the hero; +x when they coincide.
static func aim(world: WorldState, slot: int) -> PackedInt64Array:
	var unit: PackedInt64Array = Fx.normalize_q14(
		world.player_x - world.enemy_x[slot], world.player_y - world.enemy_y[slot]
	)
	if unit[0] == 0 and unit[1] == 0:
		unit[0] = Fx.Q14
	return unit


## One active tick of a charge: `step` su along the fixed direction, clamped into the arena;
## the first touch of the hero in this attack instance deals the kind damage.
static func _dash(config: SimConfig, world: WorldState, slot: int, step: int) -> void:
	var kind: int = world.enemy_kind[slot]
	var r: int = config.kind_value(kind, SimConfig.KIND_RADIUS)
	var x: int = world.enemy_x[slot] + Fx.mul_q14(step, world.enemy_dir_x[slot])
	var y: int = world.enemy_y[slot] + Fx.mul_q14(step, world.enemy_dir_y[slot])
	world.enemy_x[slot] = clampi(x, config.arena_min_x + r, config.arena_max_x - r)
	world.enemy_y[slot] = clampi(y, config.arena_min_y + r, config.arena_max_y - r)
	if world.enemy_hit[slot] == 0 and EnemySystem.touching(config, world, slot):
		world.hero_hp -= config.kind_value(kind, SimConfig.KIND_DAMAGE)
		world.enemy_hit[slot] = 1


## The hero centre at (dx, dy) from the enemy is within 3R/4 (16 d^2 <= 9 R^2, tested after
## d^2 <= R^2 so the products stay inside int64).
static func in_launch_range(reach: int, dx: int, dy: int) -> bool:
	var d2: int = dx * dx + dy * dy
	return d2 <= reach * reach and 16 * d2 <= 9 * reach * reach


## (dx, dy) lies in the sector of radius `reach` and width `arc` degrees (1..180) around the
## Q14 direction (ux, uy): d <= R, dot >= 0 and cos(2 theta) >= cos(arc), with
## cos(2 theta) = 2 cos^2(theta) - 1 and dot = d cos(theta) floored to su. The centre is inside.
static func in_sector(reach: int, arc: int, ux: int, uy: int, dx: int, dy: int) -> bool:
	var d2: int = dx * dx + dy * dy
	if d2 > reach * reach:
		return false
	if d2 == 0:
		return true
	var dot: int = ux * dx + uy * dy
	if dot < 0:
		return false
	var dot_su: int = dot >> 14
	return 2 * dot_su * dot_su * Fx.Q14 >= d2 * (Fx.Q14 + COS_Q14[arc])
