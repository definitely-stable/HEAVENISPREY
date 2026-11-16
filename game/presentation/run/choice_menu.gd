class_name ChoiceMenu
extends Control
## Level-up choice menu (ADR-010 section 6) in the gold kit after REF-011 (ADR-014 section 16): a
## title banner, up to three cards (rank ribbon, illustration, name, lotus divider, "before ->
## after" line) and the Choose button over the paused run, below the HUD stage plaque. The run
## behind is dimmed by RunView through the frame grade (DIM), so the HUD above stays bright.
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
## The "before -> after" values, under the stat name.
const CHANGE_FONT_SIZE: int = 20
const RANK_FONT_SIZE: int = 16
const BUTTON_FONT_SIZE: int = 22
## Share of light the paused run behind the menu loses (FrameGrade.dim).
const DIM: float = 0.62
const COLOR_TITLE: Color = Color(0.97, 0.85, 0.56)
const COLOR_TEXT: Color = Color(0.95, 0.91, 0.84)
const COLOR_RANK: Color = Color(0.93, 0.9, 0.98)
const COLOR_CHANGE: Color = Color(1.0, 0.86, 0.52)
## A card without focus is a little darker; the focused one glows like the chosen card of REF-011:
## a warm halo shaped like its frame, added to the scene behind it, breathing slowly.
const COLOR_IDLE: Color = Color(0.72, 0.7, 0.68)
const COLOR_GLOW: Color = Color(1.0, 0.62, 0.24)
## Two halos: a wide soft one and a tight one that makes the gold rim read as lit.
const GLOW_SPREAD: float = 34.0
const GLOW_RIM_SPREAD: float = 9.0
const GLOW_PULSE_HZ: float = 0.8
const GLOW_PULSE: Vector2 = Vector2(0.75, 1.0)
## Text keeps this far (screen px) inside the dark panel of the card, clear of its gold border.
const CARD_TEXT_INSET: float = 18.0
## The lotus crest of the frame rises this far into the bottom of the panel.
const CARD_BOTTOM_PAD: float = 24.0
const ART_TOP: float = 18.0
const DIVIDER_GAP: float = 3.0
## The banner window runs under its cloud scrolls; the title stays between them.
const BANNER_TEXT_INSET: float = 34.0
const BUTTON_TEXT_INSET: float = 22.0
const DIGIT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
## The line under Choose that says how many level-ups wait (screen px tall).
const MORE_HEIGHT: float = 26.0
const MORE_FONT_SIZE: int = 18

## build_revision the shown hand was built for (-1 when closed).
var revision: int = -1
var cards: Array[Button] = []
## Text of each shown card: UpgradeCard.describe plus "art".
var card_texts: Array[Dictionary] = []
var kit: HudKit
var choose_button: Button
var _arm_left: float = 0.0
var _focused: int = 0
var _title_text: String = ""
var _banner: Control
var _more: Control
var _more_text: String = ""
var _row: HBoxContainer
## The halo behind each card, drawn with additive blending.
var _glows: Array[Control] = []
var _time: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
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
		card.focus_exited.connect(_on_focus_lost.bind(index))
		card.mouse_entered.connect(card.grab_focus)
		var glow: Control = Control.new()
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.show_behind_parent = true
		glow.material = additive
		glow.draw.connect(_draw_glow.bind(index))
		card.add_child(glow)
		_row.add_child(card)
		cards.append(card)
		_glows.append(glow)
		card_texts.append({})
	choose_button = _flat_button()
	choose_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose_button.pressed.connect(func() -> void: press(_focused))
	choose_button.draw.connect(_draw_choose)
	column.add_child(choose_button)
	_more = Control.new()
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.custom_minimum_size = Vector2(0, MORE_HEIGHT)
	_more.draw.connect(_draw_more)
	column.add_child(_more)


## Shows the hand of `world` (built for its build_revision) with the card texts.
func open(config: SimConfig, world: WorldState) -> void:
	if kit == null:
		kit = HudKit.load_default()
	_fit_to_kit()
	revision = world.build_revision
	_title_text = UiText.text("UI_LEVEL_UP_TITLE")
	var waiting: int = world.pending_level_choices - 1
	_more_text = UiText.text("UI_LEVEL_UP_MORE") % waiting if waiting > 0 else ""
	_more.queue_redraw()
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
		_glows[index].queue_redraw()
	_arm_left = ARM_DELAY
	_time = 0.0
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
	_time += maxf(delta, 0.0)
	if is_armed() != was_armed:
		choose_button.queue_redraw()
	if visible and _focused < _glows.size():
		_glows[_focused].queue_redraw()


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
	_glows[index].queue_redraw()


func _on_focus_lost(index: int) -> void:
	cards[index].queue_redraw()
	_glows[index].queue_redraw()


## Strength of the focused card's halo now (it breathes between GLOW_PULSE.x and .y).
func glow_strength() -> float:
	var wave: float = 0.5 - 0.5 * cos(_time * TAU * GLOW_PULSE_HZ)
	return lerpf(GLOW_PULSE.x, GLOW_PULSE.y, wave)


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
	var panel: Rect2 = kit.window("title_banner", rect).grow_individual(-BANNER_TEXT_INSET, 0, -BANNER_TEXT_INSET, 0)
	kit.draw_text_in(_banner, _title_text, panel, TITLE_FONT_SIZE, COLOR_TITLE)


