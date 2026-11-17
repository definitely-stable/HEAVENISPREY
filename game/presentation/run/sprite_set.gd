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
## Sprite atlases are packed into one shared CanvasTexture at load (bottom-left skyline), so a
## horde of mixed kinds sorted by depth is drawn in one batch instead of one per texture switch.
## An animated atlas (ADR-014 section 3) holds clips (idle, run, attack, death): one row per
## generated direction, the other directions drawn mirrored (sw <- se, w <- e, nw <- ne).

const MANIFEST_PATH: String = "res://assets/manifest.json"
## Atlas pixels per screen pixel.
const DENSITY: float = 2.0
## Walk-cycle frames per second.
const WALK_FPS: float = 8.0

## Kinds drawn standing up (packed together, lit like bodies).
const UPRIGHT_KINDS: Array[String] = ["sprite_atlas", "anim_atlas", "prop_atlas"]
## Width the packed atlas grows to before it starts a new level (px; a wider atlas sets it).
const PACK_WIDTH_PX: int = 4096
## Screen directions of an animated atlas, clockwise from east (ADR-014 section 3).
const EIGHT_WAY: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
## Transparent px between packed atlases, so mipmaps do not bleed one into the next.
const PACK_GAP_PX: int = 16

## The default set, packed once: packing every atlas with mipmaps takes seconds, and a set is
## read-only once loaded, so each run (and each test) shares it.
static var _default: SpriteSet = null

## asset_id -> {texture, canvas, origin, kind, directions, frames, frame_size, feet_anchor, cells}
var _assets: Dictionary = {}


static func load_default() -> SpriteSet:
	if _default == null:
		_default = SpriteSet._from_manifest(MANIFEST_PATH)
	return _default


static func _from_manifest(path: String) -> SpriteSet:
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
	if str(entry.get("kind", "")) in ["ui_atlas", "vfx_atlas"]:
		return  # The HUD kit and the effects are drawn through HudKit, unlit, without normals.
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
		"clips": _clips_of(layout),
		"mirror": layout.get("mirror", {}),
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


## name -> {row, frames, fps, loop, directions} of an animated atlas.
static func _clips_of(layout: Dictionary) -> Dictionary:
	var clips: Dictionary = {}
	var source: Variant = layout.get("clips", {})
	if not source is Dictionary:
		return clips
	for name: Variant in source:
		var clip: Dictionary = source[name]
		clips[str(name)] = {
			"row": int(clip.get("row", 0)),
			"frames": int(clip.get("frames", 1)),
			"fps": float(clip.get("fps", WALK_FPS)),
			"loop": bool(clip.get("loop", true)),
			"directions": PackedStringArray(clip.get("directions", [])),
		}
	return clips


## Packs every sprite atlas with a normal map into one CanvasTexture (diffuse and normals at
## the same offsets) and points the assets at it; a single atlas or a failed read stays as is.
func _pack_atlases() -> void:
	var ids: Array[String] = []
	for asset_id: String in _assets:
		if _assets[asset_id]["kind"] in UPRIGHT_KINDS and has_normals(asset_id):
			ids.append(asset_id)
	if ids.size() < 2:
		return
	# Tallest first, then by id: a stable layout for the same manifest.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ha: int = _assets[a]["texture"].get_height()
		var hb: int = _assets[b]["texture"].get_height()
		return ha > hb or (ha == hb and a < b))
	var sizes: Array[Vector2i] = []
	var limit: int = PACK_WIDTH_PX
	for asset_id: String in ids:
		sizes.append(Vector2i(_assets[asset_id]["texture"].get_size()) + Vector2i.ONE * PACK_GAP_PX)
		limit = maxi(limit, sizes[-1].x)
	var places: Array[Vector2i] = skyline_pack(sizes, limit)
	var width: int = 0
	var height: int = 0
	for index: int in ids.size():
		width = maxi(width, places[index].x + sizes[index].x - PACK_GAP_PX)
		height = maxi(height, places[index].y + sizes[index].y - PACK_GAP_PX)
	var diffuse: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var normals: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	normals.fill(Color(0.5, 0.5, 1.0, 0.0))
	var origins: Dictionary = {}
	for index: int in ids.size():
		var asset_id: String = ids[index]
		var at: Vector2i = places[index]
		var canvas: CanvasTexture = _assets[asset_id]["canvas"]
		var colour: Image = _rgba(canvas.diffuse_texture)
		var normal: Image = _rgba(canvas.normal_texture)
		if colour == null or normal == null or colour.get_size() != normal.get_size():
			push_error("SpriteSet: cannot pack " + asset_id)
			return
		diffuse.blit_rect(colour, Rect2i(Vector2i.ZERO, colour.get_size()), at)
		normals.blit_rect(normal, Rect2i(Vector2i.ZERO, normal.get_size()), at)
		origins[asset_id] = Vector2(at)
	diffuse.generate_mipmaps()
	normals.generate_mipmaps(true)
	var shared: CanvasTexture = CanvasTexture.new()
	shared.diffuse_texture = ImageTexture.create_from_image(diffuse)
	shared.normal_texture = ImageTexture.create_from_image(normals)
	for asset_id: String in ids:
		_assets[asset_id]["canvas"] = shared
		_assets[asset_id]["origin"] = origins[asset_id]


## Bottom-left skyline packing: the top-left corner of each rect (in order) inside `limit` px
## of width, each placed where it rests lowest (then leftmost) on what is already placed.
static func skyline_pack(sizes: Array[Vector2i], limit: int) -> Array[Vector2i]:
	var places: Array[Vector2i] = []
	# Skyline segments (x, y, width), left to right, covering 0..limit.
	var skyline: Array[Vector3i] = [Vector3i(0, 0, limit)]
	for size: Vector2i in sizes:
		var best: Vector2i = Vector2i(-1, -1)
		for start: Vector3i in skyline:
			var right: int = start.x + size.x
			if right > limit:
				break
			var y: int = 0
			for segment: Vector3i in skyline:
				if segment.x < right and segment.x + segment.z > start.x:
					y = maxi(y, segment.y)
			if best.y < 0 or y < best.y:
				best = Vector2i(start.x, y)
		places.append(best)
		var next: Array[Vector3i] = []
		var end: int = best.x + size.x
		for segment: Vector3i in skyline:
			var segment_end: int = segment.x + segment.z
			if segment_end <= best.x or segment.x >= end:
				next.append(segment)
				continue
			if segment.x < best.x:
				next.append(Vector3i(segment.x, segment.y, best.x - segment.x))
			if segment_end > end:
				next.append(Vector3i(end, segment.y, segment_end - end))
		next.append(Vector3i(best.x, best.y + size.y, size.x))
		next.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x)
		skyline = next
	return places


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


func has_clip(asset_id: String, clip: String) -> bool:
	return _assets.has(asset_id) and (_assets[asset_id]["clips"] as Dictionary).has(clip)


## Frames of a clip (0 for an unknown asset or clip).
func clip_frames(asset_id: String, clip: String) -> int:
	return int(_assets[asset_id]["clips"][clip]["frames"]) if has_clip(asset_id, clip) else 0


## Seconds a clip takes once through.
func clip_length(asset_id: String, clip: String) -> float:
	if not has_clip(asset_id, clip):
		return 0.0
	var data: Dictionary = _assets[asset_id]["clips"][clip]
	return data["frames"] / data["fps"]


## Frame of `clip` after `seconds`: looping clips wrap, the others hold their last frame.
func clip_frame(asset_id: String, clip: String, seconds: float) -> int:
	if not has_clip(asset_id, clip):
		return 0
	var data: Dictionary = _assets[asset_id]["clips"][clip]
	var frame: int = int(floor(maxf(seconds, 0.0) * data["fps"]))
	return posmod(frame, data["frames"]) if data["loop"] else mini(frame, data["frames"] - 1)


## [atlas region, mirrored] of a clip frame facing `direction` (one of EIGHT_WAY): a generated
## direction is its own row, a mirrored one uses its source row flipped, a clip with fewer
## directions falls back to its first. An empty region for an unknown asset or clip.
func clip_region(asset_id: String, clip: String, direction: String, frame: int) -> Array:
	if not has_clip(asset_id, clip):
		return [Rect2(), false]
	var asset: Dictionary = _assets[asset_id]
	var data: Dictionary = asset["clips"][clip]
	var directions: PackedStringArray = data["directions"]
	var flip: bool = false
	var row: int = directions.find(direction)
	if row < 0 and (asset["mirror"] as Dictionary).has(direction):
		row = directions.find(str(asset["mirror"][direction]))
		flip = row >= 0
	row = maxi(row, 0)
	var size: float = float(asset["frame_size"])
	var column: int = posmod(frame, int(data["frames"]))
	return [Rect2(column * size, (data["row"] + row) * size, size, size), flip]


