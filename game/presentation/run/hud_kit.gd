class_name HudKit
extends RefCounted
## The gold HUD kit (ADR-014 section 15): pieces of `asset.ui.hud_kit` cut from sheets generated
## after the REF-022 and REF-008 kits, with the window each frame holds, and the HUD font.
## Drawn over the scene in screen px, unlit. Rects passed in are on-screen rects; the atlas holds
## `density` px per screen px. Presentation only.

const ASSET_ID: String = "asset.ui.hud_kit"
const MANIFEST_PATH: String = "res://assets/manifest.json"
const FONT_PATH: String = "res://assets/fonts/CormorantGaramond-Variable.ttf"
## Weight of the variable font (OpenType wght axis, 300-700).
const FONT_WEIGHT: int = 650
## Text that does not fit its window is set smaller, down to this size, never past the frame.
const MIN_FONT_SIZE: int = 10
## The baseline of a line centred in a window sits this share of the font size below the centre
## (half the cap height of the face).
const CAP_CENTER: float = 0.33
## Cap height of the face (OS/2 sCapHeight 625 of 1000): the lining figures stand this tall.
const CAP_HEIGHT: float = 0.625
const OUTLINE_COLOR: Color = Color(0.06, 0.03, 0.02, 0.9)
const INK: Color = Color("#1b151c")
const BRONZE: Color = Color("#8b6a4a")
const GOLD: Color = Color("#e9c583")
const FOCUS: Color = Color("#ffe0a8")
const TEXT: Color = Color("#f8ead7")
const MUTED: Color = Color("#d6c0ab")
const JADE: Color = Color("#8bd6bd")
const CRIMSON: Color = Color("#f0a19a")

var texture: Texture2D
var font: Font = ThemeDB.fallback_font
var density: float = 2.0
## name -> {region: Rect2, inner: Rect2 (relative to the region, atlas px; empty when none),
## slice: Vector2 (left and right caps, atlas px; zero when the piece does not stretch)}
var _pieces: Dictionary = {}


## The lacquer plate used behind text in the HUD, cards and results.
static func draw_plate(canvas: CanvasItem, rect: Rect2, fill: Color = INK, edge: Color = BRONZE,
		line_width: float = 1.0) -> void:
	var cut: float = minf(rect.size.y * 0.2, 9.0)
	var a: Vector2 = rect.position
	var b: Vector2 = rect.end
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut),
		Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y),
		Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut),
	])
	var colors: PackedColorArray = PackedColorArray()
	var top: Color = Color(fill.lerp(Color("#684536"), 0.20), fill.a)
	for point: Vector2 in points:
		colors.append(top.lerp(fill.darkened(0.12), (point.y - a.y) / rect.size.y))
	canvas.draw_polygon(points, colors)
	points.append(points[0])
	canvas.draw_polyline(points, edge, line_width, true)


func menu_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	theme.set_stylebox("normal", "Button", _button_style(Color("#412b25"), BRONZE, 1))
	theme.set_stylebox("hover", "Button", _button_style(Color("#50372d"), GOLD, 1))
	theme.set_stylebox("pressed", "Button", _button_style(Color("#2a2021"), GOLD, 1))
	theme.set_stylebox("focus", "Button", _button_style(Color.TRANSPARENT, FOCUS, 2))
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		theme.set_color(state, "Button", TEXT)
	return theme


static func _button_style(fill: Color, edge: Color, border: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(4)
	return style


static func load_default() -> HudKit:
	var kit: HudKit = load_kit(ASSET_ID)
	if ResourceLoader.exists(FONT_PATH):
		var file: Font = load(FONT_PATH) as Font
		if file != null:
			var weighted: FontVariation = FontVariation.new()
			weighted.base_font = file
			var server: TextServer = TextServerManager.get_primary_interface()
			weighted.variation_opentype = {server.name_to_tag("wght"): FONT_WEIGHT}
			# Lining figures: the old-style digits of the face read "0" as "o" in counters.
			# Tabular figures: every digit is as wide as the others, so a counter does not shift
			# as it counts.
			weighted.opentype_features = {server.name_to_tag("lnum"): 1, server.name_to_tag("tnum"): 1}
			kit.font = weighted
	return kit


## The pieces of any atlas of named pieces in the manifest (the HUD kit, the effects atlas), with
## the fallback font.
static func load_kit(asset_id: String) -> HudKit:
	var kit: HudKit = HudKit.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary:
		for entry: Variant in (parsed as Dictionary).get("assets", []):
			if entry is Dictionary and str((entry as Dictionary).get("asset_id", "")) == asset_id:
				kit._read(entry as Dictionary)
	return kit


func _read(entry: Dictionary) -> void:
	var res_path: String = "res://" + str(entry.get("path", "")).trim_prefix("game/")
	if not ResourceLoader.exists(res_path):
		push_error("HudKit: cannot load " + res_path)
		return
	texture = load(res_path) as Texture2D
	var layout: Dictionary = entry.get("layout", {})
	density = float(layout.get("density", 2.0))
	for piece: Variant in layout.get("pieces", []):
		if not piece is Dictionary:
			continue
		var region: Rect2 = _rect(piece.get("region", []))
		var inner: Rect2 = _rect(piece.get("inner", []))
		if inner.has_area():
			inner.position -= region.position
		var caps: Array = piece.get("slice", [0, 0])
		_pieces[str(piece.get("name", ""))] = {
			"region": region, "inner": inner, "slice": Vector2(float(caps[0]), float(caps[1])),
		}


func has(piece: String) -> bool:
	return texture != null and _pieces.has(piece)


## On-screen size of a piece drawn at its native scale.
func size_of(piece: String) -> Vector2:
	return (_pieces[piece]["region"] as Rect2).size / density if has(piece) else Vector2.ZERO


## The window of a frame drawn into `rect` (stretched pieces keep their caps at the height scale).
func window(piece: String, rect: Rect2) -> Rect2:
	if not has(piece):
		return rect
	var data: Dictionary = _pieces[piece]
	var region: Rect2 = data["region"]
	var inner: Rect2 = data["inner"]
	if not inner.has_area():
		return rect
	var scale: float = rect.size.y / region.size.y
	var top: float = rect.position.y + inner.position.y * scale
	if (data["slice"] as Vector2) == Vector2.ZERO:
		var scale_x: float = rect.size.x / region.size.x
		return Rect2(rect.position.x + inner.position.x * scale_x, top, inner.size.x * scale_x, inner.size.y * scale)
	var right_gap: float = (region.size.x - inner.end.x) * scale
	var left: float = rect.position.x + inner.position.x * scale
	return Rect2(left, top, rect.end.x - right_gap - left, inner.size.y * scale)


## Draws a piece into `rect`; a stretchable piece keeps its end caps and stretches its middle.
func draw(canvas: CanvasItem, piece: String, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if not has(piece):
		return
	var data: Dictionary = _pieces[piece]
	var region: Rect2 = data["region"]
	var caps: Vector2 = data["slice"]
	if caps == Vector2.ZERO:
		canvas.draw_texture_rect_region(texture, rect, region, modulate)
		return
	var scale: float = rect.size.y / region.size.y
	var left: float = minf(caps.x * scale, rect.size.x * 0.5)
	var right: float = minf(caps.y * scale, rect.size.x * 0.5)
	var middle: Rect2 = Rect2(
		region.position.x + caps.x, region.position.y, region.size.x - caps.x - caps.y, region.size.y
	)
	canvas.draw_texture_rect_region(texture, Rect2(rect.position, Vector2(left, rect.size.y)),
		Rect2(region.position, Vector2(caps.x, region.size.y)), modulate)
	canvas.draw_texture_rect_region(texture, Rect2(rect.position.x + left, rect.position.y,
		rect.size.x - left - right, rect.size.y), middle, modulate)
	canvas.draw_texture_rect_region(texture, Rect2(rect.end.x - right, rect.position.y, right, rect.size.y),
		Rect2(region.end.x - caps.y, region.position.y, caps.y, region.size.y), modulate)


## Feather the edges of the painted card illustrations into the lacquer.
func draw_card_art(canvas: CanvasItem, piece: String, rect: Rect2) -> void:
	if not has(piece):
		return
	var region: Rect2 = _pieces[piece]["region"]
	var atlas_size: Vector2 = texture.get_size()
	var knots: PackedFloat32Array = PackedFloat32Array([0.0, 0.12, 0.88, 1.0])
	for y: int in 3:
		for x: int in 3:
			var a: Vector2 = Vector2(knots[x], knots[y])
			var b: Vector2 = Vector2(knots[x + 1], knots[y + 1])
			var points: PackedVector2Array = PackedVector2Array()
			var uvs: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()
			for uv: Vector2 in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]:
				points.append(rect.position + uv * rect.size)
				uvs.append((region.position + region.size * uv) / atlas_size)
				var edge: float = minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
				colors.append(Color(1, 1, 1, clampf(edge / knots[1], 0.0, 1.0)))
			canvas.draw_polygon(points, colors, uvs, texture)


## Text with a dark outline, horizontally centred on `center_x` with its baseline at `baseline`.
## With a `width` the text is set smaller until it fits that many px. `outline` adds px to the
## outline (numbers over a bright fill).
func draw_text(
	canvas: CanvasItem, text: String, center_x: float, baseline: float, size: int, color: Color, width: float = -1.0,
	outline: int = 0
) -> void:
	if width > 0.0:
		size = fit_size(text, width, size)
	var span: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = Vector2(roundf(center_x - span * 0.5), roundf(baseline))
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size(size) + outline,
		OUTLINE_COLOR)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## One line centred in `rect` (both ways), set smaller when it is wider or taller than the rect.
