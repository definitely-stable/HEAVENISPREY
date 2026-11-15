class_name GroundLayer
extends CanvasLayer
## ADR-014 sections 4, A3 and A3 polish: the lit ground of the run scene, on its own canvas so
## the dusk ambient and the lights touch nothing else (telegraphs keep their exact colour,
## PLAYABILITY G3). The courtyard of the ruined sect floats over mist (REF-033, REF-056):
## - canvas layer MIST_LAYER, behind everything: the dusk sky, the distant rock spires and
##   pagodas with a slow parallax, the drifting mist veil over them;
## - the terrace: a platform with its far and near corners cut (outline()), wider on the far
##   sides where the gate, the lanterns and the maples stand; clean flagstones blended with a
##   worn, mossy, leaf-strewn variant by a baked wear mask (floor.gdshader), so the paving does
##   not repeat;
## - the ritual seal with its gold inlay lines to the four sides and a faint glow;
## - stone and cliff faces under the three near edges with waterfalls pouring into the mist;
## - the warm lights of the lanterns and braziers and the hero aura.
## Presentation only.

const LAYER: int = -2
const MIST_LAYER: int = -3
## Cells of flagstones past the far wall lines (x = 0 and y = 0): the terrace of the gate.
const FAR_APRON_CELLS: float = 3.5
## Cells of flagstones past the near wall lines (the walk along the balustrades).
const NEAR_APRON_CELLS: float = 2.4
## Corner cuts of the platform (cells along each edge) at its far and near corners; the left
## and right tips stay sharp (a cut there would be a face seen edge-on).
const CHAMFER_FAR_CELLS: float = 3.0
const CHAMFER_NEAR_CELLS: float = 2.6
## Screen px the cliff face drops under the near edges before the mist swallows it.
const CLIFF_PX: float = 240.0
const COLOR_FLOOR_FLAT: Color = Color(0.42, 0.37, 0.44)
const COLOR_CLIFF_FLAT: Color = Color(0.22, 0.18, 0.25)
const MIST_SHADER: Shader = preload("res://presentation/run/shaders/mist.gdshader")
const FLOOR_SHADER: Shader = preload("res://presentation/run/shaders/floor.gdshader")
const WATERFALL_SHADER: Shader = preload("res://presentation/run/shaders/waterfall.gdshader")
## Seal decal over the centre of the arena, and its additive glow.
const SEAL_TINT: Color = Color(0.84, 0.7, 0.5, 0.74)
const SEAL_GLOW: Color = Color(1.0, 0.7, 0.36, 0.13)
## Gold inlay lines from the seal to the four sides (REF-033): a pair of thin lines per side.
const INLAY_COLOR: Color = Color(0.77, 0.6, 0.28, 0.62)
const INLAY_WIDTH_PX: float = 3.0
const INLAY_GAP_PX: float = 11.0
## The lines start at this share of the seal radius and stop this many cells before the wall.
const INLAY_SEAL_SHARE: float = 0.96
const INLAY_WALL_INSET_CELLS: float = 0.6
## Wear mask: texels per cell, the seed of its noise, the size of a worn patch (cells) and how
## far from the walls the paving is more worn.
const MASK_TEXELS_PER_CELL: int = 4
const MASK_SEED: int = 3301
const WEAR_PATCH_CELLS: float = 7.0
const WEAR_EDGE_CELLS: float = 3.0
const WEAR_EDGE_BOOST: float = 0.24
## Mean wear before the noise: lower leaves fewer worn patches in the open field.
const WEAR_BASE: float = 0.4
## Size (cells) of the patches that swap the clean paving for its second layer (the same
## texture turned half a circle, repeating every ALT_REPEAT_CELLS instead of its own period).
const ALT_PATCH_CELLS: float = 4.0
const ALT_REPEAT_CELLS: float = 9.0
## Waterfalls on the near cliff faces: [face (0 left, 1 front, 2 right), share along the
## face, width (screen px)].
const WATERFALLS: Array = [[0, 0.22, 60.0], [2, 0.36, 72.0], [2, 0.84, 48.0]]
## Screen px a waterfall starts under the edge (below the capping course) and how far it falls.
const WATERFALL_TOP_PX: float = 24.0
const WATERFALL_DROP_PX: float = 330.0
## Share of the camera travel the distant scenery follows (1 = glued to the courtyard).
const BACKDROP_PARALLAX: float = 0.5
## Distant spires fade into the mist over this share of their height from the base, and are
## tinted by the haze: far ones more than near ones.
const BACKDROP_FADE: float = 0.45
const BACKDROP_HAZE_FAR: Color = Color(0.5, 0.47, 0.68, 0.82)
const BACKDROP_HAZE_NEAR: Color = Color(0.7, 0.64, 0.82, 0.95)

var lights: Array[Light2D] = []
var waterfalls: Array[ColorRect] = []
## The paving polygon, and the gold inlay as closed or open polylines (world px).
var paving: Polygon2D
var inlay: Array[PackedVector2Array] = []
var _iso: Node2D
var _aura: PointLight2D
var _sky: ColorRect
var _veil: ColorRect
var _backdrop: Node2D
var _backdrop_items: Array[Dictionary] = []
var _sprites: SpriteSet
var _arena: Vector2
var _cell_px: int


func _init(
	sprites: SpriteSet, floor_asset: String, arena: Vector2, cell_px: int,
	light_points: Array[Dictionary] = [], seal_asset: String = "", cliff_asset: String = "",
	worn_asset: String = "", backdrop: Array[Dictionary] = []
) -> void:
	layer = LAYER
	follow_viewport_enabled = true
	_sprites = sprites
	_arena = arena
	_cell_px = cell_px
	_backdrop_items = backdrop
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
	_build_floor(sprites, floor_asset, worn_asset, sprites.decal_world_px(seal_asset) * 0.5)
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


## The platform under the arena (world px), clockwise from the far corner: the walkable field
## plus the far and near aprons, with its far and near corners cut (REF-033: the terrace of the
## arena is cut at the corners, not a plain rectangle). Points: far cut, right tip, near cut
## (two points), left tip, far cut.
static func outline(arena: Vector2, cell_px: int) -> PackedVector2Array:
	var lo: Vector2 = -Vector2.ONE * FAR_APRON_CELLS * cell_px
	var hi: Vector2 = arena + Vector2.ONE * NEAR_APRON_CELLS * cell_px
	var far: float = CHAMFER_FAR_CELLS * cell_px
	var near: float = CHAMFER_NEAR_CELLS * cell_px
	return PackedVector2Array([
		Vector2(lo.x + far, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y - near),
		Vector2(hi.x - near, hi.y), Vector2(lo.x, hi.y), Vector2(lo.x, lo.y + far),
	])


## The three near edges of the platform that show a cliff face, left to right on screen:
## pairs of world points (the left near edge, the front cut, the right near edge).
static func near_edges(arena: Vector2, cell_px: int) -> Array[PackedVector2Array]:
	var points: PackedVector2Array = outline(arena, cell_px)
	return [
		PackedVector2Array([points[4], points[3]]), PackedVector2Array([points[3], points[2]]),
		PackedVector2Array([points[2], points[1]]),
	]


## The wear of the paving, one texel per 1 / MASK_TEXELS_PER_CELL of a cell over the bounding
## box of the platform: red = how worn (cracked, mossy, leaf-strewn) the flagstones are, green
## = a slow tone drift around 0.5, blue = which layer of the clean paving shows. Patches of
## fixed-seed noise, more wear near the walls and on the terrace, none inside `clear_radius` of
## the arena centre (the seal stays clean).
static func wear_mask(arena: Vector2, cell_px: int, clear_radius: float) -> Image:
	var lo: Vector2 = -Vector2.ONE * FAR_APRON_CELLS * cell_px
	var hi: Vector2 = arena + Vector2.ONE * NEAR_APRON_CELLS * cell_px
	var texel: float = float(cell_px) / MASK_TEXELS_PER_CELL
	var size: Vector2i = Vector2i(((hi - lo) / texel).ceil())
	var patches: FastNoiseLite = FastNoiseLite.new()
	patches.seed = MASK_SEED
	patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patches.fractal_octaves = 3
	patches.frequency = 1.0 / (WEAR_PATCH_CELLS * cell_px)
	var tone: FastNoiseLite = FastNoiseLite.new()
	tone.seed = MASK_SEED + 1
	tone.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tone.fractal_octaves = 2
	tone.frequency = 0.5 / (WEAR_PATCH_CELLS * cell_px)
	var layers: FastNoiseLite = FastNoiseLite.new()
	layers.seed = MASK_SEED + 2
	layers.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	layers.fractal_octaves = 2
	layers.frequency = 1.0 / (ALT_PATCH_CELLS * cell_px)
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
	var centre: Vector2 = arena * 0.5
	var edge_px: float = WEAR_EDGE_CELLS * cell_px
	for y: int in size.y:
		for x: int in size.x:
			var at: Vector2 = lo + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			# Distance to the nearest wall line from inside the field; 0 on the terrace.
			var inside: float = maxf(minf(minf(at.x, at.y), minf(arena.x - at.x, arena.y - at.y)), 0.0)
			var wear: float = WEAR_BASE + patches.get_noise_2d(at.x, at.y) * 0.95
			wear += WEAR_EDGE_BOOST * clampf(1.0 - inside / edge_px, 0.0, 1.0)
			wear *= smoothstep(clear_radius, clear_radius + edge_px, at.distance_to(centre))
			var drift: float = 0.5 + tone.get_noise_2d(at.x, at.y) * 0.9
			var layer: float = 0.5 + layers.get_noise_2d(at.x, at.y) * 1.2
			image.set_pixel(x, y, Color(clampf(wear, 0.0, 1.0), clampf(drift, 0.0, 1.0), clampf(layer, 0.0, 1.0)))
	return image


## Moves the hero aura to the hero's ground point (world px), drifts the mist and slides the
## distant scenery with the view. `view_centre` is the screen point (projected px) the camera
## aims at, `zoom` its zoom; by default the view is centred on the hero at zoom 1.
func follow(hero: Vector2, view_centre: Vector2 = Vector2.INF, zoom: float = 1.0) -> void:
	var centre: Vector2 = IsoProjection.to_screen(hero) if view_centre == Vector2.INF else view_centre
	_aura.position = IsoProjection.to_screen(hero)
	for rect: ColorRect in [_sky, _veil]:
		(rect.material as ShaderMaterial).set_shader_parameter("camera_offset", centre)
	var size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	_backdrop.transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), backdrop_origin(centre, zoom, size))


## Screen point of the backdrop's origin (the arena centre of the distant scenery) for a view
## centred on `view_centre` (projected px) at `zoom` in a window of `size` px.
func backdrop_origin(view_centre: Vector2, zoom: float, size: Vector2) -> Vector2:
	var travel: Vector2 = view_centre - IsoProjection.to_screen(_arena * 0.5)
	return size * 0.5 - travel * BACKDROP_PARALLAX * zoom


## Ground point (world px) the hero aura shines on.
func aura_position() -> Vector2:
	return IsoProjection.to_world(_aura.position)


## Behind the courtyard, on a canvas layer that does not follow the camera: the dusk sky, the
## distant spires and pagodas (REF-033, REF-056) and the mist veil drifting in front of them.
## The shaders slide with camera_offset; the scenery node is moved by follow().
func _build_mist() -> void:
	var back: CanvasLayer = CanvasLayer.new()
	back.layer = MIST_LAYER
	add_child(back)
	_sky = _mist_rect(false)
	back.add_child(_sky)
	_backdrop = Node2D.new()
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_backdrop.draw.connect(_draw_backdrop)
	back.add_child(_backdrop)
	_veil = _mist_rect(true)
	back.add_child(_veil)


func _mist_rect(veil: bool) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mist_material: ShaderMaterial = ShaderMaterial.new()
	mist_material.shader = MIST_SHADER
	mist_material.set_shader_parameter("veil", veil)
	rect.material = mist_material
	return rect


