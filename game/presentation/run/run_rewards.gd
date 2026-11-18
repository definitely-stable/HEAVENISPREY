class_name RunRewards
extends Control
## Reads the existing receipt. No mutations or reward settlement occur here.

signal continue_requested

const ARM_DELAY: float = 0.35
const PANEL_SIZE: Vector2 = Vector2(586, 378)

var kit: HudKit
var title: Label
var milestone_line: Label
var stones_line: Label
var unlock_line: Label
var notice: Label
var hint: Label
var continue_button: Button
var _arm_left: float = 0.0


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
	var plate: Control = Control.new()
	plate.custom_minimum_size = PANEL_SIZE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(_draw_plate.bind(plate))
	center.add_child(plate)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 30.0
	column.offset_right = -30.0
	column.offset_top = 36.0
	column.offset_bottom = -24.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 11)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	title = _add_line(column, 39, HudKit.TEXT)
	milestone_line = _add_line(column, 22, HudKit.MUTED)
	stones_line = _add_line(column, 28, HudKit.GOLD)
	unlock_line = _add_line(column, 22, HudKit.JADE)
	notice = _add_line(column, 19, HudKit.MUTED)
	continue_button = Button.new()
	continue_button.custom_minimum_size = Vector2(224, 48)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(continue_button)
	hint = _add_line(column, 18, HudKit.MUTED)


func open(receipt: RunResultReceipt, milestone: Dictionary, unlocked_class: String) -> void:
	if kit == null:
		kit = HudKit.load_default()
		theme = kit.menu_theme()
	var fields: Dictionary = receipt.fields()
	var events: Array = fields["reward_events"]
	var requirements: Array[int] = [int(milestone["at_game_minute"]), int(milestone["minimum_kills"])]
	title.text = UiText.text("UI_REWARDS_TITLE")
	if events.is_empty():
		milestone_line.text = UiText.text("UI_REWARDS_MILESTONE_MISSED") % requirements
	else:
		requirements.append(int(events[0]["stones"]))
		milestone_line.text = UiText.text("UI_REWARDS_MILESTONE") % requirements
	stones_line.text = UiText.text("UI_REWARDS_STONES") % int(fields["stones_preview"])
	unlock_line.visible = not unlocked_class.is_empty()
	unlock_line.text = UiText.text("UI_REWARDS_UNLOCK") % unlocked_class
	notice.text = UiText.text("UI_REWARDS_NOT_SAVED")
	continue_button.text = UiText.text("UI_CLASS_SELECT_TITLE")
	continue_button.self_modulate = Color(0.7, 0.7, 0.7)
	hint.text = UiText.text("UI_REWARDS_CONTINUE")
	_arm_left = ARM_DELAY
	show()
	if is_inside_tree():
		var button_path: NodePath = continue_button.get_path()
		continue_button.focus_next = button_path
		continue_button.focus_previous = button_path
		continue_button.grab_focus()


func age(delta: float) -> void:
	if _arm_left > 0.0:
		_arm_left = maxf(0.0, _arm_left - maxf(delta, 0.0))
		if is_armed():
			continue_button.self_modulate = Color.WHITE


func is_armed() -> bool:
	return visible and _arm_left <= 0.0


func _on_continue_pressed() -> void:
	if is_armed():
		continue_requested.emit()


func _draw_plate(plate: Control) -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, plate.size)
	HudKit.draw_plate(plate, rect, HudKit.INK, HudKit.GOLD)
	HudKit.draw_plate(plate, rect.grow(-5.0), HudKit.INK, Color("#523a30"))
	if kit != null:
		kit.draw(plate, "divider_lotus", Rect2(rect.get_center().x - 102.0, 21, 204, 18))


static func _add_line(column: VBoxContainer, font_size: int, color: Color) -> Label:
	var label: Label = RunResults._label(font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	return label