## With a `sample` (the widest text the place can hold, e.g. "99999") the size is fitted to the
## sample, so it stays the same while the value changes; a text wider still is fitted on its own.
func draw_text_in(
	canvas: CanvasItem, text: String, rect: Rect2, size: int, color: Color, sample: String = "", outline: int = 0,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> void:
	size = line_size(text, rect, size, sample, outline)
	var center_x: float = rect.get_center().x
	if alignment != HORIZONTAL_ALIGNMENT_CENTER:
		var span: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		center_x = rect.position.x + span * 0.5 if alignment == HORIZONTAL_ALIGNMENT_LEFT else rect.end.x - span * 0.5
	draw_text(canvas, text, center_x, rect.get_center().y + size * CAP_CENTER, size, color, -1.0, outline)


## The size draw_text_in sets `text` at in `rect` (see there).
func line_size(text: String, rect: Rect2, size: int, sample: String = "", outline: int = 0) -> int:
	size = mini(size, fit_height(rect.size.y, size, outline))
	if not sample.is_empty():
		size = fit_size(sample, rect.size.x - outline, size)
	return fit_size(text, rect.size.x - outline, size)


## The largest size, at most `size`, at which capitals and lining figures with their outline
## stand inside `height` px.
func fit_height(height: float, size: int, outline: int = 0) -> int:
	var fitted: int = size
	while fitted > MIN_FONT_SIZE and fitted * CAP_HEIGHT + 2.0 * (outline_size(fitted) + outline) > height + 0.5:
		fitted -= 1
	return fitted


## The largest size, at most `size`, at which `text` with its outline is at most `width` px wide.
func fit_size(text: String, width: float, size: int) -> int:
	var fitted: int = size
	while fitted > MIN_FONT_SIZE and text_width(text, fitted) > width:
		fitted -= 1
	return fitted


## Width of one line of `text` with its outline.
func text_width(text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + outline_size(size)


static func outline_size(size: int) -> int:
	return maxi(2, size / 6)


## The largest size, at most `size`, at which `text` wraps into at most `max_lines` lines of
## `width` px and no word is wider than the line.
func fit_paragraph_size(text: String, width: float, size: int, max_lines: int) -> int:
	var fitted: int = size
	while fitted > MIN_FONT_SIZE and not _paragraph_fits(text, width, fitted, max_lines):
		fitted -= 1
	return fitted


## Height of `text` wrapped in `width` px at `size`.
func paragraph_height(text: String, width: float, size: int) -> float:
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, size).y


## Wrapped, centred text in `width` px from `top_left` (the top of the first line), set at the
## size from fit_paragraph_size; returns the height it took.
func draw_paragraph(
	canvas: CanvasItem, text: String, top_left: Vector2, width: float, size: int, color: Color, max_lines: int
) -> float:
	size = fit_paragraph_size(text, width, size, max_lines)
	var at: Vector2 = Vector2(roundf(top_left.x), roundf(top_left.y + font.get_ascent(size)))
	canvas.draw_multiline_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, max_lines,
		outline_size(size), OUTLINE_COLOR)
	canvas.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, max_lines, color)
	return paragraph_height(text, width, size)


func _paragraph_fits(text: String, width: float, size: int, max_lines: int) -> bool:
	for word: String in text.split(" ", false):
		if text_width(word, size) > width:
			return false
	return paragraph_height(text, width, size) <= font.get_height(size) * max_lines + 0.5


static func _rect(values: Variant) -> Rect2:
	if not values is Array or (values as Array).size() != 4:
		return Rect2()
	var v: Array = values
	return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
