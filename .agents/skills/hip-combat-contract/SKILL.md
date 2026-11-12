---
name: hip-combat-contract
description: Check or design HEAVEN IS PREY combat semantics - auto-cast scheduling, targeting, hits, DoT, statuses, procs, multicast, damage provenance, fixed tick and event order. Use when a change touches Combat, AutoCast, Status, Enemy attacks or Boss patterns (бой, автокаст, таргетинг, статусы, проки, мультикаст, порядок событий). Not for content balance numbers.
---

# hip-combat-contract — детерминированная боевая семантика

## Use when
- Новое/изменённое правило попаданий, автоатаки, статуса, реакции, proc chain, мультикаста, атаки врага/босса.
- Вопрос «кто источник урона» (DoT, summon, zone, chain) или «в каком порядке события одного тика».

## Not for
- Подбор чисел баланса (это гипотезы в `.work/config/v7`, правятся через [hip-build-authoring](../hip-build-authoring/SKILL.md)).

## Canonical sources
- [ADR-002 combat kernel](../../../.work/decisions/ADR-002-combat.md) — симуляция независима от presentation.
- [Семантика v5](../../../.work/spec/v5/v5_semantics.md) · [Event budget](../../../.work/spec/v5/v5_budget.md) · [Scheduler s06](../../../.work/spec/core/s06.md)
- [Run event order GAME-ARCH-00](../../../.work/spec/v7/game-arch-00-run-orchestration.md) · [FOUNDATION-2026](../../../.work/spec/v7/foundation-research-2026.md)
- [Типы build/effect ARCH-01](../../../.work/spec/v7/build-skill-type-contract.md) · [FLEXIBILITY-FIRST](../../../.work/spec/v7/flexibility-first-build-policies.md)
- [Контракт угроз врагов](../../../.work/spec/v7/enemy-threat-contract.md)

## Procedure
1. Назвать затронутые сущности по stable ID и слой: simulation / presentation (VFX не меняет урон, ADR-002).
2. Проверить инварианты: фиксированный тик, явный порядок фаз, tie-break таргетинга, конечность proc-цепочек, provenance (`root_cast_uid`, `parent_uid`, owner), отсутствие скрытого discard попаданий.
3. Лимиты (слоты, мультикаст, глубина цепочек) — конфигурируемые policy, не hardcoded ceiling.
4. Добавить fixture/тест: позитивный witness + негативный контрпример (бесконечный цикл, двойной урон, потерянный источник).
5. Если меняется принятое правило ADR-002 — остановиться и предложить ADR amendment.

## Acceptance
- `python scripts/validate_build_proposal.py`, `python scripts/validate_run_loop_proposal.py`, `python -m unittest discover -s tests` зелёные; новый негативный тест падает на некорректной фикстуре.

## Evidence output
Список инвариантов + ссылки на тесты/фикстуры; явно «не доказывает Godot runtime/FPS».
