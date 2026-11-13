class_name XpSystem
extends RefCounted
## XP gems, pickup and level progression (ADR-010). Exact port of tools/content/sim_core.py.
##
## Drop (phase 8a, per dead enemy): the value is fixed at the drop (x1 gain in P0); a new gem
## takes the lowest free slot with a fresh uid from `next_gem_uid`. With all `max_gems` slots
## taken the value joins the gem nearest to the death point (d2, then the lower slot) and
## `gems_merged` counts it: game rule OVERFLOW_POLICY_ID, not a neutral consolidation.
## Pickup (phase 9, skipped in the tick the hero dies): every gem whose centre is within
## `pickup_radius_su` of the hero centre (inclusive), slot order, each credited once.
## Progression (phase 10): every crossed threshold is paid from the bank and earns one
## pending choice; the remainder stays in the bank.
## P0 guarantee: XP has one path (death -> drop -> pickup) and a gem uid identifies the item,
## not the XP source; a second XP path needs a source-claim ledger first (ADR-010 section 5).

const OVERFLOW_POLICY_ID: String = "xp.overflow.nearest_v1"


static func drop(config: SimConfig, world: WorldState, x: int, y: int, value: int) -> void:
	world.xp_dropped_total += value
	var slot: int = world.gem_uid.find(0)
	if slot < 0 and world.gem_slots() >= config.max_gems:
		var best: int = -1
		var best_d2: int = 0
		for index: int in world.gem_slots():
			var d2: int = EnemySystem.dist2(world.gem_x[index], world.gem_y[index], x, y)
			if best < 0 or d2 < best_d2:
				best = index
				best_d2 = d2
		world.gem_value[best] += value
		world.gems_merged += 1
		return
	if slot < 0:
		slot = world.gem_slots()
		world.gem_uid.append(0)
		world.gem_x.append(0)
		world.gem_y.append(0)
		world.gem_value.append(0)
	world.gem_uid[slot] = world.next_gem_uid
	world.gem_x[slot] = x
	world.gem_y[slot] = y
	world.gem_value[slot] = value
	world.next_gem_uid += 1
	world.gems_alive += 1


## Credits the gem in `slot` once; a stale or repeated (slot, uid) is rejected unchanged.
static func collect(world: WorldState, slot: int, uid: int) -> bool:
	if uid == 0 or slot < 0 or slot >= world.gem_slots() or world.gem_uid[slot] != uid:
		return false
	var value: int = world.gem_value[slot]
	world.gem_uid[slot] = 0
	world.gem_x[slot] = 0
	world.gem_y[slot] = 0
	world.gem_value[slot] = 0
	world.gems_alive -= 1
	world.xp_collected_total += value
	world.xp_bank += value
	return true


static func pickup(config: SimConfig, world: WorldState) -> void:
	var reach: int = config.pickup_radius_su * config.pickup_radius_su
	for slot: int in world.gem_slots():
		var uid: int = world.gem_uid[slot]
		if uid != 0 and EnemySystem.dist2(world.gem_x[slot], world.gem_y[slot], world.player_x, world.player_y) <= reach:
			collect(world, slot, uid)


static func progress(config: SimConfig, world: WorldState) -> void:
	while world.xp_bank >= config.xp_cost(world.level):
		world.xp_bank -= config.xp_cost(world.level)
		world.level += 1
		world.pending_level_choices += 1
