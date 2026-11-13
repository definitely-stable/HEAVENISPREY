# Следующие рабочие срезы

## Текущая фаза — ТОЛЬКО архитектура (2026-11-11)

По текущему решению пользователя **не создавать игру, Godot runtime, сцены или игровые ассеты**. Архитектуру нужно довести до содержательных схем, валидаторов, отрицательных фикстур и эффективного контентного workflow. Следующие задачи — ПРОЕКТНЫЕ ПРЕДЛОЖЕНИЯ, а не подтверждённые реализационные результаты.

| Architecture slice | Предмет | Статическая приёмка |
|---|---|---|
| ARCH-00 | Решения и реестр открытых вопросов для [BUILD-SKILL-001](../spec/v7/build-skill-architecture-proposal.md) | Нет неявных противоречащих политик |
| ARCH-01 | [Контракт типов](../spec/v7/build-skill-type-contract.md), [FLEXIBILITY-FIRST](../spec/v7/flexibility-first-build-policies.md), архитектурные фикстуры | Параметризованные слоты/ранги, конечные циклические реакции, негативные тесты; **полные формальные схемы ещё открыты** |
| ARCH-02 | [Эволюции, Union, Gift, меридианы](../spec/v7/arch-02-recipe-graph.md) | **Design-оракул готов:** witness с replay или одна из 6 причин недостижимости, 17 тестов |
| ARCH-03 | DraftService: eligibility, rarity, fallback, RNG streams | Детерминированные списки допустимых предложений |
| ARCH-04 | [Реакции, Skill Chain, Multicast и static proc budget](../spec/v7/arch-04-effect-chains.md) | **Design-оракул готов:** 5 типов op, provenance, 3 способа доказать конечность, вердикты профиля без discard, 18 тестов |
| ARCH-05 | [Авторский конвейер](../guides/CONTENT_AUTHORING_ACCELERATOR.md), traceability, impact graph, арт-паспорт | Никакого второго источника истины; проверяемые документы |

### Подготовка инженерной среды — DEV-ENV (2026-11-12, без runtime)

[DEV-ENV-001](../spec/v7/dev-env-001-toolchain.md) делает воспроизводимыми инструменты, которые понадобятся P0-00, не создавая игру. Подсрезы выполняются по зависимостям и не смешиваются с runtime.

| Slice | Результат | Gate |
|---|---|---|
| DEV-ENV-001 | Pinned toolchain lock, установка Godot 4.7.2 с SHA-512, headless smoke, doctor, hosted CI | validate_toolchain, unit tests, Ubuntu + Windows smoke |
| DEV-ENV-002 | Агентские адаптеры и skills без второй системы инструкций | Проверяемые триггеры, ссылки на `.work`, pin/лицензия сторонних skills |
| DEV-ENV-003 | MCP-стек и аудит Godot MCP (интеграция только с P0-00) | Без секретов, pin версий, editor MCP выключен до runtime |
| DEV-ENV-004 | Связь контрактов/skills с системами игры, недостающие контракты | Каждая система имеет контракт, gate и маршрут |
| DEV-ENV-005 | Readiness audit, tooling matrix, GO/NO-GO пакет P0-00 | `tooling_matrix.py validate`; P0-00 — **GO** с 2026-11-12 (решение делегировано, [READINESS_AUDIT §5](../development/READINESS_AUDIT.md)) |
| ART-REF-001 | Каталог референсов `ref/` | Все файлы учтены; статус «референс, не production» |

### Foundation gates — 2026 best practices / research, **только архитектура**

[FOUNDATION-2026](../spec/v7/foundation-research-2026.md): 15 приоритизированных требований (детерминированный replay, схемы/версии, источники эффектов, модельные/property tests, UX, будущее profiling, AI-agent workflow) и [машинный реестр](../proposals/foundation-2026/README.md). Этот срез **не начинает** ECS, Godot runtime, RL/PCG или GDExtension. Конкретные технологии производительности и баланс выбираются по будущим измерениям.

| Foundation Slice | Архитектурный результат | Статический gate |
|---|---|---|
| FOUNDATION-2026 | Research-to-project decision map + dependency DAG + Metamorphic/negative fixtures | Evidence/source refs и положительные/отрицательные property tests; без утверждения игрового FPS |
| SAVE-CONTRACT-001 | [Контракт и статическая проверка](../spec/v7/save-contract-001.md): версии, RulesHash, RNG policy, восстановление очереди и synthetic RunBuild | Reference JSON roundtrip, partial choice resume, v0 header migration, negative tests; **не настоящий Godot Save/Replay** |
| CHOICE-VIEWMODEL-001 | [Контракт, статический hand, Focus, Reroll/Banish/Lock](../spec/v7/choice-viewmodel-001.md) | Проверяемые факты, no-charge no-alternative reroll, overlay replay, Select/Skip exactly-once; **не UI/runtime** |
| DRAFT-CONTRACT-002 | [Версионированная RNG и драфт](../spec/v7/draft-contract-002.md): run-scoped bans, soft pity, anti-brick | Static seeded/rejection tests, 2-earned-choice replay/overlay; **не утверждённый runtime RNG** |
| CHOICE-SAVE-002 | [SaveEnvelope v2](../spec/v7/choice-save-002.md): run + build + draft в одной записи, один offers cursor | **Design-оракул готов:** migration v1→v2, cursor parity, focus после загрузки, два слота, 28 тестов |
| ARCH-02 | [Граф достижимости N→M рецептов и развитие после max rank](../spec/v7/arch-02-recipe-graph.md) | **Готово (design):** witness paths или объяснимые недостижимые рецепты |

