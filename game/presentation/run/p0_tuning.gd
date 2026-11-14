class_name P0Tuning
extends RefCounted
## P0 placeholder run setup: builds a SimConfig from canonical content plus placeholder bases.
##
## From content (read-only): the jade_grove roster window w0 (enemy IDs and spawn weights),
## each enemy's speed/radius/health multipliers and its attack: CONTACT (damage multiplier,
## hit interval), MELEE_ARC (damage multiplier, telegraph/active/recovery/cooldown ticks,
## radius multiplier of the danger radius H, arc degrees, status.venom), CHARGE (the same
## timings, dash length in hero radii, no retarget) or PROJECTILE (the same timings, the
## active ticks as the shot lifetime, shot speed in hero speeds; one shot, no homing, aim
## locked at the end of tell), ON_DEATH_ZONE (telegraph, persistent ticks, the zone of radius
## H) or GROUND_ZONE (the same timings, radius multiplier of H, status.root_slow, one zone per
## caster, no barrier) with the venom and root values from the status catalog (ADR-011); the
## sword class start skill and its cooldown. NOT canonical (ADR-009 section 3): the bases
## those multipliers scale (hero speed, radius and HP, base enemy HP and contact damage),
## spawn cadence, ramp and cap, arena size, the skill's range, damage and projectile, the
## enemy shot radius, launch range and keep distance, the ground-zone launch range
## (ADR-011 section 3), and the XP
## settings of ADR-010 (pickup radius, gem cap, level costs, XP per kind = XP_BASE +
## XP_PER_SPAWN_COST x the enemy's content spawn_cost). They are placeholders until combat
## bases enter content; nothing here writes content.

const CELL_PX: int = 48
const ARENA_CELLS: Vector2i = Vector2i(32, 20)
const HERO_RADIUS_PX: int = 24
const HERO_SPEED_SU_PER_TICK: int = 4800
const HERO_HP_MHP: int = 100000
const BASE_ENEMY_HP_MHP: int = 10000
const BASE_CONTACT_DAMAGE_MHP: int = 10000
## One spawn per 1.5 s at x1 rate; the rate grows by x1 every 3 min up to x2.
const SPAWN_PERIOD_MT: int = 90000
const SPAWN_RAMP_TICKS: int = 10800
const SPAWN_RATE_MAX_FX: int = 2000
const MAX_ENEMIES: int = 48
const MIN_SPAWN_DISTANCE_CELLS: int = 8
const ROSTER_ID: String = "roster.jade_grove"
const WINDOW_ID: String = "jade_grove.w0"
const CLASS_ID: String = "class.sword"
const STAGE_ID: String = "stage.jade_grove"
## Base danger radius H = 2 cells (ADR-011 section 3, placeholder).
const DANGER_RADIUS_SU: int = 2 * CELL_PX * Fx.FX_ONE
const VENOM_ID: String = "status.venom"
const ROOT_ID: String = "status.root_slow"
## Enemy shots (ADR-011 section 3, placeholders): a ranged kind launches within 8 cells,
## stops chasing at 6 cells; the shot radius is 8 px.
const RANGED_TRIGGER_CELLS: int = 8
const KEEP_DISTANCE_CELLS: int = 6
## A ground-zone caster launches within 8 cells (ADR-011 section 3, placeholder).
const ZONE_TRIGGER_CELLS: int = 8
const ENEMY_SHOT_RADIUS_PX: int = 8
const SKILL_RANGE_CELLS: int = 8
const SKILL_DAMAGE_MHP: int = 10000
const PROJECTILE_SPEED_SU: int = 12000
const PROJECTILE_RADIUS_PX: int = 10
const PROJECTILE_TTL_TICKS: int = 40
const PROJECTILE_PIERCE: int = 1
const MAX_PROJECTILES: int = 64
const PICKUP_RADIUS_PX: int = 48
const MAX_GEMS: int = 512
const XP_BASE: int = 5
const XP_PER_SPAWN_COST: int = 5
## Incremental level costs (5L^2 + 15L + 20) / 2 for levels 2..21; the last one repeats.
const XP_COSTS: Array[int] = [
	20, 35, 55, 80, 110, 145, 185, 230, 280, 335, 395, 460, 530, 605, 685, 770, 860, 955, 1055, 1160,
]

