class_name SpriteSet
extends RefCounted
## Game sprites by stable asset_id (ADR-009 section 5, ADR-013): reads
## res://assets/manifest.json, loads each atlas or floor texture and answers frame regions.
## An atlas holds one row per direction and `frames` columns of `frame_size` px, drawn at
## half size (double density for the 1280x720 window); the simulation position is the
## frame's feet_anchor. A missing or broken asset is skipped with an error, so the scene
## falls back to its primitives. Presentation only: nothing here reaches the simulation.
## Each asset also carries its normal map (ADR-014 section 4) as a CanvasTexture, so 2D
## lights and the rim shader see its shape; without a normal map the plain texture is used.
## Sprite atlases are packed side by side into one shared CanvasTexture at load, so a horde
## of mixed kinds sorted by depth is drawn in one batch instead of one per texture switch.

const MANIFEST_PATH: String = "res://assets/manifest.json"
## Atlas pixels per screen pixel.
const DENSITY: float = 2.0
## Walk-cycle frames per second.
const WALK_FPS: float = 8.0

## Kinds drawn standing up (packed together, lit like bodies).
const UPRIGHT_KINDS: Array[String] = ["sprite_atlas", "prop_atlas"]
## Transparent px between packed atlases, so mipmaps do not bleed one into the next.
const PACK_GAP_PX: int = 16

## asset_id -> {texture, canvas, origin, kind, directions, frames, frame_size, feet_anchor, cells}
var _assets: Dictionary = {}


static func load_default() -> SpriteSet:
	return SpriteSet.from_manifest(MANIFEST_PATH)


static func from_manifest(path: String) -> SpriteSet:
	var sprites: SpriteSet = SpriteSet.new()
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SpriteSet: no asset manifest at " + path)
		return sprites
	for entry: Variant in (parsed as Dictionary).get("assets", []):
		if entry is Dictionary:
			sprites._add(entry as Dictionary)
	sprites._pack_atlases()
	return sprites


func _add(entry: Dictionary) -> void:
	var asset_id: String = str(entry.get("asset_id", ""))
	var res_path: String = "res://" + str(entry.get("path", "")).trim_prefix("game/")
	var texture: Texture2D = load(res_path) as Texture2D if ResourceLoader.exists(res_path) else null
	if texture == null:
		push_error("SpriteSet: cannot load " + asset_id + " from " + res_path)
		return
	var canvas: Texture2D = texture
	var normal: Dictionary = entry.get("normal", {})
	var normal_path: String = "res://" + str(normal.get("path", "")).trim_prefix("game/")
	if not normal.is_empty() and ResourceLoader.exists(normal_path):
		var lit: CanvasTexture = CanvasTexture.new()
		lit.diffuse_texture = texture
		lit.normal_texture = load(normal_path) as Texture2D
		lit.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		canvas = lit
	var layout: Dictionary = entry.get("layout", {})
	var anchor: Array = layout.get("feet_anchor", [0, 0])
	_assets[asset_id] = {
		"texture": texture,
		"canvas": canvas,
		"origin": Vector2.ZERO,
		"kind": str(entry.get("kind", "")),
		"directions": PackedStringArray(layout.get("directions", [])),
		"frames": int(layout.get("frames", 1)),
		"frame_size": int(layout.get("frame_size", 0)),
		"feet_anchor": Vector2(float(anchor[0]), float(anchor[1])),
		"cells": int(layout.get("cells", 1)),
		"density": float(layout.get("density", DENSITY)),
		"world_px": float(layout.get("world_px", 0.0)),
		"props": _props_of(layout),
	}


## name -> {region: Rect2, feet: Vector2} of a prop atlas (atlas px).
static func _props_of(layout: Dictionary) -> Dictionary:
	var props: Dictionary = {}
	for prop: Variant in layout.get("props", []):
		if prop is Dictionary:
			var region: Array = prop.get("region", [0, 0, 0, 0])
			var feet: Array = prop.get("feet", [0, 0])
			props[str(prop.get("name", ""))] = {
				"region": Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3])),
				"feet": Vector2(float(feet[0]), float(feet[1])),
			}
	return props


