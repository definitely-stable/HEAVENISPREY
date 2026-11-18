# TASK_SPEC · P0-02-C1

- **Status:** IN_PROGRESS
- **Goal:** Build the authoritative class and seed snapshot before starting the default sword run.
- **Boundaries:** RunView, P0Tuning, the in-memory profile stub and their callers. Chain, class selection and reward receipts follow in C2–C4.
- **Inputs:** [ADR-012 §§4,9](../../decisions/ADR-012-p0-02-classes-run-loop.md) and [ADR-007](../../decisions/ADR-007-runtime-bootstrap.md).
- **Files allowed:** game/presentation/run, direct callers and integration tests under game/tests, CURRENT_STATE and SYSTEM_BINDING.
- **Dependencies:** Godot 4.7.2, valid runtime ContentRegistry, arena 07.
- **Contracts:** RunView creates a RunRulesSnapshot with eligibility and takes the seed from Crypto unless explicitly supplied. P0Tuning uses the validated class, stage and seed from the snapshot. No simulation format changes.
- **Acceptance:** Sword accepts the largest canonical uint64 seed. A locked class or malformed seed preserves the previous run. The same sword journal has the existing world and log digests.
- **Test commands:** python scripts/validate_work.py, python -m unittest discover -s tests -v, Python reference vector checks and the pinned Godot import and GUT suite.
- **Evidence:** Start integration coverage verifies accepted and rejected seeds and closed-class eligibility. Tests use the pinned Godot 4.7.2 engine and unchanged sword fixtures.
- **Risk / rollback:** Revert this isolated runtime setup and caller migration.
- **Next action:** C2.
