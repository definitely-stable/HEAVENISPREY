# Арена 07 «Руины секты Юнхэ»: сетка по REF-033

Проектное предложение [ADR-015](../../decisions/ADR-015-arena-07-sect-ruins.md). Игры не меняет. Арена в симуляции пока прямоугольник P0.

- [`topology.json`](topology.json) — сетка 76 × 71 клеток по 48 px, её рисует [`tools/content/arena_layout.py`](../../../tools/content/arena_layout.py). Руками не правится.
- Проверка: `python tools/content/arena_layout.py --check` и `python scripts/validate_arena_layout.py`.
- Легенда и правила — в ADR-015 §2–§3.
