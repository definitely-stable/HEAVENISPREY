class_name GroundLayer
extends CanvasLayer
## ADR-014 sections 4 and A3: the lit ground of the run scene, on its own canvas so the dusk
## ambient and the lights touch nothing else (telegraphs keep their exact colour, PLAYABILITY
## G3). The courtyard of the ruined sect floats over mist (REF-033, REF-056): flagstones in
## chunks of one texture tile (CanvasTexture with a normal map), the ritual seal at the
## centre, the stone and cliff faces under the two near edges, the mist behind everything
## (canvas layer MIST_LAYER), the warm lights of the lanterns and braziers and the hero aura.
## Presentation only.

const LAYER: int = -2
const MIST_LAYER: int = -3
## Cells of flagstones past each wall line (the terrace under the balustrades).
const APRON_CELLS: float = 1.5
## Screen px the cliff face drops under the near edges before the mist swallows it.
const CLIFF_PX: float = 230.0
const COLOR_FLOOR_FLAT: Color = Color(0.42, 0.37, 0.44)
const COLOR_CLIFF_FLAT: Color = Color(0.22, 0.18, 0.25)
const MIST_SHADER: Shader = preload("res://presentation/run/shaders/mist.gdshader")
## Seal decal over the centre of the arena.
const SEAL_TINT: Color = Color(0.82, 0.7, 0.52, 0.78)

var floor_chunks: int = 0
var lights: Array[Light2D] = []
var _iso: Node2D
var _aura: PointLight2D
var _mist: ColorRect
var _arena: Vector2
var _cell_px: int


func _init(
	sprites: SpriteSet, floor_asset: String, arena: Vector2, cell_px: int,
	light_points: Array[Dictionary] = [], seal_asset: String = "", cliff_asset: String = ""
) -> void:
	layer = LAYER
	follow_viewport_enabled = true
	_arena = arena
	_cell_px = cell_px
	_build_mist()
	var ambient: CanvasModulate = CanvasModulate.new()
	ambient.color = RunLighting.AMBIENT
	add_child(ambient)
	_build_cliffs(sprites, cliff_asset)
	_iso = Node2D.new()
	_iso.transform = IsoProjection.ground()
	_iso.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_iso.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_iso)
	_build_floor(sprites, floor_asset)
	_build_seal(sprites, seal_asset)
	var moon: DirectionalLight2D = DirectionalLight2D.new()
	moon.color = RunLighting.MOON_COLOR
	moon.energy = RunLighting.MOON_ENERGY
	moon.height = RunLighting.MOON_HEIGHT
	moon.rotation = RunLighting.moon_rotation()
	_add_light(moon)
	for point: Dictionary in light_points:
		_add_point(point["at"], RunLighting.LANTERN_COLOR, RunLighting.LANTERN_ENERGY, RunLighting.LANTERN_RADIUS_PX)
	_aura = _add_point(arena * 0.5, RunLighting.AURA_COLOR, RunLighting.AURA_ENERGY, RunLighting.AURA_RADIUS_PX)


## Moves the hero aura to the hero's ground point (world px) and drifts the mist with the view.
func follow(hero: Vector2) -> void:
	_aura.position = IsoProjection.to_screen(hero)
	(_mist.material as ShaderMaterial).set_shader_parameter("camera_offset", IsoProjection.to_screen(hero))


## Ground point (world px) the hero aura shines on.
func aura_position() -> Vector2:
	return IsoProjection.to_world(_aura.position)


## The mist behind the courtyard: a screen-wide rect on its own canvas layer, not following
## the camera (the shader drifts it with camera_offset instead).
func _build_mist() -> void:
	var back: CanvasLayer = CanvasLayer.new()
	back.layer = MIST_LAYER
	add_child(back)
	_mist = ColorRect.new()
	_mist.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mist_material: ShaderMaterial = ShaderMaterial.new()
	mist_material.shader = MIST_SHADER
	_mist.material = mist_material
	back.add_child(_mist)