func _draw_glow(index: int) -> void:
	var card: Button = cards[index]
	if kit == null or card_texts[index].is_empty() or not card.has_focus():
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, card.size)
	var strength: float = glow_strength()
	kit.draw_halo(_glows[index], "card_frame", rect, GLOW_SPREAD, Color(COLOR_GLOW, strength))
	kit.draw_halo(_glows[index], "card_frame", rect, GLOW_RIM_SPREAD, Color(COLOR_GLOW, strength * 0.8))


func _draw_card(index: int) -> void:
	var card: Button = cards[index]
	var text: Dictionary = card_texts[index]
	if text.is_empty() or kit == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, card.size)
	var tint: Color = Color.WHITE if card.has_focus() else COLOR_IDLE
	kit.draw(card, "card_frame", rect, tint)
	var at: Dictionary = card_layout(kit, rect, text)
	kit.draw(card, str(text["art"]), at["art"], tint)
	var ribbon: Rect2 = at["ribbon"]
	if ribbon.has_area():
		kit.draw(card, "rank_ribbon", ribbon)
		kit.draw_text_in(card, str(text["rank"]), kit.window("rank_ribbon", ribbon).grow_individual(-4, 0, -4, 0),
			RANK_FONT_SIZE, COLOR_RANK)
	var name_box: Rect2 = at["name"]
	kit.draw_paragraph(card, str(text["name"]), name_box.position, name_box.size.x, NAME_FONT_SIZE, COLOR_TITLE, 2)
	kit.draw(card, "divider_lotus", at["divider"])
	kit.draw_text_in(card, str(text["label"]), at["label"], LINE_FONT_SIZE, COLOR_TEXT)
	kit.draw_text_in(card, str(text["change"]), at["change"], CHANGE_FONT_SIZE, COLOR_CHANGE)


## Rects of a card drawn into `rect`: the text block (name, divider, stat label, change) sits on
## the bottom of the dark panel, each line fitted to its width; the illustration fills the panel
## above it, as large as the text leaves room for. Keys: art, ribbon, name, divider, label, change.
static func card_layout(hud_kit: HudKit, rect: Rect2, text: Dictionary) -> Dictionary:
	var panel: Rect2 = hud_kit.window("card_frame", rect)
	var left: float = panel.position.x + CARD_TEXT_INSET
	var width: float = panel.size.x - CARD_TEXT_INSET * 2.0
	var title: String = str(text.get("name", ""))
	var name_size: int = hud_kit.fit_paragraph_size(title, width, NAME_FONT_SIZE, 2)
	var name_height: float = hud_kit.paragraph_height(title, width, name_size)
	# Every card keeps room for two name lines and the stat label, so the illustrations of one
	# hand are the same size whatever the names; a one-line name sits low, on the divider.
	var name_room: float = hud_kit.font.get_height(NAME_FONT_SIZE) * 2.0
	var divider_size: Vector2 = hud_kit.size_of("divider_lotus") * 0.8
	var label_height: float = hud_kit.font.get_height(LINE_FONT_SIZE)
	var change_height: float = hud_kit.font.get_height(CHANGE_FONT_SIZE)
	var bottom: float = panel.end.y - CARD_BOTTOM_PAD
	var change: Rect2 = Rect2(left, bottom - change_height, width, change_height)
	var label: Rect2 = Rect2(left, change.position.y - label_height, width, label_height)
	var divider: Rect2 = Rect2(Vector2(rect.get_center().x - divider_size.x * 0.5,
		label.position.y - DIVIDER_GAP - divider_size.y), divider_size)
	var name_box: Rect2 = Rect2(left, divider.position.y - DIVIDER_GAP - name_height, width, name_height)
	var art_top: float = panel.position.y + ART_TOP
	var name_top: float = divider.position.y - DIVIDER_GAP - maxf(name_room, name_height)
	var side: float = minf(panel.size.x - 20.0, name_top - 2.0 - art_top)
	var art: Rect2 = Rect2(rect.get_center().x - side * 0.5, art_top, side, side)
	var ribbon: Rect2 = Rect2()
	var ribbon_size: Vector2 = hud_kit.size_of("rank_ribbon")
	if not str(text.get("rank", "")).is_empty() and ribbon_size != Vector2.ZERO:
		ribbon = Rect2(Vector2(rect.get_center().x - ribbon_size.x * 0.5, panel.position.y - 6.0), ribbon_size)
	return {"art": art, "ribbon": ribbon, "name": name_box, "divider": divider, "label": label, "change": change}


## How many level-ups wait after this one, in the kit font with its outline.
func more_text() -> String:
	return _more_text


func _draw_more() -> void:
	if kit == null or _more_text.is_empty():
		return
	kit.draw_text_in(_more, _more_text, Rect2(Vector2.ZERO, _more.size), MORE_FONT_SIZE, COLOR_TITLE)


func _draw_choose() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, choose_button.size)
	var lit: bool = is_armed() and (choose_button.has_focus() or choose_button.is_hovered())
	kit.draw(choose_button, "choose_button", rect, Color.WHITE if lit or is_armed() else COLOR_IDLE)
	var panel: Rect2 = kit.window("choose_button", rect).grow_individual(-BUTTON_TEXT_INSET, 0, -BUTTON_TEXT_INSET, 0)
	kit.draw_text_in(choose_button, UiText.text("UI_CHOICE_PICK"), panel, BUTTON_FONT_SIZE,
		COLOR_TITLE if is_armed() else COLOR_IDLE)


## A button that draws nothing itself: the card or the Choose plate is drawn by this menu.
static func _flat_button() -> Button:
	var button: Button = Button.new()
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	return button