var error: String = ""
## Enemy IDs in kind order (kind index = position).
var enemy_ids: PackedStringArray = PackedStringArray()
## The hero's auto-attack skill (the class start skill).
var skill_id: String = ""


## Movement only: the hero in the empty arena.
static func movement_config() -> SimConfig:
	var w: int = ARENA_CELLS.x * CELL_PX * Fx.FX_ONE
	var h: int = ARENA_CELLS.y * CELL_PX * Fx.FX_ONE
	return SimConfig.create(PackedInt64Array([
		HERO_SPEED_SU_PER_TICK, HERO_RADIUS_PX * Fx.FX_ONE, 0, 0, w, h, w >> 1, h >> 1,
	]))


## Movement, the w0 enemies, the class start skill, XP, the immediate level-up choice and the
## stage duration; null with `error` set when content is missing or invalid.
func run_config(registry: ContentRegistry, seed_text: String) -> SimConfig:
	enemy_ids.clear()
	if registry == null or not registry.is_valid():
		return _fail("content registry is not valid")
	var window: Dictionary = _window(registry.catalog("enemy_rosters"))
	if window.is_empty():
		return _fail("roster window " + WINDOW_ID + " not found")
	var kinds: PackedInt64Array = PackedInt64Array()
	var attacks: PackedInt64Array = PackedInt64Array()
	var has_arcs: bool = false
	var kind_xp: PackedInt64Array = PackedInt64Array()
	for entry: Variant in window.get("weighted_enemies", []):
		var weighted: Dictionary = entry if entry is Dictionary else {}
		var enemy_id: String = str(weighted.get("enemy_id", ""))
		var record: PackedInt64Array = kind_record(registry, enemy_id, weighted.get("weight"))
		if record.is_empty():
			return null
		attacks.append_array(record.slice(SimConfig.KIND_STRIDE))
		has_arcs = has_arcs or record[SimConfig.KIND_STRIDE] != SimConfig.FORM_CONTACT
		record = record.slice(0, SimConfig.KIND_STRIDE)
		var spawn_cost: Variant = ContentRegistry.integral(registry.definition(enemy_id).get("spawn_cost"))
		if spawn_cost == null or int(spawn_cost) < 0:
			return _fail(enemy_id + ": spawn_cost is not a non-negative integer")
		kinds.append_array(record)
		kind_xp.append(XP_BASE + XP_PER_SPAWN_COST * int(spawn_cost))
		enemy_ids.append(enemy_id)
	var values: PackedInt64Array = PackedInt64Array([
		HERO_HP_MHP, SPAWN_PERIOD_MT, SPAWN_RAMP_TICKS, SPAWN_RATE_MAX_FX, MAX_ENEMIES,
		MIN_SPAWN_DISTANCE_CELLS * CELL_PX * Fx.FX_ONE,
	])
	var skill: PackedInt64Array = _skill(registry)
	if skill.is_empty():
		return null
	var config: SimConfig = movement_config().with_enemies(values, kinds, seed_text).with_skill(skill)
	if has_arcs:
		var venom: PackedInt64Array = venom_values(registry)
		var root: PackedInt64Array = root_values(registry)
		if venom.is_empty() or root.is_empty():
			return null
		config.with_attacks(attacks, venom, root)
	config.with_xp(
		PackedInt64Array([PICKUP_RADIUS_PX * Fx.FX_ONE, MAX_GEMS]), kind_xp, PackedInt64Array(XP_COSTS)
	)
	# Immediate level-up choice: the run pauses on a pending choice (ADR-010 section 6).
	config.with_choice_mode(SimConfig.CHOICE_IMMEDIATE)
	# Victory after the stage duration from content (ADR-011 section 1).
	var minutes: Variant = ContentRegistry.integral(registry.definition(STAGE_ID).get("duration_minutes"))
	if minutes == null or int(minutes) <= 0:
		return _fail(STAGE_ID + ": duration_minutes is not a positive integer")
	config.with_run_ticks(int(minutes) * 60 * Fx.TICKS_PER_SECOND)
	if not config.is_valid():
		return _fail("assembled run config is not valid")
	return config


