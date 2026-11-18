class_name P0SessionProfile
extends RefCounted
## Session-only unlocks for the P0 run start.


func granted_unlock_ids() -> PackedStringArray:
	return PackedStringArray()


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
