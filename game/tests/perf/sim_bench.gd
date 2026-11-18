extends SceneTree
## Headless simulation benchmark (ADR-009 section 2 stress fixture, s24 sim_tick_ms gate):
## 150 enemies, P0 skill, hero circling; ticks 1000..3999 are measured (all 150 spawned).
## Prints one JSON line per scenario with p50/p95/p99 tick time and separation time in
## microseconds.
##   godot --headless --path game -s res://tests/perf/sim_bench.gd
## `stress_150_separation`: the two w0 kinds. `stress_150_attacks` (ADR-011 E6): the ten P0
## kinds and attacks from content in one window, with the threat_caps; the same configs as the
## traces of tools/content/sim_core.py.

const WARMUP_TICKS: int = 1000
const MEASURED_TICKS: int = 3000
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]


static func stress_config() -> SimConfig:
	return SimConfig.create(PackedInt64Array([4800, 24000, 0, 0, 1536000, 960000, 768000, 480000])).with_enemies(
		PackedInt64Array([500000000, 6000, 0, 1000, 150, 384000]),
		PackedInt64Array([3264, 24000, 12800, 6500, 36, 8, 6144, 21600, 7800, 7600, 42, 2]),
		"20261113"
	).with_skill(PackedInt64Array([50000, 384000, 10000, 12000, 10000, 40, 1, 64]))


static func stress_attacks_config(tuned: SimConfig = null) -> SimConfig:
	if tuned == null:
		tuned = P0TestSetup.sword_config("20261113")
	return tuned.with_enemies(
		PackedInt64Array([500000000, 6000, 0, 1000, 150, 384000]), tuned.kinds, "20261113"
	).with_windows(
		PackedInt64Array([0, 4000, 2, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1]), tuned.caps
	).with_choice_mode(SimConfig.CHOICE_NONE).with_run_ticks(0)


static func percentile(sorted: Array[int], share: int) -> int:
	return sorted[mini(sorted.size() - 1, floori(sorted.size() * share / 100.0))]


func _initialize() -> void:
	if "--thunder" in OS.get_cmdline_user_args():
		var registry: ContentRegistry = ContentRegistry.load_dir()
		var snapshot: RunRulesSnapshot = RunRulesSnapshot.create_for_new_run(
			registry, PackedStringArray(["unlock.thunder"]), "class.thunder", P0Tuning.STAGE_ID,
			"difficulty.standard", PackedStringArray(["mode.normal"]), "20261113"
		)
		var thunder: SimConfig = stress_attacks_config(P0Tuning.new().run_config(registry, snapshot))
		measure("thunder_6_max_ranks", thunder, UpgradeSystem.RANK_TABLES[SimConfig.SKILL_CHAIN])
		thunder.chain_hits = SimConfig.MAX_CHAIN_HITS
		measure("thunder_8_targets", thunder)
		quit()
		return
	measure("stress_150_separation", stress_config())
	measure("stress_150_attacks", stress_attacks_config())
	quit()


func measure(scenario: String, config: SimConfig, ranks: PackedInt64Array = []) -> void:
	var commands: CommandLog = CommandLog.new()
	for index: int in range(0, ceili((WARMUP_TICKS + MEASURED_TICKS) / 30.0)):
		var move: Vector2i = DIRS[index % DIRS.size()]
		commands.append(PlayerCommand.create(index * 30, index, move.x, move.y), 0)
	var world: WorldState = WorldState.initial(config)
	if not ranks.is_empty():
		world.ranks = ranks.duplicate()
	var ticks: Array[int] = []
	var separation: Array[int] = []
	for tick: int in WARMUP_TICKS + MEASURED_TICKS:
		var started: int = Time.get_ticks_usec()
		SimKernel.step(config, world, commands)
		var spent: int = Time.get_ticks_usec() - started
		if tick < WARMUP_TICKS:
			continue
		ticks.append(spent)
		var probe: WorldState = world.copy()
		started = Time.get_ticks_usec()
		SeparationSystem.chase_and_separate(config, probe)
		separation.append(Time.get_ticks_usec() - started)
	ticks.sort()
	separation.sort()
	print(JSON.stringify({
		"scenario": scenario, "enemy_alive": world.enemy_alive, "ticks": MEASURED_TICKS,
		"chain_targets": UpgradeSystem.chain_hits(config, world) if config.skill_form == SimConfig.SKILL_CHAIN else 0,
		"tick_us_p50": percentile(ticks, 50), "tick_us_p95": percentile(ticks, 95),
		"tick_us_p99": percentile(ticks, 99), "separation_us_p50": percentile(separation, 50),
		"separation_us_p95": percentile(separation, 95), "digest": world.digest(),
	}))
