extends GutTest

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"
const TICK: float = 1.0 / 60.0


func test_horde_warning_edges_and_hero_stay_above_glow() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	assert_true(view.start_run("101"))
	assert_lt((view._danger.get_parent() as CanvasLayer).layer, 0, "fill lies on the ground")
	assert_lt(view._glow.get_index(), view._warning_edges.get_index())
	assert_lt(view._warning_edges.get_index(), view._hero_item.get_index())
	assert_lt(view._hero_item.get_index(), view._over.get_index(), "the health bar stays on top")

	var world: WorldState = view.driver.world
	var slot: int = _place_enemy(view, "enemy.sickle_mantis", 48000)
	world.enemy_state[slot] = EnemyAttackSystem.ST_TELL
	var before: String = world.digest()
	var journal: String = view.driver.commands.digest()
	RunEffectsPasses.prepare_danger(view)
	assert_eq(view._danger_marks.size(), 1)
	var mark: Dictionary = view._danger_marks[0] if not view._danger_marks.is_empty() else {}
	assert_eq(mark.get("form"), SimConfig.FORM_CHARGE)
	assert_eq(mark.get("center"), view.driver.enemy_position_px(slot))
	assert_eq(world.digest(), before)
	assert_eq(view.driver.commands.digest(), journal)

	world.enemy_state[slot] = EnemyAttackSystem.ST_APPROACH
	RunEffectsPasses.prepare_danger(view)
	assert_true(view._danger_marks.is_empty(), "the preceding warning is discarded")


func test_hero_hit_cue_expires_and_rearms_after_cooldown() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	assert_true(view.start_run("101"))
	var world: WorldState = view.driver.world
	var slot: int = _place_enemy(view, "enemy.yin_corpse", 0)
	view.advance_frame(TICK, Vector2i.ZERO)
	assert_eq(view._flash, RunView.HIT_FLASH)
	var hp: int = world.hero_hp
	world.enemy_cooldown[slot] = 0
	view.advance_frame(TICK, Vector2i.ZERO)
	assert_lt(world.hero_hp, hp)
	assert_lt(view._flash, RunView.HIT_FLASH, "consecutive hits do not restart the cue")
	world.enemy_cooldown[slot] = 120
	for _tick: int in ceili((RunView.HIT_FLASH + RunView.HIT_FLASH_REST) / TICK):
		view.advance_frame(TICK, Vector2i.ZERO)
	assert_eq(view._flash, 0.0)
	world.enemy_cooldown[slot] = 0
	view.advance_frame(TICK, Vector2i.ZERO)
	assert_eq(view._flash, RunView.HIT_FLASH)


static func _place_enemy(view: RunView, enemy_id: String, offset_x: int) -> int:
	var world: WorldState = view.driver.world
	var slot: int = world.append_enemy_slot()
	world.enemy_uid[slot] = world.next_enemy_uid
	world.next_enemy_uid += 1
	world.enemy_alive += 1
	world.enemy_kind[slot] = view.tuning.enemy_ids.find(enemy_id)
	world.enemy_x[slot] = world.player_x + offset_x
	world.enemy_y[slot] = world.player_y
	world.enemy_hp[slot] = 1000000
	return slot
