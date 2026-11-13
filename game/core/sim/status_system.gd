class_name StatusSystem
extends RefCounted
## Hero statuses (ADR-011 section 4), ticked before the death phase. Exact port of
## tools/content/sim_core.py.
##
## status.venom, refresh_and_add: a new stack (up to max_stacks) restarts the duration; the
## damage period runs from the first stack. The tick a status is applied counts as the first
## of its duration and period; each period deals stacks x damage_mhp, in the same tick before
## the expiry. Venom does not slow the hero; upgrades do not change statuses.


static func add_venom(config: SimConfig, world: WorldState) -> void:
	if world.venom_stacks == 0:
		world.venom_phase = config.venom_value(2)
	world.venom_stacks = mini(world.venom_stacks + 1, config.venom_value(0))
	world.venom_left = config.venom_value(1)


static func tick(config: SimConfig, world: WorldState) -> void:
	if world.venom_stacks == 0:
		return
	world.venom_left -= 1
	world.venom_phase -= 1
	if world.venom_phase == 0:
		world.hero_hp -= world.venom_stacks * config.venom_value(3)
		world.venom_phase = config.venom_value(2)
	if world.venom_left == 0:
		world.venom_stacks = 0
		world.venom_phase = 0
