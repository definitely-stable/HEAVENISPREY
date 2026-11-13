class_name WorldState
extends RefCounted
## IC-05: the complete simulation state, integers only (ADR-008, ADR-009 section 1,
## ADR-010).
##
## `tick` is the next tick to simulate. Enemies and hero projectiles live in parallel arrays
## indexed by slot. A slot is free when its enemy uid is 0 (projectile: damage 0) and then
## all its fields are 0 (gem: uid 0); spawns and drops take the lowest free slot, arrays
## never shrink, so slot
## order (= iteration order) stays deterministic. A projectile keeps the damage and capacity
## (pierce + 1) of its cast and counts its hits; its first hit_count ledger cells are used.
## Enemy attacks (ADR-011 section 2): per slot the attack state, the ticks left in it, the
## direction fixed at the start of `tell` (Q14) and the attack instance uid (from
## next_attack_uid). status.venom on the hero (ADR-011 section 4): stacks, ticks left, ticks to
## the next damage.
## The build (ADR-010 section 6): upgrade ranks in UpgradeSystem code order, the maximum hero
## HP and the offered hand (non-empty only while the run is paused for a choice). The state
## digest is SHA-256 over the little-endian bytes of `to_ints()`, never `hash()` or
## `var_to_bytes`.

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
## 1 once the hero survived the stage duration (ADR-011 section 1); the run is over.
var won: int = 0
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
var next_gem_uid: int = 1
var gems_alive: int = 0
## Drops that joined the nearest gem because all gem slots were taken.
var gems_merged: int = 0
var xp_dropped_total: int = 0
var xp_collected_total: int = 0
## Collected XP not yet spent on a level.
var xp_bank: int = 0
var level: int = 1
## Earned level-up choices not resolved yet.
var pending_level_choices: int = 0
## Earned choices cancelled when the run ended.
var choices_voided: int = 0
var choices_done: int = 0
## Number of choices applied to the build; a CHOOSE names the revision its hand was built for.
var build_revision: int = 0
## Words consumed from the hip-rng-v1 `offers` stream of the run seed.
var offers_rng_cursor: int = 0
## Offered upgrade codes; the run is paused while it is not empty.
var hand: PackedInt64Array = PackedInt64Array()
## Upgrade ranks in UpgradeSystem code order.
var ranks: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0])
var hero_hp_max: int = 0
var next_attack_uid: int = 1
var venom_stacks: int = 0
var venom_left: int = 0
var venom_phase: int = 0

var enemy_uid: PackedInt64Array = PackedInt64Array()
var enemy_kind: PackedInt64Array = PackedInt64Array()
var enemy_x: PackedInt64Array = PackedInt64Array()
var enemy_y: PackedInt64Array = PackedInt64Array()
var enemy_hp: PackedInt64Array = PackedInt64Array()
## Ticks until the enemy's contact attack may hit again (0 = ready).
var enemy_cooldown: PackedInt64Array = PackedInt64Array()
## EnemySystem.ST_* attack state (0 = approach).
var enemy_state: PackedInt64Array = PackedInt64Array()
## Ticks left in the attack state.
var enemy_left: PackedInt64Array = PackedInt64Array()
var enemy_dir_x: PackedInt64Array = PackedInt64Array()
var enemy_dir_y: PackedInt64Array = PackedInt64Array()
## Uid of the current attack instance (0 = none).
var enemy_attack_uid: PackedInt64Array = PackedInt64Array()

var proj_x: PackedInt64Array = PackedInt64Array()
var proj_y: PackedInt64Array = PackedInt64Array()
var proj_vx: PackedInt64Array = PackedInt64Array()
var proj_vy: PackedInt64Array = PackedInt64Array()
var proj_ttl: PackedInt64Array = PackedInt64Array()
## Damage per hit, fixed at the cast; > 0 marks a live projectile.
var proj_damage: PackedInt64Array = PackedInt64Array()
var proj_hits: PackedInt64Array = PackedInt64Array()
## Targets the projectile may hit (pierce at the cast + 1); it is freed after that many hits.
var proj_capacity: PackedInt64Array = PackedInt64Array()
## Enemy uids already hit, `ledger_stride` cells per projectile slot (0 = empty).
var proj_ledger: PackedInt64Array = PackedInt64Array()
var ledger_stride: int = 1

var gem_uid: PackedInt64Array = PackedInt64Array()
var gem_x: PackedInt64Array = PackedInt64Array()
var gem_y: PackedInt64Array = PackedInt64Array()
var gem_value: PackedInt64Array = PackedInt64Array()


static func initial(config: SimConfig) -> WorldState:
	var world: WorldState = WorldState.new()
	world.player_x = config.start_x
	world.player_y = config.start_y
	world.hero_hp = config.hero_hp_mhp
	world.hero_hp_max = config.hero_hp_mhp
	world.ledger_stride = config.ledger_size()
	return world


func enemy_slots() -> int:
	return enemy_uid.size()


