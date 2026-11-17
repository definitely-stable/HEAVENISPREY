class_name RunResults
extends Control
## The stopped run and its summary (ADR-011 §1). A new run needs a deliberate
## press after the first second.

signal restart_requested

const ARM_DELAY: float = 1.0
const PANEL_SIZE: Vector2 = Vector2(566, 416)
const COLOR_DIM: Color = Color(0.045, 0.027, 0.07, 0.69)
const STAT_KEYS: Array[String] = [
	"UI_RUN_TIME_LABEL", "UI_RUN_KILLS_LABEL", "UI_RUN_LEVEL_LABEL", "UI_RUN_XP_LABEL",
]

var kit: HudKit
var title: Label
var hint: Label
var new_run_button: Button
var stat_values: Array[Label] = []
var _stat_labels: Array[Label] = []
var _arm_left: float = 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim: ColorRect = ColorRect.new()
	dim.color = COLOR_DIM
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
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 30
	margin.offset_right = -30
	margin.offset_top = 36
	margin.offset_bottom = -24
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	title = _label(42, HudKit.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.y = 60.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(title)
	var stats: GridContainer = GridContainer.new()
	stats.columns = 2
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 10)
	column.add_child(stats)
	var tile_style: StyleBoxFlat = StyleBoxFlat.new()
	tile_style.bg_color = Color("#271d26")
	tile_style.border_color = Color("#59413e")
	tile_style.set_border_width_all(1)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		tile_style.set_content_margin(side, 10.0)
	for _key: String in STAT_KEYS:
		_add_stat(stats, tile_style)
	new_run_button = Button.new()
	new_run_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_run_button.custom_minimum_size = Vector2(224, 48)
	new_run_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	new_run_button.pressed.connect(_on_restart_pressed)
	column.add_child(new_run_button)
	hint = _label(19, HudKit.MUTED)
	column.add_child(hint)


func _add_stat(stats: GridContainer, tile_style: StyleBoxFlat) -> void:
	var tile: PanelContainer = PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_stylebox_override("panel", tile_style)
	stats.add_child(tile)
	var row: VBoxContainer = VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	tile.add_child(row)
	var label: Label = _label(20, HudKit.MUTED)
	var value: Label = _label(33, HudKit.TEXT)
	row.add_child(label)
	row.add_child(value)
	_stat_labels.append(label)
	stat_values.append(value)


func _draw_plate(plate: Control) -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, plate.size)
	HudKit.draw_plate(plate, rect, HudKit.INK, HudKit.GOLD)
	HudKit.draw_plate(plate, rect.grow(-5.0), HudKit.INK, Color("#523a30"))
	if kit != null:
		kit.draw(plate, "divider_lotus", Rect2(rect.get_center().x - 102.0, 21, 204, 18))


func open(world: WorldState) -> void:
	if kit == null:
		kit = HudKit.load_default()
		theme = kit.menu_theme()
	var won: bool = world.won != 0
	title.text = UiText.text("UI_RUN_VICTORY" if won else "UI_RUN_DEFEAT")
	title.add_theme_color_override("font_color", HudKit.JADE if won else HudKit.CRIMSON)
	var values: Array[String] = [clock(world.tick), str(world.kills), str(world.level), str(world.xp_collected_total)]
	for index: int in STAT_KEYS.size():
		_stat_labels[index].text = UiText.text(STAT_KEYS[index])
		stat_values[index].text = values[index]
	new_run_button.text = UiText.text("UI_RUN_NEW")
	new_run_button.self_modulate = Color(0.7, 0.7, 0.7)
	hint.text = UiText.text("UI_RUN_CONFIRM_INPUT")
	hint.modulate.a = 0.0
	_arm_left = ARM_DELAY
	visible = true
	if is_inside_tree():
		var action: NodePath = new_run_button.get_path()
		new_run_button.focus_next = action
		new_run_button.focus_previous = action
		new_run_button.grab_focus()


func close() -> void:
	visible = false
	_arm_left = 0.0


func age(delta: float) -> void:
	if _arm_left <= 0.0:
		return
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)
	if is_armed():
		hint.modulate.a = 1.0
		new_run_button.self_modulate = Color.WHITE


func _on_restart_pressed() -> void:
	if is_armed():
		restart_requested.emit()


func is_armed() -> bool:
	return visible and _arm_left <= 0.0


static func clock(tick: int) -> String:
	var seconds: int = floori(tick / float(Fx.TICKS_PER_SECOND))
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


static func _label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
