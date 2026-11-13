class_name SimConfig
extends RefCounted
## Integer parameters of one simulated run (hip-fx-v1 units: su, su/tick, mhp, ticks).
##
## Movement (P0-01b): hero speed and radius, arena rectangle, start point.
## Enemies (P0-01d, optional): enemy kinds, spawn cadence and cap, hero HP and the run seed of
## the `enemy` RNG stream. With no kinds the run has no enemies and the hero cannot die.
## Values come from typed content definitions in later slices; tests pass them directly.

## Enemy kind record: [speed_su_per_tick, radius_su, hp_mhp, contact_damage_mhp,
## contact_interval_ticks, spawn_weight].
const KIND_STRIDE: int = 6
const KIND_SPEED: int = 0
const KIND_RADIUS: int = 1
const KIND_HP: int = 2
const KIND_DAMAGE: int = 3
const KIND_INTERVAL: int = 4
const KIND_WEIGHT: int = 5
const MAX_ENEMIES_LIMIT: int = 4096
## hip-rng-v1 below(n) accepts n <= 2^32.
const BELOW_LIMIT: int = 4294967296

var speed_su_per_tick: int = 0
var player_radius_su: int = 0
var arena_min_x: int = 0
var arena_min_y: int = 0
var arena_max_x: int = 0
var arena_max_y: int = 0
var start_x: int = 0
var start_y: int = 0

var hero_hp_mhp: int = 0
var spawn_period_ticks: int = 0
var max_enemies: int = 0
var spawn_min_distance_su: int = 0
var run_seed: String = "0"
var kinds: PackedInt64Array = PackedInt64Array()


static func create(values: PackedInt64Array) -> SimConfig:
	var config: SimConfig = SimConfig.new()
	if values.size() != 8:
		return config
	config.speed_su_per_tick = values[0]
	config.player_radius_su = values[1]
	config.arena_min_x = values[2]
	config.arena_min_y = values[3]
	config.arena_max_x = values[4]
	config.arena_max_y = values[5]
	config.start_x = values[6]
	config.start_y = values[7]
	return config


## Enables enemies: `p_values` = [hero_hp_mhp, spawn_period_ticks, max_enemies,
## spawn_min_distance_su]; `p_kinds` = flat KIND_STRIDE records.
func with_enemies(p_values: PackedInt64Array, p_kinds: PackedInt64Array, p_seed: String) -> SimConfig:
	if p_values.size() == 4:
		hero_hp_mhp = p_values[0]
		spawn_period_ticks = p_values[1]
		max_enemies = p_values[2]
		spawn_min_distance_su = p_values[3]
	kinds = p_kinds.duplicate()
	run_seed = p_seed
	return self


func kind_count() -> int:
	return Fx.floor_div(kinds.size(), KIND_STRIDE)


func kind_value(kind: int, field: int) -> int:
	return kinds[kind * KIND_STRIDE + field]


func total_weight() -> int:
	var total: int = 0
	for kind: int in kind_count():
		total += kind_value(kind, KIND_WEIGHT)
	return total


func has_enemies() -> bool:
	return not kinds.is_empty()


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([
		speed_su_per_tick, player_radius_su, arena_min_x, arena_min_y,
		arena_max_x, arena_max_y, start_x, start_y,
		hero_hp_mhp, spawn_period_ticks, max_enemies, spawn_min_distance_su,
	])
	out.append_array(kinds)
	return out


## Bounds stay inside hip-fx-v1 coordinate limits, the hero fits, the start is reachable,
## and enemy settings (when present) are complete and drawable with hip-rng-v1.
func is_valid() -> bool:
	for value: int in to_ints():
		if absi(value) > Fx.COORD_MAX:
			return false
	var r: int = player_radius_su
	var movement_ok: bool = (
		speed_su_per_tick >= 0
		and r > 0
		and arena_max_x - arena_min_x >= 2 * r
		and arena_max_y - arena_min_y >= 2 * r
		and start_x >= arena_min_x + r
		and start_x <= arena_max_x - r
		and start_y >= arena_min_y + r
		and start_y <= arena_max_y - r
	)
	if not movement_ok:
		return false
	if not has_enemies():
		return true
	return _enemies_valid()


func _enemies_valid() -> bool:
	if kinds.size() != kind_count() * KIND_STRIDE or HipRng.parse_u64(run_seed).is_empty():
		return false
	if hero_hp_mhp <= 0 or spawn_period_ticks <= 0 or spawn_min_distance_su < 0:
		return false
	if max_enemies <= 0 or max_enemies > MAX_ENEMIES_LIMIT:
		return false
	var total: int = total_weight()
	if total <= 0 or total > BELOW_LIMIT:
		return false
	for kind: int in kind_count():
		var radius: int = kind_value(kind, KIND_RADIUS)
		var perimeter: int = 2 * (arena_max_x - arena_min_x - 4 * radius + arena_max_y - arena_min_y)
		var kind_ok: bool = (
			kind_value(kind, KIND_SPEED) >= 0
			and radius > 0
			and arena_max_x - arena_min_x > 2 * radius
			and arena_max_y - arena_min_y > 2 * radius
			and perimeter <= BELOW_LIMIT
			and kind_value(kind, KIND_HP) > 0
			and kind_value(kind, KIND_DAMAGE) >= 0
			and kind_value(kind, KIND_INTERVAL) > 0
			and kind_value(kind, KIND_WEIGHT) > 0
		)
		if not kind_ok:
			return false
	return true
