class_name ChoiceMenu
extends Control
## Level-up picker (ADR-010 §6): opens over the paused run, and emits a guarded choice
## through the same path for mouse, keyboard and controller.

signal picked(index: int)

const ARM_DELAY: float = 0.35
const CARD_SIZE: Vector2 = Vector2(252, 354)
const CARD_GAP: int = 22
const TOP: float = 110.0
const TITLE_FONT_SIZE: int = 42
const NAME_FONT_SIZE: int = 27
const LINE_FONT_SIZE: int = 20
const CHANGE_FONT_SIZE: int = 26
const RANK_FONT_SIZE: int = 19
const DIM: float = 0.68
const CARD_TEXT_INSET: float = 17.0
const CARD_BOTTOM_PAD: float = 16.0
const ART_TOP: float = 47.0
const DIVIDER_GAP: float = 4.0
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
const SELECTED_FILL: Color = Color("#2c2025")
const RULE: Color = Color("#583f37")

var revision: int = -1
var cards: Array[Button] = []
var card_texts: Array[Dictionary] = []
var kit: HudKit
var choose_button: Button
var _arm_left: float = 0.0
var _focused: int = 0
var _banner: Control
var _more: Label
var _controls: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = TOP
	center.offset_bottom = -16.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 11)
	center.add_child(column)
	_banner = Control.new()
	_banner.custom_minimum_size = Vector2(536, 62)
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.draw.connect(_draw_banner)
	column.add_child(_banner)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CARD_GAP)
	column.add_child(row)
	for index: int in UpgradeSystem.HAND_SIZE:
		var card: Button = _flat_button()
		card.custom_minimum_size = CARD_SIZE
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		card.pressed.connect(press.bind(index))
		card.draw.connect(_draw_card.bind(index))
		card.focus_entered.connect(_on_focus.bind(index))
		card.focus_exited.connect(card.queue_redraw)
		card.mouse_entered.connect(card.grab_focus)
		row.add_child(card)
		cards.append(card)
		card_texts.append({})
	choose_button = Button.new()
	choose_button.custom_minimum_size = Vector2(218, 48)
	choose_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	choose_button.pressed.connect(func() -> void: press(_focused))
	column.add_child(choose_button)
	_controls = _caption()
	column.add_child(_controls)
	_more = _caption()
	_more.add_theme_color_override("font_color", HudKit.GOLD)
	column.add_child(_more)


func open(config: SimConfig, world: WorldState) -> void:
	if kit == null:
		kit = HudKit.load_default()
		theme = kit.menu_theme()
	revision = world.build_revision
	var waiting: int = world.pending_level_choices - 1
	_banner.accessibility_name = UiText.text("UI_LEVEL_UP_TITLE")
	_more.text = UiText.text("UI_LEVEL_UP_MORE") % waiting if waiting > 0 else ""
	_more.visible = waiting > 0
	_controls.text = UiText.text("UI_CHOICE_INPUT")
	choose_button.text = UiText.text("UI_CHOICE_PICK")
	choose_button.self_modulate = Color(0.7, 0.7, 0.7)
	var count: int = mini(world.hand.size(), cards.size())
	for index: int in cards.size():
		var card: Button = cards[index]
		card.visible = index < count
		card_texts[index] = {}
		if not card.visible:
			continue
		var code: int = world.hand[index]
		var text: Dictionary = UpgradeCard.describe(config, world, code)
		text["art"] = UpgradeCard.art_piece(code)
		card_texts[index] = text
		card.accessibility_name = str(text["name"])
		card.accessibility_description = str(text["stat"])
		card.tooltip_text = "%d. %s\n%s" % [index + 1, text["name"], text["stat"]]
		card.queue_redraw()
	_arm_left = ARM_DELAY
	_focused = 0
	visible = true
	_banner.queue_redraw()
	if is_inside_tree() and count > 0:
		_wire_focus(count)
		cards[0].grab_focus()


func close() -> void:
	visible = false
	revision = -1
	_arm_left = 0.0


func age(delta: float) -> void:
	if _arm_left <= 0.0:
		return
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)
	if is_armed():
		choose_button.self_modulate = Color.WHITE


func is_armed() -> bool:
	return visible and _arm_left <= 0.0


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


func _wire_focus(count: int) -> void:
	var action: NodePath = choose_button.get_path()
	for index: int in count:
		var card: Button = cards[index]
		card.focus_neighbor_left = cards[maxi(index - 1, 0)].get_path()
		card.focus_neighbor_right = cards[mini(index + 1, count - 1)].get_path()
		card.focus_neighbor_top = card.get_path()
		card.focus_neighbor_bottom = action
		card.focus_previous = cards[index - 1].get_path() if index > 0 else action
		card.focus_next = cards[index + 1].get_path() if index + 1 < count else action
	choose_button.focus_neighbor_top = cards[0].get_path()
	choose_button.focus_neighbor_bottom = action
	choose_button.focus_neighbor_left = action
	choose_button.focus_neighbor_right = action
	choose_button.focus_next = cards[0].get_path()
	choose_button.focus_previous = cards[count - 1].get_path()


