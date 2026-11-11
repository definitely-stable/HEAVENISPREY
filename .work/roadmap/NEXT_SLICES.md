# Следующие рабочие срезы

## Текущая фаза — ТОЛЬКО архитектура (2026-11-11)

По текущему решению пользователя **не создавать игру, Godot runtime, сцены или игровые ассеты**. Архитектуру нужно довести до содержательных схем, валидаторов, отрицательных фикстур и эффективного контентного workflow. Следующие задачи — ПРОЕКТНЫЕ ПРЕДЛОЖЕНИЯ, а не подтверждённые реализационные результаты.

| Architecture slice | Предмет | Статическая приёмка |
|---|---|---|
| ARCH-00 | Решения и реестр открытых вопросов для [BUILD-SKILL-001](../spec/v7/build-skill-architecture-proposal.md) | Нет неявных противоречащих политик |
| ARCH-01 | [Контракт типов](../spec/v7/build-skill-type-contract.md), [FLEXIBILITY-FIRST](../spec/v7/flexibility-first-build-policies.md), архитектурные фикстуры | Параметризованные слоты/ранги, конечные циклические реакции, негативные тесты; **полные формальные схемы ещё открыты** |
| ARCH-02 | Эволюции, Union, Gift, меридианы | Positive witness и negative counterexamples на граф рецептов |
| ARCH-03 | DraftService: eligibility, rarity, fallback, RNG streams | Детерминированные списки допустимых предложений |
| ARCH-04 | Реакции, Skill Chain, Multicast и static proc budget | Формально ограниченные цепочки без неявного discard |
| ARCH-05 | [Авторский конвейер](../guides/CONTENT_AUTHORING_ACCELERATOR.md), traceability, impact graph, арт-паспорт | Никакого второго источника истины; проверяемые документы |

### Foundation gates — 2026 best practices / research, **только архитектура**

[FOUNDATION-2026](../spec/v7/foundation-research-2026.md): 15 приоритизированных требований (детерминированный replay, схемы/версии, источники эффектов, модельные/property tests, UX, будущее profiling, AI-agent workflow) и [машинный реестр](../proposals/foundation-2026/README.md). Этот срез **не начинает** ECS, Godot runtime, RL/PCG или GDExtension. Конкретные технологии производительности и баланс выбираются по будущим измерениям.

| Foundation Slice | Архитектурный результат | Статический gate |
|---|---|---|
| FOUNDATION-2026 | Research-to-project decision map + dependency DAG + Metamorphic/negative fixtures | Evidence/source refs и положительные/отрицательные property tests; без утверждения игрового FPS |
| SAVE-CONTRACT-001 | [Контракт и статическая проверка](../spec/v7/save-contract-001.md): версии, RulesHash, RNG policy, восстановление очереди и synthetic RunBuild | Reference JSON roundtrip, partial choice resume, v0 header migration, negative tests; **не настоящий Godot Save/Replay** |
| CHOICE-VIEWMODEL-001 | [Контракт, статический hand, Focus, Reroll/Banish/Lock](../spec/v7/choice-viewmodel-001.md) | Проверяемые факты, no-charge no-alternative reroll, overlay replay, Select/Skip exactly-once; **не UI/runtime** |
| DRAFT-CONTRACT-002 | [Версионированная RNG и драфт](../spec/v7/draft-contract-002.md): run-scoped bans, soft pity, anti-brick | Static seeded/rejection tests, 2-earned-choice replay/overlay; **не утверждённый runtime RNG** |
| CHOICE-SAVE-002 | Интеграция draft hand в строго типизированный SAVE envelope | Schema migration, draw cursor parity, durable Focus и backup |
| ARCH-02 | Граф достижимости N→M рецептов и развитие после max rank | Witness paths или объяснимые недостижимые рецепты |

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
| GAME-ARCH-02 | Драматургия волн, сценарии боссов и stage topology | Честные окна угроз, достижимые цели, определённые reward gates |
| GAME-ARCH-03 | Предзабеговые руны/обеты и варианты стартовых техник | Корректный RunRulesHash, совместимость с классом и v7 прогрессией |
| GAME-ARCH-04 | Источники специальных наград и точки интереса | Однократность награды, достижимость POI и event sequencing |
| GAME-ARCH-05 | Режимы, качественные модификаторы и завершение/продолжение забега | Совместимость с существующими late-game валютами и режимами |
| GAME-ARCH-06 | Атрибуция DoT/суммонов/зон и контракты UX | Negative fixtures для совместимости баффов, паузы, hitbox |
| GAME-ARCH-07/08 | Канон техник, подсказки, гипотезы экспериментов | Не дублировать v7 определения; проверяемые исследования |

**Переход к P0-00 допустим только после отдельного решения о начале разработки игры.** Старый план ниже сохраняется как будущий вариант, не текущий разрешённый шаг.

## Будущие исполняемые срезы — ОТЛОЖЕНЫ

| Slice | Результат | Acceptance |
|---|---|---|
| P0-00 | Godot 4.7.2 2D bootstrap, typed GDScript, GUT, ContentRegistry v7 | headless import Windows/Linux + canonical content digest |
| P0-01 | Combat Kernel, PlayerCommand, RNG | golden tests для попаданий, DoT, replay |
| P0-01E | Два простых обычных врага (Мертвец Инь + Волк), общие EnemyDef/AttackDef, один базовый состав волны | Godot spawn/damage/replay tests, нормальные tier, read-only content ID |
| P0-02E | Телеграфируемые атаки богомола/фонаря, отложенная печать и мягкие корни | Пройденные bot-сценарии, нет неизбежных ловушек и скрытых ударов |
| P0-02 | Два класса, 5-минутный забег, RU/EN | игровой цикл и экран наград |
| P0-03 | Сохранения, Spirit Stones, талант секты | exactly-once payout, бесплатный respec |
| M1-00 | Карты, боссы, класс-мастерство, unlock graph | Небесная кара достижима, но не автоматически |
| M1-01 | Dao Seals, Небесная кара, Бездна Дао | нет поздней валюты на ранних сложностях |
| M1-02 | ProgressionBot и StressBot | воспроизводимые серии прогонов, фарм-эксплойты |
| M2 | 20–30 минут, 4 архетипа, полный UX | человеческие playtest и CI |

**Текущий этап — только документационная инфраструктура. Игровой код ещё не написан.**
