# Навигация **по задаче**, а не по исполнителю

Любой доступный агент или разработчик использует одну и ту же архитектуру. Нет фиксированного распределения «одна модель пишет код, другая делает ревью». Для каждого изменения выполняются одинаковые тесты и приёмка.

| Область работы | Сначала прочитать | Затем при необходимости |
|---|---|---|
| Автоатаки, попадания, DoT, proc chains | [Combat ADR](../decisions/ADR-002-combat.md) · [Семантика](../spec/v5/v5_semantics.md) | [Scheduler](../spec/core/s06.md) · [Event budgets](../spec/v5/v5_budget.md) |
| Противники, движение, спавн, performance | [Spatial](../spec/core/s10.md) · [Орда](../spec/core/s11.md) | [Визуализация](../spec/core/s14.md) · [Профилирование](../spec/core/s24.md) |
| Сложности, unlock, поздние валюты | [ADR-003](../decisions/ADR-003-late-game.md) · [Late-game](../spec/v7/late-game-progression.md) | [v7 data](../config/v7/README.md) · [Боты](../spec/v7/bot-acceptance.md) |
| Классы, таланты, экономика | [Экономика v7](../spec/v7/economy-and-talent-sinks.md) · [Классы v6](../spec/v6/v6_classes.md) | [Rewards](../config/v7/reward_contract.json) |
| Режимы, баланс, испытания | [Режимы v7](../spec/v7/modes-and-compatibility.md) | [Боты](../spec/v7/bot-acceptance.md) · [Design](../spec/v5/v5_design.md) |
| Переводы, тексты, UI | [Локализация](../spec/v6/v6_i18n.md) · [UX](../spec/v5/v5_ux.md) | [Ключи RU/EN](../config/v7/localization_additions.csv) |
| Графика/спрайты/эффекты | [2D презентация](../spec/core/s14.md) · [Визуальный QA](../spec/v5/v5_assets.md) | [Контракт ассетов](../spec/core/s17.md) |
| Reverse engineering | [RE](../spec/core/s23.md) · [Доказательства](../spec/v5/v5_re.md) | [Реестр источников](../research/SOURCES.md) |
| Тестирование, CI, изменения инфраструктуры | [Порядок работы](../guides/WORKFLOW.md) · [Тесты](../spec/v5/v5_tests.md) | [CI](../spec/core/s25.md) · [Backlog](../roadmap/NEXT_SLICES.md) |
| Изменение документации и конфигов | [Правила документов](../guides/DOC_STANDARDS.md) · [Аудит переноса](../guides/MIGRATION_AUDIT.md) | [Индекс](../INDEX.md) · [Манифест](../MANIFEST.json) |

**Любая задача, меняющая игровые определения:** [Контракт ContentRegistry](../spec/v7/content-registry-contract.md) → [JSON/CSV v7](../config/v7/README.md) → [совместимость ID](../config/v7/id_compatibility.json) → [сквозные проверки](../../scripts/validate_content.py). Роли не закреплены за моделями AI.

Оформлять работу по [TASK_SPEC](../templates/TASK_SPEC.md) и evidence по [EVIDENCE](../templates/EVIDENCE.md). [Предметный индекс](../guides/START_HERE.md).
