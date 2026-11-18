class_name RewardPreview
extends RefCounted
## ADR-012 §6. Pure computation for the one P0 milestone.

const POLICY_ID: String = "hip-reward-preview-v1"
const MILESTONE_ID: String = "reward.minute3"
const TICKS_PER_MINUTE: int = 60 * Fx.TICKS_PER_SECOND


@warning_ignore("integer_division")
static func compute(fields: Dictionary, registry: ContentRegistry) -> Dictionary:
	var uid: String = fields["run_uid"]
	if not RunResultReceipt.valid_run_uid(uid):
		return {"error": "invalid_run_uid"}
	if fields["result"] not in ["victory", "defeat", "abandoned"]:
		return {"error": "invalid_result"}
	var difficulty: Dictionary = registry.definition(fields["difficulty_id"])
	var multiplier: Variant = difficulty.get("spirit_stones_mult")
	if typeof(multiplier) not in [TYPE_FLOAT, TYPE_INT]:
		return {"error": "invalid_difficulty_multiplier"}
	var milli: float = float(multiplier) * 1000.0
	if not is_finite(milli) or milli < 0.0 or milli > float(ContentRegistry.MAX_SAFE_INTEGER):
		return {"error": "invalid_difficulty_multiplier"}
	var diff_milli: int = roundi(milli)
	if float(diff_milli) / 1000.0 != float(multiplier):
		return {"error": "invalid_difficulty_multiplier"}
	var eligible: bool = true
	for mode_id: String in fields["mode_ids"]:
		var mode: Dictionary = registry.definition(mode_id)
		var effect: Variant = mode.get("effect", {})
		if typeof(mode.get("reward_eligible")) != TYPE_BOOL or not effect is Dictionary:
			return {"error": "invalid_mode"}
		if effect.has("spirit_stones_reward_mult"):
			return {"error": "unsupported_mode_multiplier"}
		eligible = eligible and mode["reward_eligible"]
	var milestone: Dictionary = registry.definition(MILESTONE_ID)
	var minute: Variant = ContentRegistry.integral(milestone.get("at_game_minute"))
	var minimum_kills: Variant = ContentRegistry.integral(milestone.get("minimum_kills"))
	var stones: Variant = ContentRegistry.integral(milestone.get("stones"))
	if minute == null or minimum_kills == null or stones == null or minute < 0 or minimum_kills < 0 or stones < 0:
		return {"error": "invalid_milestone"}
	if not eligible or fields["survived_ticks"] < minute * TICKS_PER_MINUTE or fields["kills"] < minimum_kills:
		return {"reward_events": [], "stones_preview": 0}
	if diff_milli > 0 and stones > 9223372036854775807 / diff_milli:
		return {"error": "invalid_milestone"}
	var event: Dictionary = {
		"source_id": MILESTONE_ID,
		"reward_event_id": "%s:%s:0" % [MILESTONE_ID, uid],
		"stones": stones,
	}
	# mode_milli is exactly 1000 in v1.
	return {"reward_events": [event], "stones_preview": (stones * diff_milli) / 1000}
