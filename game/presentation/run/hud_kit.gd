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

var texture: Texture2D
var font: Font = ThemeDB.fallback_font
var density: float = 2.0
## name -> {region: Rect2, inner: Rect2 (relative to the region, atlas px; empty when none),
## slice: Vector2 (left and right caps, atlas px; zero when the piece does not stretch)}
var _pieces: Dictionary = {}


static func load_default() -> HudKit:
	var kit: HudKit = HudKit.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary:
		for entry: Variant in (parsed as Dictionary).get("assets", []):
			if entry is Dictionary and str((entry as Dictionary).get("asset_id", "")) == ASSET_ID:
				kit._read(entry as Dictionary)
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
func draw_text(canvas: CanvasItem, text: String, center_x: float, baseline: float, size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at: Vector2 = Vector2(roundf(center_x - width * 0.5), roundf(baseline))
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 6),
		Color(0.06, 0.03, 0.02, 0.9))
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _rect(values: Variant) -> Rect2:
	if not values is Array or (values as Array).size() != 4:
		return Rect2()
	var v: Array = values
	return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
