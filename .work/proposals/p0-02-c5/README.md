# TASK_SPEC · P0-02-C5

- **Status:** IN_PROGRESS.
- **Goal:** compare both P0-02 classes under existing bot policies and verify thunder in the full five-minute run.
- **Inputs:** ADR-012 §8, C2 chain rules, C4 reward preview, arena 07 and the bot fixtures.
- **Scope:** class-parameterized Python bot, deterministic fixtures and parity tests, thunder stress at six and eight targets.
- **Contracts:** bot policy version 4 and fixture schema 6. Sword trace IDs stay stable. The thunder trace uses the canonical log and simulation schema.
- **Acceptance:** exact seed-101 replays for both classes; at least 28/32 thunder runs finish. Measure p95 tick time for both thunder stress cases.
- **Tests:** `python tools/content/sim_bots.py --check`, Python bot tests, Godot replay and `sim_bench.gd`.
- **Rollback:** revert bot and fixture changes independently of runtime.

## Tuning evidence

Measured with the same `kiter_upgrades` and seeds 101–132. The baseline damage of 8000 won 14/32. At 11000 and 12000 it won 23/32. At 12500 and 12750 it won 24/32. At 12800 and 13000 it won 32/32. 12800 is the smallest tested passing value. Python and GDScript use that value as P0 tuning and keep the original 65-tick cooldown, four targets and three-cell reach.

The Windows stress harness kept exactly 150 live enemies through all 3000 measured ticks and reached both intended chain lengths. Tick p95 was 5.256 ms for six targets and 5.768 ms for eight. These results exceed the 4 ms gate on the loaded test machine. A field-cache experiment reproduced the same digests after correction but did not improve the measured timing; the prototype was reverted. A successful uncontended measure is still required.

```text
python tools/content/sim_bots.py --check --jobs 4
godot --headless --path game -s res://tests/perf/sim_bench.gd -- --thunder
```
