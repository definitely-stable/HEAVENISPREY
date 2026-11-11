# HEAVENISPREY

**Состояние:** архитектура и игровые конфигурации; исполняемая игра Godot ещё не создана.

Изометрический **2D xianxia survivor-like** с автоатаками, мультикастом, стаками эффектов, классами, метапрогрессией, переводами RU/EN и открываемыми уровнями сложности. Референсы боевых механик: Vampire Survivors и Soulstone Survivors.

## Где начинать

| Вопрос | Документ |
|---|---|
| Что утверждено и как найти нужную тему? | **[Предметная карта проекта](.work/guides/START_HERE.md)** |
| Полный каталог 63 исходных разделов | [Индекс архитектуры](.work/INDEX.md) |
| Правила для **любого** исполнителя | [AGENTS.md](AGENTS.md) · [Единый процесс работы](.work/guides/WORKFLOW.md) |
| Контракты и приоритет документов | [Стандарты документации](.work/guides/DOC_STANDARDS.md) · [ADR](.work/decisions/README.md) |
| Поздние сложности / вторая валюта | [Небесная кара и Бездна Дао](.work/spec/v7/late-game-progression.md) · [Экономика](.work/spec/v7/economy-and-talent-sinks.md) |
| **Канонические данные и связи** | **[ContentRegistry](.work/spec/v7/content-registry-contract.md)** · [JSON/CSV v7](.work/config/v7/README.md) · [Аудит пакетов v5/v6](.work/guides/PACKAGE_RECONCILIATION.md) |
| Конфиги и локализация | [v7 fixtures](.work/config/v7/README.md) · [RU/EN](.work/spec/v6/v6_i18n.md) |
| Что перенесено, а что ещё нет? | **[Аудит переноса](.work/guides/MIGRATION_AUDIT.md)** · [Матрица требований](.work/indexes/TRACEABILITY.md) |
| Что проверено на GitHub? | [CURRENT_STATE](.work/CURRENT_STATE.md) · [Тесты](.github/workflows/design-validation.yml) |

## Обычные противники (новый бестиарий)

**[12 монстров из скриншотов + Осквернённый культиватор](.work/spec/v7/ordinary-enemy-bestiary.md)** — все 13 относятся к обычным врагам, **не** элитам и **не** боссам. Описание ролей, контрприёмов, китайских имён и распределение по двум картам: [враги](.work/config/v7/enemies.json) · [атаки](.work/config/v7/enemy_attacks.json) · [волны](.work/config/v7/enemy_rosters.json) · [угрозы и безопасность](.work/spec/v7/enemy-threat-contract.md).

**Статус:** дизайн-данные, не готовые анимации или игровой runtime. Скриншоты используются только как исходные визуальные ориентиры.

## Непересматриваемые решения

Godot **4.7.2, 2D**, typed GDScript. GPU NVIDIA 12 ГБ VRAM, RAM 32 ГБ. Нативный GDExtension C++ / Rust — только после профилирования hot path. Графика через утверждённый GPT imagegen в имеющейся подписке; дополнительных платных AI API не требовать. GitHub-hosted CI, без необходимости включённого пользовательского ПК.

**Никаких назначений задач по моделям:** архитектура, изменения, ревью и тесты не привязаны к Codex, Claude, Opus или OpenCode. Конкретный инструмент определяется доступностью и свойствами задачи; требования к результату одинаковы.

## Прогрессия

«Небесная кара» и «Бездна Дао» открываются только в поздней игре и дают значительно больше Духовных камней, а также особую зарабатываемую валюту — **Печати Дао**. Коэффициенты и требования из v7 — *начальные гипотезы*, не подтверждённые тестами игры.

[План реализации](.work/roadmap/NEXT_SLICES.md) · [Реестр источников](.work/research/SOURCES.md) · [Оригинал v6](.work/archive/architecture-v6-original.md).
