# TASK_SPEC: P0-02 C3

- **Status:** APPROVED by [ADR-012 §4, §7–10](../../decisions/ADR-012-p0-02-classes-run-loop.md).
- **Goal:** On launch, the player chooses a class over the empty arena. Sword starts unlocked. The first completed Jade Grove run opens Thunder for the session.
- **Non-goals:** Full receipt, reward preview and Rewards screen belong to C4. Production art, combat HUD, simulation, balance and persistent saves are outside this slice.
- **Inputs:** ADR-012, class, skill, stage and unlock definitions in the v7 registry, and the current choice/results menu theme.
- **Files allowed:** Class Select, in-memory profile, RunView startup and input integration, UI translations and generated strings, menu capture, focused integration tests and evidence.
- **Dependencies:** C1 authorized run setup and C2 Thunder gameplay.
- **Contracts:** Catalog order and `planned_first_playable` control the cards. Locked classes cannot be started. Authoritative setup remains `RunRulesSnapshot.create_for_new_run`. Only a victory or defeat counts toward `unlock.thunder`. The test flag is `--unlock-all`.
- **Acceptance:** Initial focus is Sword and no run advances behind the screen. Arrow keys, controller actions, digits, mouse and `ui_accept` use the guarded confirm path after 0.35 s. A locked-card attempt starts no run. A completed run opens Thunder for the session, and restart during a run leaves it locked. Both locales render realistic card contents and preserve layout.
- **Tests:** `python scripts/dev/local_ci.py`, `python scripts/dev/godot_tool.py test`, and `capture_run.gd` in `class-select` mode.
- **Risks / rollback:** Revert the slice to restore immediate Sword startup. Session unlocks reset when the application closes.
- **Evidence:** See [EVIDENCE](EVIDENCE.md).
- **Next action:** C4 connects the results, receipt and reward preview to Class Select.
