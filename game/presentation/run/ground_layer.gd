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
const CLIFF_PX: float = 240.0
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
## The lights of the lanterns and braziers, in the order of the light points.
var _fires: Array[PointLight2D] = []
var _sky: ColorRect
var _veil: ColorRect
var _backdrop: Node2D
var _backdrop_items: Array[Dictionary] = []
var _sprites: SpriteSet
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
	_sprites = sprites
	_data = data
	_arena = Vector2(cells_of(data) * cell_px)
	_centre = centre_of(data, cell_px)
	_cell_px = cell_px
	_backdrop_items = backdrop
	_build_mist()
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
	_backdrop.transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), backdrop_origin(centre, zoom, size))


## Screen point of the backdrop's origin (the arena centre of the distant scenery) for a view
## centred on `view_centre` (projected px) at `zoom` in a window of `size` px.
func backdrop_origin(view_centre: Vector2, zoom: float, size: Vector2) -> Vector2:
	var travel: Vector2 = view_centre - IsoProjection.to_screen(_centre)
	return size * 0.5 - travel * BACKDROP_PARALLAX * zoom


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
	var faces: Node2D = Node2D.new()
	faces.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	faces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	faces.draw.connect(_draw_cliffs.bind(faces, sprites, cliff_asset))
	add_child(faces)
	var water: ShaderMaterial = ShaderMaterial.new()
	water.shader = WATERFALL_SHADER
	for fall: Array in WATERFALLS:
		var top: Vector2 = waterfall_top(_data, _cell_px, fall[0])
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
	var left: float = INF
	var right: float = -INF
	for face: PackedVector2Array in faces:
		for point: Vector2 in face:
			left = minf(left, IsoProjection.to_screen(point).x)
			right = maxf(right, IsoProjection.to_screen(point).x)
	var target: float = lerpf(left, right, share)
	var best: Vector2 = Vector2(target, -INF)
	for face: PackedVector2Array in faces:
		var middle: Vector2 = IsoProjection.to_screen((face[0] + face[1]) * 0.5)
		if absf(middle.x - target) <= cell_px and middle.y > best.y:
			best = middle
	return best


func _draw_cliffs(canvas: Node2D, sprites: SpriteSet, cliff_asset: String) -> void:
	var texture: Texture2D = sprites.canvas_texture(cliff_asset)
	var span: float = sprites.decal_world_px(cliff_asset) if texture != null else 1.0
	var drop: Vector2 = Vector2(0.0, CLIFF_PX)
	var fade: Color = Color(1.0, 1.0, 1.0, 0.0)
	for edge: PackedVector2Array in near_faces(_data, _cell_px):
		var a: Vector2 = IsoProjection.to_screen(edge[0])
		var b: Vector2 = IsoProjection.to_screen(edge[1])
		var points: PackedVector2Array = PackedVector2Array([a, b, b + drop, a + drop])
		var colors: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, fade, fade])
		if texture == null:
			for index: int in 4:
				colors[index] = Color(COLOR_CLIFF_FLAT, colors[index].a)
			canvas.draw_polygon(points, colors)
			continue
		# The strip is mapped by screen x, so the masonry runs on from face to face.
		var uvs: PackedVector2Array = PackedVector2Array([
			Vector2(a.x / span, 0), Vector2(b.x / span, 0), Vector2(b.x / span, 1), Vector2(a.x / span, 1),
		])
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
