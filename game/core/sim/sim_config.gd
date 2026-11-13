class_name SimConfig
extends RefCounted
## Integer parameters of one simulated run (hip-fx-v1 units: su, su/tick, mhp, ticks, mt).
##
## Movement (P0-01b): hero speed and radius, arena rectangle, start point.
## Enemies (P0-01E, ADR-009 section 3): kinds, accumulator spawn with a linear rate ramp,
## alive cap, minimum spawn distance, hero HP and the run seed of the `enemy` RNG stream.
## Hero skill (ADR-009 section 1): accumulator cooldown, acquire range, projectile.
## XP (ADR-010): pickup radius, gem slot cap, XP per kind (kind order), level costs.
## Level-up choice (ADR-010 section 6): choice_mode 0 never stops the run (choices stay
## pending), 1 = Immediate (the run pauses for each choice; needs XP and the skill).
## Run end (ADR-011 section 1): run_ticks is the stage duration; a hero who is not dead after
## the tick that reaches it wins. 0 = no time limit.
## With no kinds the run has no enemies; with no skill damage the hero does not attack.

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
const MAX_PROJECTILES_LIMIT: int = 256
const MAX_PIERCE: int = 7
const MAX_GEMS_LIMIT: int = 4096
const MAX_XP_COSTS: int = 64
const MAX_KIND_XP: int = 1000000
const CHOICE_NONE: int = 0
const CHOICE_IMMEDIATE: int = 1
## Normal speed of an accumulator (ADR-008: rate_fx 1000 = x1).
const RATE_ONE: int = 1000
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
var spawn_period_mt: int = 0
## Ticks for the spawn rate to grow by +1000 (0 = constant rate).
var spawn_ramp_ticks: int = 0
var spawn_rate_max_fx: int = RATE_ONE
var max_enemies: int = 0
var spawn_min_distance_su: int = 0
var run_seed: String = "0"
var kinds: PackedInt64Array = PackedInt64Array()

var skill_period_mt: int = 0
var skill_range_su: int = 0
var skill_damage_mhp: int = 0
var projectile_speed_su: int = 0
var projectile_radius_su: int = 0
var projectile_ttl_ticks: int = 0
var projectile_pierce: int = 0
var max_projectiles: int = 0

var pickup_radius_su: int = 0
var max_gems: int = 0
## XP value of each kind's drop, in kind order (0 = drops nothing).
var kind_xp: PackedInt64Array = PackedInt64Array()
## Incremental XP cost of level L -> L + 1 from level 1; the last cost repeats.
var xp_costs: PackedInt64Array = PackedInt64Array()
var choice_mode: int = CHOICE_NONE
var run_ticks: int = 0


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


## Enables enemies: `p_values` = [hero_hp_mhp, spawn_period_mt, spawn_ramp_ticks,
## spawn_rate_max_fx, max_enemies, spawn_min_distance_su]; `p_kinds` = KIND_STRIDE records.
func with_enemies(p_values: PackedInt64Array, p_kinds: PackedInt64Array, p_seed: String) -> SimConfig:
	if p_values.size() == 6:
		hero_hp_mhp = p_values[0]
		spawn_period_mt = p_values[1]
		spawn_ramp_ticks = p_values[2]
		spawn_rate_max_fx = p_values[3]
		max_enemies = p_values[4]
		spawn_min_distance_su = p_values[5]
	kinds = p_kinds.duplicate()
	run_seed = p_seed
	return self


## Enables the hero skill: [period_mt, range_su, damage_mhp, projectile_speed_su,
## projectile_radius_su, projectile_ttl_ticks, projectile_pierce, max_projectiles].
func with_skill(p_values: PackedInt64Array) -> SimConfig:
	if p_values.size() == 8:
		skill_period_mt = p_values[0]
		skill_range_su = p_values[1]
		skill_damage_mhp = p_values[2]
		projectile_speed_su = p_values[3]
		projectile_radius_su = p_values[4]
		projectile_ttl_ticks = p_values[5]
		projectile_pierce = p_values[6]
		max_projectiles = p_values[7]
	return self


## Enables XP: `p_values` = [pickup_radius_su, max_gems]; `p_kind_xp` one value per kind;
## `p_costs` incremental level costs.
func with_xp(p_values: PackedInt64Array, p_kind_xp: PackedInt64Array, p_costs: PackedInt64Array) -> SimConfig:
	if p_values.size() == 2:
		pickup_radius_su = p_values[0]
		max_gems = p_values[1]
	kind_xp = p_kind_xp.duplicate()
	xp_costs = p_costs.duplicate()
	return self


## Sets the level-up choice mode (CHOICE_NONE or CHOICE_IMMEDIATE).
func with_choice_mode(p_mode: int) -> SimConfig:
	choice_mode = p_mode
	return self


