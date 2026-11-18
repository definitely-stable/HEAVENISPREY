extends GutTest

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"


func test_start_seals_rules_and_refuses_invalid_or_locked_starts() -> void:
	var packed: PackedScene = load(RUN_SCENE)
	var view: RunView = packed.instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	assert_true(view.start_run())
	assert_false(HipRng.parse_u64(view.rules_snapshot.run_seed).is_empty())
	assert_true(view.start_run("18446744073709551615", "class.sword"))
	var stable: FixedTickDriver = view.driver
	var snapshot: RunRulesSnapshot = view.rules_snapshot
	assert_eq(snapshot.run_seed, "18446744073709551615")
	assert_eq(stable.config.run_seed, snapshot.run_seed)
	assert_eq(snapshot.class_id, "class.sword")
	assert_true(snapshot.is_valid())
	assert_false(view.start_run("1", "class.thunder"))
	assert_eq(view.start_error, "not eligible: class_locked")
	assert_false(view.start_run("01"))
	assert_eq(view.start_error, "seed must be a canonical uint64 decimal string")
	assert_false(view.start_run(""))
	assert_eq(view.start_error, "seed must be a canonical uint64 decimal string")
	assert_same(view.driver, stable)
	assert_same(view.rules_snapshot, snapshot)