### Аудит UX и связность существующей архитектуры (октябрь 2026)

[GAME-UX-001](../spec/v7/game-ux-001-oct-2026.md) проверяет не новый контент, а **взаимодействие** уже предложенных систем: выбор, XP, ритуал, билд и интерфейс. В эталонной модели реализованы два режима отображения выбора (Immediate / Bank Levels), безопасная XP-консолидация только для XP, контроль авторитетных source-values и статический cross-layer путь к эволюции. Auto-pick, actual UI/gamepad, реальная лут-экономика и измерения UX остаются design-proposal.

| Slice | Результат | Приёмка без Godot |
|---|---|---|
| GAME-UX-001 | [UX-дизайн выбора и развития](../spec/v7/game-ux-001-oct-2026.md) | Нет потери/повтора наград; UI-пауза отделена от наличия pending choices; независимые проверки cross-layer билда |

### Системный геймплейный аудит — архитектура, НЕ создание игры

[GAMEPLAY-GAP-001](../spec/v7/gameplay-loop-gap-audit.md) выявил недоопределённые связи игрового цикла. Данный раздел **не отменяет** ARCH-01 и не утверждает никакие новые механики/баланс автоматически.

| Slice | Архитектурный результат | Будущая проверка без Godot |
|---|---|---|
| GAME-ARCH-00 | [RunOrchestrator + ChoiceCoordinator](../spec/v7/game-arch-00-run-orchestration.md) | **Эталонная модель** событий, receipt и очереди, отрицательные тесты; приёмка игрового runtime отложена |
| GAME-ARCH-01 | [XP, Drops, Pickups](../spec/v7/game-arch-01-xp-pickups.md) | **Эталонная модель** сохранения стоимости/источников, переполнения XP и уровней; физическая игра не реализована |
| GAME-ARCH-02 | [Драматургия волн, сценарии боссов и stage topology](../spec/v7/game-arch-02-encounters.md) | **Design-оракул готов:** арена, телеграфы 14 атак v7, MIXED slow, паттерн босса с маршрутами ухода, 23 теста |
| GAME-ARCH-03 | Предзабеговые руны/обеты и варианты стартовых техник | Корректный RunRulesHash, совместимость с классом и v7 прогрессией |
| GAME-ARCH-04 | Источники специальных наград и точки интереса | **Базовые проверки в [GAME-ARCH-02 §5](../spec/v7/game-arch-02-encounters.md):** однократность, достижимость POI, порядок событий; остаются каталог POI и виды наград |
| GAME-ARCH-05 | Режимы, качественные модификаторы и завершение/продолжение забега | Совместимость с существующими late-game валютами и режимами |
| GAME-ARCH-06 | Атрибуция DoT/суммонов/зон и контракты UX | Negative fixtures для совместимости баффов, паузы, hitbox |
| GAME-ARCH-07/08 | Канон техник, подсказки, гипотезы экспериментов | Не дублировать v7 определения; проверяемые исследования |

**P0-00 — GO с 2026-11-12** в границах [RUNTIME_BOOTSTRAP_PLAN §3](../development/RUNTIME_BOOTSTRAP_PLAN.md); следующие срезы (P0-01 и далее) — после приёмки P0-00. Таблица ниже — план, а не уже разрешённые шаги.

## Исполняемые срезы (P0-00 — GO, остальные после его приёмки)

| Slice | Результат | Acceptance |
|---|---|---|
| P0-00 | Godot 4.7.2 2D bootstrap, typed GDScript, GUT, ContentRegistry v7 | headless import Windows/Linux + canonical content digest; реализация — [ADR-007](../decisions/ADR-007-runtime-bootstrap.md), workflow `godot-tests.yml` |
| P0-01 | Combat Kernel, PlayerCommand, RNG | golden tests для попаданий, DoT, replay |
| P0-01E | Два простых обычных врага (Мертвец Инь + Волк), общие EnemyDef/AttackDef, один базовый состав волны | Godot spawn/damage/replay tests, нормальные tier, read-only content ID |
| P0-02E | Телеграфируемые атаки богомола/фонаря, отложенная печать и мягкие корни | Пройденные bot-сценарии, нет неизбежных ловушек и скрытых ударов |
| P0-02 | Два класса, 5-минутный забег, RU/EN | игровой цикл и экран наград |
| P0-03 | Сохранения, Spirit Stones, талант секты | exactly-once payout, бесплатный respec |
| M1-00 | Карты, боссы, класс-мастерство, unlock graph | Небесная кара достижима, но не автоматически |
| M1-01 | Dao Seals, Небесная кара, Бездна Дао | нет поздней валюты на ранних сложностях |
| M1-02 | ProgressionBot и StressBot | воспроизводимые серии прогонов, фарм-эксплойты |
| M2 | 20–30 минут, 4 архетипа, полный UX | человеческие playtest и CI |

**Текущий этап — P0-01 в работе:** играбельная placeholder-сцена с детерминированной симуляцией (движение, два обычных врага, контактный урон, смерть героя). Порядок следующих срезов — [ADR-009 §6](../decisions/ADR-009-p0-01-combat-loop.md); актуальное состояние — [CURRENT_STATE](../CURRENT_STATE.md).
