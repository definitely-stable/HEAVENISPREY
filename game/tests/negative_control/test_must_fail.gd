extends GutTest
## Negative control (toolchain lock, tool.gut): this suite MUST fail.
## `godot_tool.py test` runs it separately and errors if the runner reports success,
## proving that a failing GUT test makes CI exit non-zero. Never include it in the main run.


func test_intentional_failure() -> void:
	assert_eq(1, 2, "intentional failure: negative control")
