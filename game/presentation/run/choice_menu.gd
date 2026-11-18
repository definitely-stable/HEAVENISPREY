class_name ChoiceMenu
extends Control
## Level-up picker (ADR-010 §6): opens over the paused run, and emits a guarded choice
## through the same path for mouse, keyboard and controller.

signal picked(index: int)

const ARM_DELAY: float = 0.35
const CARD_SIZE: Vector2 = Vector2(252, 384)
const CARD_GAP: int = 26
const TOP: float = 105.0
const TITLE_FONT_SIZE: int = 34
const NAME_FONT_SIZE: int = 26
const LINE_FONT_SIZE: int = 20
const CHANGE_FONT_SIZE: int = 26
const RANK_FONT_SIZE: int = 18
const DIM: float = 0.62
const CARD_TEXT_INSET: float = 12.0
const CARD_BOTTOM_PAD: float = 13.0
const ART_TOP: float = 34.0
const DIVIDER_GAP: float = 4.0
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
const IDLE_FRAME: Color = Color("#c8bab0")
const GLOW: Color = Color(1.0, 0.60, 0.21, 0.71)
const GLOW_SPREAD: float = 18.0
const THUNDER_ART: String = "asset.ui.thunder_cards"
const BANNER_SIZE: Vector2 = Vector2(420, 90)

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
var _thunder_art: HudKit


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = TOP
	center.offset_bottom = -12.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	_banner = Control.new()
	_banner.custom_minimum_size = BANNER_SIZE
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
	choose_button = _flat_button()
	choose_button.custom_minimum_size = Vector2(246, 50)
	choose_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	choose_button.pressed.connect(func() -> void: press(_focused))
	choose_button.draw.connect(_draw_choose)
	column.add_child(choose_button)
	_controls = _caption()
	column.add_child(_controls)
	_more = _caption()
	_more.custom_minimum_size.y = 22.0
	_more.add_theme_color_override("font_color", HudKit.GOLD)
	column.add_child(_more)


func open(config: SimConfig, world: WorldState) -> void:
	if kit == null:
		kit = HudKit.load_default()
	if config.skill_form == SimConfig.SKILL_CHAIN and _thunder_art == null:
		_thunder_art = HudKit.load_kit(THUNDER_ART)
		theme = kit.menu_theme()
	revision = world.build_revision
	var waiting: int = world.pending_level_choices - 1
	_banner.accessibility_name = UiText.text("UI_LEVEL_UP_TITLE")
	_more.text = UiText.text("UI_LEVEL_UP_MORE") % waiting if waiting > 0 else ""
	_controls.text = UiText.text("UI_CHOICE_INPUT")
	choose_button.accessibility_name = UiText.text("UI_CHOICE_PICK")
	var count: int = mini(world.hand.size(), cards.size())
	for index: int in cards.size():
		var card: Button = cards[index]
		card.visible = index < count
		card_texts[index] = {}
		if not card.visible:
			continue
		var code: int = world.hand[index]
		var text: Dictionary = UpgradeCard.describe(config, world, code)
		text["art"] = UpgradeCard.art_piece(code, config.skill_form)
		card_texts[index] = text
		card.accessibility_name = str(text["name"])
		card.accessibility_description = str(text["stat"])
		card.tooltip_text = "%d. %s\n%s" % [index + 1, text["name"], text["stat"]]
		card.queue_redraw()
	_arm_left = ARM_DELAY
	_focused = 0
	visible = true
	_banner.queue_redraw()
	choose_button.queue_redraw()
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
		choose_button.queue_redraw()


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
	if kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _banner.size)
	kit.draw(_banner, "title_banner", rect)
	var panel: Rect2 = kit.window("title_banner", rect).grow_individual(-22.0, 0.0, -22.0, 0.0)
	kit.draw_text_in(_banner, _banner.accessibility_name, panel, TITLE_FONT_SIZE, HudKit.GOLD)


func _draw_choose() -> void:
	if kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, choose_button.size)
	var ready: bool = is_armed()
	if ready and choose_button.has_focus():
		kit.draw_halo(choose_button, "choose_button", rect, GLOW_SPREAD, GLOW)
	kit.draw(choose_button, "choose_button", rect, Color.WHITE if ready else IDLE_FRAME)
	var panel: Rect2 = kit.window("choose_button", rect).grow_individual(-14.0, 0.0, -14.0, 0.0)
	kit.draw_text_in(choose_button, choose_button.accessibility_name, panel, 23, HudKit.TEXT if ready else HudKit.MUTED)