## The SimConfig kind record of `enemy_id` (KIND_STRIDE values) followed by its attack record
## (ATTACK_STRIDE values, all zeros for CONTACT); empty with `error` set when content is not
## usable in P0.
func kind_record(registry: ContentRegistry, enemy_id: String, weight: Variant) -> PackedInt64Array:
	var enemy: Dictionary = registry.definition(enemy_id)
	var stats: Dictionary = enemy.get("stats", {})
	var attack_ids: Array = enemy.get("attack_ids", [])
	if enemy.is_empty() or attack_ids.size() != 1:
		_fail(enemy_id + ": needs exactly one attack in P0")
		return PackedInt64Array()
	if enemy.get("combat_tier") != "normal":
		_fail(enemy_id + ": only normal-tier enemies belong to a P0 wave")
		return PackedInt64Array()
	var attack: Dictionary = registry.definition(str(attack_ids[0]))
	var params: Dictionary = attack.get("params", {})
	var form: String = str(attack.get("kind", ""))
	if not ["CONTACT", "MELEE_ARC", "CHARGE", "PROJECTILE", "ON_DEATH_ZONE", "GROUND_ZONE"].has(form):
		_fail(enemy_id + ": " + form + " attacks are not simulated")
		return PackedInt64Array()
	var speed: Variant = Fx.from_catalog(stats.get("speed_mult"))
	var radius: Variant = Fx.from_catalog(stats.get("collision_radius_mult"))
	var health: Variant = Fx.from_catalog(stats.get("health_mult"))
	var damage: Variant = Fx.from_catalog(attack.get("damage_mult"))
	var interval: Variant = ContentRegistry.integral(params.get("hit_interval_ticks"))
	var attack_record: PackedInt64Array = PackedInt64Array()
	attack_record.resize(SimConfig.ATTACK_STRIDE)
	if form != "CONTACT":
		interval = ContentRegistry.integral(attack.get("cooldown_ticks"))
		if form == "MELEE_ARC":
			attack_record = _arc_record(enemy_id, attack)
		elif form == "CHARGE":
			attack_record = _charge_record(enemy_id, attack)
		elif form == "PROJECTILE":
			attack_record = _projectile_record(enemy_id, attack)
		else:
			attack_record = _zone_record(enemy_id, attack)
		if attack_record.is_empty():
			return PackedInt64Array()
	var spawn_weight: Variant = ContentRegistry.integral(weight)
	var numbers: Array = [speed, radius, health, damage, interval, spawn_weight]
	if numbers.has(null):
		_fail(enemy_id + ": stats, attack or weight are not exact catalog numbers")
		return PackedInt64Array()
	var fx: PackedInt64Array = PackedInt64Array(numbers)
	var record: PackedInt64Array = PackedInt64Array([
		Fx.mul(HERO_SPEED_SU_PER_TICK, fx[0]),
		Fx.mul(HERO_RADIUS_PX * Fx.FX_ONE, fx[1]),
		Fx.mul(BASE_ENEMY_HP_MHP, fx[2]),
		Fx.mul(BASE_CONTACT_DAMAGE_MHP, fx[3]),
		fx[4],
		fx[5],
	])
	record.append_array(attack_record)
	return record


## MELEE_ARC attack record: [FORM_ARC, telegraph, active, recovery, radius_mult x H, arc
## degrees, 1 when it applies status.venom, 0, 0, 0].
func _arc_record(enemy_id: String, attack: Dictionary) -> PackedInt64Array:
	var params: Dictionary = attack.get("params", {})
	var numbers: Array = [
		ContentRegistry.integral(attack.get("telegraph_ticks")),
		ContentRegistry.integral(attack.get("active_ticks")),
		ContentRegistry.integral(attack.get("recovery_ticks")),
		Fx.from_catalog(params.get("radius_mult")),
		ContentRegistry.integral(params.get("arc_degrees")),
	]
	var status: Variant = attack.get("apply_status_id")
	if numbers.has(null) or (status != null and status != VENOM_ID):
		_fail(enemy_id + ": MELEE_ARC timings, radius, arc or status are not usable in P0")
		return PackedInt64Array()
	return PackedInt64Array([
		SimConfig.FORM_ARC, numbers[0], numbers[1], numbers[2],
		Fx.mul(DANGER_RADIUS_SU, numbers[3]), numbers[4], 1 if status == VENOM_ID else 0, 0, 0, 0,
	])