## Packs every sprite atlas with a normal map into one CanvasTexture (diffuse and normals at
## the same offsets) and points the assets at it; a single atlas or a failed read stays as is.
func _pack_atlases() -> void:
	var ids: Array[String] = []
	var width: int = 0
	var height: int = 0
	for asset_id: String in _assets:
		if _assets[asset_id]["kind"] in UPRIGHT_KINDS and has_normals(asset_id):
			ids.append(asset_id)
			var size: Vector2i = Vector2i(_assets[asset_id]["texture"].get_size())
			width += size.x + (PACK_GAP_PX if width > 0 else 0)
			height = maxi(height, size.y)
	if ids.size() < 2:
		return
	var diffuse: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var normals: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	normals.fill(Color(0.5, 0.5, 1.0, 0.0))
	var origins: Dictionary = {}
	var x: int = 0
	for asset_id: String in ids:
		var canvas: CanvasTexture = _assets[asset_id]["canvas"]
		var colour: Image = _rgba(canvas.diffuse_texture)
		var normal: Image = _rgba(canvas.normal_texture)
		if colour == null or normal == null or colour.get_size() != normal.get_size():
			push_error("SpriteSet: cannot pack " + asset_id)
			return
		diffuse.blit_rect(colour, Rect2i(Vector2i.ZERO, colour.get_size()), Vector2i(x, 0))
		normals.blit_rect(normal, Rect2i(Vector2i.ZERO, normal.get_size()), Vector2i(x, 0))
		origins[asset_id] = Vector2(x, 0)
		x += colour.get_width() + PACK_GAP_PX
	diffuse.generate_mipmaps()
	normals.generate_mipmaps(true)
	var shared: CanvasTexture = CanvasTexture.new()
	shared.diffuse_texture = ImageTexture.create_from_image(diffuse)
	shared.normal_texture = ImageTexture.create_from_image(normals)
	for asset_id: String in ids:
		_assets[asset_id]["canvas"] = shared
		_assets[asset_id]["origin"] = origins[asset_id]


static func _rgba(texture: Texture2D) -> Image:
	var image: Image = texture.get_image() if texture != null else null
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


func has(asset_id: String) -> bool:
	return _assets.has(asset_id)


func texture(asset_id: String) -> Texture2D:
	return _assets[asset_id]["texture"] if _assets.has(asset_id) else null


## The texture to draw with: diffuse plus normal map when the asset has one (for a packed
## atlas, the shared texture; its frame regions start at atlas_origin()).
func canvas_texture(asset_id: String) -> Texture2D:
	return _assets[asset_id]["canvas"] if _assets.has(asset_id) else null


## Where the asset's atlas starts inside canvas_texture().
func atlas_origin(asset_id: String) -> Vector2:
	return _assets[asset_id]["origin"] if _assets.has(asset_id) else Vector2.ZERO


func has_normals(asset_id: String) -> bool:
	return _assets.has(asset_id) and _assets[asset_id]["canvas"] is CanvasTexture


func directions(asset_id: String) -> PackedStringArray:
	return _assets[asset_id]["directions"] if _assets.has(asset_id) else PackedStringArray()


## Atlas region of `frame` (wrapped) facing `direction`; an empty Rect2 for an unknown asset
## or direction.
func frame_region(asset_id: String, direction: String, frame: int) -> Rect2:
	if not _assets.has(asset_id):
		return Rect2()
	var asset: Dictionary = _assets[asset_id]
	var row: int = (asset["directions"] as PackedStringArray).find(direction)
	if row < 0:
		return Rect2()
	var size: float = float(asset["frame_size"])
	var column: int = posmod(frame, int(asset["frames"]))
	return Rect2(column * size, row * size, size, size)


## Draws one frame with its feet_anchor on `feet` (px); false when the asset is missing.
func draw_frame(
	canvas: CanvasItem, asset_id: String, direction: String, frame: int, feet: Vector2, tint: Color
) -> bool:
	var region: Rect2 = frame_region(asset_id, direction, frame)
	if region.size == Vector2.ZERO:
		return false
	var asset: Dictionary = _assets[asset_id]
	var anchor: Vector2 = asset["feet_anchor"]
	var rect: Rect2 = Rect2(feet - anchor / DENSITY, region.size / DENSITY)
	var source: Rect2 = Rect2(region.position + asset["origin"], region.size)
	canvas.draw_texture_rect_region(asset["canvas"], rect, source, tint)
	return true


