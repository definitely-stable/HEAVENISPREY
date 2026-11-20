class_name RunThreatSilhouettes
extends Node2D
## Brief silhouettes keep a windup visible through tall foreground architecture.

const OUTLINE: Shader = preload("res://presentation/run/shaders/threat_silhouette.gdshader")
const COVER_ASSETS: Array[String] = [
	ArenaDressing.GATE_ASSET, ArenaDressing.GUARDIANS_ASSET, ArenaDressing.NATURE_ASSET,
]
const BODY_SAMPLES: Array[Vector2] = [
	Vector2(0.0, -0.55), Vector2(0.0, -1.45), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
]

var _view: RunView
var _cover: Array[Dictionary] = []


func _init(view: RunView) -> void:
	name = "ThreatSilhouettes"
	_view = view
	var outline: ShaderMaterial = ShaderMaterial.new()
	outline.shader = OUTLINE
	material = outline
	view.draw.connect(queue_redraw)
	var masks: Dictionary[String, BitMap] = {}
	for prop: Dictionary in view._props:
		var asset: String = prop["asset"]
		if not prop.has("draw_bounds") or (asset not in COVER_ASSETS and prop["prop"] != "pillar_stump"):
			continue
		if not masks.has(asset):
			var source: Image = view._sprites.texture(asset).get_image()
			if source == null or (source.is_compressed() and source.decompress() != OK):
				continue
			var mask: BitMap = BitMap.new()
			mask.create_from_image_alpha(source, 0.65)
			masks[asset] = mask
		var quad: Dictionary = view._sprites.prop_quad(asset, prop["prop"], prop["screen"], 1.0, prop["flip"])
		var uv: Rect2 = quad["uv"]
		var full: Vector2 = quad["texture"].get_size()
		var region: Rect2 = Rect2((uv.position * full - view._sprites.atlas_origin(asset)).round(),
			(uv.size * full).round())
		_cover.append({"bounds": quad["rect"], "order": prop["order"].x, "mask": masks[asset], "region": region})


## The same depth tie as the arena painter: a prop sorts before an enemy at equal depth.
static func covers(cover: Dictionary, core: Vector2, depth: int) -> bool:
	var bounds: Rect2 = cover["bounds"]
	if depth >= int(cover["order"]) or not bounds.has_point(core):
		return false
	var region: Rect2 = cover["region"]
	var texel: Vector2 = region.position + (core - bounds.position) / bounds.size * region.size
	var interior: Rect2 = region.abs().grow(-0.5)
	var mask: BitMap = cover["mask"]
	return mask.get_bitv(Vector2i(texel.clamp(interior.position, interior.end).floor()))


static func covers_body(cover: Dictionary, feet: Vector2, radius: float, depth: int) -> bool:
	var covered: int = 0
	for sample: Vector2 in BODY_SAMPLES:
		covered += int(covers(cover, feet + sample * radius, depth))
	return covered >= 2


func _draw() -> void:
	if _view.driver == null:
		return
	var world: WorldState = _view.driver.world
	var config: SimConfig = _view.driver.config
	var window: Rect2 = ArenaDressing.rail_draw_window(_view, _view._camera.get_screen_center_position())
	for slot: int in world.enemy_slots():
		if world.enemy_uid[slot] == 0 or world.enemy_state[slot] != EnemyAttackSystem.ST_TELL:
			continue
		var feet: Vector2 = _view.surface_at(_view._enemy_feet(slot))
		if not window.has_point(feet):
			continue
		var pose: Array = _view._frame_pose(slot)
		var kind: int = world.enemy_kind[slot]
		feet.y -= EnemyMotion.lift(pose[0], world.enemy_uid[slot], _view._anim_time)
		var radius: float = _view._kind_radius_px(kind)
		var depth: int = roundi(IsoProjection.depth(_view.driver.enemy_position_px(slot)) * 16.0)
		if not _cover.any(func(prop: Dictionary) -> bool: return covers_body(prop, feet, radius, depth)):
			continue
		var tint: Color = AttackTelegraph.COLOR_TELL_EDGE
		match config.attack_value(kind, SimConfig.ATTACK_FORM):
			SimConfig.FORM_CHARGE:
				tint = AttackTelegraph.COLOR_CHARGE_EDGE
			SimConfig.FORM_PROJECTILE:
				tint = AttackTelegraph.COLOR_SHOT_EDGE
		_view._draw_pose(self, pose, feet, tint)
