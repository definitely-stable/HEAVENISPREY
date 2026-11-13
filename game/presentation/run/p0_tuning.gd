class_name P0Tuning
extends RefCounted
## P0 placeholder run setup: builds a SimConfig from canonical content plus placeholder bases.
##
## From content (read-only): the jade_grove roster window w0 (enemy IDs and spawn weights),
## each enemy's speed/radius/health multipliers and its CONTACT attack (damage multiplier,
## hit interval). NOT canonical: the bases those multipliers scale (hero speed, radius and HP,
## base enemy HP and contact damage), spawn cadence and cap, arena size. They are GAME-ARCH-02
## hypotheses until the hero/arena tuning is agreed; nothing here writes content.

const CELL_PX: int = 48
const ARENA_CELLS: Vector2i = Vector2i(32, 20)
const HERO_RADIUS_PX: int = 24
const HERO_SPEED_SU_PER_TICK: int = 4800
const HERO_HP_MHP: int = 100000
const BASE_ENEMY_HP_MHP: int = 10000
const BASE_CONTACT_DAMAGE_MHP: int = 10000
const SPAWN_PERIOD_TICKS: int = 45
const MAX_ENEMIES: int = 48
const MIN_SPAWN_DISTANCE_CELLS: int = 8
const ROSTER_ID: String = "roster.jade_grove"
const WINDOW_ID: String = "jade_grove.w0"

var error: String = ""
## Enemy IDs in kind order (kind index = position).
var enemy_ids: PackedStringArray = PackedStringArray()


## Movement only: the hero in the empty arena.
static func movement_config() -> SimConfig:
	var w: int = ARENA_CELLS.x * CELL_PX * Fx.FX_ONE
	var h: int = ARENA_CELLS.y * CELL_PX * Fx.FX_ONE
	return SimConfig.create(PackedInt64Array([
		HERO_SPEED_SU_PER_TICK, HERO_RADIUS_PX * Fx.FX_ONE, 0, 0, w, h, w >> 1, h >> 1,
	]))


## Movement plus the w0 enemies; null with `error` set when content is missing or invalid.
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
		HERO_HP_MHP, SPAWN_PERIOD_TICKS, MAX_ENEMIES,
		MIN_SPAWN_DISTANCE_CELLS * CELL_PX * Fx.FX_ONE,
	])
	var config: SimConfig = movement_config().with_enemies(values, kinds, seed_text)
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
