class_name GroundLayer
extends CanvasLayer
## ADR-014 sections 4, A3 and A3 polish, ADR-015 A1: the lit ground of the run scene, on its
## own canvas so the dusk ambient and the lights touch nothing else (telegraphs keep their exact
## colour, PLAYABILITY G3). The courtyard of arena 07 floats over mist (REF-033, REF-056):
## - canvas layer MIST_LAYER, behind everything: the dusk sky, the distant rock spires and
##   pagodas with a slow parallax, the drifting mist veil over them;
## - the paving over every cell of the arena that is not void (footprint()): clean flagstones
##   blended with a worn, mossy, leaf-strewn variant by a baked wear mask (floor.gdshader), so
##   the paving does not repeat;
## - the ritual seal at the arena centre with its gold inlay lines to the four sides and a
##   faint glow;
## - stone and cliff faces under every near edge that drops into the void (near_faces()), with
##   waterfalls on three of them;
## - the warm lights of the braziers and the gate and the hero aura.
## Presentation only.

const LAYER: int = -2
const MIST_LAYER: int = -3
## Arena cells that carry paving: everything but the void.
const VOID_CHAR: String = " "
## Arena cells of open floor (the inlay runs over them).
const FLOOR_CHARS: String = ".S"
## Screen px the cliff face drops under the near edges before the mist swallows it.
const CLIFF_PX: float = 288.0
const CLIFF_DEPTHS: Array[float] = [0.0, 0.08, 0.15, 0.38, 0.67, 1.0]
const CLIFF_VISIBILITY: Array[float] = [1.0, 1.0, 1.0, 0.97, 0.71, 0.0]
const BRIDGE_SPANS: int = 2
const BRIDGE_INTRADOS_PX: float = 58.0
const BRIDGE_EDGE_STEPS: int = 4
const BRIDGE_ARCH_WIDTH: float = 0.72
const ARCH_STONES: int = 15
const COLOR_FLOOR_FLAT: Color = Color(0.42, 0.37, 0.44)
const COLOR_CLIFF_FLAT: Color = Color(0.22, 0.18, 0.25)
const MIST_SHADER: Shader = preload("res://presentation/run/shaders/mist.gdshader")
const FLOOR_SHADER: Shader = preload("res://presentation/run/shaders/floor.gdshader")
const WATERFALL_SHADER: Shader = preload("res://presentation/run/shaders/waterfall.gdshader")
## Seal decal over the centre of the arena, and its additive glow: an engraving in the
## paving, as on REF-023, not a gold plate that outshines the fight (ADR-014 section 20).
const SEAL_TINT: Color = Color(0.8, 0.66, 0.48, 0.46)
const SEAL_GLOW: Color = Color(1.0, 0.7, 0.36, 0.06)
## Gold inlay lines from the seal to the four sides (REF-033): a pair of thin lines per side.
const INLAY_COLOR: Color = Color(0.77, 0.6, 0.28, 0.4)
const INLAY_WIDTH_PX: float = 3.0
const INLAY_GAP_PX: float = 11.0
## The lines start at this share of the seal radius and stop this many cells before a wall.
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
## Damp patches of the paving (ADR-014 section 26): their size (cells), and the level of the
## noise above which the stone is damp; past it the dampness grows over DAMP_RAMP.
const DAMP_PATCH_CELLS: float = 5.0
const DAMP_LEVEL: float = 0.05
const DAMP_RAMP: float = 0.35
## Waterfalls on the near cliff faces: [share across the arena on screen (left to right),
## width (screen px)]; each pours from the lowest face near that share.
const WATERFALLS: Array = [[0.2, 60.0], [0.62, 72.0], [0.86, 48.0]]
## Screen px a waterfall starts under the edge (below the capping course) and how far it falls.
const WATERFALL_TOP_PX: float = 24.0
const WATERFALL_DROP_PX: float = 330.0
## Share of the camera travel the distant scenery follows (1 = glued to the courtyard).
const BACKDROP_PARALLAX: float = 0.5
const FAR_PARALLAX: float = 0.24
const NEAR_PLANE: float = 0.55
## Distant spires fade into the mist over this share of their height from the base, and are
## tinted by the haze: far ones more than near ones.
const BACKDROP_FADE: float = 0.62
const BACKDROP_HAZE_FAR: Color = Color(0.54, 0.61, 0.76, 0.57)
const BACKDROP_HAZE_NEAR: Color = Color(0.73, 0.77, 0.91, 0.93)

