# TASK_SPEC · ARENA-OPENING-PROBE

- **Status:** VERIFIED experiment on `6e7bed6` (2026-11-18). Recommendation: keep A.
- **Goal:** compare early pressure and bridge retreat for the three approved spawn experiments on arena 07.
- **Scope:** tooling-only candidate configs, seeded bot telemetry, one fixed bridge replay, captured Godot evidence. Live balance changes require separate manual acceptance and PR.
- **Files allowed:** this proposal, `tools/content/sim_bots.py`, the opening probe and its tests, `game/tools/capture_opening.gd`, and `CURRENT_STATE`.
- **Dependencies:** Godot 4.7.2, the existing Python/Godot simulation and command log, the ADR-015 terrain validator and the current bot fixtures.
- **Contracts:** A uses the unmodified config. B uses 78000 milli-ticks per spawn. C swaps S [41, 14] with floor [25, 50]. The route starts at 600 ticks, visits [27, 47], waits 180 ticks and returns to [8, 63]. Both probe artifacts use schema version 1. Seed, policies and simulation behavior stay reproducible.
- **Acceptance:** full 101–132 survey for four existing policies; first approach, damage, level, terminal HP and censoring recorded. Enabling observation preserves log and world digests. Route has exact Python/Godot parity, including when enemies are present. Losing bot or route metrics disqualifies candidates under the agreed thresholds.
- **Risk/rollback:** experiment results apply only to the tested arena, policies and seeds. Reverting the tooling slice affects only diagnostics.
- **Tests:** `python -m unittest discover -s tests -p test_arena_opening_probe.py -v`, `python scripts/validate_arena_layout.py`, `python scripts/validate_work.py`, full Python discovery, Godot replay.
- **Next action:** if the opening is revisited, design a change limited to the first roster window and evaluate it against both time ranges.

## Evidence

Run from the repository root on a fixed checkout:

```text
python tools/content/arena_opening_probe.py .tools/arena-opening --jobs 3
python tools/content/arena_opening_probe.py .tools/arena-opening --jobs 2 --full B
godot --headless --path game -s res://tools/capture_opening.gd -- .tools/arena-opening/bridge.json
godot --headless --path game -s res://tools/capture_opening.gd -- .tools/arena-opening/full-replay-B.json
godot --path game --resolution 1280x720 -s res://tools/capture_opening.gd -- .tools/arena-opening/bridge.json .tools/arena-opening/frames 117
```

Pass absolute paths to Godot if the launcher changes its working directory. The full survey covers 384 opening runs. Times are seconds. Approach is the idle median, level is the `kiter_upgrades` median, first damage is the earliest across all four policies, and bridge returns are out of three fixed route seeds.

| Variant | Approach | First damage | Level 2 | Median HP at 90 s¹ | Bridge returns |
|---|---:|---:|---:|---:|---:|
| A | 25.28 | 11.62 | 12.04 | 100 | 2 |
| B | 21.25 | 11.38 | 11.57 | 100 | 2 |
| C | 22.48 | 11.40 | 10.63 | 100 | 1 |

¹ `kiter_upgrades`. `survey.json` includes the raw observations, censoring counts, p10 damage time and medians for every policy. C uses the same row order for spawn points as the live arena parser.

- Nine bridge journals reproduced the Python digest in Godot 4.7.2. Routes A and B returned on 101 and 117. C returned on 101. On 117 it reached the courtyard, then died at tick 1091 during the wait before the return. Godot captured all three seeds at 1280×720.
- B reached the early target: approach was 16% sooner and the bridge return count matched A. The five-minute survey covered another 128 runs, with 32/32 wins for `kiter_upgrades`. B failed all three existing lower median survival bounds for the baseline bots. Idle: 93.35 s vs 115 s minimum. Circle: 52.26 s vs 65 s. Kiter: 171.89 s vs 210 s. At 90 s the idle bot's median HP was 6.8 in B vs 54.5 in A.
- The full B replay on seed 101 reached tick 18000 in Godot and matched the Python digest `7fed4d1522f4f658e5da0c61fc414d7906a6b983fd802d5bd696fad6d5917452`. Local CI completed with 36 passing and 4 documented toolchain skips.
- The diagnostic config retained the spawn-distance setting and threat caps. C retained the terrain coverage and passed the arena validation. A remains the live configuration. No candidate reached the manual acceptance step.
