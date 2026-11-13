extends GutTest
## Level-up choice (ADR-010 section 6): golden hands from tools/content/sim_core.py, the pause
## at the tick boundary, CHOOSE rejection, and the projectile snapshot of the cast. The choice
## traces in test_sim_core.gd cover the whole chain end to end.

const VECTORS: String = "res://tests/fixtures/sim_core_vectors.json"
const BASE: Array[int] = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]
const P0_VALUES: Array[int] = [100000, 90000, 10800, 2000, 48, 384000]
const W0_KINDS: Array[int] = [3264, 24000, 12800, 6500, 36, 8, 6144, 21600, 7800, 7600, 42, 2]
const P0_SKILL: Array[int] = [50000, 384000, 10000, 12000, 10000, 40, 1, 64]
const P0_COSTS: Array[int] = [
	20, 35, 55, 80, 110, 145, 185, 230, 280, 335, 395, 460, 530, 605, 685, 770, 860, 955, 1055, 1160,
]
## Frozen, harmless targets; no spawn for ~536870 ticks.
const TARGET_KINDS: Array[int] = [0, 24000, 1000000, 0, 36, 1]
const TOUGH: int = 500000000
const CX: int = 768000
const CY: int = 480000

var _data: Dictionary = {}


func before_all() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


static func _p0(seed_text: String) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array(P0_VALUES), PackedInt64Array(W0_KINDS), seed_text
	).with_skill(PackedInt64Array(P0_SKILL)).with_xp(
		PackedInt64Array([48000, 512]), PackedInt64Array([10, 15]), PackedInt64Array(P0_COSTS)
	).with_choice_mode(SimConfig.CHOICE_IMMEDIATE)


static func _arena(skill: Array[int]) -> SimConfig:
	return SimConfig.create(PackedInt64Array(BASE)).with_enemies(
		PackedInt64Array([TOUGH, 536870912, 0, 1000, 64, 0]), PackedInt64Array(TARGET_KINDS), "1"
	).with_skill(PackedInt64Array(skill)).with_xp(
		PackedInt64Array([48000, 512]), PackedInt64Array([15]), PackedInt64Array([5, 12, 20, 30])
	).with_choice_mode(SimConfig.CHOICE_IMMEDIATE)


static func _place(world: WorldState, x: int, y: int, hp: int) -> void:
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.enemy_x[slot] = x
	world.enemy_y[slot] = y
	world.enemy_hp[slot] = hp
	world.next_enemy_uid += 1
	world.enemy_alive += 1


static func _ids(world: WorldState) -> Array:
	var out: Array = []
	for code: int in world.hand:
		out.append(UpgradeSystem.card_id(code))
	return out


static func _live_projectiles(world: WorldState) -> int:
	return world.projectile_slots() - world.proj_damage.count(0)


func test_upgrade_table_matches_reference() -> void:
	var upgrades: Array = _data.get("upgrades", [])
	assert_eq(upgrades.size(), UpgradeSystem.IDS.size())
	for code: int in upgrades.size():
		var row: Dictionary = upgrades[code]
		assert_eq(str(row["id"]), UpgradeSystem.IDS[code])
		assert_eq(int(row["max_rank"]), UpgradeSystem.MAX_RANKS[code])
	assert_eq(str(_data.get("recover_id")), UpgradeSystem.RECOVER_ID)


func test_golden_hands() -> void:
	var hands: Dictionary = _data.get("hands", {})
	var cases: Array = hands.get("cases", [])
	assert_gt(cases.size(), 0)
	for entry: Variant in cases:
		var row: Dictionary = entry
		var config: SimConfig = _p0(str(row["seed"]))
		var world: WorldState = WorldState.initial(config)
		for code: int in 7:
			world.ranks[code] = int((row["ranks"] as Array)[code])
		world.offers_rng_cursor = int(row["cursor"])
		UpgradeSystem.build_hand(config, world)
		assert_eq(_ids(world), row["hand"], str(row["name"]))
		assert_eq(world.offers_rng_cursor, int(row["cursor_after"]), str(row["name"]) + " cursor")