var lights: Array[Light2D] = []
var waterfalls: Array[ColorRect] = []
## The paving polygon, and the gold inlay as closed or open polylines (world px).
var paving: Polygon2D
var inlay: Array[PackedVector2Array] = []
var _iso: Node2D
var _aura: PointLight2D
## The lights of the lanterns and braziers, in the order of the light points.
var _fires: Array[PointLight2D] = []
var _sky: ColorRect
var _veil: ColorRect
var _backdrop: Node2D
## The arena file (P0Tuning.arena_data()), its size (world px) and the seal centre (world px).
var _data: Dictionary
var _arena: Vector2
var _centre: Vector2
var _cell_px: int


func _init(
	sprites: SpriteSet, floor_asset: String, data: Dictionary, cell_px: int,
	light_points: Array[Dictionary] = [], seal_asset: String = "", cliff_asset: String = "",
	worn_asset: String = "", backdrop: Array[Dictionary] = []
) -> void:
	layer = LAYER
	follow_viewport_enabled = true
	_data = data
	_arena = Vector2(cells_of(data) * cell_px)
	_centre = centre_of(data, cell_px)
	_cell_px = cell_px
	_build_mist(sprites, backdrop)
	var ambient: CanvasModulate = CanvasModulate.new()
	ambient.color = RunLighting.GROUND_AMBIENT
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
		_fires.append(_add_point(point["at"], RunLighting.LANTERN_COLOR, RunLighting.LANTERN_ENERGY,
			RunLighting.LANTERN_RADIUS_PX))
	_aura = _add_point(_centre, RunLighting.AURA_COLOR, RunLighting.AURA_ENERGY, RunLighting.AURA_RADIUS_PX)


## Arena size in cells.
static func cells_of(data: Dictionary) -> Vector2i:
	var cells: Array = data.get("cells", [0, 0])
	return Vector2i(int(cells[0]), int(cells[1]))


## The seal at the centre of the arena (world px): the centre of its centre cell.
static func centre_of(data: Dictionary, cell_px: int) -> Vector2:
	var centre: Array = data.get("centre", [0, 0])
	return (Vector2(float(centre[0]), float(centre[1])) + Vector2(0.5, 0.5)) * cell_px


