class_name P0SessionProfile
extends RefCounted
## Session-only unlocks for the P0 run start.

const THUNDER_UNLOCK: String = "unlock.thunder"

var registry: ContentRegistry
var unlock_all: bool = false
var _receipts: Dictionary[String, RunResultReceipt] = {}


func finish(uid: String, rules: RunRulesSnapshot, driver: FixedTickDriver) -> RunResultReceipt:
	if not _receipts.has(uid):
		var receipt: RunResultReceipt = RunResultReceipt.create(uid, rules, driver, registry)
		if receipt != null:
			_receipts[uid] = receipt
	return _receipts.get(uid)


func receipts() -> Array[RunResultReceipt]:
	return _receipts.values()


func granted_unlock_ids() -> PackedStringArray:
	var grants: PackedStringArray = []
	if registry == null:
		return grants
	if unlock_all:
		for class_id: String in registry.ids("classes"):
			var class_def: Dictionary = registry.definition(class_id)
			var grant: Variant = class_def.get("unlock_id")
			if class_def.get("planned_first_playable") == true and grant is String:
				grants.append(grant)
		return grants

	if _thunder_unlocking_receipt() != null:
		grants.append(THUNDER_UNLOCK)
	return grants


func unlocked_class_for(receipt: RunResultReceipt) -> String:
	return "class.thunder" if receipt != null and not unlock_all and receipt == _thunder_unlocking_receipt() else ""


func _thunder_unlocking_receipt() -> RunResultReceipt:
	var conditions: Array = registry.definition(THUNDER_UNLOCK).get("all", [])
	if conditions.size() != 1:
		return null
	var condition: Dictionary = conditions[0]
	var required_stage: String = condition.get("stage_id", "")
	var required_count: Variant = ContentRegistry.integral(condition.get("count"))
	if condition.get("event") != "run_finished" or required_count == null or required_count < 1:
		return null
	var finished: int = 0
	for receipt: RunResultReceipt in _receipts.values():
		var fields: Dictionary = receipt.fields()
		if fields["stage_id"] == required_stage and fields["result"] in ["victory", "defeat"]:
			finished += 1
			if finished == required_count:
				return receipt
	return null

static func random_run_seed() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	if bytes.size() != 8:
		return ""
	var signed_word: int = bytes.decode_s64(0)
	if signed_word >= 0:
		return str(signed_word)
	# The signed shift supplies the upper 63 bits. Use 10 = 2 * 5 before doubling.
	var upper: int = (signed_word >> 1) & 0x7fffffffffffffff
	var prefix: int = Fx.floor_div(upper, 5)
	return str(prefix) + str((upper - prefix * 5) * 2 + (signed_word & 1))
