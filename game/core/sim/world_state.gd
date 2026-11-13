class_name WorldState
extends RefCounted
## IC-05: the complete simulation state, integers only (ADR-008, ADR-009 section 1).
##
## `tick` is the next tick to simulate. Enemies and hero projectiles live in parallel arrays
## indexed by slot. A slot is free when its enemy uid is 0 (projectile: damage 0) and then
## all its fields are 0; spawns take the lowest free slot, arrays never shrink, so slot
## order (= iteration order) stays deterministic. The state digest is SHA-256 over the
## little-endian bytes of `to_ints()`, never `hash()` or `var_to_bytes`.

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
## Spawn accumulator in milli-ticks (ADR-008 periodic processes).
var spawn_acc: int = 0
## Words consumed from the hip-rng-v1 `enemy` stream of the run seed.
var enemy_rng_cursor: int = 0
var next_enemy_uid: int = 1
var enemy_alive: int = 0
var kills: int = 0
## Hero skill cooldown accumulator in milli-ticks.
var skill_acc: int = 0
## Grid cell where the next separation pass starts (0 after a complete pass).
var sep_cursor: int = 0

var enemy_uid: PackedInt64Array = PackedInt64Array()
var enemy_kind: PackedInt64Array = PackedInt64Array()
var enemy_x: PackedInt64Array = PackedInt64Array()
var enemy_y: PackedInt64Array = PackedInt64Array()
var enemy_hp: PackedInt64Array = PackedInt64Array()
## Ticks until the enemy's contact attack may hit again (0 = ready).
var enemy_cooldown: PackedInt64Array = PackedInt64Array()

var proj_x: PackedInt64Array = PackedInt64Array()
var proj_y: PackedInt64Array = PackedInt64Array()
var proj_vx: PackedInt64Array = PackedInt64Array()
var proj_vy: PackedInt64Array = PackedInt64Array()
var proj_ttl: PackedInt64Array = PackedInt64Array()
var proj_pierce_left: PackedInt64Array = PackedInt64Array()
## Damage per hit; > 0 marks a live projectile.
var proj_damage: PackedInt64Array = PackedInt64Array()
## Enemy uids already hit, `ledger_stride` cells per projectile slot (0 = empty).
var proj_ledger: PackedInt64Array = PackedInt64Array()
var ledger_stride: int = 1


static func initial(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.new()
	world.player_x = config.start_x
	world.player_y = config.start_y
	world.hero_hp = config.hero_hp_mhp
	world.ledger_stride = config.ledger_size()
	return world


func enemy_slots() -> int:
	return enemy_uid.size()


func projectile_slots() -> int:
	return proj_damage.size()


func is_over() -> bool:
	return hero_dead != 0


func is_enemy_live(slot: int) -> bool:
	return enemy_uid[slot] != 0 and enemy_hp[slot] > 0


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([
		tick, player_x, player_y, move_x, move_y, command_cursor,
		hero_hp, hero_dead, spawn_acc, enemy_rng_cursor, next_enemy_uid, enemy_alive, kills,
		skill_acc, sep_cursor, enemy_slots(), projectile_slots(),
	])
	for slot: int in enemy_slots():
		out.append_array(PackedInt64Array([
			enemy_uid[slot], enemy_kind[slot], enemy_x[slot], enemy_y[slot], enemy_hp[slot],
			enemy_cooldown[slot],
		]))
	for slot: int in projectile_slots():
		out.append_array(PackedInt64Array([
			proj_x[slot], proj_y[slot], proj_vx[slot], proj_vy[slot], proj_ttl[slot],
			proj_pierce_left[slot], proj_damage[slot],
		]))
		out.append_array(proj_ledger.slice(slot * ledger_stride, (slot + 1) * ledger_stride))
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
	other.spawn_acc = spawn_acc
	other.enemy_rng_cursor = enemy_rng_cursor
	other.next_enemy_uid = next_enemy_uid
	other.enemy_alive = enemy_alive
	other.kills = kills
	other.skill_acc = skill_acc
	other.sep_cursor = sep_cursor
	other.enemy_uid = enemy_uid.duplicate()
	other.enemy_kind = enemy_kind.duplicate()
	other.enemy_x = enemy_x.duplicate()
	other.enemy_y = enemy_y.duplicate()
	other.enemy_hp = enemy_hp.duplicate()
	other.enemy_cooldown = enemy_cooldown.duplicate()
	other.proj_x = proj_x.duplicate()
	other.proj_y = proj_y.duplicate()
	other.proj_vx = proj_vx.duplicate()
	other.proj_vy = proj_vy.duplicate()
	other.proj_ttl = proj_ttl.duplicate()
	other.proj_pierce_left = proj_pierce_left.duplicate()
	other.proj_damage = proj_damage.duplicate()
	other.proj_ledger = proj_ledger.duplicate()
	other.ledger_stride = ledger_stride
	return other
