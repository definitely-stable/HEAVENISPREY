extends GutTest
## ADR-014 section 18 (A6): the combat effects kit and the effects a run adds - a spark and a
## number on every blow, crimson decay where an enemy falls, a sword circle on a cast and a
## pillar of light on a level; effects expire and a horde cannot pile them up without end.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0
const PIECES: Array[String] = [
	"sword", "spark", "slash", "sword_circle", "qi_wisp", "qi_lotus", "motes", "light_pillar",
	"yin_burst", "yin_circle", "yin_claw", "yin_smoke",
]


func test_kit_has_every_piece() -> void:
	var vfx: CombatVfx = CombatVfx.load_default()
	for piece: String in PIECES:
		assert_true(vfx.kit.has(piece), piece)
		assert_gt(vfx.kit.size_of(piece).x, 0.0, piece)
	var sword: Vector2 = vfx.kit.size_of("sword")
	assert_gt(sword.x, sword.y * 3.0, "the sword is a long streak along x")
	assert_false(SpriteSet.load_default().has(CombatVfx.ASSET_ID), "effects are not lit scene sprites")


func test_strikes_add_sparks_and_numbers() -> void:
	var vfx: CombatVfx = CombatVfx.new()
	vfx.add_strike(Vector2(10, 20), 12400, 7, false)
	vfx.add_strike(Vector2(30, 20), 300, 8, false)
	vfx.add_strike(Vector2(50, 20), 5000, 9, true)
	assert_eq(vfx.sparks.size(), 3, "a spark on every blow")
	assert_eq(vfx.numbers.size(), 2, "no number for a blow under half a point")
	assert_eq(vfx.numbers[0][2], "12")
	assert_false(vfx.numbers[0][3])
	assert_true(vfx.numbers[1][3], "a killing blow is marked")
	var again: CombatVfx = CombatVfx.new()
	again.add_strike(Vector2(10, 20), 12400, 7, false)
	assert_eq(again.sparks[0], vfx.sparks[0], "the spark turn and size follow the uid")


func test_effects_expire() -> void:
	var vfx: CombatVfx = CombatVfx.new()
	vfx.add_strike(Vector2.ZERO, 3000, 1, false)
	vfx.add_death(Vector2.ZERO, ["", "", "", 0])
	vfx.add_cast(Vector2.ZERO)
	vfx.level_up(Vector2.ZERO)
	vfx.age(CombatVfx.SPARK_TIME + 0.01)
	assert_eq(vfx.sparks.size(), 0)
	assert_eq(vfx.numbers.size(), 1, "numbers stay longer than sparks")
	vfx.age(1.0)
	assert_eq(vfx.numbers.size(), 0)
	assert_eq(vfx.deaths.size(), 0)
	assert_eq(vfx.casts.size(), 0)
	assert_lt(vfx.level_age, 0.0, "the pillar is gone")
	vfx.add_cast(Vector2.ZERO)
	vfx.age(-1.0)
	assert_eq(vfx.casts[0][1], 0.0, "time never runs back")
	vfx.clear()
	assert_eq(vfx.casts.size(), 0)


## ADR-014 A5b: a fallen body decays and the yin burst rises only once its death clip played.
func test_a_fall_decays_after_its_death_clip() -> void:
	var vfx: CombatVfx = CombatVfx.new()
	vfx.add_death(Vector2.ZERO, ["asset.enemy.yin_corpse", "death", "se", 0], 0.6)
	vfx.age(0.5)
	assert_eq(CombatVfx.decay(vfx.deaths[0]), 0.0, "whole while it falls")
	vfx.age(0.1 + CombatVfx.DECAY_TIME * 0.5)
	assert_almost_eq(CombatVfx.decay(vfx.deaths[0]), 0.5, 0.01, "then it decays")
	vfx.age(maxf(CombatVfx.DECAY_TIME, CombatVfx.DEATH_TIME))
	assert_eq(vfx.deaths.size(), 0, "gone after the fall and the decay")


func test_a_horde_cannot_pile_up_effects() -> void:
	var vfx: CombatVfx = CombatVfx.new()
	for uid: int in 200:
		vfx.add_strike(Vector2(uid, 0), 4000, uid, true)
		vfx.add_death(Vector2(uid, 0), ["", "", "", 0])
	assert_eq(vfx.sparks.size(), CombatVfx.MAX_SPARKS)
	assert_eq(vfx.numbers.size(), CombatVfx.MAX_NUMBERS)
	assert_eq(vfx.deaths.size(), CombatVfx.MAX_DEATHS)
	assert_eq(vfx.sparks[-1][0], Vector2(199, 0), "the newest blow is kept")


func test_large_gems_are_lotuses() -> void:
	assert_eq(CombatVfx.gem_piece(1), "qi_wisp")
	assert_eq(CombatVfx.gem_piece(CombatVfx.LARGE_GEM_VALUE), "qi_wisp")
	assert_eq(CombatVfx.gem_piece(CombatVfx.LARGE_GEM_VALUE + 1), "qi_lotus")


func test_driver_reports_every_blow_with_its_damage() -> void:
	var config: SimConfig = P0TestSetup.sword_config("20261113")
	var driver: FixedTickDriver = FixedTickDriver.create(config)
	var hits: int = 0
	var kills: Array = []
	var strikes: Array = []
	for _i: int in 1200:
		if driver.world.is_paused():
			driver.choose(0)
		driver.advance(TICK, Vector2i.ZERO)
		var events: Dictionary = driver.take_events()
		hits += (events["hit"] as PackedInt64Array).size()
		kills.append_array(events["killed"])
		strikes.append_array(events["strikes"])
	assert_gt(hits, 0)
	assert_eq(strikes.size(), hits + kills.size(), "one strike per hit and per killing blow")
	var killing: int = 0
	for strike: Array in strikes:
		assert_gt(int(strike[1]), 0, "a blow does damage")
		assert_gt(int(strike[2]), 0, "a blow names its enemy")
		killing += 1 if strike[3] else 0
	assert_eq(killing, kills.size())
	for kill: Array in kills:
		assert_gt(int(kill[2]), 0, "a death names its enemy")
	assert_true((driver.take_events()["strikes"] as Array).is_empty(), "events are cleared when taken")


func test_scene_shows_the_effects_of_a_fight() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	view.start_run("20261113")
	var vfx: CombatVfx = view.get("_vfx")
	assert_not_null(vfx)
	var saw_spark: bool = false
	var saw_number: bool = false
	var saw_death: bool = false
	var saw_cast: bool = false
	for _i: int in 1200:
		if view.driver.world.is_paused():
			view.choose(0)
		else:
			view.advance_frame(TICK, Vector2i.ZERO)
		saw_spark = saw_spark or not vfx.sparks.is_empty()
		saw_number = saw_number or not vfx.numbers.is_empty()
		saw_death = saw_death or not vfx.deaths.is_empty()
		saw_cast = saw_cast or not vfx.casts.is_empty()
	assert_true(saw_spark, "sparks")
	assert_true(saw_number, "numbers")
	assert_true(saw_death, "decay")
	assert_true(saw_cast, "cast circle")
	view.start_run("20261113")
	assert_true(vfx.sparks.is_empty() and vfx.deaths.is_empty(), "a new run starts clean")
