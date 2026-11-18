# TASK_SPEC · JADE-GROVE-15

- **Status:** IN_PROGRESS.
- **Goal:** a Jade Grove run lasts 15 minutes of combat time, changes enemy formations after minute five, and continues to grant class upgrades across the run.
- **Scope:** Jade Grove roster and pacing, XP costs for the existing ranked upgrades, and Python/Godot playback of the new run.
- **Non-goals:** additional classes, new active skill slots, bosses, and permanent rewards.
- **Inputs:** ADR-010 for choices, ADR-011 for roster windows and victory, ADR-012 for class upgrades, and ADR-015 for the arena.
- **Files allowed:** stage and roster catalogs, generated registry, P0 tuning, bot tooling and fixtures, affected tests and documentation, and the desktop replay checks.
- **Contracts:** stable stage, enemy, roster and upgrade IDs. Keep the existing arena, threat caps and first four compositions. Preserve the historical five-minute journals with their original configs.
- **Acceptance:** 54000 ticks to victory with no gaps in the roster; at least six distinct compositions after minute five; no increase in simultaneous high-threat caps; both classes reach the final phase on seed 101 and take meaningful upgrade ranks after minute ten; Python/Godot agree on the config, command log and final world digest.
- **Tests:** content and encounter validators, Python unittest discovery, Godot GUT and two exact 15-minute replays.
- **Risk and rollback:** the new pacing is playtest balance. The isolated slice can be reverted without modifying historical journals.

| Combat time | Formation |
| --- | --- |
| 00:00–05:00 | Four opening formations introduce ordinary enemies and special attacks |
| 05:00–06:45 | Wolves and corpses build up while spirits and snakes join them |
| 06:45–08:30 | Spirits and sword disciples with lanterns and mantises |
| 08:30–10:15 | A dense melee group around guardians, puppets and roots |
| 10:15–12:00 | Wolves and mantises lead a fast pursuit |
| 12:00–13:30 | Spirits and corpses screen guardians, roots and lanterns |
| 13:30–15:00 | Mixed finale with melee bodies and distinct threats under the same caps |

## Balance evidence

On seeds 101–132 with the existing `kiter_upgrades` policy, Sword cleared 32/32 and Thunder cleared 19/32. Successful runs had median kills of 2471 and 2470 respectively. The highest concurrent population was 32 and 31. On seed 101 both classes took their last ranked upgrade at 11:16 and made 26 level-up picks overall. Sword's bot had filled its damage, haste, count and pierce ranks by 02:37, while Thunder's continued improving chain reach through 11:16. Further balance work is needed for Thunder on the longer profile.

```text
python tools/content/sim_bots.py --jade-grove-15 --check
python scripts/validate_encounter_proposal.py
```