func test_golden_chain_builds_each_hand_from_the_new_build() -> void:
	var chain: Dictionary = (_data.get("hands", {}) as Dictionary).get("chain", {})
	var config: SimConfig = _p0(str(chain["seed"]))
	var world: WorldState = WorldState.initial(config)
	world.pending_level_choices = int(chain["pending"])
	UpgradeSystem.build_hand(config, world)
	for entry: Variant in chain["steps"]:
		var stage: Dictionary = entry
		assert_eq(_ids(world), stage["hand"])
		assert_eq(world.offers_rng_cursor, int(stage["cursor"]))
		assert_eq(world.build_revision, int(stage["revision"]))
		assert_true(UpgradeSystem.choose(config, world, 0, world.build_revision))
	assert_false(world.is_paused())
	var ranks: PackedInt64Array = PackedInt64Array()
	for rank: Variant in chain["ranks"]:
		ranks.append(int(rank))
	assert_eq(world.ranks, ranks)
	assert_eq(world.offers_rng_cursor, int(chain["cursor"]))


static func _run_to_pause(config: SimConfig, world: WorldState, commands: CommandLog) -> void:
	var guard: int = 0
	while not world.is_paused() and guard < 20000:
		SimKernel.step(config, world, commands)
		guard += 1


func test_pause_changes_nothing_without_choose() -> void:
	var config: SimConfig = _p0("20261113")
	var world: WorldState = WorldState.initial(config)
	var commands: CommandLog = CommandLog.new()
	_run_to_pause(config, world, commands)
	assert_true(world.is_paused())
	var frozen: String = world.digest()
	var rng: int = world.enemy_rng_cursor
	SimKernel.run(config, world, commands, 300)
	assert_eq(world.digest(), frozen, "five seconds of menu change nothing")
	assert_eq(world.enemy_rng_cursor, rng)


func test_bad_choose_is_rejected_and_good_one_resolves_once() -> void:
	var config: SimConfig = _p0("20261113")
	var world: WorldState = WorldState.initial(config)
	_run_to_pause(config, world, CommandLog.new())
	var frozen: PackedInt64Array = world.to_ints()
	var revision: int = world.build_revision
	for call: Array in [[3, revision], [-1, revision], [0, revision + 1], [0, revision - 1]]:
		assert_false(UpgradeSystem.choose(config, world, call[0], call[1]), str(call))
		assert_eq(world.to_ints(), frozen, "a rejected CHOOSE changes nothing")
	assert_true(UpgradeSystem.choose(config, world, 1, revision))
	assert_false(UpgradeSystem.choose(config, world, 1, revision), "repeated")
	assert_eq([world.choices_done, world.build_revision], [1, revision + 1])


func test_paused_step_resolves_one_choice_and_move_waits() -> void:
	var config: SimConfig = _arena([50000, 384000, 10000, 12000, 10000, 40, 1, 64])
	var world: WorldState = WorldState.initial(config)
	world.pending_level_choices = 2
	world.level = 3
	UpgradeSystem.build_hand(config, world)
	var commands: CommandLog = CommandLog.new()
	assert_eq(commands.append(PlayerCommand.create(0, 0, 1, 0), 0), CommandLog.OK)
	assert_eq(commands.append(PlayerCommand.choose(0, 1, 0, 0), 0), CommandLog.OK)
	assert_eq(commands.append(PlayerCommand.choose(0, 2, 0, 1), 0), CommandLog.OK)
	assert_eq(commands.append(PlayerCommand.create(0, 3, -1, 0), 0), CommandLog.OK)
	SimKernel.step(config, world, commands)
	assert_eq([world.choices_done, world.command_cursor, world.tick], [1, 2, 0])
	assert_eq(world.player_x, CX, "the hero does not move in a pause")
	SimKernel.step(config, world, commands)
	assert_eq([world.choices_done, world.command_cursor], [2, 3])
	assert_false(world.is_paused())
	SimKernel.step(config, world, commands)
	var speed: int = UpgradeSystem.hero_speed(config, world)
	assert_eq([world.tick, world.player_x], [1, CX - speed], "the last MOVE wins after the pause")