## The paving under the arena (world px): one rectangle per run of cells that are not void
## in each row, top to bottom, left to right.
static func footprint(data: Dictionary, cell_px: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var rows: Array = data.get("rows", [])
	for y: int in rows.size():
		var row: String = rows[y]
		var x: int = 0
		while x < row.length():
			if row[x] == VOID_CHAR:
				x += 1
				continue
			var start: int = x
			while x < row.length() and row[x] != VOID_CHAR:
				x += 1
			out.append(Rect2(Vector2(start, y) * cell_px, Vector2(x - start, 1) * cell_px))
	return out


## The near edges that drop into the void, as pairs of world points: the +x side (lower right
## on screen) and the +y side (lower left) of every paved cell whose neighbour there is void.
static func near_faces(data: Dictionary, cell_px: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var rows: Array = data.get("rows", [])
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == VOID_CHAR:
				continue
			if x + 1 >= row.length() or row[x + 1] == VOID_CHAR:
				out.append(PackedVector2Array([Vector2(x + 1, y) * cell_px, Vector2(x + 1, y + 1) * cell_px]))
			var below: String = rows[y + 1] if y + 1 < rows.size() else ""
			if x >= below.length() or below[x] == VOID_CHAR:
				out.append(PackedVector2Array([Vector2(x, y + 1) * cell_px, Vector2(x + 1, y + 1) * cell_px]))
	return out


## Distance (cells, four neighbours) of every cell from the nearest cell that is not open
## floor or a raised floor, stairs or bridge: 0 on walls and the void.
static func wall_distance(data: Dictionary) -> PackedInt32Array:
	var rows: Array = data.get("rows", [])
	var size: Vector2i = cells_of(data)
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(size.x * size.y)
	dist.fill(-1)
	var queue: Array[int] = []
	for y: int in size.y:
		var row: String = rows[y]
		for x: int in size.x:
			if not ArenaTopology.WALK_CHARS.contains(row[x]):
				dist[y * size.x + x] = 0
				queue.append(y * size.x + x)
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		var x: int = at % size.x
		var y: int = at / size.x
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = Vector2i(x, y) + step
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y or dist[n.y * size.x + n.x] >= 0:
				continue
			dist[n.y * size.x + n.x] = dist[at] + 1
			queue.append(n.y * size.x + n.x)
	return dist


## The wear of the paving, one texel per 1 / MASK_TEXELS_PER_CELL of a cell over the arena:
## red = how worn (cracked, mossy, leaf-strewn) the flagstones are, green = a slow tone drift
## around 0.5, blue = which layer of the clean paving shows, alpha = how damp the stone is
## (darker, flatter and glossier: section 26). Patches of fixed-seed noise, more wear near walls
## and the void, none inside `clear_radius` of the seal (it stays clean).
static func wear_mask(data: Dictionary, cell_px: int, clear_radius: float) -> Image:
	var cells: Vector2i = cells_of(data)
	var size: Vector2i = cells * MASK_TEXELS_PER_CELL
	var texel: float = float(cell_px) / MASK_TEXELS_PER_CELL
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
	var damp: FastNoiseLite = FastNoiseLite.new()
	damp.seed = MASK_SEED + 3
	damp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	damp.fractal_octaves = 3
	damp.frequency = 1.0 / (DAMP_PATCH_CELLS * cell_px)
	var walls: PackedInt32Array = wall_distance(data)
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = centre_of(data, cell_px)
	var edge_cells: float = WEAR_EDGE_CELLS
	for y: int in size.y:
		for x: int in size.x:
			var at: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			var cell: int = (y / MASK_TEXELS_PER_CELL) * cells.x + x / MASK_TEXELS_PER_CELL
			var inside: float = float(maxi(walls[cell], 0))
			var wear: float = WEAR_BASE + patches.get_noise_2d(at.x, at.y) * 0.95
			wear += WEAR_EDGE_BOOST * clampf(1.0 - inside / edge_cells, 0.0, 1.0)
			wear *= smoothstep(clear_radius, clear_radius + edge_cells * cell_px, at.distance_to(centre))
			var drift: float = 0.5 + tone.get_noise_2d(at.x, at.y) * 0.9
			var layer: float = 0.5 + layers.get_noise_2d(at.x, at.y) * 1.2
			var wet: float = clampf((damp.get_noise_2d(at.x, at.y) - DAMP_LEVEL) / DAMP_RAMP, 0.0, 1.0)
			image.set_pixel(x, y, Color(clampf(wear, 0.0, 1.0), clampf(drift, 0.0, 1.0), clampf(layer, 0.0, 1.0), wet))
	return image


## Moves the hero aura to the hero's ground point (world px), drifts the mist and slides the
## distant scenery with the view. `view_centre` is the screen point (projected px) the camera
## aims at, `zoom` its zoom; by default the view is centred on the hero at zoom 1.
func follow(hero: Vector2, view_centre: Vector2 = Vector2.INF, zoom: float = 1.0, show_aura: bool = true) -> void:
	var centre: Vector2 = IsoProjection.to_screen(hero) if view_centre == Vector2.INF else view_centre
	_aura.position = IsoProjection.to_screen(hero)
	_aura.visible = show_aura
	for rect: ColorRect in [_sky, _veil]:
		(rect.material as ShaderMaterial).set_shader_parameter("camera_offset", centre)
	var size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	for index: int in _backdrop.get_child_count():
		var plane: Node2D = _backdrop.get_child(index) as Node2D
		var parallax: float = FAR_PARALLAX if index == 0 else BACKDROP_PARALLAX
		plane.scale = Vector2.ONE * zoom
		plane.position = backdrop_origin(centre, zoom, size, parallax)


## Screen point of the backdrop's origin (the arena centre of the distant scenery) for a view
## centred on `view_centre` (projected px) at `zoom` in a window of `size` px.
func backdrop_origin(view_centre: Vector2, zoom: float, size: Vector2, parallax: float = BACKDROP_PARALLAX) -> Vector2:
	var travel: Vector2 = view_centre - IsoProjection.to_screen(_centre)
	return size * 0.5 - travel * parallax * zoom


## The fire lights at `seconds` of the run (RunLighting.flicker).
func flicker(seconds: float) -> void:
	for index: int in _fires.size():
		_fires[index].energy = RunLighting.LANTERN_ENERGY * RunLighting.flicker(seconds, index)


## Energy of each fire light now.
func fire_energies() -> Array[float]:
	var out: Array[float] = []
	for light: PointLight2D in _fires:
		out.append(light.energy)
	return out


## Ground point (world px) the hero aura shines on.
func aura_position() -> Vector2:
	return IsoProjection.to_world(_aura.position)


## Behind the courtyard, on a canvas layer that does not follow the camera: the dusk sky, the
## distant spires and pagodas (REF-033, REF-056) and the mist veil drifting in front of them.
## The shaders slide with camera_offset; the scenery node is moved by follow().
func _build_mist(sprites: SpriteSet, backdrop: Array[Dictionary]) -> void:
	var back: CanvasLayer = CanvasLayer.new()
	back.layer = MIST_LAYER
	add_child(back)
	_sky = _mist_rect(false)
	back.add_child(_sky)
	_backdrop = Node2D.new()
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.add_child(_backdrop)
	_backdrop.add_child(_backdrop_plane(sprites, backdrop, false))
	_backdrop.add_child(_backdrop_plane(sprites, backdrop, true))
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


## One atlas surface per depth, with the lower part of each peak fading into the mist.
static func _backdrop_plane(sprites: SpriteSet, backdrop: Array[Dictionary], near_plane: bool) -> MeshInstance2D:
	var plane: MeshInstance2D = MeshInstance2D.new()
	var vertices: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for item: Dictionary in backdrop:
		if (float(item["near"]) >= NEAR_PLANE) != near_plane:
			continue
		var quad: Dictionary = sprites.prop_quad(item["asset"], item["prop"], item["at"], item["scale"], item["flip"])
		if quad.is_empty():
			continue
		if plane.texture == null:
			plane.texture = quad["texture"]
		var rect: Rect2 = quad["rect"]
		var uv: Rect2 = quad["uv"]
		var haze: Color = BACKDROP_HAZE_FAR.lerp(BACKDROP_HAZE_NEAR, item["near"])
		var gone: Color = Color(haze, 0.0)
		var keep: float = 1.0 - BACKDROP_FADE
		var mid: float = rect.position.y + rect.size.y * keep
		var uv_mid: float = uv.position.y + uv.size.y * keep
		var base: int = vertices.size()
		vertices.append_array(PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, mid),
			Vector2(rect.end.x, mid), Vector2(rect.position.x, rect.end.y), rect.end,
		]))
		uvs.append_array(PackedVector2Array([
			uv.position, Vector2(uv.end.x, uv.position.y), Vector2(uv.position.x, uv_mid),
			Vector2(uv.end.x, uv_mid), Vector2(uv.position.x, uv.end.y), uv.end,
		]))
		colors.append_array(PackedColorArray([haze, haze, haze, haze, gone, gone]))
		for offset: int in [0, 2]:
			indices.append_array(_quad_indices(base + offset))
	plane.mesh = _surface_mesh(vertices, colors, uvs, indices)
	return plane