func _on_focus(index: int) -> void:
	cards[_focused].queue_redraw()
	_focused = index
	cards[index].queue_redraw()
	choose_button.focus_neighbor_top = cards[index].get_path()


func _draw_banner() -> void:
	var width: float = _banner.size.x
	kit.draw_text_in(_banner, _banner.accessibility_name, Rect2(0, 0, width, 46), TITLE_FONT_SIZE, HudKit.TEXT)
	kit.draw(_banner, "divider_lotus", Rect2(width * 0.5 - 70.0, 49, 140, 13))


func _draw_card(index: int) -> void:
	var card: Button = cards[index]
	var text: Dictionary = card_texts[index]
	if text.is_empty() or kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ONE, card.size - Vector2.ONE * 2.0)
	var selected: bool = index == _focused
	var focus: bool = card.has_focus()
	var edge: Color = HudKit.FOCUS if focus else (HudKit.GOLD if selected else HudKit.BRONZE)
	HudKit.draw_plate(card, Rect2(rect.position + Vector2(0, 4), rect.size),
		Color(0.05, 0.03, 0.05, 0.6), Color.TRANSPARENT)
	HudKit.draw_plate(card, rect, SELECTED_FILL if selected else HudKit.INK, edge, 2.0 if focus else 1.0)
	var at: Dictionary = card_layout(kit, Rect2(Vector2.ZERO, card.size), text)
	kit.draw_card_art(card, str(text["art"]), at["art"])
	var chip: Rect2 = Rect2(16, 13, 26, 24)
	HudKit.draw_plate(card, chip, Color("#51372e") if selected else SELECTED_FILL, edge)
	kit.draw_text_in(card, str(index + 1), chip, 18, HudKit.TEXT)
	kit.draw_text_in(card, str(text["rank"]), Rect2(52, 13, card.size.x - 69, 24),
		RANK_FONT_SIZE, HudKit.MUTED, "", 0, HORIZONTAL_ALIGNMENT_RIGHT)
	card.draw_line(Vector2(17, 42), Vector2(card.size.x - 17, 42), RULE)
	var name_box: Rect2 = at["name"]
	kit.draw_paragraph(card, str(text["name"]), name_box.position, name_box.size.x, NAME_FONT_SIZE, HudKit.TEXT, 2)
	kit.draw(card, "divider_lotus", at["divider"], Color(1, 1, 1, 0.8))
	kit.draw_text_in(card, str(text["label"]), at["label"], LINE_FONT_SIZE, HudKit.MUTED)
	kit.draw_text_in(card, str(text["change"]), at["change"], CHANGE_FONT_SIZE, HudKit.GOLD)


static func card_layout(hud_kit: HudKit, rect: Rect2, text: Dictionary) -> Dictionary:
	var left: float = rect.position.x + CARD_TEXT_INSET
	var width: float = rect.size.x - CARD_TEXT_INSET * 2.0
	var title: String = str(text.get("name", ""))
	var name_size: int = hud_kit.fit_paragraph_size(title, width, NAME_FONT_SIZE, 2)
	var name_height: float = hud_kit.paragraph_height(title, width, name_size)
	var name_room: float = hud_kit.font.get_height(NAME_FONT_SIZE) * 2.0
	var bottom: float = rect.end.y - CARD_BOTTOM_PAD
	var change: Rect2 = Rect2(left, bottom - 30.0, width, 30)
	var label: Rect2 = Rect2(left, change.position.y - 23.0, width, 23)
	var divider: Rect2 = Rect2(rect.get_center().x - 48.0, label.position.y - 13.0, 96, 11)
	var name_box: Rect2 = Rect2(left, divider.position.y - DIVIDER_GAP - name_height, width, name_height)
	var art_top: float = rect.position.y + ART_TOP
	var side: float = minf(width, divider.position.y - DIVIDER_GAP - maxf(name_room, name_height) - art_top)
	var art: Rect2 = Rect2(rect.get_center().x - side * 0.5, art_top, side, side)
	return {"art": art, "name": name_box, "divider": divider, "label": label, "change": change}


func more_text() -> String:
	return _more.text


static func _caption() -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", HudKit.MUTED)
	return label


static func _flat_button() -> Button:
	var button: Button = Button.new()
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	return button
