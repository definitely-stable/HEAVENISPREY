class_name GroundLayer
extends CanvasLayer
## ADR-014 section 4: the lit ground of the run scene, on its own canvas so the night ambient
## and the lights touch nothing else (telegraphs keep their exact colour, PLAYABILITY G3).
## Under the isometric matrix: the floor in chunks of one texture tile (CanvasTexture with a
## normal map, so each chunk is reached by few lights), the floor continued past the walls and
## faded into the void, the wall band, the lanterns and the hero aura. Presentation only.

const LAYER: int = -2
## Cells of floor drawn past each wall before the fade to the void ends.
const APRON_CELLS: int = 6
const WALL_PX: float = 10.0
## Darkness of the floor just past the wall, before the apron fades on to the void.
const APRON_SHADE: float = 0.45
const COLOR_WALL: Color = Color(0.36, 0.31, 0.26)
const COLOR_WALL_TOP: Color = Color(0.72, 0.64, 0.5)
const COLOR_FLOOR_FLAT: Color = Color(0.2, 0.19, 0.23)

var floor_chunks: int = 0
var lights: Array[Light2D] = []
var _iso: Node2D
var _aura: PointLight2D
var _arena: Vector2
var _cell_px: int


func _init(sprites: SpriteSet, floor_asset: String, arena: Vector2, cell_px: int) -> void:
	layer = LAYER
	follow_viewport_enabled = true
	_arena = arena
	_cell_px = cell_px
	var ambient: CanvasModulate = CanvasModulate.new()
	ambient.color = RunLighting.AMBIENT
	add_child(ambient)
	_iso = Node2D.new()
	_iso.transform = IsoProjection.ground()
	_iso.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_iso.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_iso)
	_build_floor(sprites, floor_asset)
	var edge: Node2D = Node2D.new()
	edge.light_mask = 0
	edge.draw.connect(_draw_edge.bind(edge))
	_iso.add_child(edge)
	var moon: DirectionalLight2D = DirectionalLight2D.new()
	moon.color = RunLighting.MOON_COLOR
	moon.energy = RunLighting.MOON_ENERGY
	moon.height = RunLighting.MOON_HEIGHT
	moon.rotation = RunLighting.moon_rotation()
	_add_light(moon)
	for at: Vector2 in RunLighting.lantern_positions(cell_px):
		_add_point(at, RunLighting.LANTERN_COLOR, RunLighting.LANTERN_ENERGY, RunLighting.LANTERN_RADIUS_PX)
	_aura = _add_point(arena * 0.5, RunLighting.AURA_COLOR, RunLighting.AURA_ENERGY, RunLighting.AURA_RADIUS_PX)


## Moves the hero aura to the hero's ground point (world px).
func follow(hero: Vector2) -> void:
	_aura.position = IsoProjection.to_screen(hero)


## Ground point (world px) the hero aura shines on.
func aura_position() -> Vector2:
	return IsoProjection.to_world(_aura.position)


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


## The apron fade past the walls (to the void colour) and the wall band with its lit top edge.
func _draw_edge(canvas: Node2D) -> void:
	var void_color: Color = RunView.COLOR_VOID
	var shade: Color = Color(void_color, APRON_SHADE)
	var apron: float = APRON_CELLS * _cell_px
	var inner: PackedVector2Array = _rect_points(Vector2.ZERO, _arena)
	var outer: PackedVector2Array = _rect_points(-Vector2.ONE * apron, _arena + Vector2.ONE * apron)
	for side: int in 4:
		var next: int = (side + 1) % 4
		canvas.draw_polygon(
			PackedVector2Array([inner[side], inner[next], outer[next], outer[side]]),
			PackedColorArray([shade, shade, void_color, void_color]))
	var band: PackedVector2Array = _rect_points(-Vector2.ONE * WALL_PX, _arena + Vector2.ONE * WALL_PX)
	for side: int in 4:
		var next: int = (side + 1) % 4
		canvas.draw_colored_polygon(PackedVector2Array([inner[side], inner[next], band[next], band[side]]), COLOR_WALL)
	canvas.draw_polyline(inner + PackedVector2Array([inner[0]]), COLOR_WALL_TOP, 2.0)


static func _rect_points(lo: Vector2, hi: Vector2) -> PackedVector2Array:
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])


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