## The paving: one polygon of rectangles over the footprint. With both floor textures the
## floor shader blends the clean flagstones with the worn ones by the wear mask.
func _build_floor(sprites: SpriteSet, floor_asset: String, worn_asset: String, clear_radius: float) -> void:
	var texture: Texture2D = sprites.canvas_texture(floor_asset)
	paving = Polygon2D.new()
	var points: PackedVector2Array = PackedVector2Array()
	var parts: Array = []
	for rect: Rect2 in footprint(_data, _cell_px):
		var first: int = points.size()
		points.append_array(PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		]))
		parts.append(PackedInt32Array([first, first + 1, first + 2, first + 3]))
	paving.polygon = points
	paving.polygons = parts
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
	var wear: ShaderMaterial = ShaderMaterial.new()
	wear.shader = FLOOR_SHADER
	wear.set_shader_parameter("worn_albedo", worn.diffuse_texture)
	wear.set_shader_parameter("worn_normal", worn.normal_texture)
	wear.set_shader_parameter("wear_mask", ImageTexture.create_from_image(wear_mask(_data, _cell_px, clear_radius)))
	wear.set_shader_parameter("mask_origin", Vector2.ZERO)
	wear.set_shader_parameter("mask_size", _arena)
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
	seal.position = _centre
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


