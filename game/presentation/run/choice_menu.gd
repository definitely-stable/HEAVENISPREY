class_name ChoiceMenu
extends Control
## Level-up choice menu (ADR-010 section 6) in the gold kit after REF-011 (ADR-014 section 16): a
## title banner, up to three cards (rank ribbon, illustration, name, lotus divider, "before ->
## after" line) and the Choose button over the dimmed, paused run, below the HUD stage plaque.
## Keyboard and gamepad move the focus (ui_left / ui_right) and pick with ui_accept; 1-3 pick
## directly; the mouse clicks a card or Choose. A pick is ignored for ARM_DELAY seconds after the
## menu opens so a button held from combat does not choose blindly. The menu only reports
## `picked`; RunView turns it into a CHOOSE through FixedTickDriver.

signal picked(index: int)

const ARM_DELAY: float = 0.35
## Card size when the kit has no card frame (screen px).
const CARD_SIZE: Vector2 = Vector2(250, 380)
const CARD_GAP: int = 30
## The menu starts under the HUD stage plaque and run time (screen px of the 720 px canvas).
const TOP: float = 100.0
const SEPARATION: int = 20
const TITLE_FONT_SIZE: int = 28
const NAME_FONT_SIZE: int = 23
const LINE_FONT_SIZE: int = 16
const RANK_FONT_SIZE: int = 16
const BUTTON_FONT_SIZE: int = 22
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.62)
const COLOR_TITLE: Color = Color(0.97, 0.85, 0.56)
const COLOR_TEXT: Color = Color(0.95, 0.91, 0.84)
const COLOR_RANK: Color = Color(0.93, 0.9, 0.98)
## A card without focus is a little darker; the focused one glows like the chosen card of REF-011.
const COLOR_IDLE: Color = Color(0.8, 0.78, 0.76)
const COLOR_GLOW: Color = Color(1.0, 0.6, 0.18, 0.55)
const GLOW_SIZE: int = 26
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]

## build_revision the shown hand was built for (-1 when closed).
var revision: int = -1
var cards: Array[Button] = []
## Text of each shown card: {"name", "stat", "rank", "art"}.
var card_texts: Array[Dictionary] = []
var kit: HudKit
var choose_button: Button
var _arm_left: float = 0.0
var _focused: int = 0
var _title_text: String = ""
var _banner: Control
var _more: Label
var _row: HBoxContainer
var _glow: StyleBoxFlat


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_glow = StyleBoxFlat.new()
	_glow.bg_color = Color(COLOR_GLOW, 0.0)
	_glow.shadow_color = COLOR_GLOW
	_glow.shadow_size = GLOW_SIZE
	_glow.set_corner_radius_all(24)
	var dim: ColorRect = ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = TOP
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", SEPARATION)
	add_child(column)
	_banner = Control.new()
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.draw.connect(_draw_banner)
	column.add_child(_banner)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", CARD_GAP)
	column.add_child(_row)
	for index: int in UpgradeSystem.HAND_SIZE:
		var card: Button = _flat_button()
		card.pressed.connect(press.bind(index))
		card.draw.connect(_draw_card.bind(index))
		card.focus_entered.connect(_on_focus.bind(index))
		card.focus_exited.connect(card.queue_redraw)
		card.mouse_entered.connect(card.queue_redraw)
		card.mouse_exited.connect(card.queue_redraw)
		_row.add_child(card)
		cards.append(card)
		card_texts.append({})
	choose_button = _flat_button()
	choose_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose_button.pressed.connect(func() -> void: press(_focused))
	choose_button.draw.connect(_draw_choose)
	column.add_child(choose_button)
	_more = Label.new()
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	_more.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_more)


## Shows the hand of `world` (built for its build_revision) with the card texts.
func open(config: SimConfig, world: WorldState) -> void:
	if kit == null:
		kit = HudKit.load_default()
	_fit_to_kit()
	revision = world.build_revision
	_title_text = UiText.text("UI_LEVEL_UP_TITLE")
	var waiting: int = world.pending_level_choices - 1
	_more.text = UiText.text("UI_LEVEL_UP_MORE") % waiting if waiting > 0 else ""
	for index: int in cards.size():
		var card: Button = cards[index]
		card.visible = index < world.hand.size()
		card_texts[index] = {}
		if not card.visible:
			continue
		var code: int = world.hand[index]
		var text: Dictionary = UpgradeCard.describe(config, world, code)
		text["art"] = UpgradeCard.art_piece(code)
		card_texts[index] = text
		card.tooltip_text = "%d. %s\n%s" % [index + 1, text["name"], text["stat"]]
		card.queue_redraw()
	_arm_left = ARM_DELAY
	_focused = 0
	visible = true
	_banner.queue_redraw()
	choose_button.queue_redraw()
	if is_inside_tree():
		cards[0].grab_focus()


