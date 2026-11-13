# Предметная карта HEAVENISPREY

**Начинайте здесь:** выберите домен, прочтите действующее решение, затем максимум несколько связанных разделов. Индексы `s00` и `v6_*` остаются стабильными идентификаторами происхождения, **не** понятными названиями доменов.

| Область | Актуальный вход | Детализация |
|---|---|---|
| **Версионированный weighted draft, RNG, anti-brick, soft pity и постоянные bans** | [DRAFT-CONTRACT-002](../spec/v7/draft-contract-002.md) | [Fixture и проверки](../proposals/draft-contract-002/README.md) |
| **Карточки уровня, Reroll/Banish/Lock, controller focus, объяснение эволюций** | [CHOICE-VIEWMODEL-001](../spec/v7/choice-viewmodel-001.md) | [Reference hand и negative tests](../proposals/choice-viewmodel-001/README.md) |
| **Сохранения, RunRulesHash, Replay, восстановление выбора и миграции** | [SAVE-CONTRACT-001](../spec/v7/save-contract-001.md) | [Эталон и негативные тесты](../proposals/save-contract-001/README.md) · [RunOrchestrator](../spec/v7/game-arch-00-run-orchestration.md) |
| **Фундамент 2026: воспроизводимость, CI, производительность, AI-агенты, UX и исследования** | [FOUNDATION-2026](../spec/v7/foundation-research-2026.md) | [Gates и тесты](../proposals/foundation-2026/README.md) · [Roadmap](../roadmap/NEXT_SLICES.md) |
| **Полный геймплейный цикл, XP, награды, карта, боссы, предзабеговые выборы** | [GAMEPLAY-GAP-001 — аудит](../spec/v7/gameplay-loop-gap-audit.md) · [RunOrchestrator](../spec/v7/game-arch-00-run-orchestration.md) · [XP/Pickups](../spec/v7/game-arch-01-xp-pickups.md) · [UX Октябрь 2026](../spec/v7/game-ux-001-oct-2026.md) | [Волны v7](../config/v7/enemy_rosters.json) · [Объекты карты](../config/v7/stages.json) · [Roadmap](../roadmap/NEXT_SLICES.md) |
| Продукт, игровая цель | [Границы и критерии](../spec/core/s02.md) | [Прогрессия](../spec/v6/v6_classes.md) · [Roadmap](../roadmap/NEXT_SLICES.md) |
| **Бестиарий и поведение обычных врагов** | [13 монстров](../spec/v7/ordinary-enemy-bestiary.md) | [Контракт угроз](../spec/v7/enemy-threat-contract.md) · [Волны](../config/v7/enemy_rosters.json) · [Атаки](../config/v7/enemy_attacks.json) |
| Симуляция, автоатаки и статусы | [ADR-002](../decisions/ADR-002-combat.md) · [ADR-008 числовая модель](../decisions/ADR-008-sim-numeric-model.md) | [Combat](../spec/v5/v5_semantics.md) · [Event budget](../spec/v5/v5_budget.md) |
| **BUILD-SKILL-001: активные/пассивные техники, Powers, эволюции, Union, драфт, культивация** | [Архитектурное предложение](../spec/v7/build-skill-architecture-proposal.md) · [FLEXIBILITY-FIRST](../spec/v7/flexibility-first-build-policies.md) · [Контракт типов](../spec/v7/build-skill-type-contract.md) | новый рецепт — [ARCH-02](../spec/v7/arch-02-recipe-graph.md) · [Контентный pipeline](CONTENT_AUTHORING_ACCELERATOR.md) · [Шаблон техники](../templates/SKILL_SPEC.md) · [Классы v6](../spec/v6/v6_classes.md) |
| Сложности, режимы, награды | [ADR-003](../decisions/ADR-003-late-game.md) | [v7 поздняя прогрессия](../spec/v7/late-game-progression.md) · [Режимы](../spec/v7/modes-and-compatibility.md) |
| Экономика и сохранения | [Экономика v7](../spec/v7/economy-and-talent-sinks.md) | [Data](../config/v7/README.md) · [Сохранения](../spec/core/s20.md) |
| **Визуальные референсы `ref/`: классификация, связь с контентом, готовность** | [Каталог ART-REF-001](../../ref/README.md) | [catalog.json](../../ref/catalog.json) · [Арт-контракт s17](../spec/core/s17.md) |
| Godot 2D, визуализация, арт | [2D rendering](../spec/core/s14.md) | [VFX](../spec/core/s15.md) · [Арты](../spec/v5/v5_assets.md) |
| RU/EN, интерфейс | [Локализация](../spec/v6/v6_i18n.md) | [UX](../spec/v5/v5_ux.md) |
| Автоматическое тестирование | [BOT-QA v7](../spec/v7/bot-acceptance.md) | [Тесты](../spec/v5/v5_tests.md) · [Replay](../spec/core/s13.md) |
| Reverse engineering | [RE pipeline](../spec/core/s23.md) | [RE evidence](../spec/v5/v5_re.md) |
| **AI-агенты: skills `hip-*`, адаптеры клиентов, цикл среза, handoff** | [AGENT_EXECUTION](../development/AGENT_EXECUTION.md) | [Аудит сторонних skills](../development/SKILLS_AUDIT.md) · [AGENT_HANDOFF](../templates/AGENT_HANDOFF.md) |
| **Среда разработки, pinned Godot, doctor, toolchain CI** | [DEV-ENV-001](../spec/v7/dev-env-001-toolchain.md) | [Установка и диагностика](DEV_ENVIRONMENT.md) · [toolchain.lock.json](../tooling/toolchain.lock.json) |
| **MCP-серверы (Context7, GitHub, Godot MCP), примеры конфигураций** | [MCP_REGISTRY](../development/MCP_REGISTRY.md) | [mcp.lock.json](../tooling/mcp.lock.json) · `python scripts/validate_mcp.py` |
| **Проверка «это игра»: game-ness gates, juice, ship gates** | [PLAYABILITY_GATES](PLAYABILITY_GATES.md) | [GAME-UX-001](../spec/v7/game-ux-001-oct-2026.md) |
| **Look-dev, паспорт стиля, сравнение с референсами, карточка ассета** | [ART-BIBLE-001](../spec/v7/art-bible-001.md) · [ART_LOOKDEV](ART_LOOKDEV.md) | [ref/catalog.json](../../ref/catalog.json) · [ASSET_CARD](../templates/ASSET_CARD.md) |
| **Арены, режим «Событие», специализации, экипировка, квесты с референсов (только примеры)** | [REF-EXAMPLES-001](../spec/v7/reference-concept-examples.md) | [ref/catalog.json](../../ref/catalog.json) |
| **Сохранение посреди выбора, offers cursor, миграция сейвов, backup-слот** | [CHOICE-SAVE-002](../spec/v7/choice-save-002.md) | [SAVE-CONTRACT-001](../spec/v7/save-contract-001.md) · [DRAFT-CONTRACT-002](../spec/v7/draft-contract-002.md) |
| **Достижимость эволюций/Union/Gift, рост после max rank, конфликт рецептов** | [ARCH-02](../spec/v7/arch-02-recipe-graph.md) | [ARCH-01](../spec/v7/build-skill-type-contract.md) · [FLEXIBILITY-FIRST](../spec/v7/flexibility-first-build-policies.md) |
| **Типы эффектов, атрибуция урона, конечность цепочек, multicast** | [ARCH-04](../spec/v7/arch-04-effect-chains.md) | [ARCH-01 §7](../spec/v7/build-skill-type-contract.md) · [statuses.json](../config/v7/statuses.json) |
| **Арена, волны, телеграфы, паттерн босса, маршруты ухода, награды алтарей/сундука/босса** | [GAME-ARCH-02](../spec/v7/game-arch-02-encounters.md) | [контракт угроз](../spec/v7/enemy-threat-contract.md) · [GAME-ARCH-00](../spec/v7/game-arch-00-run-orchestration.md) |
| **Какая система к какому контракту, skill и проверке; открытые пробелы** | [SYSTEM_BINDING](../development/SYSTEM_BINDING.md) | [INTERFACE-CONTRACTS-001](../spec/v7/interface-contracts-001.md) · [system_binding.json](../tooling/system_binding.json) |
| **Godot-проект `game/`: generated ContentRegistry, digest, RNG `hip-rng-v1`, `rules_hash`, GUT-тесты** | [ADR-007](../decisions/ADR-007-runtime-bootstrap.md) | [DEV_ENVIRONMENT §2a](DEV_ENVIRONMENT.md) · `game/core/` · `game/tests/` |
| **Готовность среды, блокеры, GO/NO-GO для Godot bootstrap** | [READINESS_AUDIT](../development/READINESS_AUDIT.md) | [RUNTIME_BOOTSTRAP_PLAN](../development/RUNTIME_BOOTSTRAP_PLAN.md) · [TOOLING_MATRIX](../development/TOOLING_MATRIX.md) |
| Инструменты, зависимости, CI | [Стек](../decisions/ADR-001-stack.md) | [Dependency tiers](../spec/core/s21.md) · [CI](../spec/core/s25.md) |