## Draws a clip frame with its feet_anchor on `feet` (px), mirrored about the anchor when the
## direction is a mirrored one; false when the asset or clip is missing.
func draw_clip(
	canvas: CanvasItem, asset_id: String, clip: String, direction: String, frame: int, feet: Vector2, tint: Color
) -> bool:
	var found: Array = clip_region(asset_id, clip, direction, frame)
	var region: Rect2 = found[0]
	if region.size == Vector2.ZERO:
		return false
	var asset: Dictionary = _assets[asset_id]
	var anchor: Vector2 = asset["feet_anchor"]
	if found[1]:
		anchor.x = region.size.x - anchor.x
	var rect: Rect2 = Rect2(feet - anchor / DENSITY, region.size / DENSITY)
	if found[1]:
		# A negative width mirrors the region inside the same rect (the server flips it).
		rect.size.x = -rect.size.x
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


## Draws a prop with the centre of its base on `feet` (screen px), mirrored when `flip`; with
## `clip` only its part between screen x clip.x and clip.y (not mirrored): one strip of a large
## prop sorted by depth strip by strip.
func draw_prop(
	canvas: CanvasItem, asset_id: String, prop: String, feet: Vector2, tint: Color, flip: bool = false,
	clip: Vector2 = Vector2(-INF, INF)
) -> bool:
	if not has_prop(asset_id, prop):
		return false
	if clip.x > -INF or clip.y < INF:
		return _draw_strip(canvas, asset_id, prop, feet, tint, clip.x, clip.y)
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


## The part of a prop between screen x `from` and `to`. The cut falls on a whole texel, so
## neighbouring strips meet without a gap or an overlap, and the texture is sampled across it
## (no clamp).
func _draw_strip(
	canvas: CanvasItem, asset_id: String, prop: String, feet: Vector2, tint: Color, from: float, to: float
) -> bool:
	var asset: Dictionary = _assets[asset_id]
	var region: Rect2 = asset["props"][prop]["region"]
	var density: float = asset["density"]
	var left: float = feet.x - ((asset["props"][prop]["feet"] as Vector2).x - region.position.x) / density
	var a: float = clampf(roundf((from - left) * density), 0.0, region.size.x)
	var b: float = clampf(roundf((to - left) * density), 0.0, region.size.x)
	if b <= a:
		return false
	var top: float = feet.y - ((asset["props"][prop]["feet"] as Vector2).y - region.position.y) / density
	var rect: Rect2 = Rect2(left + a / density, top, (b - a) / density, region.size.y / density)
	var source: Rect2 = Rect2(region.position + asset["origin"] + Vector2(a, 0.0), Vector2(b - a, region.size.y))
	canvas.draw_texture_rect_region(asset["canvas"], rect, source, tint, false, false)
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
## The EIGHT_WAY screen direction nearest to `facing` (screen px; y grows down).
static func eight_way(facing: Vector2) -> String:
	if facing == Vector2.ZERO:
		return "s"
	var sector: int = posmod(roundi(facing.angle() / (PI / 4.0)), 8)
	return EIGHT_WAY[sector]


## The screen diagonal (se, sw, ne, nw) of a facing given as screen signs (x, y; y grows down):
## the four directions of a rank-and-file enemy (ADR-014 section 3).
static func diagonal(signs: Vector2i) -> String:
	return ("n" if signs.y < 0 else "s") + ("w" if signs.x < 0 else "e")


static func four_way(facing: Vector2) -> String:
	if absf(facing.y) > absf(facing.x):
		return "down" if facing.y > 0.0 else "up"
	return "left" if facing.x < 0.0 else "right"


## Walk frame for `seconds` of animation, offset by a per-entity phase so a horde does not
## step in unison.
static func walk_frame(seconds: float, phase: int) -> int:
	return int(floor(seconds * WALK_FPS)) + phase