## A pair of thin gold lines from the rim of the seal towards the first wall along each grid
## axis, ending in a small square knot (REF-033, REF-029: the inlay runs from the seal across
## the paving). One item draws them all, lit with the floor.
func _build_inlay(seal_radius: float) -> void:
	var inset: float = INLAY_WALL_INSET_CELLS * _cell_px
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var reach: float = _floor_reach(axis) - inset
		var from: Vector2 = _centre + axis * seal_radius * INLAY_SEAL_SHARE
		var knot: float = INLAY_GAP_PX * 2.4
		if reach - knot <= seal_radius * INLAY_SEAL_SHARE:
			continue
		var to: Vector2 = _centre + axis * (reach - knot)
		var across: Vector2 = axis.orthogonal() * INLAY_GAP_PX * 0.5
		for side: float in [-1.0, 1.0]:
			inlay.append(PackedVector2Array([from + across * side, to + across * side]))
		var end: Vector2 = _centre + axis * reach
		var half: Vector2 = axis.orthogonal() * knot * 0.5
		inlay.append(PackedVector2Array([to - half, to + half, end + half, end - half, to - half]))
	var lines: Node2D = Node2D.new()
	lines.draw.connect(func() -> void:
		for line: PackedVector2Array in inlay:
			lines.draw_polyline(line, INLAY_COLOR, INLAY_WIDTH_PX))
	_iso.add_child(lines)


## World px from the seal centre along `axis` to the edge of the last open floor cell.
func _floor_reach(axis: Vector2) -> float:
	var rows: Array = _data.get("rows", [])
	var centre: Array = _data.get("centre", [0, 0])
	var step: Vector2i = Vector2i(axis)
	var at: Vector2i = Vector2i(int(centre[0]), int(centre[1]))
	var count: int = 0
	while true:
		var next: Vector2i = at + step
		if next.y < 0 or next.y >= rows.size() or next.x < 0 or next.x >= (rows[next.y] as String).length():
			break
		if not FLOOR_CHARS.contains((rows[next.y] as String)[next.x]):
			break
		at = next
		count += 1
	return (float(count) + 0.5) * _cell_px


## Stone and cliff faces under every near edge over the void, dropping CLIFF_PX down the
## screen and fading into the mist, and the waterfalls that pour down three of them
## (REF-033, REF-029).
func _build_cliffs(sprites: SpriteSet, cliff_asset: String) -> void:
	var faces: MeshInstance2D = MeshInstance2D.new()
	faces.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	faces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	faces.texture = sprites.canvas_texture(cliff_asset)
	faces.mesh = _cliff_mesh(faces.texture, sprites.decal_world_px(cliff_asset))
	add_child(faces)
	var water: ShaderMaterial = ShaderMaterial.new()
	water.shader = WATERFALL_SHADER
	for fall: Array in WATERFALLS:
		var top: Vector2 = waterfall_top(_data, _cell_px, fall[0])
		if not top.is_finite():
			continue
		var width: float = fall[1]
		var rect: ColorRect = ColorRect.new()
		rect.material = water
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.position = top + Vector2(-width * 0.5, WATERFALL_TOP_PX)
		rect.size = Vector2(width, WATERFALL_DROP_PX)
		add_child(rect)
		waterfalls.append(rect)


