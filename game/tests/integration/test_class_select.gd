extends GutTest

const EXPECTED_CLASSES: PackedStringArray = ["class.sword", "class.thunder"]


func _menu(last_class: String = "class.sword", granted: PackedStringArray = []) -> ClassSelect:
	UiText.apply_locale("en")
	var menu: ClassSelect = ClassSelect.new()
	add_child_autofree(menu)
	menu.open(ContentRegistry.load_dir(), granted, last_class)
	watch_signals(menu)
	return menu


func test_catalog_order_locales_and_locked_focus() -> void:
	var menu: ClassSelect = _menu()
	assert_eq(menu.class_ids, EXPECTED_CLASSES)
	assert_eq(menu.locked, [false, true])
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.cards[0])
	for locale: String in ["en", "ru"]:
		TranslationServer.set_locale(locale)
		menu.open(ContentRegistry.load_dir(), [], "class.thunder")
		await wait_process_frames(2)
		assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.cards[1])
		assert_eq(menu.cards[0].accessibility_name, UiText.text("CLASS_SWORD_NAME"))
		assert_eq(menu.cards[1].accessibility_name, UiText.text("CLASS_THUNDER_NAME"))
		assert_true(menu.cards[1].accessibility_description.contains(UiText.text("SKILL_THUNDER_NAME")))
		assert_true(menu.cards[1].accessibility_description.contains(UiText.text("STAGE_JADE_NAME")))
		assert_false(menu.cards[1].accessibility_description.contains("UI_CLASS_LOCKED"))
		for card: Button in menu.cards:
			var text_area: VBoxContainer = card.get_child(0)
			assert_lte(text_area.position.y + text_area.size.y, card.size.y, locale)


func test_guard_locks_and_shortcuts() -> void:
	var menu: ClassSelect = _menu()
	var viewport: Viewport = menu.get_viewport()
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	viewport.push_input(enter)
	assert_signal_not_emitted(menu, "class_confirmed", "Enter during arm delay")
	await wait_process_frames(2)
	menu.age(ClassSelect.ARM_DELAY)
	var right: InputEventJoypadButton = InputEventJoypadButton.new()
	right.button_index = JOY_BUTTON_DPAD_RIGHT
	right.pressed = true
	viewport.push_input(right)
	assert_eq(viewport.gui_get_focus_owner(), menu.cards[1], "D-pad focuses the locked card")
	var accept: InputEventJoypadButton = InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	viewport.push_input(accept)
	assert_signal_not_emitted(menu, "class_confirmed", "A cannot confirm the locked card")
	var left: InputEventJoypadMotion = InputEventJoypadMotion.new()
	left.axis = JOY_AXIS_LEFT_X
	left.axis_value = -1.0
	viewport.push_input(left)
	assert_eq(viewport.gui_get_focus_owner(), menu.cards[0], "left stick changes focus")
	var two: InputEventKey = InputEventKey.new()
	two.keycode = KEY_2
	two.pressed = true
	viewport.push_input(two)
	assert_eq(viewport.gui_get_focus_owner(), menu.cards[1])
	assert_signal_not_emitted(menu, "class_confirmed", "2 cannot start a locked card")
	var one: InputEventKey = InputEventKey.new()
	one.keycode = KEY_1
	one.pressed = true
	viewport.push_input(one)
	assert_signal_emitted_with_parameters(menu, "class_confirmed", ["class.sword"])


func test_unlocked_thunder_confirms_with_mouse() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	UiText.apply_locale("en")
	var menu: ClassSelect = ClassSelect.new()
	viewport.add_child(menu)
	menu.open(ContentRegistry.load_dir(), ["unlock.thunder"], "class.thunder")
	watch_signals(menu)
	await wait_process_frames(2)
	menu.age(ClassSelect.ARM_DELAY)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = menu.cards[1].get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	viewport.push_input(click, true)
	assert_signal_emitted_with_parameters(menu, "class_confirmed", ["class.thunder"])


func test_run_view_starts_only_after_selection_and_restart_keeps_lock() -> void:
	var view: RunView = load("res://presentation/run/run_view.tscn").instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	assert_true(view.is_class_select_open())
	assert_null(view.driver)
	assert_eq(view.advance_frame(0.2, Vector2i.RIGHT), 0)
	assert_eq(view.runs_started, 0)
	assert_false(view._class_select.press(0), "early selection is ignored")
	view.advance_frame(0.2, Vector2i.ZERO)
	assert_false(view._class_select.press(1), "Thunder is locked")
	assert_eq(view.runs_started, 0)
	assert_true(view._class_select.press(0))
	assert_eq(view.rules_snapshot.class_id, "class.sword")
	assert_eq(view.driver.world.tick, 0)
	assert_true(view.restart_run())
	assert_eq(view.rules_snapshot.class_id, "class.sword")
	assert_eq(view.session_profile.granted_unlock_ids(), PackedStringArray())


func test_dev_unlock_opens_only_first_playable_classes() -> void:
	var view: RunView = load("res://presentation/run/run_view.tscn").instantiate()
	view.read_player_input = false
	add_child_autofree(view)
	view.session_profile.unlock_all = true
	view._show_class_select()
	var menu: ClassSelect = view._class_select
	assert_eq(menu.class_ids, EXPECTED_CLASSES)
	assert_eq(menu.locked, [false, false])
	menu.age(ClassSelect.ARM_DELAY)
	assert_true(menu.press(1))
	assert_not_null(view.rules_snapshot, "Thunder starts with the dev flag")
	if view.rules_snapshot != null:
		assert_eq(view.rules_snapshot.class_id, "class.thunder")