func _build_floor(sprites: SpriteSet, floor_asset: String) -> void:
	var texture: Texture2D = sprites.canvas_texture(floor_asset)
	var lo: Vector2 = -Vector2.ONE * APRON_CELLS * _cell_px
	var hi: Vector2 = _arena + Vector2.ONE * APRON_CELLS * _cell_px
	if texture == null:
		var flat: Polygon2D = Polygon2D.new()
		flat.polygon = PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
		flat.color = COLOR_FLOOR_FLAT
		_iso.add_child(flat)
		floor_chunks = 1
		return
	# One chunk per texture tile; the tile repeats every floor_repeat_px world px.
	var tile: float = sprites.floor_repeat_px(floor_asset, _cell_px)
	var scale: float = tile / float(texture.get_width())
	var y: float = lo.y
	while y < hi.y:
		var x: float = lo.x
		while x < hi.x:
			var size: Vector2 = Vector2(minf(tile, hi.x - x), minf(tile, hi.y - y))
			var chunk: Sprite2D = Sprite2D.new()
			chunk.texture = texture
			chunk.centered = false
			chunk.region_enabled = true
			chunk.region_rect = Rect2(Vector2.ZERO, size / scale)
			chunk.scale = Vector2(scale, scale)
			chunk.position = Vector2(x, y)
			_iso.add_child(chunk)
			floor_chunks += 1
			x += tile
		y += tile


## The ritual seal inlaid at the centre of the arena (lit with the floor).
func _build_seal(sprites: SpriteSet, seal_asset: String) -> void:
	var texture: Texture2D = sprites.canvas_texture(seal_asset)
	if texture == null:
		return
	var seal: Sprite2D = Sprite2D.new()
	seal.texture = texture
	seal.position = _arena * 0.5
	seal.scale = Vector2.ONE * sprites.decal_world_px(seal_asset) / float(texture.get_width())
	seal.modulate = SEAL_TINT
	seal.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_iso.add_child(seal)


## Stone and cliff faces under the two near edges (x = arena.x and y = arena.y), dropping
## CLIFF_PX down the screen and fading into the mist.
func _build_cliffs(sprites: SpriteSet, cliff_asset: String) -> void:
	var faces: Node2D = Node2D.new()
	faces.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	faces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	faces.draw.connect(_draw_cliffs.bind(faces, sprites, cliff_asset))
	add_child(faces)


func _draw_cliffs(canvas: Node2D, sprites: SpriteSet, cliff_asset: String) -> void:
	var apron: float = APRON_CELLS * _cell_px
	var corner: Vector2 = IsoProjection.to_screen(_arena + Vector2.ONE * apron)
	var right: Vector2 = IsoProjection.to_screen(Vector2(_arena.x + apron, -apron))
	var left: Vector2 = IsoProjection.to_screen(Vector2(-apron, _arena.y + apron))
	var texture: Texture2D = sprites.canvas_texture(cliff_asset)
	var span: float = sprites.decal_world_px(cliff_asset) if texture != null else 1.0
	for edge: Array in [[left, corner], [corner, right]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var drop: Vector2 = Vector2(0.0, CLIFF_PX)
		var points: PackedVector2Array = PackedVector2Array([a, b, b + drop, a + drop])
		var fade: Color = Color(1.0, 1.0, 1.0, 0.0)
		var colors: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, fade, fade])
		if texture == null:
			for index: int in 4:
				colors[index] = Color(COLOR_CLIFF_FLAT, colors[index].a)
			canvas.draw_polygon(points, colors)
			continue
		var u: float = a.distance_to(b) / span
		var uvs: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(u, 0), Vector2(u, 1), Vector2(0, 1)])
		canvas.draw_polygon(points, colors, uvs, texture)


func _add_point(at: Vector2, color: Color, energy: float, radius: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.texture = _radial_texture(256)
	light.texture_scale = radius * 2.0 / 256.0
	light.color = color
	light.energy = energy
	light.height = RunLighting.LIGHT_HEIGHT_PX
	# Lights live in screen space: a world circle of `radius` is a 2:1 ellipse on screen.
	light.position = IsoProjection.to_screen(at)
	light.scale = Vector2(1.0, 0.5)
	_add_light(light)
	return light


## A light reaches only items of the canvas layers in its layer range (0..0 by default).
func _add_light(light: Light2D) -> void:
	light.range_layer_min = LAYER
	light.range_layer_max = LAYER
	add_child(light)
	lights.append(light)


static func _radial_texture(size: int) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture
