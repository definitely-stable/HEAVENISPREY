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
## A halo is blurred at 1 / HALO_STEP of the atlas resolution: it is soft, it needs no detail.
const HALO_STEP: int = 3
const OUTLINE_COLOR: Color = Color(0.06, 0.03, 0.02, 0.9)

var texture: Texture2D
var font: Font = ThemeDB.fallback_font
var density: float = 2.0
## name -> {region: Rect2, inner: Rect2 (relative to the region, atlas px; empty when none),
## slice: Vector2 (left and right caps, atlas px; zero when the piece does not stretch)}
var _pieces: Dictionary = {}
## "piece@spread" -> {"texture": ImageTexture, "pad": float (atlas px around the piece)}
var _halos: Dictionary = {}


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
			weighted.opentype_features = {server.name_to_tag("lnum"): 1}
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


## Draws the left `share` (0-1) of a fill strip into `rect`: the strip is cut, not squeezed.
func draw_fill(canvas: CanvasItem, piece: String, rect: Rect2, share: float) -> void:
	share = clampf(share, 0.0, 1.0)
	if not has(piece) or share <= 0.0:
		return
	var region: Rect2 = _pieces[piece]["region"]
	canvas.draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)),
		Rect2(region.position, Vector2(region.size.x * share, region.size.y)))


## Text with a dark outline, horizontally centred on `center_x` with its baseline at `baseline`.
## With a `width` the text is set smaller until it fits that many px.
func draw_text(
	canvas: CanvasItem, text: String, center_x: float, baseline: float, size: int, color: Color, width: float = -1.0
) -> void:
	if width > 0.0:
		size = fit_size(text, width, size)
	var span: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = Vector2(roundf(center_x - span * 0.5), roundf(baseline))
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size(size), OUTLINE_COLOR)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## One line centred in `rect` (both ways), set smaller when it is wider than the rect.
func draw_text_in(canvas: CanvasItem, text: String, rect: Rect2, size: int, color: Color) -> void:
	size = fit_size(text, rect.size.x, size)
	draw_text(canvas, text, rect.get_center().x, rect.get_center().y + size * CAP_CENTER, size, color)


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


## Draws the soft halo of `piece` around `rect` (the rect the piece itself is drawn into): its
## silhouette blurred `spread` screen px outwards, white, tinted by `modulate`. Meant for a canvas
## item with additive blending, behind the piece.
func draw_halo(canvas: CanvasItem, piece: String, rect: Rect2, spread: float, modulate: Color) -> void:
	var halo: Dictionary = halo_of(piece, spread)
	if halo.is_empty():
		return
	var scale: float = rect.size.y / (_pieces[piece]["region"] as Rect2).size.y
	canvas.draw_texture_rect(halo["texture"], rect.grow(float(halo["pad"]) * scale), false, modulate)


## The halo of `piece`, made once from its alpha in the atlas: the silhouette at 1 / HALO_STEP
## resolution, padded, box-blurred three times each way (close to a gaussian).
func halo_of(piece: String, spread: float) -> Dictionary:
	var key: String = "%s@%d" % [piece, roundi(spread)]
	if _halos.has(key):
		return _halos[key]
	if not has(piece):
		return {}
	var atlas: Image = texture.get_image()
	if atlas == null:
		return {}
	if atlas.is_compressed():
		atlas.decompress()
	var region: Rect2i = Rect2i(_pieces[piece]["region"] as Rect2)
	var part: Image = atlas.get_region(region)
	var w: int = maxi(1, region.size.x / HALO_STEP)
	var h: int = maxi(1, region.size.y / HALO_STEP)
	part.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var radius: int = maxi(1, roundi(spread * density / HALO_STEP / 3.0))
	var pad: int = radius * 3 + 1
	var cols: int = w + pad * 2
	var rows: int = h + pad * 2
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(cols * rows)
	for y: int in h:
		for x: int in w:
			field[(y + pad) * cols + x + pad] = part.get_pixel(x, y).a
	for _pass: int in 3:
		field = _box_blur(field, cols, rows, radius, 1, cols)
		field = _box_blur(field, rows, cols, radius, cols, 1)
	var image: Image = Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	for y: int in rows:
		for x: int in cols:
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(field[y * cols + x], 0.0, 1.0)))
	_halos[key] = {"texture": ImageTexture.create_from_image(image), "pad": float(pad * HALO_STEP)}
	return _halos[key]


## One box-blur pass of `radius` along lines of `length` samples (`step` apart); `lines` lines,
## each `stride` apart. Samples past the ends count as zero.
static func _box_blur(
	field: PackedFloat32Array, length: int, lines: int, radius: int, step: int, stride: int
) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(field.size())
	var norm: float = 1.0 / float(radius * 2 + 1)
	for line: int in lines:
		var base: int = line * stride
		var sum: float = 0.0
		for i: int in mini(radius, length):
			sum += field[base + i * step]
		for i: int in length:
			if i + radius < length:
				sum += field[base + (i + radius) * step]
			if i - radius - 1 >= 0:
				sum -= field[base + (i - radius - 1) * step]
			out[base + i * step] = sum * norm
	return out


static func _rect(values: Variant) -> Rect2:
	if not values is Array or (values as Array).size() != 4:
		return Rect2()
	var v: Array = values
	return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
