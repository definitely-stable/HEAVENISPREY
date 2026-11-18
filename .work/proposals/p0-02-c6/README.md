# TASK_SPEC · P0-02-C6

- **Status:** IN_PROGRESS.
- **Goal:** release export for Windows x86_64 and Linux x86_64 and bit-exact replay of both classes outside the editor.
- **Inputs:** ADR-012 §8, RUNTIME_BOOTSTRAP_PLAN §4, toolchain lock, C5 seed 101 traces.
- **Scope:** export presets, pinned template extraction, build workflow, headless explicit replay entry. Save/settlement, signing and publishing installers are outside the slice.
- **Contracts:** existing command journal schema and simulation schema, trace digests as authored by the Python oracle. Export CLI consumes the two C5 fixtures without rebaking expected digests. Artifacts identify the tested commit.
- **Acceptance:** strict SHA-512 template validation; native smoke on Windows and Linux, each verifying sword and thunder final digests and rejecting a corrupted trace. Ordinary build launch uses the existing game scene.
- **Tests:** `python scripts/validate_toolchain.py`, regular design/GUT CI, build-artifacts workflow on both platforms.
- **Rollback:** revert the export entry and workflow. Default desktop gameplay runs through RunView.
