# TASK_SPEC · P0-02-C6

- **Status:** IN_PROGRESS.
- **Goal:** release export for Windows x86_64 and Linux x86_64 and bit-exact replay of both classes outside the editor.
- **Inputs:** ADR-012 §8, RUNTIME_BOOTSTRAP_PLAN §4, toolchain lock, C5 seed 101 traces.
- **Scope:** export presets, pinned template extraction, build workflow, headless explicit replay entry. Save/settlement, signing and publishing installers are outside the slice.
- **Contracts:** existing command journal schema and simulation schema, trace digests as authored by the Python oracle. Export CLI consumes the two C5 fixtures without rebaking expected digests. Artifacts identify the tested commit.
- **Acceptance:** strict SHA-512 template validation; native smoke on Windows and Linux, each verifying sword and thunder final digests and rejecting a corrupted trace. Ordinary build launch uses the existing game scene.
- **Tests:** `python scripts/validate_toolchain.py`, regular design/GUT CI, build-artifacts workflow on both platforms.
- **Rollback:** revert the export entry and workflow. Default desktop gameplay runs through RunView.

## Evidence

On 2026-11-18 the pinned local Windows build opened the ordinary game scene and verified both class replays at tick 18000. Native Linux passed the same positive and corrupted-digest controls in GitHub run 44347713728. Windows in that run passed the replay step, then the Bash tar command misread the drive letter as a remote host; packaging now uses Python's cross-platform tarfile command.

- Sword seed 101: `0365b3398c345a42f29105b23221fb0049e01baa089c7ca6cb2d3a897bd018b1`
- Thunder seed 101: `dddbeec8a7b58ffe033ba7be58d48ab7c53e6cacafaa09879e9d6396328db804`
