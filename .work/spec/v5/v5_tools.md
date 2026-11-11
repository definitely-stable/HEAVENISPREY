---
id: v5_tools
title: "Дополнение K. Реальные зависимости и AI-агенты: меньше пакетов, больше воспроизводимости"
source: architecture-v6-2026-11-11
status: adapted-role-neutral
last_review: "2026-11-11"
---

> **Адаптация v7:** текстовые назначения задач конкретным моделям отменены. [Единый регламент](../../guides/WORKFLOW.md) применим к любому исполнителю. [Историческая версия](../../archive/architecture-v6-original.md) сохранена без правок.

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_tools"></a>
## Дополнение K. Реальные зависимости и AI-агенты: меньше пакетов, больше воспроизводимости

### 32K.1. Dependency tiers

`Tier0 runtime`: только Godot engine + game content. `Tier1 QA/build`: GUT **9.7.1** для Godot 4.7; gdformat/gdlint **4.5.0** в Python venv; Python/Pillow только для QA/asset generation; GitHub Actions. `Tier2 authoring`: `hi-godot/godot-ai v4.4.1` после интеграционного smoke, Codex `$imagegen` и Claude Code; `studioigor-skill/ref2game` можно изучать как inspiration, но не писать в critical runtime dependency list. `Tier3 optional`: native C++/Rust и другие плагины после измерений. [R21](https://github.com/bitwes/Gut)[R22](https://github.com/godot-gdunit-labs/gdUnit4)[R23](https://github.com/Scony/godot-gdscript-toolkit/releases)[R46](https://github.com/hi-godot/godot-ai/releases)[R47](https://learn.chatgpt.com/docs/image-generation)

**Критическое уточнение:** актуальная версия gdUnit4 — **v6.2.3** от 01.11.2026, а не неопределённое «6.2.x», и она исправляла ошибки взаимодействия с Godot 4.7. Это не значит, что надо её устанавливать поверх GUT: она остаётся альтернативой для A/B smoke. [R45](https://github.com/godot-gdunit-labs/gdUnit4/releases)

### 32K.2. Editor MCP зависит от доступного живого Godot

`godot-ai v4.4.1` заявляет Godot 4.7+, Python/uv, поддержку Codex и Claude Code и большое количество операций через live editor. Это полезно для сцен, но **не заменяет headless CI**. Если агент работает в окружении без открытого редактора, MCP недоступен или бессмысленен; решение — обычные `git patch`, `.tscn/.gd` changes и `godot --headless` из command runner. Не создавать ложное обязательство, что Windows пользователя должен быть онлайн для завершения GitHub-hosted тестов. Также проверять scope MCP-конфигурации: инструмент может писать глобальные client entries; закрепить project scope и проводить git diff после scene edit. [R46](https://github.com/hi-godot/godot-ai/releases)

### 32K.3. Три агента — не тройная скорость по умолчанию

| Агент | Содержательная ответственность | Запрещённый конфликт |
|---|---|---|
| Любой исполнитель | Scoped code/content/docs/QA task согласно TASK_SPEC | Избегать конкурентных правок одного файла; не менять схемы без ADR |

Каждый работает в отдельном `git worktree`; PR содержит `scope`, `contract_revision`, `input_refs`, `exact commands`, `test log excerpt`, `known_uncertainty`. Результаты второго агента дают независимый review *только если его контекст не копирует весь ответ первого как истину*; передавать требования и исходники, не предварительный «вердикт». Для художественного review хранить два screenshot comparison, не заявление «красиво».

### 32K.4. CI-gate для любого plugin/skill

1. Реальная версия и Git SHA, заявленная поддержка Godot 4.7.
2. Установка в **чистом временном проекте** без пользовательского кэша.
3. `godot --headless --editor --import`, script parsing, один scene serialization round trip.
4. Негативный тест: invalid script / failing unit действительно завершают job ошибкой.
5. Удаление плагина не ломает runtime/game build.
6. Время и память запуска не ухудшаются незаметно.

Если любое условие не выполнено — инструмент не входит в базу; допустим как эксперимент в отдельной ветке. «Лучший skill» — тот, который создаёт корректный проверенный результат, а не самый объёмный README.