## Each distant prop is a quad whose lower part fades out (the mist swallows its base).
func _draw_backdrop() -> void:
	for item: Dictionary in _backdrop_items:
		var quad: Dictionary = _sprites.prop_quad(item["asset"], item["prop"], item["at"], item["scale"], item["flip"])
		if quad.is_empty():
			continue
		var rect: Rect2 = quad["rect"]
		var uv: Rect2 = quad["uv"]
		var haze: Color = BACKDROP_HAZE_FAR.lerp(BACKDROP_HAZE_NEAR, clampf(item["near"], 0.0, 1.0))
		var gone: Color = Color(haze, 0.0)
		var keep: float = 1.0 - BACKDROP_FADE
		var mid: float = rect.position.y + rect.size.y * keep
		var uv_mid: float = uv.position.y + uv.size.y * keep
		var points: PackedVector2Array = PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, mid), rect.end,
			Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, mid),
		])
		var uvs: PackedVector2Array = PackedVector2Array([
			uv.position, Vector2(uv.end.x, uv.position.y), Vector2(uv.end.x, uv_mid), uv.end,
			Vector2(uv.position.x, uv.end.y), Vector2(uv.position.x, uv_mid),
		])
		_backdrop.draw_polygon(points, PackedColorArray([haze, haze, haze, gone, gone, haze]), uvs, quad["texture"])


## The paving: one polygon over the platform. With both floor textures the floor shader blends
## the clean flagstones with the worn ones by the wear mask.
func _build_floor(sprites: SpriteSet, floor_asset: String, worn_asset: String, clear_radius: float) -> void:
	var texture: Texture2D = sprites.canvas_texture(floor_asset)
	paving = Polygon2D.new()
	paving.polygon = outline(_arena, _cell_px)
	_iso.add_child(paving)
	if texture == null:
		paving.color = COLOR_FLOOR_FLAT
		return
	paving.texture = texture
	# Polygon UVs are in texels; the tile repeats every floor_repeat_px world px.
	var scale: float = sprites.floor_repeat_px(floor_asset, _cell_px) / float(texture.get_width())
	var uvs: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in paving.polygon:
		uvs.append(point / scale)
	paving.uv = uvs
	var worn: CanvasTexture = sprites.canvas_texture(worn_asset) as CanvasTexture
	if worn == null:
		return
	var lo: Vector2 = -Vector2.ONE * FAR_APRON_CELLS * _cell_px
	var hi: Vector2 = _arena + Vector2.ONE * NEAR_APRON_CELLS * _cell_px
	var wear: ShaderMaterial = ShaderMaterial.new()
	wear.shader = FLOOR_SHADER
	wear.set_shader_parameter("worn_albedo", worn.diffuse_texture)
	wear.set_shader_parameter("worn_normal", worn.normal_texture)
	wear.set_shader_parameter("wear_mask", ImageTexture.create_from_image(wear_mask(_arena, _cell_px, clear_radius)))
	wear.set_shader_parameter("mask_origin", lo)
	wear.set_shader_parameter("mask_size", hi - lo)
	wear.set_shader_parameter("worn_repeat_px", sprites.floor_repeat_px(worn_asset, _cell_px))
	wear.set_shader_parameter("alt_scale", sprites.floor_repeat_px(floor_asset, _cell_px) / (ALT_REPEAT_CELLS * _cell_px))
	paving.material = wear


## The ritual seal inlaid at the centre of the arena (lit with the floor), its gold lines to
## the four sides and a faint additive glow.
func _build_seal(sprites: SpriteSet, seal_asset: String) -> void:
	var texture: Texture2D = sprites.canvas_texture(seal_asset)
	if texture == null:
		return
	var world_px: float = sprites.decal_world_px(seal_asset)
	_build_inlay(world_px * 0.5)
	var seal: Sprite2D = Sprite2D.new()
	seal.texture = texture
	seal.position = _arena * 0.5
	seal.scale = Vector2.ONE * world_px / float(texture.get_width())
	seal.modulate = SEAL_TINT
	seal.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_iso.add_child(seal)
	var glow: Sprite2D = Sprite2D.new()
	glow.name = "SealGlow"
	glow.texture = sprites.texture(seal_asset)
	glow.position = seal.position
	glow.scale = seal.scale
	glow.modulate = SEAL_GLOW
	glow.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = additive
	_iso.add_child(glow)