## CHARGE attack record: [FORM_CHARGE, telegraph, active, recovery, dash_player_radii x hero
## radius, 0, 0, 0, 0, 0]; a charge that may retarget is not simulated.
func _charge_record(enemy_id: String, attack: Dictionary) -> PackedInt64Array:
	var params: Dictionary = attack.get("params", {})
	var numbers: Array = [
		ContentRegistry.integral(attack.get("telegraph_ticks")),
		ContentRegistry.integral(attack.get("active_ticks")),
		ContentRegistry.integral(attack.get("recovery_ticks")),
		Fx.from_catalog(params.get("dash_player_radii")),
	]
	if numbers.has(null) or params.get("can_retarget") != false or attack.get("apply_status_id") != null:
		_fail(enemy_id + ": CHARGE timings, dash length, retarget or status are not usable in P0")
		return PackedInt64Array()
	return PackedInt64Array([
		SimConfig.FORM_CHARGE, numbers[0], numbers[1], numbers[2],
		Fx.mul(HERO_RADIUS_PX * Fx.FX_ONE, numbers[3]), 0, 0, 0, 0, 0,
	])


## PROJECTILE attack record: [FORM_PROJECTILE, telegraph, shot lifetime (active_ticks),
## recovery, launch range, 0, 0, shot speed (speed mult x hero speed), shot radius, keep
## distance]; only one unguided shot per cast, aimed at the end of tell, is simulated.
func _projectile_record(enemy_id: String, attack: Dictionary) -> PackedInt64Array:
	var params: Dictionary = attack.get("params", {})
	var numbers: Array = [
		ContentRegistry.integral(attack.get("telegraph_ticks")),
		ContentRegistry.integral(attack.get("active_ticks")),
		ContentRegistry.integral(attack.get("recovery_ticks")),
		Fx.from_catalog(params.get("projectile_speed_as_player_mult")),
	]
	var shape_ok: bool = (
		ContentRegistry.integral(params.get("projectiles_per_cast")) == 1
		and params.get("homing") == false
		and params.get("aim_lock") == "telegraph_end"
		and attack.get("apply_status_id") == null
	)
	if numbers.has(null) or not shape_ok:
		_fail(enemy_id + ": PROJECTILE timings, speed, shot count, homing, aim or status are not usable in P0")
		return PackedInt64Array()
	return PackedInt64Array([
		SimConfig.FORM_PROJECTILE, numbers[0], numbers[1], numbers[2],
		RANGED_TRIGGER_CELLS * CELL_PX * Fx.FX_ONE, 0, 0,
		Fx.mul(HERO_SPEED_SU_PER_TICK, numbers[3]), ENEMY_SHOT_RADIUS_PX * Fx.FX_ONE,
		KEEP_DISTANCE_CELLS * CELL_PX * Fx.FX_ONE,
	])


## Zone attack record: ON_DEATH_ZONE [FORM_DEATH_ZONE, telegraph, persistent ticks, 0, 0, 0,
## 0, 0, H, 0] (needs requires_death and no retrigger by a death proc); GROUND_ZONE
## [FORM_GROUND_ZONE, telegraph, persistent ticks, recovery, launch range, 0, 0, 0,
## radius_mult x H, 0] (status.root_slow, one zone per caster, no solid barrier). The
## persistent ticks must equal active_ticks.
func _zone_record(enemy_id: String, attack: Dictionary) -> PackedInt64Array:
	var params: Dictionary = attack.get("params", {})
	var death: bool = attack.get("kind") == "ON_DEATH_ZONE"
	var numbers: Array = [
		ContentRegistry.integral(attack.get("telegraph_ticks")),
		ContentRegistry.integral(attack.get("active_ticks")),
		ContentRegistry.integral(attack.get("recovery_ticks")),
		ContentRegistry.integral(params.get("persistent_ticks")),
	]
	var shape_ok: bool = not numbers.has(null) and numbers[1] == numbers[3]
	if death:
		shape_ok = (
			shape_ok
			and params.get("requires_death") == true
			and params.get("no_retrigger_by_death_proc") == true
			and numbers[2] == 0
			and ContentRegistry.integral(attack.get("cooldown_ticks")) == 0
			and attack.get("apply_status_id") == null
		)
		if not shape_ok:
			_fail(enemy_id + ": ON_DEATH_ZONE timings, death trigger, retrigger or status are not usable in P0")
			return PackedInt64Array()
		return PackedInt64Array([SimConfig.FORM_DEATH_ZONE, numbers[0], numbers[1], 0, 0, 0, 0, 0, DANGER_RADIUS_SU, 0])
	var radius: Variant = Fx.from_catalog(params.get("radius_mult"))
	shape_ok = (
		shape_ok
		and radius != null
		and attack.get("apply_status_id") == ROOT_ID
		and params.get("solid_barrier") == false
		and ContentRegistry.integral(params.get("max_zones_per_caster")) == 1
		and Fx.from_catalog(attack.get("damage_mult")) == 0
	)
	if not shape_ok:
		_fail(enemy_id + ": GROUND_ZONE timings, radius, status, barrier or zone count are not usable in P0")
		return PackedInt64Array()
	return PackedInt64Array([
		SimConfig.FORM_GROUND_ZONE, numbers[0], numbers[1], numbers[2],
		ZONE_TRIGGER_CELLS * CELL_PX * Fx.FX_ONE, 0, 0, 0, Fx.mul(DANGER_RADIUS_SU, radius), 0,
	])


