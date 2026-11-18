# TASK_SPEC · Q2-SCREEN-SHAKE

- **Status:** VERIFIED locally (2026-11-19); hosted CI on the PR
- **Goal:** the camera shakes a little when the hero takes damage and more when the hero dies, scaled by the player's `screenshake` setting; at 0 the camera is exactly as before.
- **Non-goals:** no shake on enemy hits, casts or level-ups; no change to `game/core/`, replays or bots; no options UI (Q6).
- **Inputs:** QUALITY-2026-11 §5 Q2 (`.work/roadmap/QUALITY_PLAN_2026-11.md`); [settings wiring](../q-settings-wiring/README.md).
- **Files allowed:** `game/presentation/run/camera_shake.gd` (+ `.uid`), `game/presentation/run/run_view.gd`, `game/tests/unit/test_camera_shake.gd` (+ `.uid`), `game/tests/integration/test_run_view_settings.gd`, this file.
- **Dependencies:** `RunView.settings` (settings wiring PR).
- **Contracts:** `CameraShake` trauma model, deterministic (two sines, 17 Hz and 23 Hz, no random numbers): +0.30 on a frame where the hero's HP drops, +0.60 when the hero dies; additions within 0.05 s keep the larger instead of stacking; decay 1.6/s; offset = 8 px × `screenshake` × trauma². It is written into `Camera2D.offset` in `_age_effects`, so `Camera2D.position`, the ground follow and `camera_target()` are unchanged. A new run and the class select reset it. Tests, replays and captures have `screenshake = 0`.
- **Acceptance:** GUT covers zero at strength 0, the bound, merging, the cap, decay to zero, determinism and reset, and in the scene a real blow: no offset at the reference look, an offset at strength 1; the full GUT suite passes.
- **Risks / rollback:** at the default `screenshake = 0.40` a blow moves the camera by under 0.3 px and a death by about 1.2 px, so the effect is subtle; the trauma values are the plan's drafts (QUALITY-2026-11 §8 В1) and can be tuned after a playtest. Venom ticks (every 0.5 s) also count as HP drops; at these amplitudes this stays sub-pixel. Reverting restores a still camera.
- **Test commands:** `python scripts/validate_work.py` · `python scripts/dev/godot_tool.py test`.
- **Evidence links:** agent full GUT 297/297 (before the test move); after it targeted GUT camera shake 8/8, run view settings 3/3, run view 20/20, gdlint 4.5.0 clean. Mutations caught: ignoring the strength fails the scene test (it was vacuous at first: the offset of a blow is written on the next frame, the test now advances one frame), disabling the merge fails the unit test.
- **Next action:** tune the trauma values with the owner after a playtest.
