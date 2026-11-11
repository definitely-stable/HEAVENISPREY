# HEAVENISPREY — короткие инструкции для AI-агентов

1. [Открой карту задач](.work/indexes/AGENT_ROUTING.md), читай **только релевантные спецификации**. Весь архив v6 автоматически не загружай.
2. Приоритет: [ADR](.work/decisions/README.md) и [v7](.work/spec/v7/late-game-progression.md) > не переопределённые v6 > v5 > core > оригинальный архив.
3. Не менять согласованный стек: **Godot 2D, typed GDScript, Codex/GPT imagegen, существующие подписки**; GDExtension только при измеренном CPU-hotspot. Никаких новых обязательных платных API.
4. Конфиги: стабильные IDs, schema_version, ключи локализации, воспроизводимый seed; отсутствие double rewards по run_uid и reward_event_id.
5. Изменения через отдельные ветки/PR; без самостоятельных merge в main. Сначала CI и тесты, затем выводы. Не выдавать конфигурационные фикстуры за работающий runtime.
6. В отчёте указывать фактически проверенные HEAD, milestone, slice, open PR, CI, acceptance, blockers, next action, дату репозиторной проверки.
