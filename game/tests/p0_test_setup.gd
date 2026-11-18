class_name P0TestSetup
extends RefCounted
## Canonical rules for the already-authorized sword run used by simulation fixtures.


static func sword_config(seed_text: String, tuning: P0Tuning = null) -> SimConfig:
	var registry: ContentRegistry = ContentRegistry.load_dir()
	var snapshot: RunRulesSnapshot = RunRulesSnapshot.create(
		registry, "class.sword", P0Tuning.STAGE_ID, "difficulty.standard",
		PackedStringArray(["mode.normal"]), seed_text
	)
	if tuning == null:
		tuning = P0Tuning.new()
	return tuning.run_config(registry, snapshot)
