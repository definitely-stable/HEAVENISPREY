extends GutTest
## ADR-014 section 20: the tone of the world frame after REF-023. An S-curve opens the range
## (shadows sink, lights climb), a vignette darkens the stone in the corners but spares the
## flames, the ground has its own darker ambient, and the HUD draws above the grade.

const RUN_SCENE: String = "res://presentation/run/run_view.tscn"


func test_curve_sinks_the_shadows_and_lifts_the_lights() -> void:
	assert_almost_eq(FrameGrade.curve_of(0.0), 0.0, 1e-6)
	assert_almost_eq(FrameGrade.curve_of(1.0), 1.0, 1e-6)
	assert_almost_eq(FrameGrade.curve_of(FrameGrade.PIVOT), FrameGrade.PIVOT, 1e-6)
	assert_lt(FrameGrade.curve_of(0.25), 0.25, "the paving in shade sinks")
	assert_gt(FrameGrade.curve_of(0.8), 0.8, "lantern light climbs")
	var last: float = -1.0
	for step: int in 101:
		var value: float = FrameGrade.curve_of(step / 100.0)
		assert_gt(value, last, "monotonic at %d" % step)
		last = value


func test_vignette_darkens_the_stone_in_the_corners_not_the_flames() -> void:
	var aspect: float = 16.0 / 9.0
	assert_almost_eq(FrameGrade.vignette_at(Vector2(0.5, 0.5), aspect), 1.0, 1e-6, "centre untouched")
	var corner: float = FrameGrade.vignette_at(Vector2(0.0, 0.0), aspect, 0.2)
	assert_almost_eq(corner, 1.0 - FrameGrade.VIGNETTE, 1e-3, "dark stone in the corner")
	assert_gt(FrameGrade.vignette_at(Vector2(0.25, 0.5), aspect, 0.2), corner, "falls off to the corner")
	assert_almost_eq(FrameGrade.vignette_at(Vector2(0.0, 0.0), aspect, 0.95), 1.0, 1e-6, "a flame keeps its heat")
	var stone: Color = FrameGrade.apply(Color(0.3, 0.27, 0.33), Vector2(0.02, 0.98), aspect)
	assert_lt(stone.r, 0.3 * (1.0 - FrameGrade.VIGNETTE * 0.5))


func test_scene_grades_the_world_under_the_hud() -> void:
	var view: RunView = (load(RUN_SCENE) as PackedScene).instantiate() as RunView
	view.read_player_input = false
	add_child_autofree(view)
	var grade: FrameGrade = null
	var hud_layer: int = -100
	var ground_ambient: Color = Color.BLACK
	for child: Node in view.get_children():
		if child is FrameGrade:
			grade = child
		elif child is GroundLayer:
			for part: Node in child.get_children():
				if part is CanvasModulate:
					ground_ambient = (part as CanvasModulate).color
		elif child is CanvasLayer and child.get_children().any(func(node: Node) -> bool: return node is RunHud):
			hud_layer = (child as CanvasLayer).layer
	assert_not_null(grade)
	assert_gt(grade.layer, 0, "over the scene")
	assert_gt(hud_layer, grade.layer, "the HUD, the menu and the results are not graded")
	assert_eq(hud_layer, RunView.HUD_LAYER)
	assert_true(grade.rect.material is ShaderMaterial)
	assert_eq(ground_ambient, RunLighting.GROUND_AMBIENT)
	var ground: float = RunLighting.GROUND_AMBIENT.get_luminance()
	assert_lt(ground, RunLighting.AMBIENT.get_luminance(), "the paving is darker than the bodies on it")