func _draw_card(index: int) -> void:
	var card: Button = cards[index]
	var text: Dictionary = card_texts[index]
	if text.is_empty() or kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, card.size)
	var selected: bool = index == _focused
	if selected:
		kit.draw_halo(card, "card_frame", rect, GLOW_SPREAD, GLOW)
	kit.draw(card, "card_frame", rect, Color.WHITE if selected else IDLE_FRAME)
	var at: Dictionary = card_layout(kit, rect, text)
	_draw_art(card, str(text["art"]), at["art"])
	var ribbon: Rect2 = at["ribbon"]
	if ribbon.has_area():
		kit.draw(card, "rank_ribbon", ribbon)
		kit.draw_text_in(card, str(text["rank"]), kit.window("rank_ribbon", ribbon), RANK_FONT_SIZE, HudKit.TEXT)
	var panel: Rect2 = kit.window("card_frame", rect)
	if card.has_focus():
		var point: Vector2 = Vector2(rect.get_center().x, panel.position.y - 10.0)
		card.draw_colored_polygon(PackedVector2Array([
			point + Vector2.UP * 5.0, point + Vector2.RIGHT * 5.0,
			point + Vector2.DOWN * 5.0, point + Vector2.LEFT * 5.0,
		]), HudKit.FOCUS)
	var name_box: Rect2 = at["name"]
	kit.draw_paragraph(card, str(text["name"]), name_box.position, name_box.size.x, NAME_FONT_SIZE, HudKit.GOLD, 2)
	kit.draw(card, "divider_lotus", at["divider"])
	kit.draw_text_in(card, str(text["label"]), at["label"], LINE_FONT_SIZE, HudKit.MUTED)
	kit.draw_text_in(card, str(text["change"]), at["change"], CHANGE_FONT_SIZE, HudKit.TEXT)


func _draw_art(card: Button, piece: String, rect: Rect2) -> void:
	if _thunder_art == null or not _thunder_art.has(piece):
		kit.draw_card_art(card, piece, rect)
		return
	var native: Vector2 = _thunder_art.size_of(piece)
	var fitted: Vector2 = native * minf(rect.size.x / native.x, rect.size.y / native.y)
	_thunder_art.draw_card_art(card, piece, Rect2(rect.get_center() - fitted * 0.5, fitted))


static func card_layout(hud_kit: HudKit, rect: Rect2, text: Dictionary) -> Dictionary:
	var panel: Rect2 = hud_kit.window("card_frame", rect)
	var left: float = panel.position.x + CARD_TEXT_INSET
	var width: float = panel.size.x - CARD_TEXT_INSET * 2.0
	var title: String = str(text.get("name", ""))
	var name_size: int = hud_kit.fit_paragraph_size(title, width, NAME_FONT_SIZE, 2)
	var name_height: float = hud_kit.paragraph_height(title, width, name_size)
	var name_room: float = hud_kit.font.get_height(NAME_FONT_SIZE) * 2.0
	var bottom: float = panel.end.y - CARD_BOTTOM_PAD
	var change: Rect2 = Rect2(left, bottom - 33.0, width, 33)
	var label: Rect2 = Rect2(left, change.position.y - 25.0, width, 25)
	var divider: Rect2 = Rect2(panel.get_center().x - 47.0, label.position.y - 12.0, 94, 11)
	var name_box: Rect2 = Rect2(left, divider.position.y - DIVIDER_GAP - name_height, width, name_height)
	var art_top: float = panel.position.y + ART_TOP
	var side: float = minf(width, divider.position.y - DIVIDER_GAP - maxf(name_room, name_height) - art_top)
	var art: Rect2 = Rect2(panel.get_center().x - side * 0.5, art_top, side, side)
	var ribbon: Rect2 = Rect2()
	if not str(text.get("rank", "")).is_empty():
		ribbon = Rect2(panel.get_center().x - 48.0, panel.position.y - 3.0, 96, 32)
	return {"art": art, "ribbon": ribbon, "name": name_box, "divider": divider, "label": label, "change": change}


func more_text() -> String:
	return _more.text


static func _caption() -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HudKit.MUTED)
	return label


static func _flat_button() -> Button:
	var button: Button = Button.new()
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	return button
