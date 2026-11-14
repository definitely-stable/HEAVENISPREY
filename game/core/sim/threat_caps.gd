class_name ThreatCaps
extends RefCounted
## Roster windows and threat_caps (ADR-011 section 5, E6). Exact port of
## tools/content/sim_core.py.
##
## Windows: SimConfig.windows holds one record of WINDOW_HEAD + kind_count() values per window,
## [start_tick, end_tick, max_control_near, weight per kind], contiguous from tick 0; the window
## of a tick is the first one with tick < end (the last one after its end). Without windows the
## kind records' weights are used.
## Spawn caps: a rolled kind over its cap (live projectile kinds, or death hazards = live
## death-zone kinds + live death zones) is replaced by the next kind in kind order (cyclic) with
## a weight in the window and under its caps, without a new RNG word; with none the spawn is
## skipped. Launch caps postpone a cast to a later tick: projectile and charge tells, live
## ground zones, and ground zones within the C_NEAR radius of the hero against the window's
## max_control_near.

const WINDOW_HEAD: int = 3
const C_SHOT_TELLS: int = 0
const C_CHARGE_TELLS: int = 1
const C_CONTROL_ZONES: int = 2
const C_DEATH_HAZARDS: int = 3
const C_RANGED: int = 4
const C_NEAR: int = 5
const CAPS_STRIDE: int = 6


## Offset of the window of `tick` in config.windows.
static func window_at(config: SimConfig, tick: int) -> int:
	var stride: int = WINDOW_HEAD + config.kind_count()
	var count: int = Fx.floor_div(config.windows.size(), stride)
	for index: int in count:
		if tick < config.windows[index * stride + 1]:
			return index * stride
	return (count - 1) * stride


static func spawn_weights(config: SimConfig, tick: int) -> PackedInt64Array:
	var weights: PackedInt64Array = PackedInt64Array()
	if config.windows.is_empty():
		for kind: int in config.kind_count():
			weights.append(config.kind_value(kind, SimConfig.KIND_WEIGHT))
		return weights
	var start: int = window_at(config, tick) + WINDOW_HEAD
	return config.windows.slice(start, start + config.kind_count())


## The rolled kind, the next allowed one over its cap, or -1 when every kind is capped.
static func allowed_kind(config: SimConfig, world: WorldState, weights: PackedInt64Array, kind: int) -> int:
	if config.caps.is_empty():
		return kind
	var count: int = config.kind_count()
	for step: int in count:
		var other: int = Fx.floor_mod(kind + step, count)
		if weights[other] > 0 and not _spawn_capped(config, world, other):
			return other
	return -1


static func launch_capped(config: SimConfig, world: WorldState, form: int) -> bool:
	if config.caps.is_empty():
		return false
	if form == SimConfig.FORM_PROJECTILE:
		return _live_of_form(config, world, form, EnemyAttackSystem.ST_TELL) >= config.caps[C_SHOT_TELLS]
	if form == SimConfig.FORM_CHARGE:
		return _live_of_form(config, world, form, EnemyAttackSystem.ST_TELL) >= config.caps[C_CHARGE_TELLS]
	if form != SimConfig.FORM_GROUND_ZONE:
		return false
	var zones: int = 0
	var close: int = 0
	var near: int = config.caps[C_NEAR] * config.caps[C_NEAR]
	for slot: int in world.zone_slots():
		if world.zone_form[slot] != SimConfig.FORM_GROUND_ZONE:
			continue
		zones += 1
		if EnemySystem.dist2(world.zone_x[slot], world.zone_y[slot], world.player_x, world.player_y) <= near:
			close += 1
	if zones >= config.caps[C_CONTROL_ZONES]:
		return true
	if config.windows.is_empty():
		return false
	return close >= config.windows[window_at(config, world.tick) + 2]


static func _spawn_capped(config: SimConfig, world: WorldState, kind: int) -> bool:
	var form: int = config.attack_value(kind, SimConfig.ATTACK_FORM)
	if form == SimConfig.FORM_PROJECTILE:
		return _live_of_form(config, world, form, -1) >= config.caps[C_RANGED]
	if form != SimConfig.FORM_DEATH_ZONE:
		return false
	var hazards: int = _live_of_form(config, world, form, -1)
	for slot: int in world.zone_slots():
		if world.zone_form[slot] == SimConfig.FORM_DEATH_ZONE:
			hazards += 1
	return hazards >= config.caps[C_DEATH_HAZARDS]


## Live enemies whose attack has `form` (in attack `state` when it is not -1).
static func _live_of_form(config: SimConfig, world: WorldState, form: int, state: int) -> int:
	var count: int = 0
	for slot: int in world.enemy_slots():
		if not world.is_enemy_live(slot):
			continue
		if config.attack_value(world.enemy_kind[slot], SimConfig.ATTACK_FORM) != form:
			continue
		if state < 0 or world.enemy_state[slot] == state:
			count += 1
	return count