## Контентные связи

[Канонические каталоги v7](../config/v7/README.md) объединяют классы → навыки → статусы, карты → боссы → открытия, таланты → валюты, режимы → награды → ботов. [Content Registry Contract](../spec/v7/content-registry-contract.md) описывает загрузку и типизацию в Godot. [Сопоставление источников](PACKAGE_RECONCILIATION.md) сохраняет исторические решения без конкурирующих конфигов.

## Поиск по мета-ссылкам

[Полный индекс 63 разделов](../INDEX.md) · [Машиночитаемый MANIFEST](../MANIFEST.json) · [Первоисточники](../research/SOURCES.md) · [Архив v6](../archive/architecture-v6-original.md).

[Что ещё не перенесено](MIGRATION_AUDIT.md) · [Правила актуальности](DOC_STANDARDS.md) · [Рабочий процесс без ролей по моделям](WORKFLOW.md).

**Текущий статус (2026-11-12):** архитектурные пробелы до P0-00 закрыты, **P0-00 — GO** в границах [RUNTIME_BOOTSTRAP_PLAN §3](../development/RUNTIME_BOOTSTRAP_PLAN.md) ([обоснование](../development/READINESS_AUDIT.md)). Первый runtime-срез P0-00 ([ADR-007](../decisions/ADR-007-runtime-bootstrap.md)): `game/project.godot`, генератор ContentRegistry, `HipRng`/`RulesHash`/`RunRulesSnapshot`, GUT-паритет с Python-оракулами. BUILD-SKILL-001 остаётся design-proposal, а не утверждённым решением; геймплейные сцены и production-ассеты — отдельными срезами. [Архитектурные gates](../roadmap/NEXT_SLICES.md).
