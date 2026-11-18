class_name ClassSelect
extends Control
## Before RUN_SETUP. Only the accepted card is passed to RunView.

signal class_confirmed(class_id: String)

const ARM_DELAY: float = 0.35
const CARD_SIZE: Vector2 = Vector2(368, 288)
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2]

var kit: HudKit
var cards: Array[Button] = []
var class_ids: PackedStringArray = PackedStringArray()
var locked: Array[bool] = []
var _arm_left: float = 0.0
var _row: HBoxContainer
var _title: Label
var _hint: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	var dim: ColorRect = ColorRect.new()
	dim.color = RunResults.COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)
	_title = RunResults._label(42, HudKit.TEXT)
	column.add_child(_title)
	var divider: Control = Control.new()
	divider.custom_minimum_size.y = 18.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.draw.connect(func() -> void:
		kit.draw(divider, "divider_lotus", Rect2(divider.size.x * 0.5 - 102, 0, 204, 18)))
	column.add_child(divider)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 20)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_row)
	_hint = RunResults._label(18, HudKit.MUTED)
	column.add_child(_hint)


func open(registry: ContentRegistry, granted: PackedStringArray, last_class_id: String) -> void:
	if kit == null:
		kit = HudKit.load_default()
		theme = kit.menu_theme()
	for card: Button in cards:
		card.free()
	cards.clear()
	class_ids.clear()
	locked.clear()
	for class_id: String in registry.ids("classes"):
		var definition: Dictionary = registry.definition(class_id)
		if definition.get("planned_first_playable") == true:
			_add_card(registry, granted, class_id, definition)
	_title.text = UiText.text("UI_CLASS_SELECT_TITLE")
	_hint.text = UiText.text("UI_CLASS_CONFIRM")
	_hint.modulate.a = 0.0
	_arm_left = ARM_DELAY
	show()
	if is_inside_tree() and not cards.is_empty():
		for index: int in cards.size():
			var card: Button = cards[index]
			card.focus_neighbor_left = cards[maxi(0, index - 1)].get_path()
			card.focus_neighbor_right = cards[mini(cards.size() - 1, index + 1)].get_path()
			card.focus_neighbor_top = card.get_path()
			card.focus_neighbor_bottom = card.get_path()
			card.focus_previous = cards[posmod(index - 1, cards.size())].get_path()
			card.focus_next = cards[(index + 1) % cards.size()].get_path()
		cards[maxi(0, class_ids.find(last_class_id))].grab_focus()


func _add_card(registry: ContentRegistry, granted: PackedStringArray, class_id: String, definition: Dictionary) -> void:
	var unlock_id: Variant = definition.get("unlock_id")
	var is_locked: bool = unlock_id != null and not granted.has(str(unlock_id))
	var skill: Dictionary = registry.definition(str(definition.get("start_skill_id")))
	var title: String = UiText.text(str(definition.get("name_key")))
	var start_skill: String = UiText.text("UI_CLASS_START_SKILL") % UiText.text(str(skill.get("name_key")))
	var description: String = UiText.text(str(definition.get("name_key")).trim_suffix("_NAME") + "_DESC")
	var card: Button = Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	card.add_theme_stylebox_override("normal", HudKit._button_style(HudKit.INK, HudKit.BRONZE, 1))
	card.add_theme_stylebox_override("hover", HudKit._button_style(Color("#2c2025"), HudKit.GOLD, 1))
	card.accessibility_name = title
	card.accessibility_description = start_skill + ". " + description
	card.pressed.connect(press.bind(cards.size()))
	_row.add_child(card)
	cards.append(card)
	class_ids.append(class_id)
	locked.append(is_locked)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24.0
	column.offset_top = 19.0
	column.offset_right = -24.0
	column.offset_bottom = -19.0
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	_add_text(column, title, 29, HudKit.TEXT)
	_add_text(column, start_skill, 20, HudKit.GOLD).custom_minimum_size.y = 52.0
	_add_text(column, description, 20, HudKit.TEXT).custom_minimum_size.y = 76.0
	if is_locked:
		var requirement: Array = registry.definition(str(unlock_id)).get("all", [])
		var stage: Dictionary = registry.definition(str(requirement[0].get("stage_id"))) if not requirement.is_empty() else {}
		var notice: String = UiText.text("UI_CLASS_LOCKED") % UiText.text(str(stage.get("name_key")))
		_add_text(column, "🔒︎ " + notice, 18, HudKit.MUTED)
		card.accessibility_description += ". " + notice


func age(delta: float) -> void:
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)
	if _arm_left <= 0.0:
		_hint.modulate.a = 1.0


func press(index: int) -> bool:
	if not visible or index < 0 or index >= cards.size():
		return false
	cards[index].grab_focus()
	if _arm_left > 0.0 or locked[index]:
		return false
	class_confirmed.emit(class_ids[index])
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	var index: int = DIGIT_KEYS.find(key.keycode)
	if index >= 0 and index < cards.size():
		press(index)
		get_viewport().set_input_as_handled()


static func _add_text(column: VBoxContainer, text: String, font_size: int, color: Color) -> Label:
	var label: Label = RunResults._label(font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label
