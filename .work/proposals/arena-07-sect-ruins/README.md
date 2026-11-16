# Арена 07 «Руины секты Юнхэ»: сетка по REF-033

Проектное предложение [ADR-015](../../decisions/ADR-015-arena-07-sect-ruins.md). С среза А1 сетка — арена игры: стены, поле потока и спавн в симуляции (ADR-015 §8).

- [`jade_grove.json`](../../../game/content/arena/jade_grove.json) — сетка 76 × 71 клеток по 48 px (с среза А1 лежит в контенте игры), её рисует [`tools/content/arena_layout.py`](../../../tools/content/arena_layout.py). Руками не правится.
- Проверка: `python tools/content/arena_layout.py --check` и `python scripts/validate_arena_layout.py`.
- Легенда и правила — в ADR-015 §2–§3.
