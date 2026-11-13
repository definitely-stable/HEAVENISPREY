extends GutTest
## XP gems, pickup and level progression (ADR-010) checked directly against hand-computed
## values; tools/content/sim_core.py traces in test_sim_core.gd cover them end to end.

const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
## Frozen, harmless target kind (radius 24000); no spawn for ~536870 ticks.
const TARGET_KINDS: Array[int] = [0, 24000, 1000000, 0, 36, 1]


static func _place(world: WorldState, x: int, y: int, hp: int) -> void:
	world.enemy_uid.append(world.next_enemy_uid)
	world.enemy_kind.append(0)
	world.enemy_x.append(x)
	world.enemy_y.append(y)
	world.enemy_hp.append(hp)
	world.enemy_cooldown.append(0)
	world.next_enemy_uid += 1
	world.enemy_alive += 1


static func _xp_arena(max_gems: int) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array([500000000, 536870912, 0, 1000, 64, 0]), PackedInt64Array(TARGET_KINDS), "1"
	).with_xp(PackedInt64Array([48000, max_gems]), PackedInt64Array([15]), PackedInt64Array([5, 12, 20, 30]))


func test_xp_drop_merge_and_inclusive_pickup() -> void:
	var config: SimConfig = _xp_arena(2)
	assert_true(config.is_valid())
	var world: WorldState = WorldState.initial(config)
	XpSystem.drop(config, world, 100000, 100000, 10)
	XpSystem.drop(config, world, 900000, 100000, 10)
	XpSystem.drop(config, world, 850000, 100000, 15)
	XpSystem.drop(config, world, 500000, 100000, 7)
	assert_eq(world.gem_value, PackedInt64Array([17, 25]), "nearest gem, then the lower slot")
	assert_eq([world.gems_merged, world.next_gem_uid, world.xp_dropped_total], [2, 3, 42])
	var near: WorldState = WorldState.initial(config)
	XpSystem.drop(config, near, 768000 + 48000, 480000, 10)
	XpSystem.drop(config, near, 768000, 480000 + 48001, 10)
	XpSystem.pickup(config, near)
	assert_eq(near.gem_uid, PackedInt64Array([0, 2]), "d2 = R2 is collected, R2 + 1 is not")
	assert_eq(near.xp_collected_total, 10)


func test_xp_collect_rejects_stale_and_repeated() -> void:
	var config: SimConfig = _xp_arena(8)
	var world: WorldState = WorldState.initial(config)
	XpSystem.drop(config, world, 1068000, 480000, 10)
	assert_true(XpSystem.collect(world, 0, 1))
	XpSystem.drop(config, world, 1068000, 480000, 15)
	var frozen: PackedInt64Array = world.to_ints()
	for call: Array in [[0, 1], [0, 0], [1, 2], [-1, 2]]:
		assert_false(XpSystem.collect(world, call[0], call[1]), str(call))
		assert_eq(world.to_ints(), frozen, "a rejected collect changes nothing")
	assert_true(XpSystem.collect(world, 0, 2))
	assert_eq([world.xp_collected_total, world.gems_alive], [25, 0])


func test_xp_terminal_tick_drops_without_pickup_and_voids_choices() -> void:
	var config: SimConfig = _xp_arena(8)
	for alive: bool in [false, true]:
		var world: WorldState = WorldState.initial(config)
		_place(world, 778000, 480000, 0)
		world.hero_hp = 500000000 if alive else 0
		world.level = 3
		world.pending_level_choices = 2
		world.xp_dropped_total = 17
		world.xp_collected_total = 17
		SimKernel.step(config, world, CommandLog.new())
		assert_eq(world.xp_dropped_total, 32, "the drop happens in the terminal tick too")
		if alive:
			assert_eq([world.xp_collected_total, world.xp_bank, world.level], [32, 15, 3])
		else:
			assert_eq([world.hero_dead, world.gems_alive, world.xp_collected_total], [1, 1, 17])
			assert_eq([world.pending_level_choices, world.choices_voided], [0, 2])


func test_xp_several_levels_keep_the_remainder() -> void:
	var config: SimConfig = _xp_arena(8)
	var world: WorldState = WorldState.initial(config)
	world.xp_bank = 40
	XpSystem.progress(config, world)
	assert_eq([world.level, world.pending_level_choices, world.xp_bank], [4, 3, 3])
	world.xp_bank = 65
	XpSystem.progress(config, world)
	assert_eq([world.level, world.xp_bank], [6, 5], "65 - 30 - 30: the last cost repeats")