## A pair of thin gold lines from the rim of the seal towards each wall, ending in a small
## square knot (REF-033, REF-029: the inlay runs from the seal across the paving). One item
## draws them all, lit with the floor.
func _build_inlay(seal_radius: float) -> void:
	var centre: Vector2 = _arena * 0.5
	var inset: float = INLAY_WALL_INSET_CELLS * _cell_px
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var reach: float = (absf(axis.x) * _arena.x + absf(axis.y) * _arena.y) * 0.5 - inset
		var from: Vector2 = centre + axis * seal_radius * INLAY_SEAL_SHARE
		var knot: float = INLAY_GAP_PX * 2.4
		var to: Vector2 = centre + axis * (reach - knot)
		var across: Vector2 = axis.orthogonal() * INLAY_GAP_PX * 0.5
		for side: float in [-1.0, 1.0]:
			inlay.append(PackedVector2Array([from + across * side, to + across * side]))
		var end: Vector2 = centre + axis * reach
		var half: Vector2 = axis.orthogonal() * knot * 0.5
		inlay.append(PackedVector2Array([to - half, to + half, end + half, end - half, to - half]))
	var lines: Node2D = Node2D.new()
	lines.draw.connect(func() -> void:
		for line: PackedVector2Array in inlay:
			lines.draw_polyline(line, INLAY_COLOR, INLAY_WIDTH_PX))
	_iso.add_child(lines)


## Stone and cliff faces under the three near edges, dropping CLIFF_PX down the screen and
## fading into the mist, and the waterfalls that pour down them (REF-033, REF-029).
func _build_cliffs(sprites: SpriteSet, cliff_asset: String) -> void:
	var faces: Node2D = Node2D.new()
	faces.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	faces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	faces.draw.connect(_draw_cliffs.bind(faces, sprites, cliff_asset))
	add_child(faces)
	var edges: Array[PackedVector2Array] = near_edges(_arena, _cell_px)
	var water: ShaderMaterial = ShaderMaterial.new()
	water.shader = WATERFALL_SHADER
	for fall: Array in WATERFALLS:
		var edge: PackedVector2Array = edges[fall[0]]
		var top: Vector2 = IsoProjection.to_screen(edge[0]).lerp(IsoProjection.to_screen(edge[1]), fall[1])
		var width: float = fall[2]
		var rect: ColorRect = ColorRect.new()
		rect.material = water
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.position = top + Vector2(-width * 0.5, WATERFALL_TOP_PX)
		rect.size = Vector2(width, WATERFALL_DROP_PX)
		add_child(rect)
		waterfalls.append(rect)


func _draw_cliffs(canvas: Node2D, sprites: SpriteSet, cliff_asset: String) -> void:
	var texture: Texture2D = sprites.canvas_texture(cliff_asset)
	var span: float = sprites.decal_world_px(cliff_asset) if texture != null else 1.0
	var drop: Vector2 = Vector2(0.0, CLIFF_PX)
	var fade: Color = Color(1.0, 1.0, 1.0, 0.0)
	var along: float = 0.0
	for edge: PackedVector2Array in near_edges(_arena, _cell_px):
		var a: Vector2 = IsoProjection.to_screen(edge[0])
		var b: Vector2 = IsoProjection.to_screen(edge[1])
		var points: PackedVector2Array = PackedVector2Array([a, b, b + drop, a + drop])
		var colors: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, fade, fade])
		if texture == null:
			for index: int in 4:
				colors[index] = Color(COLOR_CLIFF_FLAT, colors[index].a)
			canvas.draw_polygon(points, colors)
			continue
		# The strip runs on from face to face, so the masonry does not restart at a corner.
		var u: float = along + a.distance_to(b) / span
		var uvs: PackedVector2Array = PackedVector2Array([Vector2(along, 0), Vector2(u, 0), Vector2(u, 1), Vector2(along, 1)])
		canvas.draw_polygon(points, colors, uvs, texture)
		along = u


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
