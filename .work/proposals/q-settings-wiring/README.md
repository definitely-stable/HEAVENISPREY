# TASK_SPEC · Q-SETTINGS-WIRING

- **Status:** VERIFIED locally (2026-11-19); hosted CI on the PR
- **Goal:** the run view owns one `PresentationSettings` instance that later wave 1 slices (Q2 screen shake, Q3 hit flash, Q4 damage numbers, Q5 own-skill opacity) read, so each slice touches only its own module plus a few lines of wiring.
- **Non-goals:** no visible change yet; no new amplifier, no options UI (Q6), no change to `game/core/` or to replays, bots or captures.
- **Inputs:** QUALITY-2026-11 §5 (`.work/roadmap/QUALITY_PLAN_2026-11.md`); [Q1 store](../q1-presentation-settings/README.md).
- **Files allowed:** `game/presentation/run/run_view.gd`, `game/presentation/settings/presentation_settings.gd`, `game/tests/unit/test_presentation_settings.gd`, `game/tests/integration/test_run_view.gd`, this file.
- **Dependencies:** `main` `356b2fe` (Q1 merged).
- **Contracts:** `RunView.settings` is set in `_ready` unless assigned before. A player run (`read_player_input = true`) loads `user://settings.cfg`; tests, replays and reference captures (`read_player_input = false`) get `PresentationSettings.reference_look()`: screen shake 0, a number on every blow (`all`, the look before the setting existed), own-skill opacity 1, the other values at their defaults. Reference frames keep the current look whatever a player saved.
- **Acceptance:** GUT checks the reference look values, that a replay view gets them and that settings assigned before `_ready` are kept; the full GUT suite passes.
- **Risks / rollback:** the field is unused until Q2; reverting removes it without side effects.
- **Test commands:** `python scripts/validate_work.py` · `python -m unittest discover -s tests -v` · `python scripts/dev/godot_tool.py test`.
- **Evidence links:** see the PR checks; local `python scripts/dev/godot_tool.py test` on base `356b2fe`.
- **Next action:** Q2, Q3, Q4 in parallel on top of this field.
