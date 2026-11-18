extends GutTest
## ADR-014 A5b: how an enemy takes a blow and falls. Presentation only.


func test_a_blow_flashes_white_then_fades() -> void:
	var reactions: EnemyReactions = EnemyReactions.new()
	assert_eq(reactions.flash(7), 0.0, "no blow, no flash")
	reactions.hit(7, 0.375)
	assert_eq(reactions.flash(7), 1.0)
	reactions.age(EnemyReactions.FLASH_PEAK, 0.375)
	assert_eq(reactions.flash(7), 1.0, "full white for the peak")
	reactions.age((EnemyReactions.FLASH_TIME - EnemyReactions.FLASH_PEAK) * 0.5, 0.375)
	assert_almost_eq(reactions.flash(7), 0.5, 0.01, "then it fades")
	reactions.age(EnemyReactions.FLASH_TIME, 0.375)
	assert_eq(reactions.flash(7), 0.0)


func test_a_blow_pushes_the_sprite_back_and_it_returns() -> void:
	var reactions: EnemyReactions = EnemyReactions.new()
	var away: Vector2 = Vector2(30.0, 40.0)
	reactions.hit(3, 0.375)
	assert_eq(reactions.knock(3, away), Vector2.ZERO, "it starts on its point")
	reactions.age(EnemyReactions.KNOCK_PEAK, 0.375)
	var out: Vector2 = reactions.knock(3, away)
	assert_almost_eq(out.length(), EnemyReactions.KNOCK_PX, 0.01, "out at the peak")
	assert_almost_eq(out.normalized().dot(away.normalized()), 1.0, 1e-4, "away from the hero")
	reactions.age(EnemyReactions.KNOCK_TIME, 0.375)
	assert_eq(reactions.knock(3, away), Vector2.ZERO, "back on its point")
	assert_eq(reactions.knock(4, away), Vector2.ZERO, "an enemy not hit stays")


func test_blows_restart_the_recoil_only_in_its_second_half() -> void:
	var reactions: EnemyReactions = EnemyReactions.new()
	reactions.hit(5, 0.4)
	reactions.age(0.1, 0.4)
	reactions.hit(5, 0.4)
	assert_almost_eq(reactions.since(5), 0.1, 1e-6, "a blow early in the recoil does not restart it")
	reactions.age(0.15, 0.4)
	reactions.hit(5, 0.4)
	assert_eq(reactions.since(5), 0.0, "a blow in its second half does")
	reactions.age(0.5, 0.4)
	assert_eq(reactions.since(5), INF, "forgotten after the clip")
	reactions.hit(6, 0.4)
	reactions.fallen(6)
	assert_eq(reactions.since(6), INF, "a fallen enemy has no reaction")
	reactions.hit(8, 0.4)
	reactions.clear()
	assert_eq(reactions.since(8), INF)


func test_a_fallen_enemy_plays_its_death_in_its_direction() -> void:
	var sprites: SpriteSet = SpriteSet.load_default()
	var fell: Array = EnemyReactions.death_pose(sprites, ["asset.enemy.blood_wolf", "walk", "nw", 3])
	assert_eq(fell[0], ["asset.enemy.blood_wolf", "death", "nw", 0])
	assert_almost_eq(fell[1], sprites.clip_length("asset.enemy.blood_wolf", "death"), 1e-6)
	var bare: Array = EnemyReactions.death_pose(sprites, ["", "", "", 0])
	assert_eq(bare, [["", "", "", 0], 0.0], "a primitive keeps its pose and decays at once")


func test_dissolve_material_has_its_noise() -> void:
	var material: ShaderMaterial = EnemyReactions.dissolve_material()
	var noise: Texture2D = material.get_shader_parameter("noise")
	assert_eq(noise.get_size(), Vector2(EnemyReactions.NOISE_SIZE, EnemyReactions.NOISE_SIZE))
	var image: Image = noise.get_image()
	var low: float = 1.0
	var high: float = 0.0
	for y: int in range(0, EnemyReactions.NOISE_SIZE, 8):
		for x: int in range(0, EnemyReactions.NOISE_SIZE, 8):
			low = minf(low, image.get_pixel(x, y).r)
			high = maxf(high, image.get_pixel(x, y).r)
	assert_gt(high - low, 0.5, "the noise spans the decay from start to end")


func test_a_flash_starts_at_most_once_per_flash_time() -> void:
	var reactions: EnemyReactions = EnemyReactions.new()
	reactions.hit(9, 0.1)
	reactions.age(EnemyReactions.FLASH_TIME * 0.6, 0.1)
	reactions.hit(9, 0.1)
	assert_gt(reactions.since(9), 0.0, "a short clip does not restart the flash inside FLASH_TIME")
	reactions.age(EnemyReactions.FLASH_TIME * 0.5, 0.1)
	reactions.hit(9, 0.1)
	assert_eq(reactions.since(9), 0.0, "after FLASH_TIME it does")
