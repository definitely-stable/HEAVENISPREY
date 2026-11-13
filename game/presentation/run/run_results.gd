class_name RunResults
extends Control
## Results of a finished run (ADR-011 section 1): victory or defeat, time, kills, level and
## experience gathered, over the stopped scene. RunView starts a new run on `restart` at any
## time or on `ui_accept` once the screen is armed (ARM_DELAY after it opened), so a button
## held in the last second of combat does not skip the results.

const ARM_DELAY: float = 1.0
const TITLE_FONT_SIZE: int = 36
const LINE_FONT_SIZE: int = 22
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.55)
const COLOR_VICTORY: Color = Color(0.36, 0.84, 0.78)
const COLOR_DEFEAT: Color = Color(0.9, 0.35, 0.3)
const COLOR_TEXT: Color = Color(0.95, 0.92, 0.85)
const COLOR_HINT: Color = Color(0.75, 0.72, 0.66)

var title: Label
var lines: Label
var hint: Label
var _arm_left: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	title = _label(TITLE_FONT_SIZE, COLOR_TEXT)
	lines = _label(LINE_FONT_SIZE, COLOR_TEXT)
	hint = _label(LINE_FONT_SIZE, COLOR_HINT)
	column.add_child(title)
	column.add_child(lines)
	column.add_child(hint)


## Shows the results of the finished `world`.
func open(world: WorldState) -> void:
	var won: bool = world.won != 0
	title.text = UiText.text("UI_RUN_VICTORY" if won else "UI_RUN_DEFEAT")
	title.add_theme_color_override("font_color", COLOR_VICTORY if won else COLOR_DEFEAT)
	lines.text = "\n".join(PackedStringArray([
		UiText.text("UI_RUN_TIME") % clock(world.tick),
		UiText.text("UI_RUN_KILLS") % world.kills,
		UiText.text("UI_RUN_LEVEL") % world.level,
		UiText.text("UI_RUN_XP") % world.xp_collected_total,
	]))
	hint.text = UiText.text("UI_RUN_RESTART")
	hint.modulate.a = 0.0
	_arm_left = ARM_DELAY
	visible = true


func close() -> void:
	visible = false
	_arm_left = 0.0


## Counts down the arm delay; the restart hint appears once armed.
func age(delta: float) -> void:
	_arm_left = maxf(_arm_left - maxf(delta, 0.0), 0.0)
	if is_armed():
		hint.modulate.a = 1.0


func is_armed() -> bool:
	return visible and _arm_left <= 0.0


## Run time as mm:ss from the tick count.
static func clock(tick: int) -> String:
	var seconds: int = floori(tick / float(Fx.TICKS_PER_SECOND))
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


static func _label(size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
