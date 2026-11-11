# ADR-006 — единый источник игровых данных и воспроизводимый импорт

**Status: ACCEPTED DESIGN, NOT IMPLEMENTED. Date: 2026-11-11.**

## Контекст
Пакет v5 содержит дубли секций полного v6, а Config Starter v6 содержит schema v1 с устаревшими правилами late game и частично неразрешёнными ссылками. Наивное копирование создаёт одновременно несколько конфликтующих источников характеристик, режимов и наград.

## Решение
- **Один источник новых конфигураций:** [`.work/config/v7/`](../config/v7/README.md). Исторические файлы/ссылки сохраняются как evidence и не используются в runtime параллельно.
- JSON и CSV удобны для изменения небольшими PR, но Godot 2D должен загружать их только через **типизированный и валидирующий ContentRegistry**. Возможность создавать Godot custom `Resource`/текстовые `.tres` рассматривается как механизм runtime/редактора, а **не второй независимый источник**. При генерации обязательно проверять digest и parity.
- `schema_version=2`, стабильные ID и зафиксированный [набор преобразований](../config/v7/id_compatibility.json). Неэквивалентные старые `mode.frenzy` и `mode.hyper` не заменяют друг друга молча.
- `name_key` разрешается только через один [translations.csv](../config/v7/translations.csv). В Godot 4.7 поле `_context` в CSV допустимо как комментарий; текущий компактный формат `keys,en,ru` — **выбор проекта**, а не ограничение движка.
- Контентный граф `class→skill→status`, `stage→boss/difficulty`, `unlock→stage/boss`, `talent→currency`, `bot→profile/stage/class/mode` проверяется до запуска мира, а не после падения сохранения.
- Нет произвольного исполняемого кода в JSON; только известные effect opcodes. Рассинхронизация новых таблиц с контрактом боевой системы или наград требует отдельного ADR и тестов.

## Приёмка
`python scripts/validate_content.py` и `python -m unittest discover -s tests -v` подтверждают **только структурные инварианты и отрицательные тесты**, не игровую реализацию или баланс. Godot headless/typed parity, реальный replay и bot testing пока NOT RUN.

[Связность контента](../spec/v7/content-registry-contract.md) · [Дедупликация/решения](../guides/PACKAGE_RECONCILIATION.md).

Первоисточники: [Godot 4.7 Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html) и [Godot 4.7 CSV localization](https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_spreadsheets.html).
