extends GutTest
## QUALITY-2026-11 Q2: trauma screen shake. Deterministic and presentation only.


func test_a_fresh_shake_does_not_move_the_camera() -> void:
	var shake: CameraShake = CameraShake.new()
	assert_eq(shake.offset(1.0), Vector2.ZERO)


func test_strength_zero_means_no_shake_at_all() -> void:
	var shake: CameraShake = CameraShake.new()
	shake.add(CameraShake.TRAUMA_HIT)
	for _i: int in 30:
		shake.age(1.0 / 60.0)
		assert_eq(shake.offset(0.0), Vector2.ZERO)


func test_a_blow_moves_the_camera_a_little() -> void:
	var shake: CameraShake = CameraShake.new()
	shake.add(CameraShake.TRAUMA_HIT)
	shake.age(0.01)
	var moved: float = shake.offset(1.0).length()
	var limit: float = CameraShake.MAX_OFFSET_PX * CameraShake.TRAUMA_HIT * CameraShake.TRAUMA_HIT * sqrt(2.0)
	assert_gt(moved, 0.0)
	assert_lte(moved, limit + 0.0001, "the blow is a nudge, not a jolt")


func test_a_second_blow_in_the_same_instant_does_not_stack() -> void:
	var same_instant: CameraShake = CameraShake.new()
	same_instant.add(CameraShake.TRAUMA_HIT)
	same_instant.add(CameraShake.TRAUMA_HIT)
	assert_almost_eq(same_instant.trauma, 0.30, 0.0001)
	var apart: CameraShake = CameraShake.new()
	apart.add(CameraShake.TRAUMA_HIT)
	apart.age(0.06)
	apart.add(CameraShake.TRAUMA_HIT)
	assert_almost_eq(apart.trauma, 0.30 - 1.6 * 0.06 + 0.30, 0.0001, "a later blow stacks")


func test_trauma_never_passes_one() -> void:
	var shake: CameraShake = CameraShake.new()
	for _i: int in 4:
		shake.add(CameraShake.TRAUMA_DEATH)
		assert_lte(shake.trauma, 1.0)
		shake.age(0.06)


func test_trauma_decays_to_zero() -> void:
	var shake: CameraShake = CameraShake.new()
	shake.add(CameraShake.TRAUMA_DEATH)
	shake.age(1.0)
	assert_eq(shake.trauma, 0.0)
	assert_eq(shake.offset(1.0), Vector2.ZERO)


func test_the_shake_is_deterministic() -> void:
	var first: CameraShake = CameraShake.new()
	var second: CameraShake = CameraShake.new()
	for shake: CameraShake in [first, second]:
		shake.add(CameraShake.TRAUMA_HIT)
		shake.age(0.03)
		shake.add(CameraShake.TRAUMA_DEATH)
		shake.age(0.12)
	assert_ne(first.offset(0.7), Vector2.ZERO)
	assert_eq(first.offset(0.7), second.offset(0.7))


func test_clear_resets_the_shake() -> void:
	var shake: CameraShake = CameraShake.new()
	shake.add(CameraShake.TRAUMA_DEATH)
	shake.age(0.05)
	assert_ne(shake.offset(1.0), Vector2.ZERO)
	shake.clear()
	assert_eq(shake.trauma, 0.0)
	assert_eq(shake.offset(1.0), Vector2.ZERO)
