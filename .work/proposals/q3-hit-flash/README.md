# TASK_SPEC · Q3-HIT-FLASH

- **Status:** VERIFIED locally (2026-11-19); hosted CI on the PR
- **Goal:** the player's `hit_flash` setting (0..1) scales the white hit flash of enemies and of the hero; 0 turns the flashes off while the recoil, knock-back, HP bar and death clip still show every blow. One enemy's flash starts at most once per `EnemyReactions.FLASH_TIME` (0.1 s), whatever its hit clip length.
- **Non-goals:** no change to the danger layer or telegraphs (PLAYABILITY_GATES G3/G10), to `game/core/`, to replays or bots; no options UI (Q6).
- **Inputs:** QUALITY-2026-11 §5 Q3 (`.work/roadmap/QUALITY_PLAN_2026-11.md`); [settings wiring](../q-settings-wiring/README.md).
- **Files allowed:** `game/presentation/run/run_view.gd`, `game/presentation/run/enemy_reactions.gd`, `game/tests/integration/test_run_view_settings.gd`, `game/tests/unit/test_enemy_reactions.gd`, this file.
- **Dependencies:** `RunView.settings` (settings wiring PR).
- **Contracts:** `RunView._enemy_flash(uid) = EnemyReactions.flash(uid) × hit_flash`; `_hero_flash_share()` is multiplied by `hit_flash`. `EnemyReactions.hit` restarts a reaction only after `max(clip × RESTART_SHARE, FLASH_TIME)`; with the current clips (≥ 0.2 s) this is the same as before. Tests, replays and captures keep `hit_flash = 1.0`, so their frames are unchanged.
- **Acceptance:** GUT checks the scale at 1, 0.5 and 0 for both flashes and the 0.1 s restart floor; the full GUT suite passes.
- **Risks / rollback:** the venom tint still waits for the hero flash timer, not its strength, so at `hit_flash = 0` the venom tint pauses for the 0.15 s flash; acceptable, revisit with Q6 if players notice. Reverting restores the fixed flash.
- **Test commands:** `python scripts/validate_work.py` · `python scripts/dev/godot_tool.py test`.
- **Evidence links:** targeted GUT 3/3 (`test_run_view_settings.gd`) and 6/6 (`test_enemy_reactions.gd`); mutations caught: `_flash_strength()` returning 1 fails the scale test, removing the `FLASH_TIME` floor fails the restart test.
- **Next action:** Q5 own-skill opacity after its design.