func test_recover_when_every_rank_is_maxed() -> void:
	var config: SimConfig = _p0("1")
	var world: WorldState = WorldState.initial(config)
	world.ranks = UpgradeSystem.MAX_RANKS.duplicate()
	world.offers_rng_cursor = 4
	world.hero_hp = 50000
	UpgradeSystem.build_hand(config, world)
	assert_eq(world.hand, PackedInt64Array([UpgradeSystem.RECOVER]))
	assert_eq(world.offers_rng_cursor, 4, "no word is drawn")
	world.pending_level_choices = 1
	assert_true(UpgradeSystem.choose(config, world, 0, 0))
	assert_eq(world.hero_hp, 70000)
	assert_eq(world.ranks, UpgradeSystem.MAX_RANKS)


func test_flying_projectile_keeps_its_cast_snapshot() -> void:
	var config: SimConfig = _arena([50000, 384000, 10000, 12000, 10000, 40, 1, 64])
	var world: WorldState = WorldState.initial(config)
	for d: int in [100000, 160000, 220000, 280000]:
		_place(world, CX + d, CY, 1000000)
	world.skill_acc = 49000
	var commands: CommandLog = CommandLog.new()
	SimKernel.step(config, world, commands)
	assert_eq([world.proj_damage[0], world.proj_hits[0], world.proj_capacity[0]], [10000, 0, 2])
	world.ranks[UpgradeSystem.PIERCE] = 2
	world.ranks[UpgradeSystem.DAMAGE] = 1
	world.skill_acc = -1000000
	for _i: int in 40:
		SimKernel.step(config, world, commands)
	assert_eq(world.enemy_hp, PackedInt64Array([990000, 990000, 1000000, 1000000]), "cast snapshot")
	world.skill_acc = 49000
	SimKernel.step(config, world, commands)
	assert_eq([world.proj_damage[0], world.proj_hits[0], world.proj_capacity[0]], [13000, 0, 4])


func test_count_three_with_one_free_slot_holds_the_cast() -> void:
	var config: SimConfig = _arena([50000, 384000, 10000, 12000, 10000, 40, 1, 2])
	var world: WorldState = WorldState.initial(config)
	for d: int in [100000, 200000, 300000]:
		_place(world, CX + d, CY, 1000000)
	CombatSystem._append_projectile_slot(world)
	world.proj_x[0] = CX
	world.proj_y[0] = CY
	world.proj_ttl[0] = 500
	world.proj_damage[0] = 10000
	world.proj_capacity[0] = 2
	world.ranks[UpgradeSystem.COUNT] = 2
	world.skill_acc = 49000
	SimKernel.step(config, world, CommandLog.new())
	assert_eq([_live_projectiles(world), world.skill_acc], [1, 49000], "held whole")
	world.ranks[UpgradeSystem.COUNT] = 0
	SimKernel.step(config, world, CommandLog.new())
	assert_eq([_live_projectiles(world), world.skill_acc], [2, 0])


func test_count_fires_one_projectile_per_target() -> void:
	var rays: Array = [[100000, 0], [0, 120000], [-140000, 0], [0, -160000]]
	for available: int in [1, 2, 3, 4]:
		var config: SimConfig = _arena([50000, 384000, 10000, 12000, 10000, 40, 1, 64])
		var world: WorldState = WorldState.initial(config)
		for k: int in available:
			_place(world, CX + int(rays[k][0]), CY + int(rays[k][1]), 1000000)
		world.ranks[UpgradeSystem.COUNT] = 2
		world.skill_acc = 49000
		SimKernel.step(config, world, CommandLog.new())
		assert_eq(_live_projectiles(world), mini(available, 3), str(available))
		assert_eq(world.skill_acc, 0)
