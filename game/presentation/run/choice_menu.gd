class_name ChoiceMenu
extends Control
## Level-up choice menu (ADR-010 section 6): up to three cards over the paused run. Keyboard
## and gamepad move the focus (ui_left / ui_right) and pick with ui_accept; 1-3 pick directly;
## the mouse clicks a card. A pick is ignored for ARM_DELAY seconds after the menu opens so a
## button held from combat does not choose blindly. The menu only reports `picked`; RunView
## turns it into a CHOOSE through FixedTickDriver.

signal picked(index: int)

const ARM_DELAY: float = 0.35
const CARD_SIZE: Vector2 = Vector2(280, 170)
const TITLE_FONT_SIZE: int = 28
const CARD_FONT_SIZE: int = 18
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_TITLE: Color = Color(0.95, 0.92, 0.85)
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]

## build_revision the shown hand was built for (-1 when closed).
var revision: int = -1
var cards: Array[Button] = []
var _arm_left: float = 0.0
var _title: Label
var _more: Label
var _row: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim: ColorRect = ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	_title = _label(TITLE_FONT_SIZE)
	column.add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 24)
	column.add_child(_row)
	for index: int in UpgradeSystem.HAND_SIZE:
		var card: Button = Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", CARD_FONT_SIZE)
		card.pressed.connect(press.bind(index))
		_row.add_child(card)
		cards.append(card)
	_more = _label(CARD_FONT_SIZE)
	column.add_child(_more)


## Shows the hand of `world` (built for its build_revision) with the card texts.
func open(config: SimConfig, world: WorldState) -> void:
	revision = world.build_revision
	_title.text = UiText.text("UI_LEVEL_UP_TITLE")
	var waiting: int = world.pending_level_choices - 1
	_more.text = UiText.text("UI_LEVEL_UP_MORE") % waiting if waiting > 0 else ""
	for index: int in cards.size():
		var card: Button = cards[index]
		card.visible = index < world.hand.size()
		if not card.visible:
			continue
		var text: Dictionary = UpgradeCard.describe(config, world, world.hand[index])
		var lines: PackedStringArray = ["%d. %s" % [index + 1, text["name"]], text["stat"]]
		if not str(text["rank"]).is_empty():
			lines.append(text["rank"])
		card.text = "\n".join(lines)
	_arm_left = ARM_DELAY
	visible = true
	if is_inside_tree():
		cards[0].grab_focus()


func close() -> void:
	visible = false
	revision = -1
	_arm_left = 0.0


## Counts down the arm delay; RunView calls it with the frame time while the run is paused.
func age(delta: float) -> void:
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)


func is_armed() -> bool:
	return visible and _arm_left <= 0.0


## Emits `picked` for a visible card once armed; returns whether it did.
func press(index: int) -> bool:
	if not is_armed() or index < 0 or index >= cards.size() or not cards[index].visible:
		return false
	picked.emit(index)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	var index: int = DIGIT_KEYS.find(key.keycode)
	if index >= 0 and press(index):
		get_viewport().set_input_as_handled()


static func _label(size: int) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TITLE)
	return label
