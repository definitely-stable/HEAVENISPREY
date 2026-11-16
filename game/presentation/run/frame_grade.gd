class_name FrameGrade
extends CanvasLayer
## ADR-014 section 20: the tone of the world frame after REF-023. The frame was flat (luma
## p5 / p50 / p99 about 50 / 89 / 197 against 20 / 75 / 246 on REF-023): no deep shadows and no
## hot lights. One full-screen pass over the scene and under the HUD (shaders/frame_grade):
## an S-curve around PIVOT on each channel, mixed in by CURVE, and a vignette that darkens the
## corners by up to VIGNETTE. The HUD, the menu and the results draw above it unchanged.
## Presentation only.

## Between the scene (canvas 0) and the HUD layer (RunView.HUD_LAYER).
const LAYER: int = 1
const SHADER: Shader = preload("res://presentation/run/shaders/frame_grade.gdshader")
const CURVE: float = 0.4
const PIVOT: float = 0.5
const VIGNETTE: float = 0.5
## The vignette starts at this share of the half diagonal and is full at the corner.
const VIGNETTE_INNER: float = 0.38
const VIGNETTE_OUTER: float = 0.95
## Luma (0-1) over which a pixel is spared the vignette: flames and gold light in the corners
## stay hot.
const HIGHLIGHT_LOW: float = 0.55
const HIGHLIGHT_HIGH: float = 0.85

var rect: ColorRect
## Share of light the world loses (the paused run under the level-up menu); the HUD above is
## not touched.
var dim: float = 0.0:
	set(value):
		dim = clampf(value, 0.0, 1.0)
		if rect != null:
			(rect.material as ShaderMaterial).set_shader_parameter("dim", dim)


func _init() -> void:
	layer = LAYER
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grade: ShaderMaterial = ShaderMaterial.new()
	grade.shader = SHADER
	grade.set_shader_parameter("curve", CURVE)
	grade.set_shader_parameter("pivot", PIVOT)
	grade.set_shader_parameter("vignette", VIGNETTE)
	grade.set_shader_parameter("vignette_inner", VIGNETTE_INNER)
	grade.set_shader_parameter("vignette_outer", VIGNETTE_OUTER)
	grade.set_shader_parameter("highlight_low", HIGHLIGHT_LOW)
	grade.set_shader_parameter("highlight_high", HIGHLIGHT_HIGH)
	rect.material = grade
	add_child(rect)


func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)


func _fit() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	(rect.material as ShaderMaterial).set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## The S-curve of one channel (0-1), as the shader applies it.
static func curve_of(value: float) -> float:
	var shaped: float
	if value < PIVOT:
		shaped = PIVOT * pow(clampf(value / PIVOT, 0.0, 1.0), 2.0)
	else:
		shaped = 1.0 - (1.0 - PIVOT) * pow(clampf((1.0 - value) / (1.0 - PIVOT), 0.0, 1.0), 2.0)
	return lerpf(value, shaped, CURVE)


## Darkening factor of the vignette at a screen point (uv 0-1) of a frame `aspect` wide, for
## a pixel of luma `luma` (after the curve): bright pixels are spared.
static func vignette_at(uv: Vector2, aspect: float, luma: float = 0.0) -> float:
	var d: Vector2 = (uv - Vector2(0.5, 0.5)) * Vector2(aspect, 1.0)
	var share: float = d.length() / (0.5 * Vector2(aspect, 1.0).length())
	var bright: float = smoothstep(HIGHLIGHT_LOW, HIGHLIGHT_HIGH, luma)
	return 1.0 - VIGNETTE * smoothstep(VIGNETTE_INNER, VIGNETTE_OUTER, share) * (1.0 - bright)


## A colour of the scene as it reaches the screen at `uv`.
static func apply(color: Color, uv: Vector2, aspect: float) -> Color:
	var curved: Color = Color(curve_of(color.r), curve_of(color.g), curve_of(color.b))
	var luma: float = curved.r * 0.2126 + curved.g * 0.7152 + curved.b * 0.0722
	var shade: float = vignette_at(uv, aspect, luma)
	return Color(curved.r * shade, curved.g * shade, curved.b * shade, 1.0)
