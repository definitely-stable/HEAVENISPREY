extends GutTest

const FIXTURE: String = "res://tests/fixtures/run_receipt_vectors.json"


func test_preview_matches_the_shared_vectors() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var registry: ContentRegistry = ContentRegistry.load_dir()
	assert_true(registry.is_valid(), registry.error)
	assert_eq(RewardPreview.POLICY_ID, vectors["policy_id"])
	var uid: String = RunResultReceipt.test_run_uid(vectors["scenario_id"], vectors["seed"])
	assert_eq(uid, vectors["run_uid"])
	for row: Dictionary in vectors["cases"]:
		var fields: Dictionary = {
			"run_uid": uid, "difficulty_id": "difficulty.standard", "mode_ids": ["mode.normal"],
		}
		fields.merge(row, true)
		var computed: Dictionary = RewardPreview.compute(fields, registry)
		if row.has("error"):
			assert_eq(computed, {"error": row["error"]}, row["name"])
			continue
		var events: Array = []
		if row["event"]:
			events.append({"source_id": "reward.minute3", "reward_event_id": vectors["reward_event_id"], "stones": 8})
		assert_eq(computed, {"reward_events": events, "stones_preview": int(row["stones_preview"])}, row["name"])


func test_preview_rejects_noncanonical_run_uid() -> void:
	var fields: Dictionary = {
		"run_uid": "110344626205FBDBD666E89804F74252",
		"result": "victory", "survived_ticks": 18000, "kills": 20,
		"difficulty_id": "difficulty.standard", "mode_ids": ["mode.normal"],
	}
	assert_eq(RewardPreview.compute(fields, ContentRegistry.load_dir()), {"error": "invalid_run_uid"})
