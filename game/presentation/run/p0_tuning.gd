class_name P0Tuning
extends RefCounted
## P0 placeholder run setup: builds a SimConfig from canonical content plus placeholder bases.
##
## From content (read-only): the jade_grove roster window w0 (enemy IDs and spawn weights),
## each enemy's speed/radius/health multipliers and its CONTACT attack (damage multiplier,
## hit interval); the sword class start skill and its cooldown. NOT canonical (ADR-009
## section 3): the bases those multipliers scale (hero speed, radius and HP, base enemy HP
## and contact damage), spawn cadence, ramp and cap, arena size, and the skill's range,
## damage and projectile. They are placeholders until combat bases enter content; nothing
## here writes content.

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
const SKILL_RANGE_CELLS: int = 8
const SKILL_DAMAGE_MHP: int = 10000
const PROJECTILE_SPEED_SU: int = 12000
const PROJECTILE_RADIUS_PX: int = 10
const PROJECTILE_TTL_TICKS: int = 40
const PROJECTILE_PIERCE: int = 1
const MAX_PROJECTILES: int = 64

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


## Movement, the w0 enemies and the class start skill; null with `error` set when content is
## missing or invalid.
func run_config(registry: ContentRegistry, seed_text: String) -> SimConfig:
	enemy_ids.clear()
	if registry == null or not registry.is_valid():
		return _fail("content registry is not valid")
	var window: Dictionary = _window(registry.catalog("enemy_rosters"))
	if window.is_empty():
		return _fail("roster window " + WINDOW_ID + " not found")
	var kinds: PackedInt64Array = PackedInt64Array()
	for entry: Variant in window.get("weighted_enemies", []):
		var weighted: Dictionary = entry if entry is Dictionary else {}
		var enemy_id: String = str(weighted.get("enemy_id", ""))
		var record: PackedInt64Array = _kind(registry, enemy_id, weighted.get("weight"))
		if record.is_empty():
			return null
		kinds.append_array(record)
		enemy_ids.append(enemy_id)
	var values: PackedInt64Array = PackedInt64Array([
		HERO_HP_MHP, SPAWN_PERIOD_MT, SPAWN_RAMP_TICKS, SPAWN_RATE_MAX_FX, MAX_ENEMIES,
		MIN_SPAWN_DISTANCE_CELLS * CELL_PX * Fx.FX_ONE,
	])
	var skill: PackedInt64Array = _skill(registry)
	if skill.is_empty():
		return null
	var config: SimConfig = movement_config().with_enemies(values, kinds, seed_text).with_skill(skill)
	if not config.is_valid():
		return _fail("assembled run config is not valid")
	return config


func _kind(registry: ContentRegistry, enemy_id: String, weight: Variant) -> PackedInt64Array:
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
	if attack.get("kind") != "CONTACT":
		_fail(enemy_id + ": only CONTACT attacks are simulated in P0")
		return PackedInt64Array()
	var speed: Variant = Fx.from_catalog(stats.get("speed_mult"))
	var radius: Variant = Fx.from_catalog(stats.get("collision_radius_mult"))
	var health: Variant = Fx.from_catalog(stats.get("health_mult"))
	var damage: Variant = Fx.from_catalog(attack.get("damage_mult"))
	var interval: Variant = ContentRegistry.integral(params.get("hit_interval_ticks"))
	var spawn_weight: Variant = ContentRegistry.integral(weight)
	var numbers: Array = [speed, radius, health, damage, interval, spawn_weight]
	if numbers.has(null):
		_fail(enemy_id + ": stats, attack or weight are not exact catalog numbers")
		return PackedInt64Array()
	var fx: PackedInt64Array = PackedInt64Array(numbers)
	return PackedInt64Array([
		Fx.mul(HERO_SPEED_SU_PER_TICK, fx[0]),
		Fx.mul(HERO_RADIUS_PX * Fx.FX_ONE, fx[1]),
		Fx.mul(BASE_ENEMY_HP_MHP, fx[2]),
		Fx.mul(BASE_CONTACT_DAMAGE_MHP, fx[3]),
		fx[4],
		fx[5],
	])


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
