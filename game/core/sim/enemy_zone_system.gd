class_name EnemyZoneSystem
extends RefCounted
## Enemy zones (ADR-011 sections 2-4, E5). Exact port of tools/content/sim_core.py.
##
## A zone is made with its telegraph starting in that tick: an ON_DEATH_ZONE kind leaves one
## where it died (death phase), a GROUND_ZONE kind makes one on the hero centre when it
## launches (attack phase). A zone takes the lowest free slot; with SimConfig.ZONES_LIMIT slots
## taken it is not made. After the enemy shots, in slot order: the telegraph is safe; a zone
## made in tick N is active from tick N + telegraph for active_ticks ticks, then freed. While
## active, with the hero centre inside the radius, a death zone deals the kind damage once per
## zone and a ground zone applies status.root_slow (its duration starts again) without damage.
## Zones never touch enemies, so no death comes from a zone; they outlive their enemy.


static func on_death(config: SimConfig, world: WorldState, slot: int) -> void:
	_make(config, world, world.enemy_kind[slot], world.enemy_x[slot], world.enemy_y[slot], world.enemy_uid[slot])


static func launch(config: SimConfig, world: WorldState, slot: int) -> void:
	_make(config, world, world.enemy_kind[slot], world.player_x, world.player_y, world.enemy_uid[slot])


## A ground-zone caster keeps at most one zone.
static func owns_zone(world: WorldState, uid: int) -> bool:
	for slot: int in world.zone_slots():
		if world.zone_form[slot] == SimConfig.FORM_GROUND_ZONE and world.zone_owner[slot] == uid:
			return true
	return false


static func tick(config: SimConfig, world: WorldState) -> void:
	for slot: int in world.zone_slots():
		if world.zone_form[slot] == 0:
			continue
		if world.zone_tell[slot] > 0:
			world.zone_tell[slot] -= 1
			if world.zone_tell[slot] > 0:
				continue
		world.zone_left[slot] -= 1
		var radius: int = world.zone_radius[slot]
		if EnemySystem.dist2(world.zone_x[slot], world.zone_y[slot], world.player_x, world.player_y) <= radius * radius:
			if world.zone_form[slot] == SimConfig.FORM_GROUND_ZONE:
				world.root_left = config.root[0]
			elif world.zone_hit[slot] == 0:
				world.hero_hp -= world.zone_damage[slot]
				world.zone_hit[slot] = 1
		if world.zone_left[slot] == 0:
			_free(world, slot)


static func _make(config: SimConfig, world: WorldState, kind: int, x: int, y: int, owner: int) -> void:
	var zone: int = -1
	for index: int in world.zone_slots():
		if world.zone_form[index] == 0:
			zone = index
			break
	if zone < 0:
		if world.zone_slots() >= SimConfig.ZONES_LIMIT:
			return
		zone = world.append_zone_slot()
	world.zone_x[zone] = x
	world.zone_y[zone] = y
	world.zone_radius[zone] = config.attack_value(kind, SimConfig.ATTACK_RADIUS)
	world.zone_tell[zone] = config.attack_value(kind, SimConfig.ATTACK_TELEGRAPH)
	world.zone_left[zone] = config.attack_value(kind, SimConfig.ATTACK_ACTIVE)
	world.zone_damage[zone] = config.kind_value(kind, SimConfig.KIND_DAMAGE)
	world.zone_form[zone] = config.attack_value(kind, SimConfig.ATTACK_FORM)
	world.zone_owner[zone] = owner
	world.zone_hit[zone] = 0


static func _free(world: WorldState, slot: int) -> void:
	world.zone_x[slot] = 0
	world.zone_y[slot] = 0
	world.zone_radius[slot] = 0
	world.zone_tell[slot] = 0
	world.zone_left[slot] = 0
	world.zone_damage[slot] = 0
	world.zone_form[slot] = 0
	world.zone_owner[slot] = 0
	world.zone_hit[slot] = 0