func close() -> void:
	visible = false
	revision = -1
	_arm_left = 0.0


## Counts down the arm delay; RunView calls it with the frame time while the run is paused.
func age(delta: float) -> void:
	var was_armed: bool = is_armed()
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)
	if is_armed() != was_armed:
		choose_button.queue_redraw()


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


func _on_focus(index: int) -> void:
	_focused = index
	cards[index].queue_redraw()


## Sizes the banner, the cards and the button to their pieces of the kit.
func _fit_to_kit() -> void:
	var card_size: Vector2 = kit.size_of("card_frame") if kit.has("card_frame") else CARD_SIZE
	for card: Button in cards:
		card.custom_minimum_size = card_size
	_banner.custom_minimum_size = kit.size_of("title_banner")
	choose_button.custom_minimum_size = kit.size_of("choose_button")


func _draw_banner() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _banner.size)
	kit.draw(_banner, "title_banner", rect)
	var panel: Rect2 = kit.window("title_banner", rect)
	kit.draw_text(_banner, _title_text, panel.get_center().x, panel.get_center().y + TITLE_FONT_SIZE * 0.32,
		TITLE_FONT_SIZE, COLOR_TITLE)


func _draw_card(index: int) -> void:
	var card: Button = cards[index]
	var text: Dictionary = card_texts[index]
	if text.is_empty() or kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, card.size)
	var lit: bool = card.has_focus() or card.is_hovered()
	if lit:
		card.draw_style_box(_glow, rect.grow(-10))
	kit.draw(card, "card_frame", rect, Color.WHITE if lit else COLOR_IDLE)
	var panel: Rect2 = kit.window("card_frame", rect)
	var side: float = panel.size.x - 20.0
	var art: Rect2 = Rect2(panel.position.x + 10.0, panel.position.y + 18.0, side, side)
	kit.draw(card, str(text["art"]), art, Color.WHITE if lit else COLOR_IDLE)
	var ribbon_size: Vector2 = kit.size_of("rank_ribbon")
	if not str(text["rank"]).is_empty() and ribbon_size != Vector2.ZERO:
		var ribbon: Rect2 = Rect2(Vector2(rect.get_center().x - ribbon_size.x * 0.5, panel.position.y - 6.0), ribbon_size)
		kit.draw(card, "rank_ribbon", ribbon)
		var label: Rect2 = kit.window("rank_ribbon", ribbon)
		kit.draw_text(card, str(text["rank"]), label.get_center().x, label.get_center().y + RANK_FONT_SIZE * 0.34,
			RANK_FONT_SIZE, COLOR_RANK)
	var width: float = panel.size.x - 12.0
	var top: float = art.end.y + 6.0
	top += kit.draw_paragraph(card, str(text["name"]), Vector2(panel.position.x + 6.0, top), width, NAME_FONT_SIZE,
		COLOR_TITLE, 2)
	var divider: Vector2 = kit.size_of("divider_lotus") * 0.8
	kit.draw(card, "divider_lotus", Rect2(Vector2(rect.get_center().x - divider.x * 0.5, top + 2.0), divider))
	top += divider.y + 6.0
	kit.draw_paragraph(card, str(text["stat"]), Vector2(panel.position.x + 6.0, top), width, LINE_FONT_SIZE, COLOR_TEXT, 3)


func _draw_choose() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, choose_button.size)
	var lit: bool = is_armed() and (choose_button.has_focus() or choose_button.is_hovered())
	kit.draw(choose_button, "choose_button", rect, Color.WHITE if lit or is_armed() else COLOR_IDLE)
	var panel: Rect2 = kit.window("choose_button", rect)
	kit.draw_text(choose_button, UiText.text("UI_CHOICE_PICK"), panel.get_center().x,
		panel.get_center().y + BUTTON_FONT_SIZE * 0.32, BUTTON_FONT_SIZE, COLOR_TITLE if is_armed() else COLOR_IDLE)


## A button that draws nothing itself: the card or the Choose plate is drawn by this menu.
static func _flat_button() -> Button:
	var button: Button = Button.new()
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	return button