## Screen point of the top of a waterfall at `share` across the arena (left to right): the
## middle of the lowest near face within a cell of that screen x.
static func waterfall_top(data: Dictionary, cell_px: int, share: float) -> Vector2:
	var faces: Array[PackedVector2Array] = near_faces(data, cell_px)
	var bridge: Dictionary[Vector2, float] = _bridge_openings(data, cell_px, faces)
	var left: float = INF
	var right: float = -INF
	var bridge_left: float = INF
	var bridge_right: float = -INF
	for point: Vector2 in bridge:
		bridge_left = minf(bridge_left, point.x)
		bridge_right = maxf(bridge_right, point.x)
	for face: PackedVector2Array in faces:
		for point: Vector2 in face:
			left = minf(left, IsoProjection.to_screen(point).x)
			right = maxf(right, IsoProjection.to_screen(point).x)
	var target: float = lerpf(left, right, share)
	var best: Vector2 = Vector2(target, -INF)
	var nearest: Vector2 = best
	var distance: float = INF
	for face: PackedVector2Array in faces:
		var middle: Vector2 = IsoProjection.to_screen((face[0] + face[1]) * 0.5)
		if middle.x >= bridge_left - cell_px and middle.x <= bridge_right + cell_px:
			continue
		var across: float = absf(middle.x - target)
		if across <= cell_px and middle.y > best.y:
			best = middle
		if across < distance:
			nearest = middle
			distance = across
	return best if is_finite(best.y) else nearest


## Rail cells bordering the bridge carry its fascia, so both bridge and rail corners share the arches.
static func _bridge_openings(
	data: Dictionary, cell_px: int, faces: Array[PackedVector2Array]
) -> Dictionary[Vector2, float]:
	var corners: Dictionary[Vector2, float] = {}
	var rows: Array = data.get("rows", [])
	var left: float = INF
	var right: float = -INF
	for edge: PackedVector2Array in faces:
		var cell: Vector2i = Vector2i((edge[0] + edge[1]) / (2.0 * cell_px))
		cell -= Vector2i.RIGHT if edge[0].x == edge[1].x else Vector2i.DOWN
		var tile: String = (rows[cell.y] as String)[cell.x]
		if tile != "B" and not (tile == "w" and _touches_bridge(rows, cell)):
			continue
		var a: Vector2 = IsoProjection.to_screen(edge[0])
		var b: Vector2 = IsoProjection.to_screen(edge[1])
		for step: int in BRIDGE_EDGE_STEPS + 1:
			var at: Vector2 = a.lerp(b, float(step) / BRIDGE_EDGE_STEPS)
			corners[at] = 0.0
			left = minf(left, at.x)
			right = maxf(right, at.x)
	if right > left:
		for corner: Vector2 in corners:
			var along: float = (corner.x - left) / (right - left) * BRIDGE_SPANS
			var rim: float = (fposmod(along, 1.0) * 2.0 - 1.0) / BRIDGE_ARCH_WIDTH
			corners[corner] = sqrt(maxf(0.0, 1.0 - rim * rim))
	return corners


static func _touches_bridge(rows: Array, cell: Vector2i) -> bool:
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at: Vector2i = cell + step
		if at.y >= 0 and at.y < rows.size():
			var row: String = rows[at.y]
			if at.x >= 0 and at.x < row.length() and row[at.x] == "B":
				return true
	return false


