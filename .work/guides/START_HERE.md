# Предметная карта HEAVENISPREY

**Начинайте здесь:** выберите домен, прочтите действующее решение, затем максимум несколько связанных разделов. Индексы `s00` и `v6_*` остаются стабильными идентификаторами происхождения, **не** понятными названиями доменов.

| Область | Актуальный вход | Детализация |
|---|---|---|
| Продукт, игровая цель | [Границы и критерии](../spec/core/s02.md) | [Прогрессия](../spec/v6/v6_classes.md) · [Roadmap](../roadmap/NEXT_SLICES.md) |
| **Бестиарий и поведение обычных врагов** | [13 монстров](../spec/v7/ordinary-enemy-bestiary.md) | [Контракт угроз](../spec/v7/enemy-threat-contract.md) · [Волны](../config/v7/enemy_rosters.json) · [Атаки](../config/v7/enemy_attacks.json) |
| Симуляция, автоатаки и статусы | [ADR-002](../decisions/ADR-002-combat.md) | [Combat](../spec/v5/v5_semantics.md) · [Event budget](../spec/v5/v5_budget.md) |
| **BUILD-SKILL-001: активные/пассивные техники, Powers, эволюции, Union, драфт, культивация** | [Архитектурное предложение](../spec/v7/build-skill-architecture-proposal.md) · [Контракт типов](../spec/v7/build-skill-type-contract.md) | [Контентный pipeline](CONTENT_AUTHORING_ACCELERATOR.md) · [Шаблон техники](../templates/SKILL_SPEC.md) · [Классы v6](../spec/v6/v6_classes.md) |
| Сложности, режимы, награды | [ADR-003](../decisions/ADR-003-late-game.md) | [v7 поздняя прогрессия](../spec/v7/late-game-progression.md) · [Режимы](../spec/v7/modes-and-compatibility.md) |
| Экономика и сохранения | [Экономика v7](../spec/v7/economy-and-talent-sinks.md) | [Data](../config/v7/README.md) · [Сохранения](../spec/core/s20.md) |
| Godot 2D, визуализация, арт | [2D rendering](../spec/core/s14.md) | [VFX](../spec/core/s15.md) · [Арты](../spec/v5/v5_assets.md) |
| RU/EN, интерфейс | [Локализация](../spec/v6/v6_i18n.md) | [UX](../spec/v5/v5_ux.md) |
| Автоматическое тестирование | [BOT-QA v7](../spec/v7/bot-acceptance.md) | [Тесты](../spec/v5/v5_tests.md) · [Replay](../spec/core/s13.md) |
| Reverse engineering | [RE pipeline](../spec/core/s23.md) | [RE evidence](../spec/v5/v5_re.md) |
| Инструменты, зависимости, CI | [Стек](../decisions/ADR-001-stack.md) | [Dependency tiers](../spec/core/s21.md) · [CI](../spec/core/s25.md) |

## Контентные связи

[Канонические каталоги v7](../config/v7/README.md) объединяют классы → навыки → статусы, карты → боссы → открытия, таланты → валюты, режимы → награды → ботов. [Content Registry Contract](../spec/v7/content-registry-contract.md) описывает загрузку и типизацию в Godot. [Сопоставление источников](PACKAGE_RECONCILIATION.md) сохраняет исторические решения без конкурирующих конфигов.

## Поиск по мета-ссылкам

[Полный индекс 63 разделов](../INDEX.md) · [Машиночитаемый MANIFEST](../MANIFEST.json) · [Первоисточники](../research/SOURCES.md) · [Архив v6](../archive/architecture-v6-original.md).

[Что ещё не перенесено](MIGRATION_AUDIT.md) · [Правила актуальности](DOC_STANDARDS.md) · [Рабочий процесс без ролей по моделям](WORKFLOW.md).

**Текущий пользовательский scope — только архитектура и ускорение контентной разработки.** Новый BUILD-SKILL-001 имеет статус design-proposal, а не утверждённое решение; Godot runtime отложен до отдельного разрешения. [Архитектурные gates](../roadmap/NEXT_SLICES.md).
