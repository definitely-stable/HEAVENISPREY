# HEAVENISPREY — индекс архитектуры

**Каталог перенесённых разделов; для работы начинайте с [предметной карты](guides/START_HERE.md).** 63 раздела исходной v6 сохранены дословно по тематическим файлам; пересмотренные правила — в v7.

## Актуальные решения и рабочая навигация

- **[Предметная карта](guides/START_HERE.md)** · [Единый процесс](guides/WORKFLOW.md) · [Правила документации](guides/DOC_STANDARDS.md) · [Аудит полноты переноса](guides/MIGRATION_AUDIT.md).
- [TASK_SPEC](templates/TASK_SPEC.md) · [EVIDENCE](templates/EVIDENCE.md) · [ADR template](templates/ADR.md).

## Актуальные решения

- [Поздние сложности и Печати Дао](spec/v7/late-game-progression.md)
- [Экономика и таланты](spec/v7/economy-and-talent-sinks.md) · [Режимы](spec/v7/modes-and-compatibility.md) · [Боты](spec/v7/bot-acceptance.md)
- [Решения ADR](decisions/README.md) · [Карта агента](indexes/AGENT_ROUTING.md) · [CURRENT_STATE](CURRENT_STATE.md)
- [Манифест](MANIFEST.json) · [Источники](research/SOURCES.md) · [Архив v6](archive/architecture-v6-original.md)

## Трассируемость

- **[Матрица требований → спецификация → тест → статус](indexes/TRACEABILITY.md)** — что действительно реализовано, а что существует только в дизайне.

## Каталог всех разделов

### Боевой движок и мир

- [s00 · 00. Executive decision и ключевые исправления](spec/core/s00.md) — historical-context
- [s02 · 02. Границы игры, продуктовые критерии и недопущение scope creep](spec/core/s02.md) — historical-context
- [s03 · 03. Версии Godot и выбор 2D-рендерера](spec/core/s03.md) — historical-context
- [s04 · 04. Runtime-система и явная модель времени](spec/core/s04.md) — historical-context
- [s05 · 05. Content definitions: типы, каталог, схемы, статические проверки](spec/core/s05.md) — historical-context
- [s06 · 06. Auto-cast scheduler: полный контракт](spec/core/s06.md) — historical-context
- [s07 · 07. Damage/stat modifier pipeline и математические ограничения](spec/core/s07.md) — historical-context
- [s08 · 08. Статусы: четыре семантики стаков и планировщик DoT](spec/core/s08.md) — historical-context
- [s09 · 09. Effect/proc engine: циклы, события и безопасные цепные реакции](spec/core/s09.md) — historical-context
- [s10 · 10. Spatial query и targeting: структуры и алгоритмы](spec/core/s10.md) — historical-context
- [s11 · 11. Орда: движение, разделение, группы, спавн и волны](spec/core/s11.md) — historical-context
- [s12 · 12. Логические снаряды, попадания, ауры и зоны](spec/core/s12.md) — historical-context
- [s13 · 13. Replay, RNG, детерминизм и отладка расхождений](spec/core/s13.md) — historical-context
- [v5_semantics · Дополнение C. Полный Combat Semantics Contract: хит, иммунитет, исход и владение эффектом](spec/v5/v5_semantics.md) — historical-context
- [v5_budget · Дополнение D. Экономика событий (главный архитектурный риск): как не получить бесконечные проки](spec/v5/v5_budget.md) — historical-context
- [v5_enemies · Дополнение E. Игрок, враги, элиты и боссы — недостающая игровая архитектура](spec/v5/v5_enemies.md) — historical-context

### Рендеринг, графика и UX

- [s14 · 14. Godot 2D presentation: проекция, Y-sort, MultiMesh, анимации](spec/core/s14.md) — historical-context
- [s15 · 15. VFX, телеграфы, damage numbers, UI и доступность боя](spec/core/s15.md) — historical-context
- [s16 · 16. AI asset factory: Codex GPT + локальный детерминированный QA](spec/core/s16.md) — historical-context
- [s17 · 17. Атласы, память, импорт и визуальная консистентность](spec/core/s17.md) — historical-context
- [v5_visual · Дополнение F. Godot 2D presentation: от декларации «MultiMesh» к работающей схеме](spec/v5/v5_visual.md) — historical-context
- [v5_assets · Дополнение G. Codex/GPT imagegen: производственный AI-конвейер без иных сервисов](spec/v5/v5_assets.md) — historical-context
- [v5_ux · Дополнение I. UI, звук, управление и доступность: почему это архитектура, а не декор](spec/v5/v5_ux.md) — historical-context

### Геймдизайн, классы, экономика

