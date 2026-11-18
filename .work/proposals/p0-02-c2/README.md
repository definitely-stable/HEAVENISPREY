# TASK_SPEC · P0-02-C2

- **Status:** IN_PROGRESS
- **Goal:** Simulate the Daoist's instantaneous chain skill and class-specific upgrades identically in Python and Godot.
- **Boundaries:** The combat form, configuration, state digest, upgrade cards and 0.12-second lightning primitive. C3 adds class selection, C5 adds Thunder bots and stress acceptance.
- **Inputs:** [ADR-012 §§1–3,7–9](../../decisions/ADR-012-p0-02-classes-run-loop.md) and [ADR-008](../../decisions/ADR-008-sim-numeric-model.md).
- **Files allowed:** core rules and simulation, P0 tuning and presentation effects/upgrade cards, runtime RU/EN generation, Python simulation and reference fixtures, related tests, binding and state.
- **Dependencies:** C1, Godot 4.7.2 and canonical ContentRegistry.
- **Contracts:** Simulation schema 14, at most eight distinct UIDs, distance and slot tie-break, cast damage snapshot, two ASCII-sorted tables.
- **Acceptance:** The three Thunder traces and targeted vectors match Python and GDScript. Tests catch wrong origin, duplicate hits, strict boundaries, UID sorting, rank read during jumps and cooldown consumption without a target. Thunder does more damage in 600 ticks to 20 clustered enemies and takes longer to kill one. Sword trace state metrics and bot anchors retain the C1 values.
- **Test commands:** python scripts/validate_work.py, python scripts/validate_effect_chain_proposal.py, python -m unittest discover -s tests -v, both simulation fixture generators in check mode, pinned Godot import and GUT.
- **Evidence:** The first targeted Godot 4.7.2 run passed 28 tests and 158 assertions. Python tests cover all four Thunder ranks in the cycle trace and directly check the chain role in both frozen-enemy fixtures. C1's 48 core traces and four bot anchors retain all comparison fields except world hashes.
- **Risk / rollback:** Version 13 digests cannot be compared directly with version 14. Revert C2 together with its fixture regeneration.
- **Next action:** C3.
