# TASK_SPEC · Q4-DAMAGE-NUMBER-MODES

- **Status:** VERIFIED locally (2026-11-19); hosted CI on the PR
- **Goal:** the player's `floating_damage_numbers` setting chooses how damage numbers appear: `off` (none, sparks stay), `aggregate` (blows on one enemy within 0.12 s add up into one number; the default for players) or `all` (a number per blow, the look before the setting existed).
- **Non-goals:** no change to the number look (font, rise, fade, kill colour), to `game/core/`, replays or bots; no options UI (Q6).
- **Inputs:** QUALITY-2026-11 §5 Q4 (`.work/roadmap/QUALITY_PLAN_2026-11.md`); [settings wiring](../q-settings-wiring/README.md).
- **Files allowed:** `game/presentation/run/combat_vfx.gd`, `game/presentation/run/run_view.gd` (one line), `game/tests/integration/test_combat_vfx.gd`, `game/tests/integration/test_run_view_settings.gd`, this file.
- **Dependencies:** `RunView.settings` (settings wiring PR).
- **Contracts:** `CombatVfx.number_mode` (`all` by default, unknown values act as `all`); a number entry is `[ground px, age, text, kill, x jitter, enemy uid, damage mhp]`. In `aggregate` a blow joins the newest number of the same enemy younger than `AGGREGATE_TIME = 0.12` s: damage adds up, the text is the rounded sum, a kill marks it, it moves to the latest blow; otherwise a new entry starts, even below half a point (drawn only once its sum rounds to 1 or more). The cap `MAX_NUMBERS = 40` (oldest dropped) and the per-blow rounding are unchanged. RunView sets the mode from the settings in `_ready`; tests, replays and captures get `all`, so their frames are unchanged. The plan's draft values (48 on screen, 0.7 s rise) were not adopted: the existing 40 and 0.8 s look stays.
- **Acceptance:** GUT covers `off`, `all`, summing in the window, a new number after it, separate enemies, the kill mark, sub-point sums, the cap and the RunView link; the full GUT suite passes.
- **Risks / rollback:** players now see summed numbers by default; `all` restores the old look. Reverting restores a number per blow.
- **Test commands:** `python scripts/validate_work.py` · `python scripts/dev/godot_tool.py test`.
- **Evidence links:** agent full GUT 296/296 (before the RunView link); after it targeted GUT combat vfx 16/16, run view settings 3/3, gdlint 4.5.0 clean; mutations caught: dropping the kill mark and ignoring `off` fail 2 tests.
- **Next action:** Q6 exposes the mode in the options menu.
