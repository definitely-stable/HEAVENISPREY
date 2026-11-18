# TASK_SPEC: P0-02 C4

- **Status:** APPROVED by [ADR-012 §5–10](../../decisions/ADR-012-p0-02-classes-run-loop.md).
- **Goal:** Complete Class Select → Running / Choice → Results → Rewards → Class Select. Keep one immutable, in-memory receipt per run.
- **Non-goals:** Persistent profile, wallet credit, extra rewards, bot benchmarks, export and combat HUD or art changes.
- **Inputs:** ADR-012 and the v7 milestone, reward, difficulty and mode catalogs.
- **Files allowed:** RunView flow, Run Results and Run Rewards screens, session profile and receipt/preview logic, locale resources, capture mode, paired Python/Godot fixtures and integration tests, evidence.
- **Dependencies:** C3 class selection and class-aware snapshots.
- **Contracts:** Receipt schema 1, `hip-reward-preview-v1`, `run_uid` as 32 lowercase hex, and `reward.minute3:<run_uid>:0`. Terminal stats bind the final world and log digests. The session profile grants unlocks from terminal receipts.
- **Acceptance:** The flow works on keyboard and controller actions with the ADR arm delays. Restart during a run or choice produces one abandoned receipt and starts the same class. Rearming, repeated finalization and reopening screens preserve receipt count and values. A qualifying finish message appears on both screens. Python and GDScript agree on ADR milestone and multiplier vectors.
- **Tests:** `python scripts/dev/local_ci.py`, `python scripts/dev/godot_tool.py test`, and RU/EN captures of Results and Rewards.
- **Risks / rollback:** Revert the slice for the C3 flow. All receipts and grants are session memory.
- **Evidence:** See [EVIDENCE](EVIDENCE.md).
- **Next action:** C5 checks Thunder bot acceptance.
