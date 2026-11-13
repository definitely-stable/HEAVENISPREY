class_name WorldState
extends RefCounted
## IC-05 (first slices): the complete simulation state, integers only (ADR-008).
##
## `tick` is the next tick to simulate. Enemies live in parallel arrays indexed by slot;
## slots keep spawn order, which is the order every per-enemy phase iterates in.
## The state digest is SHA-256 over the little-endian bytes of `to_ints()`, never `hash()`
## or `var_to_bytes`.

var tick: int = 0
var player_x: int = 0
var player_y: int = 0
var move_x: int = 0
var move_y: int = 0
## Index of the next CommandLog record to apply.
var command_cursor: int = 0

var hero_hp: int = 0
## 1 once the hero's HP reached 0; the run is over and further steps do nothing.
var hero_dead: int = 0
var next_spawn_tick: int = 0
## Words consumed from the hip-rng-v1 `enemy` stream of the run seed.
var enemy_rng_cursor: int = 0
var enemy_kind: PackedInt64Array = PackedInt64Array()
var enemy_x: PackedInt64Array = PackedInt64Array()
var enemy_y: PackedInt64Array = PackedInt64Array()
var enemy_hp: PackedInt64Array = PackedInt64Array()
## Ticks until the enemy's contact attack may hit again (0 = ready).
var enemy_cooldown: PackedInt64Array = PackedInt64Array()


static func initial(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.new()
	world.player_x = config.start_x
	world.player_y = config.start_y
	world.hero_hp = config.hero_hp_mhp
	world.next_spawn_tick = config.spawn_period_ticks
	return world


func enemy_count() -> int:
	return enemy_kind.size()


func is_over() -> bool:
	return hero_dead != 0


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([
		tick, player_x, player_y, move_x, move_y, command_cursor,
		hero_hp, hero_dead, next_spawn_tick, enemy_rng_cursor, enemy_count(),
	])
	for slot: int in enemy_count():
		out.append_array(PackedInt64Array([
			enemy_kind[slot], enemy_x[slot], enemy_y[slot], enemy_hp[slot], enemy_cooldown[slot],
		]))
	return out


func digest() -> String:
	return ContentRegistry.sha256_hex(to_ints().to_byte_array())


func copy() -> WorldState:
	var other: WorldState = WorldState.new()
	other.tick = tick
	other.player_x = player_x
	other.player_y = player_y
	other.move_x = move_x
	other.move_y = move_y
	other.command_cursor = command_cursor
	other.hero_hp = hero_hp
	other.hero_dead = hero_dead
	other.next_spawn_tick = next_spawn_tick
	other.enemy_rng_cursor = enemy_rng_cursor
	other.enemy_kind = enemy_kind.duplicate()
	other.enemy_x = enemy_x.duplicate()
	other.enemy_y = enemy_y.duplicate()
	other.enemy_hp = enemy_hp.duplicate()
	other.enemy_cooldown = enemy_cooldown.duplicate()
	return other