## Sets the stage duration in ticks (0 = no time limit).
func with_run_ticks(p_ticks: int) -> SimConfig:
	run_ticks = p_ticks
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


func has_skill() -> bool:
	return skill_damage_mhp > 0


func has_xp() -> bool:
	return not xp_costs.is_empty()


## XP to go from `level` to `level + 1`; the last listed cost repeats.
func xp_cost(level: int) -> int:
	return xp_costs[mini(level - 1, xp_costs.size() - 1)]


## Ledger cells of every projectile slot: enough for the largest pierce an upgrade can reach;
## a projectile uses `pierce at cast + 1` of them (its capacity).
func ledger_size() -> int:
	return mini(MAX_PIERCE, projectile_pierce + UpgradeSystem.MAX_RANKS[UpgradeSystem.PIERCE]) + 1


## Spawn accumulator rate at `tick`: 1000 rising by 1000 every `spawn_ramp_ticks`, capped.
func spawn_rate(tick: int) -> int:
	if spawn_ramp_ticks <= 0:
		return RATE_ONE
	return mini(spawn_rate_max_fx, RATE_ONE + Fx.floor_div(tick * RATE_ONE, spawn_ramp_ticks))


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([
		speed_su_per_tick, player_radius_su, arena_min_x, arena_min_y,
		arena_max_x, arena_max_y, start_x, start_y,
		hero_hp_mhp, spawn_period_mt, spawn_ramp_ticks, spawn_rate_max_fx, max_enemies,
		spawn_min_distance_su, skill_period_mt, skill_range_su, skill_damage_mhp,
		projectile_speed_su, projectile_radius_su, projectile_ttl_ticks, projectile_pierce,
		max_projectiles,
	])
	out.append_array(kinds)
	out.append_array(PackedInt64Array([pickup_radius_su, max_gems]))
	out.append_array(kind_xp)
	out.append_array(xp_costs)
	out.append(choice_mode)
	out.append(run_ticks)
	return out


## Bounds stay inside hip-fx-v1 coordinate limits, the hero fits, the start is reachable,
## and enemy and skill settings (when present) are complete and safe to simulate.
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
	if has_enemies() and not _enemies_valid():
		return false
	if has_skill() and not _skill_valid():
		return false
	if (has_xp() or not kind_xp.is_empty()) and not _xp_valid():
		return false
	if choice_mode != CHOICE_NONE and choice_mode != CHOICE_IMMEDIATE:
		return false
	if choice_mode == CHOICE_IMMEDIATE and not (has_xp() and has_skill()):
		return false
	return run_ticks >= 0


func _enemies_valid() -> bool:
	if kinds.size() != kind_count() * KIND_STRIDE or HipRng.parse_u64(run_seed).is_empty():
		return false
	if hero_hp_mhp <= 0 or spawn_period_mt <= 0 or spawn_ramp_ticks < 0 or spawn_rate_max_fx < RATE_ONE:
		return false
	if spawn_min_distance_su < 0 or max_enemies <= 0 or max_enemies > MAX_ENEMIES_LIMIT:
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


## A projectile must not step over the smallest enemy in one tick (no tunnelling).
func _skill_valid() -> bool:
	if not has_enemies():
		return false
	var min_radius: int = Fx.COORD_MAX
	for kind: int in kind_count():
		min_radius = mini(min_radius, kind_value(kind, KIND_RADIUS))
	return (
		skill_period_mt > 0
		and skill_range_su >= 0
		and projectile_speed_su > 0
		and projectile_radius_su > 0
		and projectile_speed_su <= projectile_radius_su + min_radius
		and projectile_ttl_ticks > 0
		and projectile_pierce >= 0
		and projectile_pierce <= MAX_PIERCE
		and max_projectiles > 0
		and max_projectiles <= MAX_PROJECTILES_LIMIT
	)


## A gem falls where its enemy died: one dropped by an enemy touching the hero must be in
## reach, so the pickup radius is at least the hero radius minus the smallest kind radius.
func _xp_valid() -> bool:
	if not has_enemies() or kind_xp.size() != kind_count():
		return false
	if xp_costs.is_empty() or xp_costs.size() > MAX_XP_COSTS:
		return false
	for cost: int in xp_costs:
		if cost <= 0:
			return false
	var min_radius: int = Fx.COORD_MAX
	for kind: int in kind_count():
		min_radius = mini(min_radius, kind_value(kind, KIND_RADIUS))
		if kind_xp[kind] < 0 or kind_xp[kind] > MAX_KIND_XP:
			return false
	return (
		pickup_radius_su >= maxi(0, player_radius_su - min_radius)
		and max_gems > 0
		and max_gems <= MAX_GEMS_LIMIT
	)