## Prop names of a prop atlas, in atlas order.
func prop_names(asset_id: String) -> PackedStringArray:
	if not _assets.has(asset_id):
		return PackedStringArray()
	return PackedStringArray((_assets[asset_id]["props"] as Dictionary).keys())


func has_prop(asset_id: String, prop: String) -> bool:
	return _assets.has(asset_id) and (_assets[asset_id]["props"] as Dictionary).has(prop)


## On-screen size of a prop (px).
func prop_size(asset_id: String, prop: String) -> Vector2:
	if not has_prop(asset_id, prop):
		return Vector2.ZERO
	var asset: Dictionary = _assets[asset_id]
	return (asset["props"][prop]["region"] as Rect2).size / float(asset["density"])


## Draws a prop with the centre of its base on `feet` (screen px), mirrored when `flip`.
func draw_prop(
	canvas: CanvasItem, asset_id: String, prop: String, feet: Vector2, tint: Color, flip: bool = false
) -> bool:
	if not has_prop(asset_id, prop):
		return false
	var asset: Dictionary = _assets[asset_id]
	var region: Rect2 = asset["props"][prop]["region"]
	var anchor: Vector2 = (asset["props"][prop]["feet"] as Vector2) - region.position
	var density: float = asset["density"]
	var size: Vector2 = region.size / density
	var offset: Vector2 = anchor / density
	if flip:
		offset.x = size.x - offset.x
	var rect: Rect2 = Rect2(feet - offset, size)
	if flip:
		# A negative width mirrors the region inside the same rect (the server flips it).
		rect.size.x = -size.x
	var source: Rect2 = Rect2(region.position + asset["origin"], region.size)
	canvas.draw_texture_rect_region(asset["canvas"], rect, source, tint)
	return true


## A prop as a textured quad for draw_polygon: {texture, rect (px, the centre of its base on
## `feet`, sized by `scale`), uv (normalised region of the texture, mirrored when `flip`)}.
## Empty when the prop is unknown.
func prop_quad(asset_id: String, prop: String, feet: Vector2, scale: float = 1.0, flip: bool = false) -> Dictionary:
	if not has_prop(asset_id, prop):
		return {}
	var asset: Dictionary = _assets[asset_id]
	var region: Rect2 = asset["props"][prop]["region"]
	var density: float = float(asset["density"]) / scale
	var size: Vector2 = region.size / density
	var offset: Vector2 = ((asset["props"][prop]["feet"] as Vector2) - region.position) / density
	if flip:
		offset.x = size.x - offset.x
	var texture: Texture2D = asset["canvas"]
	var full: Vector2 = texture.get_size()
	var uv: Rect2 = Rect2((region.position + asset["origin"]) / full, region.size / full)
	if flip:
		uv = Rect2(Vector2(uv.end.x, uv.position.y), Vector2(-uv.size.x, uv.size.y))
	return {"texture": texture, "rect": Rect2(feet - offset, size), "uv": uv}


## World px a floor decal spans (its texture covers a world square of this side).
func decal_world_px(asset_id: String) -> float:
	return float(_assets[asset_id]["world_px"]) if _assets.has(asset_id) else 0.0


## Screen px covered by one repeat of a floor texture (cells x cell size).
func floor_repeat_px(asset_id: String, cell_px: int) -> float:
	if not _assets.has(asset_id):
		return 0.0
	return float(int(_assets[asset_id]["cells"]) * cell_px)


## The direction row for a facing vector: the dominant axis, ties going to the side views.
static func four_way(facing: Vector2) -> String:
	if absf(facing.y) > absf(facing.x):
		return "down" if facing.y > 0.0 else "up"
	return "left" if facing.x < 0.0 else "right"


## Walk frame for `seconds` of animation, offset by a per-entity phase so a horde does not
## step in unison.
static func walk_frame(seconds: float, phase: int) -> int:
	return int(floor(seconds * WALK_FPS)) + phase