## Subdivide the bridge fascia so the curve of each arch reads underneath the stepped top.
static func _cliff_segments(
	faces: Array[PackedVector2Array], bridge: Dictionary[Vector2, float]
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for edge: PackedVector2Array in faces:
		var a: Vector2 = IsoProjection.to_screen(edge[0])
		var b: Vector2 = IsoProjection.to_screen(edge[1])
		var steps: int = BRIDGE_EDGE_STEPS if bridge.has(a.lerp(b, 0.5)) else 1
		for index: int in steps:
			out.append(PackedVector2Array([a.lerp(b, float(index) / steps), a.lerp(b, float(index + 1) / steps)]))
	return out


## Average only the teeth of across-screen runs. Corners and the contact with the floor stay put.
static func cliff_courses(faces: Array[PackedVector2Array]) -> Dictionary[Vector2, float]:
	var left: Dictionary[Vector2, Vector2] = {}
	var right: Dictionary[Vector2, Vector2] = {}
	for face: PackedVector2Array in faces:
		var a: Vector2 = IsoProjection.to_screen(face[0])
		var b: Vector2 = IsoProjection.to_screen(face[1])
		if a.x > b.x:
			var swap: Vector2 = a
			a = b
			b = swap
		right[a] = b
		left[b] = a
	var courses: Dictionary[Vector2, float] = {}
	for at: Vector2 in right:
		if left.has(at) and is_equal_approx(left[at].y, right[at].y):
			courses[at] = lerpf(at.y, left[at].y, 0.43)
	return courses


## One surface for coping, rock and bridge trim. The first row always lands on the floor.
func _cliff_mesh(texture: Texture2D, span: float) -> ArrayMesh:
	var vertices: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var top_color: Color = Color.WHITE if texture != null else COLOR_CLIFF_FLAT
	var cold: Color = top_color * Color(0.63, 0.73, 0.92)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = MASK_SEED + 4
	noise.frequency = 0.005
	var centre_x: float = IsoProjection.to_screen(_centre).x
	var faces: Array[PackedVector2Array] = near_faces(_data, _cell_px)
	var courses: Dictionary[Vector2, float] = cliff_courses(faces)
	var bridge: Dictionary[Vector2, float] = _bridge_openings(_data, _cell_px, faces)
	var bridge_y: float = 0.0
	var bridge_left: float = INF
	var bridge_right: float = -INF
	for point: Vector2 in bridge:
		bridge_y += point.y
		bridge_left = minf(bridge_left, point.x)
		bridge_right = maxf(bridge_right, point.x)
	bridge_y /= maxi(bridge.size(), 1)
	var bay: float = (bridge_right - bridge_left) / BRIDGE_SPANS
	for edge: PackedVector2Array in _cliff_segments(faces, bridge):
		var base: int = vertices.size()
		for row: int in CLIFF_DEPTHS.size():
			var depth: float = CLIFF_DEPTHS[row]
			for at: Vector2 in edge:
				var masonry: bool = bridge.has(at)
				var opening: float = bridge.get(at, 0.0)
				var abutment: float = smoothstep(0.0, 68.0, minf(at.x - bridge_left, bridge_right - at.x))
				var height: float = lerpf(CLIFF_PX, BRIDGE_INTRADOS_PX + bridge_y - at.y, opening)
				var course: float = lerpf(courses.get(at, at.y), bridge_y, abutment if masonry else 0.0)
				var drop: float = height * depth
				if masonry and row > 0:
					var footing: float = minf(39.0, height - 4.0)
					var courses_px: Array[float] = [0.0, footing * 0.53, footing,
						lerpf(footing, height, 0.32), lerpf(footing, height, 0.65), height]
					drop = lerpf(drop, courses_px[row], abutment)
				# Depth in screen pixels keeps the bridge's masonry courses level above each opening.
				var band: float = smoothstep(0.0, 18.0, drop) * (1.0 - smoothstep(28.0, 90.0, drop))
				var taper: float = smoothstep(0.08, 0.45, depth)
				var inset: float = clampf((centre_x - at.x) / 800.0, -1.0, 1.0)
				var relief: float = noise.get_noise_2d(at.x, at.y * 0.7) + 0.21 * sin(at.y * 0.020 + at.x * 0.006)
				var shelf: float = (1.0 - smoothstep(0.38, 0.98, depth)) * taper
				var offset: Vector2 = Vector2(inset * 42.0 * taper + relief * 104.0 * shelf, relief * 38.0 * shelf)
				if masonry:
					offset *= 1.0 - abutment
				var down: Vector2 = at + Vector2(0.0, drop + (course - at.y) * band) + offset
				vertices.append(down)
				var shade: float = 0.20 if row == 2 else 0.0
				var tint: Color = top_color.lerp(cold, depth * 0.82).darkened(shade)
				var v: float = depth
				if masonry:
					var pier: float = absf((at.x - bridge_left) - bay)
					var reveal: float = smoothstep(27.0, 59.0, pier)
					tint *= Color.WHITE.lerp(Color(0.92, 0.94, 1.0).darkened(reveal * depth * 0.14), abutment)
					var below_deck: float = maxf(0.0, down.y - bridge_y)
					var masonry_v: float = maxf(drop * 0.50, below_deck) / 420.0
					v = lerpf(depth, masonry_v, abutment)
				tint.a = lerpf(CLIFF_VISIBILITY[row], 1.0, smoothstep(0.0, 0.20, opening))
				colors.append(tint)
				if texture != null:
					var warp: float = relief * 0.07 * smoothstep(0.12, 0.6, depth)
					warp *= 1.0 - abutment if masonry else 1.0
					uvs.append(Vector2((at.x + offset.x * 0.42) / span + warp, v))
			if row + 1 < CLIFF_DEPTHS.size():
				indices.append_array(_quad_indices(base + row * 2))
	if bay > 0.0 and texture != null:
		_bridge_pier(Vector2(bridge_left + bay, bridge_y), vertices, colors, uvs, indices)
		for index: int in BRIDGE_SPANS:
			var spring: Vector2 = Vector2(bridge_left + bay * (index + 0.5), bridge_y + CLIFF_PX)
			_arch_stonework(spring, bay * BRIDGE_ARCH_WIDTH * 0.5, vertices, colors, uvs, indices)
	return _surface_mesh(vertices, colors, uvs, indices)


## The middle pier projects slightly in front of the spandrel and widens toward the footings.
static func _bridge_pier(
	at: Vector2, vertices: PackedVector2Array, colors: PackedColorArray,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	var base: int = vertices.size()
	for row: int in 4:
		var height: float = [33.0, 110.0, 192.0, CLIFF_PX][row]
		var half_width: float = [19.0, 23.0, 29.0, 36.0][row]
		var alpha: float = [0.90, 0.96, 0.84, 0.0][row]
		for side: int in 2:
			var x: float = half_width * (-1.0 if side == 0 else 1.0)
			vertices.append(at + Vector2(x, height + side * 5.0))
			var tone: Color = Color(0.84, 0.86, 0.93, alpha) if side == 0 else Color(0.64, 0.66, 0.74, alpha)
			colors.append(tone)
			uvs.append(Vector2(0.245 + side * 0.087, 0.097 + height * 0.001))
	for row: int in 3:
		indices.append_array(_quad_indices(base + row * 2))


## The cut stone has a lit face and a recessed return. Both darken into the gorge at the spring.
static func _arch_stonework(
	spring: Vector2, radius: float, vertices: PackedVector2Array, colors: PackedColorArray,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	var rise: float = CLIFF_PX - BRIDGE_INTRADOS_PX
	for stone: int in ARCH_STONES:
		var base: int = vertices.size()
		var u: float = 0.235 + float(stone % 3) * 0.046
		for row: int in 3:
			for side: int in 2:
				var angle: float = (stone + side) * PI / ARCH_STONES
				var radial: Vector2 = Vector2(-cos(angle), -sin(angle))
				var rim: Vector2 = spring + radial * Vector2(radius, rise)
				var offsets: Array[float] = [-11.0, 2.5, 22.0]
				var tint: Color = [Color(0.45, 0.48, 0.55), Color(1.05, 1.02, 1.0),
					Color(0.86, 0.85, 0.9)][row]
				tint *= [0.81, 0.92, 1.0, 0.85, 0.96][stone % 5]
				tint.a = smoothstep(0.04, 0.42, sin(angle))
				vertices.append(rim + radial * offsets[row])
				colors.append(tint)
				uvs.append(Vector2(u + side * 0.037, 0.128 + row * 0.03))
		indices.append_array(_quad_indices(base))
		indices.append_array(_quad_indices(base + 2))


## Each band is laid out as two consecutive rows of left and right vertices.
static func _quad_indices(base: int) -> PackedInt32Array:
	return PackedInt32Array([base, base + 1, base + 3, base, base + 3, base + 2])


static func _surface_mesh(
	vertices: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array
) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		if not uvs.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