## status.root_slow from the status catalog: [duration_ticks, movement_speed_multiplier fx];
## empty with `error` set when the entry is incomplete or not a one-stack refresh.
func root_values(registry: ContentRegistry) -> PackedInt64Array:
	var root: Dictionary = registry.definition(ROOT_ID)
	var duration: Variant = ContentRegistry.integral(root.get("duration_ticks"))
	var mult: Variant = Fx.from_catalog(root.get("movement_speed_multiplier"))
	var shape_ok: bool = (
		root.get("stack_policy") == "refresh_only"
		and ContentRegistry.integral(root.get("max_stacks")) == 1
		and ContentRegistry.integral(root.get("dot_damage")) == 0
	)
	if duration == null or mult == null or not shape_ok:
		_fail(ROOT_ID + ": duration, speed multiplier or stacking are not usable in P0")
		return PackedInt64Array()
	return PackedInt64Array([duration, mult])


## status.venom from the status catalog: [max_stacks, duration_ticks, tick_period_ticks,
## dot_damage x 1000 mhp]; empty with `error` set when the entry is incomplete.
func venom_values(registry: ContentRegistry) -> PackedInt64Array:
	var venom: Dictionary = registry.definition(VENOM_ID)
	var numbers: Array = [
		ContentRegistry.integral(venom.get("max_stacks")),
		ContentRegistry.integral(venom.get("duration_ticks")),
		ContentRegistry.integral(venom.get("tick_period_ticks")),
		ContentRegistry.integral(venom.get("dot_damage")),
	]
	if numbers.has(null):
		_fail(VENOM_ID + ": stacks, duration, period or damage are not integers")
		return PackedInt64Array()
	return PackedInt64Array([numbers[0], numbers[1], numbers[2], int(numbers[3]) * Fx.FX_ONE])


func _skill(registry: ContentRegistry) -> PackedInt64Array:
	skill_id = str(registry.definition(CLASS_ID).get("start_skill_id", ""))
	var skill: Dictionary = registry.definition(skill_id)
	if skill.get("archetype") != "projectile":
		_fail(CLASS_ID + ": the start skill must be a projectile skill in P0")
		return PackedInt64Array()
	var cooldown: Variant = ContentRegistry.integral(skill.get("base_cooldown_ticks"))
	if cooldown == null or int(cooldown) <= 0:
		_fail(skill_id + ": base_cooldown_ticks is not a positive integer")
		return PackedInt64Array()
	return PackedInt64Array([
		int(cooldown) * SimConfig.RATE_ONE,
		SKILL_RANGE_CELLS * CELL_PX * Fx.FX_ONE,
		SKILL_DAMAGE_MHP,
		PROJECTILE_SPEED_SU,
		PROJECTILE_RADIUS_PX * Fx.FX_ONE,
		PROJECTILE_TTL_TICKS,
		PROJECTILE_PIERCE,
		MAX_PROJECTILES,
	])


static func _window(rosters_catalog: Dictionary) -> Dictionary:
	for roster: Variant in rosters_catalog.get("rosters", []):
		if roster is Dictionary and (roster as Dictionary).get("id") == ROSTER_ID:
			for window: Variant in (roster as Dictionary).get("windows", []):
				if window is Dictionary and (window as Dictionary).get("id") == WINDOW_ID:
					return window
	return {}


func _fail(message: String) -> SimConfig:
	if error.is_empty():
		error = message
	return null
