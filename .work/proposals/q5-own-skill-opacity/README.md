# TASK_SPEC · Q5-OWN-SKILL-OPACITY

- **Status:** VERIFIED locally (2026-11-19); hosted CI on the PR
- **Goal:** the player's `own_skill_opacity` setting (0.2..1, default 0.8) fades the hero's own skill effects so a crowded fight stays readable, while every threat keeps its full look (PLAYABILITY_GATES G3: no setting hides a telegraph).
- **Non-goals:** no change to the danger layer, telegraphs, enemy shots or zones, gems, lantern light, the HP bar, the hero sprite, bursts of the fallen, the level pillar or the damage numbers (Q4 has its own setting); no change to `game/core/`, replays or bots; no options UI (Q6).
- **Inputs:** QUALITY-2026-11 §3 rule 3 and §5 Q5 (`.work/roadmap/QUALITY_PLAN_2026-11.md`); [s15](../../spec/core/s15.md) separate VFX settings; [settings wiring](../q-settings-wiring/README.md).
- **Files allowed:** `game/presentation/run/combat_vfx.gd`, `game/presentation/run/run_effects_passes.gd`, `game/presentation/run/run_view.gd`, `game/tests/integration/test_run_view_settings.gd`, this file.
- **Dependencies:** settings wiring and Q4 (both add a line after the `CombatVfx` load in `RunView._ready`).
- **Contracts:** the hero's own effects are the chain line, the flying swords (atlas sword, fallback trail, glow halo and primitive blade), the cast circles and the hit sparks. Their alpha is multiplied by `own_skill_opacity`: `CombatVfx.own_opacity` (set in `_ready`) for the atlas pieces, `RunView.own_color(color)` for the drawn lines and halos. Under additive blending the alpha scales the added light. Tests, replays and captures have 1.0, so their frames are unchanged.
- **Acceptance:** GUT checks the alpha scale and that only the alpha changes, the reference value 1.0, and a source guard that `attack_telegraph.gd` and `RunView._draw_danger_pass` never read the setting; the full GUT suite passes.
- **Risks / rollback:** the draw calls themselves are not captured in a test (headless GUT has no frame readback); the 1280×720 before/after capture of QUALITY-2026-11 §7 step 5 is the visual check. Reverting restores full-opacity effects.
- **Test commands:** `python scripts/validate_work.py` · `python scripts/dev/godot_tool.py test`.
- **Evidence links:** targeted GUT run view settings 4/4, combat vfx 16/16, run view 20/20; gdlint 4.5.0 clean; mutation caught: `own_color` ignoring the setting fails the test.
- **Next action:** Q6 options menu for all wave 1 settings.
