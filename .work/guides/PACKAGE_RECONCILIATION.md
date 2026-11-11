# Сопоставление пакетов v5/v6 с канонической архитектурой

**Status: ACCEPTED DOCUMENTATION INTEGRATION, DESIGN NOT IMPLEMENTED.** Проверено по двум приложенным ZIP и полной редакции v6; исходные архивы доступны как вложения предыдущих сообщений, но их бинарные копии **не коммитились** в Git. SHA-256 и покомпонентное отображение сохранены в [машинном реестре](../archive/package-source-inventory.json).

## 1. Почему не копируем всё поверх текущей структуры

Семь независимых `docs/*.md` из v5 имеют **дословно совпадающие секции** с полным документом v6 (после удаления краевого пробела). Они уже представлены в [`.work/spec/v5/`](../spec/v5/), включая первоначальные ссылки/якоря. Копирование под вторыми именами создаст два источника правил, быстро расходящихся после правок.

| Источник v5 | Существующий рабочий документ | Решение |
|---|---|---|
| `docs/combat_semantics.md` | [v5_semantics](../spec/v5/v5_semantics.md) | exact source section; normative combat semantics subject to ADR-002 |
| `docs/event_workload.md` | [v5_budget](../spec/v5/v5_budget.md) | exact source section; proc budget, no VFX physics coupling |
| `docs/ai_art_pipeline.md` | [v5_assets](../spec/v5/v5_assets.md) | exact source section; tool choice is capability, not agent responsibility |
| `docs/reverse_engineering_protocol.md` | [v5_re](../spec/v5/v5_re.md) | exact source section; adapted role-neutral; historical original in v6 archive |
| `docs/dependency_agent_strategy.md` | [v5_tools](../spec/v5/v5_tools.md) | exact source section; adapted role-neutral; use common agent workflow |
| `docs/test_strategy.md` | [v5_tests](../spec/v5/v5_tests.md) | exact source section; test tiers independent of implementation |
| `docs/implementation_backlog.md` | [v5_scope](../spec/v5/v5_scope.md) | exact source section; backlog is historical, current roadmap overrides |

Перенесён отдельно исходный [CSV evidence](../research/claim_evidence.csv). Его строка `SS-STAT-001` имеет статус UNKNOWN/E0: это **пример фиксации гипотезы**, не доказанная механика Soulstone Survivors. Старые роли моделей из v5 заменены [единым регламентом](WORKFLOW.md).

## 2. Что изменилось при переносе v6 Config Starter

[Канонические каталоги](../config/v7/README.md) включают весь необходимый *тип* контента первоначального v6 starter: `classes`, `skills`, `stages`, `talents`, `bot_scenarios`, `economy_milestones`, `settings`, RU/EN. Не стал просто сохранять JSON schema v1 — в v7 принята единая версия схемы 2.

**Разрешённые конфликты (специально, без потери решения):**

- `unlock.tribulation` и `unlock.abyss`: условия одной победы из v6 **заменены** поздними воротами v7 (разные карты, боссы, мастерство, 3 победы); см. [late game](../spec/v7/late-game-progression.md).
- `mode.frenzy` из v6 **не тождественен** `mode.hyper` v7: различаются эффекты, исходные run snapshots автоматически не мигрируют; см. [id_compatibility.json](../config/v7/id_compatibility.json).
- `mode.endless` → `mode.endless_limited`: сохранён режим, но ограничены повторные поздние награды.
- `mode.ascetic`: сохранён как отдельный планируемый режим. Не считать его действующим до появления совместимости и баланс-тестов.
- `tree.global` → `tree.sect`: общие таланты используют расходуемые Духовные камни, классовое мастерство — **не расходуемая валюта**.
- В v6 у `skill.effect_ops` было просто `apply_status` **без идентификатора эффекта**. В v7 каждый навык явно ссылается на `status.mark`, `status.shock` или `status.burn`; добавлен каталог статусов.
- Late unlock требовал несколько карт и `boss.tribulation_avatar`, которых v6 не определял. Добавлены **только дизайн-заглушки**, не готовые игры/сцены, и проверка crossrefs. Это решает структурную несогласованность, но не реализует сам бой.
- В v6 `reward.minute3` опирался только на время: для снижения idle-farm добавлено требование подтверждённого игрового прогресса. Пороги — гипотезы для будущих ботов.
- По официальной документации Godot 4.7 столбец `_context` из v6 был **допустим**, поскольку `_` помечает комментарий. [translations.csv](../config/v7/translations.csv) с `keys,en,ru` выбран для удобства единого каталога; дополнительные подсказки находятся в [localization_context.json](../config/v7/localization_context.json).

## 3. Что НЕ является реализацией

1. JSON с `availability: design-only` не означает наличие Godot scene, анимации и боевого AI.
2. Python crossref валидатор **не** подтверждает численные значения баланса, успешное выполнение покупки в Godot или runtime миграции сохранений.
3. `ContentRegistry` и `RunRulesResolver` ещё не написаны. [Формальный контракт](../spec/v7/content-registry-contract.md) описывает ожидаемые свойства, а не тестированный код.
4. Старые автономные Python-скрипты v6 не перенесены дословно: они проверяли **schema v1** и демонстрировали time-only награды. Их применение без адаптации противоречит v7. Новые скрипты расширяют проверки, а старые учитываются по имени в реестре источников.
5. Полные бинарные ZIP и отдельный исторический отчёт v5 не копированы в Git. Это сознательное исключение дублей, **не** доказательство полноты архивирования всех исходных файлов.

## 4. Взаимосвязи

[Карта требований](../indexes/TRACEABILITY.md) → [ContentRegistry](../spec/v7/content-registry-contract.md) → [Конфигурации](../config/v7/README.md) → [Проверка каталогов](../../scripts/validate_content.py) → [Godot bootstrap backlog](../roadmap/NEXT_SLICES.md).

Принцип: изменения `skill` проверяются против `class`, `status`, `talents`, `bots`, `stage` и локализации; изменения `difficulty` проверяются против `unlocks`, `stages`, `bosses`, `rewards` и `profile fixtures`. Смена только одного числа без такой проверки не считается законченной конфигурационной работой.
