class_name SpriteSet
extends RefCounted
## Game sprites by stable asset_id (ADR-009 section 5, ADR-013): reads
## res://assets/manifest.json, loads each atlas or floor texture and answers frame regions.
## An atlas holds one row per direction and `frames` columns of `frame_size` px, drawn at
## half size (double density for the 1280x720 window); the simulation position is the
## frame's feet_anchor. A missing or broken asset is skipped with an error, so the scene
## falls back to its primitives. Presentation only: nothing here reaches the simulation.

const MANIFEST_PATH: String = "res://assets/manifest.json"
## Atlas pixels per screen pixel.
const DENSITY: float = 2.0
## Walk-cycle frames per second.
const WALK_FPS: float = 8.0

## asset_id -> {texture, kind, directions, frames, frame_size, feet_anchor, cells, texture_px}
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
	return sprites


func _add(entry: Dictionary) -> void:
	var asset_id: String = str(entry.get("asset_id", ""))
	var res_path: String = "res://" + str(entry.get("path", "")).trim_prefix("game/")
	var texture: Texture2D = load(res_path) as Texture2D if ResourceLoader.exists(res_path) else null
	if texture == null:
		push_error("SpriteSet: cannot load " + asset_id + " from " + res_path)
		return
	var layout: Dictionary = entry.get("layout", {})
	var anchor: Array = layout.get("feet_anchor", [0, 0])
	_assets[asset_id] = {
		"texture": texture,
		"kind": str(entry.get("kind", "")),
		"directions": PackedStringArray(layout.get("directions", [])),
		"frames": int(layout.get("frames", 1)),
		"frame_size": int(layout.get("frame_size", 0)),
		"feet_anchor": Vector2(float(anchor[0]), float(anchor[1])),
		"cells": int(layout.get("cells", 1)),
	}


func has(asset_id: String) -> bool:
	return _assets.has(asset_id)


func texture(asset_id: String) -> Texture2D:
	return _assets[asset_id]["texture"] if _assets.has(asset_id) else null


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
	var anchor: Vector2 = _assets[asset_id]["feet_anchor"]
	var rect: Rect2 = Rect2(feet - anchor / DENSITY, region.size / DENSITY)
	canvas.draw_texture_rect_region(_assets[asset_id]["texture"], rect, region, tint)
	return true


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
