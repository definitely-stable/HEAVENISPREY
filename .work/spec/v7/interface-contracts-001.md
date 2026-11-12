# INTERFACE-CONTRACTS-001 — 12 критических интерфейсов до runtime

- **ID:** INTERFACE-CONTRACTS-001
- **Статус:** PROPOSAL. Сводит в одно место границы, уже описанные в принятых ADR и v7-спецификациях, и называет недостающее. Не утверждает новые игровые правила, баланс или сцены; при расхождении действует первоисточник из колонки «Канон».
- **Дата:** 2026-11-12 · **Связь:** [SYSTEM_BINDING](../../development/SYSTEM_BINDING.md) (система → интерфейс → проверка) · [реестр пробелов](../../tooling/system_binding.json)
- **Слои:** `core` (данные и типы) · `simulation` (детерминированный мир, без Godot presentation) · `meta` (профиль, сохранения, награды) · `presentation` (только чтение). Граница simulation/presentation — [ADR-002](../../decisions/ADR-002-combat.md) и [s26 §26.1](../core/s26.md).

## Общие инварианты

1. Simulation не читает узлы сцены, аудио, локализацию и настройки отображения; presentation не пишет в simulation.
2. Все ID стабильны и версионированы ([ADR-005](../../decisions/ADR-005-config-contract.md), [ADR-006](../../decisions/ADR-006-content-catalog.md)); случайность только из именованных seeded-потоков.
3. Любая награда и списание идемпотентны по `run_uid` / `reward_event_id` / `event_uid`.
4. Ошибка восстановления или несовпадение версии — fail-closed с диагностикой, без «тихого» дефолта.

## Контракты

| ID | Интерфейс | Слой | Ответственность и инварианты | Канон | Статическая проверка сейчас | Чего не хватает |
|---|---|---|---|---|---|---|
| IC-01 | `ContentRegistry` | core | v7 → проверенные типизированные defs → сгенерированные runtime-артефакты; canonical digest и parity; никаких ручных чисел в `.tres` | [content-registry-contract](content-registry-contract.md), [ADR-006](../../decisions/ADR-006-content-catalog.md) | `validate_content.py`, `content_impact.py` | генератор (GAP-REGISTRY-GEN), валидатор `localization_context.json` / `settings.example.cfg` (GAP-SCHEMA-COVERAGE) |
| IC-02 | `RunRulesSnapshot` | core | неизменяемые class/stage/difficulty/modes/seed + версии алгоритмов → `RulesHash`; меняется только новым забегом | [save-contract-001](save-contract-001.md), [ADR-005](../../decisions/ADR-005-config-contract.md), [modes](modes-and-compatibility.md) | `validate_save_contract_proposal.py` | список версий алгоритмов фиксируется в P0-00 |
| IC-03 | `PlayerCommand` | simulation | ввод нормализуется к принятому тику; во время паузы UI-ввод не становится игровым событием | [ADR-002](../../decisions/ADR-002-combat.md), [bot-acceptance](bot-acceptance.md) | bot-сценарии в `validate_content.py` | тип команды и квантование направления (P0-01) |
| IC-04 | `RunEvent` | simulation | `run_uid`, `event_uid`, tick, phase, sequence, emitter UID/generation, origin ID, typed payload; батч не пересекает тики | [game-arch-00](game-arch-00-run-orchestration.md) | `validate_run_loop_proposal.py` (cross-tick батч отклоняется) | приоритет событий одного тика (GAP-PRECEDENCE) |
| IC-05 | `WorldState` / `CombatKernel` | simulation | единственный источник попаданий, здоровья, смерти и статусов; VFX не наносят урон | [ADR-002](../../decisions/ADR-002-combat.md), [s26](../core/s26.md), [enemy-threat](enemy-threat-contract.md) | только контракт | реализация и golden tests (P0-01, GAP-PY-GD-PARITY) |
| IC-06 | `AutoCastScheduler` / `Targeting` / `EffectEngine` | simulation | детерминированный порядок, конечность цепочек, provenance урона (DoT, summon, chain, zone) | [build-skill-architecture](build-skill-architecture-proposal.md), [type contract](build-skill-type-contract.md) | `validate_build_proposal.py` | типизированные EffectOp/TargetingPolicy/StatusStackPolicy/ProcOrigin/ProcBudget — предложения (GAP-ARCH-04) |
| IC-07 | `BuildTransaction` | simulation | ожидаемая ревизия, атомарное получение/трансформация, без частичной мутации | [build-skill-architecture](build-skill-architecture-proposal.md), [game-arch-00](game-arch-00-run-orchestration.md) | `validate_build_proposal.py`, `validate_run_loop_proposal.py` | открытые решения BLD (GAP-BLD-OPEN), достижимость рецептов (GAP-ARCH-02) |
| IC-08 | `ChoiceCoordinator` / `DraftState` | simulation | очередь выборов, допустимые предложения, курсор RNG, exactly-once Select/Skip/Reroll/Banish/Lock | [choice-viewmodel-001](choice-viewmodel-001.md), [draft-contract-002](draft-contract-002.md) | `validate_choice_viewmodel_proposal.py`, `validate_draft_contract_proposal.py`, `validate_choice_bridge_proposal.py` | сохранение руки и курсора в SaveEnvelope (GAP-CHOICE-SAVE) |
| IC-09 | `XP / Loot / SourceLedger` | simulation | сохранение стоимости, заявка источника, без двойной выплаты; доверенный манифест источников | [game-arch-01](game-arch-01-xp-pickups.md) | `validate_run_loop_proposal.py` | имя `SourceLedger` вводится этим документом как обобщение manifest из game-arch-01 |
| IC-10 | `SaveEnvelope` / `Replay` | meta | версии, content/rules hash, все RNG-потоки, восстановление, fail-closed миграция; replay воспроизводит хеш событий | [save-contract-001](save-contract-001.md), [ADR-002](../../decisions/ADR-002-combat.md) | `validate_save_contract_proposal.py` | draft-состояние (GAP-CHOICE-SAVE), parity Python↔Godot (GAP-PY-GD-PARITY) |
| IC-11 | `RewardSettlement` | meta | один раз на забег по `run_uid` / `reward_event_id`; поздние валюты не выплачиваются дважды | [reward_contract.json](../../config/v7/reward_contract.json), [economy](economy-and-talent-sinks.md), [game-arch-00](game-arch-00-run-orchestration.md) | `validate_content.py`, `tests/test_design_contracts.py` | специальные награды и POI (GAP-SPECIAL-REWARDS) |
| IC-12 | `PresentationBridge` | presentation | read-only проекции и семантические VFX/audio cue; визуальные настройки не меняют симуляцию; danger-layer нельзя скрыть | [game-arch-00](game-arch-00-run-orchestration.md), [s15](../core/s15.md), [PLAYABILITY_GATES](../../guides/PLAYABILITY_GATES.md) | косвенно: ChoiceViewModel | snapshot-тесты читаемости после P0-00 |

## Порядок закрытия (по зависимостям, без runtime)

IC-08 + IC-10 (CHOICE-SAVE-002) → IC-07 (ARCH-02) → IC-06 (ARCH-04) → IC-04 (GAME-ARCH-05: приоритеты одного тика) → IC-01 генератор, IC-03, IC-05, IC-12 — только после разрешения P0-00 (см. [RUNTIME_BOOTSTRAP_PLAN](../../development/RUNTIME_BOOTSTRAP_PLAN.md)).