- [s18 · 18. Геймдизайн культивации и спецификация первых способностей](spec/core/s18.md) — historical-context
- [s19 · 19. Баланс, массовые симуляции и экспериментальный дизайн](spec/core/s19.md) — historical-context
- [v5_design · Дополнение H. Геймдизайн билдов и культивации как формальные системы, а не список бонусов](spec/v5/v5_design.md) — historical-context
- [v6_difficulty · R. Настраиваемая сложность: пресеты угроз, а не один HP-множитель](spec/v6/v6_difficulty.md) — superseded-by-v7
- [v6_modes · S. Режимы и испытания: независимые модификаторы с контрактом композиции](spec/v6/v6_modes.md) — superseded-by-v7
- [v6_economy · U. Валюты и метапрогрессия: полная система источников, трат, ресета и антифарма](spec/v6/v6_economy.md) — superseded-by-v7
- [v6_rewards · V. Экономическая модель: формулы, темп, критическая проверка и симуляция](spec/v6/v6_rewards.md) — superseded-by-v7
- [v6_classes · W. Классы и деревья: содержательные специализации вместо разных числовых стартов](spec/v6/v6_classes.md) — superseded-by-v7
- [v6_ux · Y. UX всей игры: карта → класс → трудность → забег → развитие](spec/v6/v6_ux.md) — superseded-by-v7

### Локализация, контент и конфигурация

- [s20 · 20. Сохранения, настройки, конфигурация и диагностика (уточнено разделами Q–V v6)](spec/core/s20.md) — historical-context
- [v6_i18n · Q. Многоязычная архитектура с первого коммита: Godot 4.7](spec/v6/v6_i18n.md) — normative-v6
- [v6_config · T. Конфигурация как продуктовый API: что агентам разрешено менять без правки кода](spec/v6/v6_config.md) — superseded-by-v7
- [v6_decision · P. Итог утверждённых решений и критика прошлой версии](spec/v6/v6_decision.md) — normative-v6

### Агенты, CI, RE, качество

- [s21 · 21. Зависимости и инструменты: pin-матрица на 11.11.2026](spec/core/s21.md) — historical-context
- [s22 · 22. Skills, MCP и разделение труда AI-агентов](spec/core/s22.md) — historical-context
- [s23 · 23. Reverse engineering обеих игр: code/data-first и протокол доказательств](spec/core/s23.md) — historical-context
- [s24 · 24. Профилирование, CPU/GPU gates и поздний GDExtension](spec/core/s24.md) — historical-context
- [s25 · 25. Тесты, GitHub Actions, CI и реальные метрики](spec/core/s25.md) — historical-context
- [s26 · 26. Структура репозитория, ADR и контракты](spec/core/s26.md) — historical-context
- [s27 · 27. Дорожная карта P0—M4 (исторический план, заменён AA v6)](spec/core/s27.md) — historical-context
- [s28 · 28. Непроверенные допущения, угрозы качеству и риск-регистр](spec/core/s28.md) — historical-context
- [s29 · 29. Готовые ограниченные задачи для Codex / Claude Code / OpenCode Go](spec/core/s29.md) — historical-context
- [v5_re · Дополнение J. Reverse engineering: конкретная программа поиска кода, данных, формул, а не видеоигра по памяти](spec/v5/v5_re.md) — historical-context
- [v5_tools · Дополнение K. Реальные зависимости и AI-агенты: меньше пакетов, больше воспроизводимости](spec/v5/v5_tools.md) — historical-context
- [v5_tests · Дополнение L. Тестирование и бенчмарки v5: не только 5000 врагов и не только FPS](spec/v5/v5_tests.md) — historical-context
- [v5_ci · Дополнение M. CI, сохранения, диагностика и GitHub-hosted workflow](spec/v5/v5_ci.md) — historical-context
- [v5_scope · Дополнение N. Новый конкретный roadmap, зависимости между этапами и критерии «действительно сделали»](spec/v5/v5_scope.md) — historical-context
- [v5_risk · Дополнение O. Приоритеты рисков и вывод после пересмотра](spec/v5/v5_risk.md) — historical-context
- [v6_bots · X. Набор ботов для автономного тестирования уровней, сложности, экономики и переводов](spec/v6/v6_bots.md) — superseded-by-v7
- [v6_re · Z. Дополнение к reverse engineering: искать не только урон, но и метаэкономику, трудность и UI](spec/v6/v6_re.md) — normative-v6
- [v6_roadmap · AA. Пересмотр roadmap: теперь M1 — полный цикл с валютой и языками, а не демонстрация снарядов](spec/v6/v6_roadmap.md) — superseded-by-v7
- [v6_tasks · AB. Конкретные задачи для Codex / Claude Code / OpenCode Go](spec/v6/v6_tasks.md) — superseded-by-v7
- [v6_risks · AC. Риски v6 и критерии отказа от выбранного решения](spec/v6/v6_risks.md) — normative-v6
- [v6_sources · AD. Новые источники (дополнение к R01–R63, проверка 11.11.2026)](spec/v6/v6_sources.md) — normative-v6
- [s30 · 30. Реестр источников: что подтверждено и что нет](research/source-register-v6.md) — historical-context
- [s31 · 31. Архивный CURRENT_STATE v5 / заменён разделом AE v6](archive/state-v5.md) — historical-context
- [v6_state · AE. CURRENT_STATE / Текущий статус после изменения документа](spec/v6/v6_state.md) — superseded-by-v7
- [s01 · 01. Аудит всех 27 глав v3: пропуски и последствия](spec/core/s01.md) — historical-context
- [v5_audit · Дополнение A. Аудит всех 32 разделов v4: что недоопределено, какое исправление принято](spec/v5/v5_audit.md) — historical-context
- [v5_decisions · Дополнение B. Непересматриваемые решения и таблица доказательств](spec/v5/v5_decisions.md) — historical-context
