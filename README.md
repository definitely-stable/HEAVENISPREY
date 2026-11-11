# HEAVENISPREY

**Планируемая игра:** изометрическая 2D xianxia survivor-like с автоатаками, мультикастом, эффектами, классами и прокачкой между забегами. **Статус:** планирование; исполняемого проекта Godot пока нет.

## Навигация

- **[Полный индекс архитектуры](.work/INDEX.md)** — все 63 раздела исходной v6 с мета-ссылками.
- **[Роутинг контекста для агентов](.work/indexes/AGENT_ROUTING.md)** и [AGENTS.md](AGENTS.md).
- **[Решения ADR](.work/decisions/README.md)** и [текущий статус](.work/CURRENT_STATE.md).
- **[Поздние сложности и новая валюта](.work/spec/v7/late-game-progression.md)**.
- [Режимы](.work/spec/v7/modes-and-compatibility.md) · [Экономика](.work/spec/v7/economy-and-talent-sinks.md) · [Боты](.work/spec/v7/bot-acceptance.md).
- **[Дизайн-конфиги v7](.work/config/v7/README.md)** · [План реализации](.work/roadmap/NEXT_SLICES.md).
- [Архив полной архитектуры v6](.work/archive/architecture-v6-original.md) · [Источники](.work/research/SOURCES.md).

## Зафиксированный стек

Godot **4.7.2 2D**, typed GDScript; GDExtension C++ или Rust только после профилирования hot path. AI-разработка и арт: Codex/GPT imagegen, ChatGPT Plus, Claude Pro и OpenCode Go — без обязательной покупки дополнительных API. NVIDIA **12 ГБ VRAM**, **32 ГБ RAM**. GitHub-hosted CI.

## Мета и сложность

Стартовые сложности: ученик и стандарт. Испытание секты открывается после стандарта. **Небесная кара** и **Бездна Дао** открываются только в late game и дают повышенные Духовные камни плюс новую earn-only валюту **Печати Дао**. Точные коэффициенты — баланс-гипотезы, до игровых симуляций не подтверждены.

**Не путать документацию с реализацией:** игровые прогоны, Godot CI и реальные боты ещё не выполнены.