## Appends a free enemy slot (all fields 0) and returns its index.
func append_enemy_slot() -> int:
	# Packed arrays are values: each member is appended to directly, not through a list.
	enemy_uid.append(0)
	enemy_kind.append(0)
	enemy_x.append(0)
	enemy_y.append(0)
	enemy_hp.append(0)
	enemy_cooldown.append(0)
	enemy_state.append(0)
	enemy_left.append(0)
	enemy_dir_x.append(0)
	enemy_dir_y.append(0)
	enemy_attack_uid.append(0)
	return enemy_slots() - 1


func projectile_slots() -> int:
	return proj_damage.size()


func gem_slots() -> int:
	return gem_uid.size()


func is_over() -> bool:
	return hero_dead != 0 or won != 0


## The run waits for a CHOOSE: no tick is simulated while a hand is offered.
func is_paused() -> bool:
	return not hand.is_empty()


func is_enemy_live(slot: int) -> bool:
	return enemy_uid[slot] != 0 and enemy_hp[slot] > 0


func to_ints() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([
		tick, player_x, player_y, move_x, move_y, command_cursor,
		hero_hp, hero_dead, won, spawn_acc, enemy_rng_cursor, next_enemy_uid, enemy_alive, kills,
		skill_acc, sep_cursor, next_gem_uid, gems_alive, gems_merged, xp_dropped_total,
		xp_collected_total, xp_bank, level, pending_level_choices, choices_voided,
		choices_done, build_revision, offers_rng_cursor,
	])
	for card: int in UpgradeSystem.HAND_SIZE:
		out.append(hand[card] if card < hand.size() else UpgradeSystem.NO_CARD)
	out.append_array(ranks)
	out.append_array(PackedInt64Array([
		hero_hp_max, next_attack_uid, venom_stacks, venom_left, venom_phase,
		enemy_slots(), projectile_slots(), gem_slots(),
	]))
	for slot: int in enemy_slots():
		out.append_array(PackedInt64Array([
			enemy_uid[slot], enemy_kind[slot], enemy_x[slot], enemy_y[slot], enemy_hp[slot],
			enemy_cooldown[slot], enemy_state[slot], enemy_left[slot], enemy_dir_x[slot],
			enemy_dir_y[slot], enemy_attack_uid[slot],
		]))
	for slot: int in projectile_slots():
		out.append_array(PackedInt64Array([
			proj_x[slot], proj_y[slot], proj_vx[slot], proj_vy[slot], proj_ttl[slot],
			proj_damage[slot], proj_hits[slot], proj_capacity[slot],
		]))
		out.append_array(proj_ledger.slice(slot * ledger_stride, (slot + 1) * ledger_stride))
	for slot: int in gem_slots():
		out.append_array(PackedInt64Array([gem_uid[slot], gem_x[slot], gem_y[slot], gem_value[slot]]))
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
	other.won = won
	other.spawn_acc = spawn_acc
	other.enemy_rng_cursor = enemy_rng_cursor
	other.next_enemy_uid = next_enemy_uid
	other.enemy_alive = enemy_alive
	other.kills = kills
	other.skill_acc = skill_acc
	other.sep_cursor = sep_cursor
	other.next_gem_uid = next_gem_uid
	other.gems_alive = gems_alive
	other.gems_merged = gems_merged
	other.xp_dropped_total = xp_dropped_total
	other.xp_collected_total = xp_collected_total
	other.xp_bank = xp_bank
	other.level = level
	other.pending_level_choices = pending_level_choices
	other.choices_voided = choices_voided
	other.choices_done = choices_done
	other.build_revision = build_revision
	other.offers_rng_cursor = offers_rng_cursor
	other.hand = hand.duplicate()
	other.ranks = ranks.duplicate()
	other.hero_hp_max = hero_hp_max
	other.next_attack_uid = next_attack_uid
	other.venom_stacks = venom_stacks
	other.venom_left = venom_left
	other.venom_phase = venom_phase
	other.enemy_uid = enemy_uid.duplicate()
	other.enemy_kind = enemy_kind.duplicate()
	other.enemy_x = enemy_x.duplicate()
	other.enemy_y = enemy_y.duplicate()
	other.enemy_hp = enemy_hp.duplicate()
	other.enemy_cooldown = enemy_cooldown.duplicate()
	other.enemy_state = enemy_state.duplicate()
	other.enemy_left = enemy_left.duplicate()
	other.enemy_dir_x = enemy_dir_x.duplicate()
	other.enemy_dir_y = enemy_dir_y.duplicate()
	other.enemy_attack_uid = enemy_attack_uid.duplicate()
	other.proj_x = proj_x.duplicate()
	other.proj_y = proj_y.duplicate()
	other.proj_vx = proj_vx.duplicate()
	other.proj_vy = proj_vy.duplicate()
	other.proj_ttl = proj_ttl.duplicate()
	other.proj_damage = proj_damage.duplicate()
	other.proj_hits = proj_hits.duplicate()
	other.proj_capacity = proj_capacity.duplicate()
	other.proj_ledger = proj_ledger.duplicate()
	other.ledger_stride = ledger_stride
	other.gem_uid = gem_uid.duplicate()
	other.gem_x = gem_x.duplicate()
	other.gem_y = gem_y.duplicate()
	other.gem_value = gem_value.duplicate()
	return other
