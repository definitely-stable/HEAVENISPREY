# SKILLS_AUDIT — отбор сторонних skills и «harness»-проектов (2026-11-12)

Машинный источник: [skills.lock.json](../tooling/skills.lock.json). Здесь — обоснование. Факты получены через GitHub API (SHA, лицензия, звёзды, теги) и чтение файлов; ничего не устанавливалось глобально.

## Вердикты

| Источник | Pin | Лицензия | Вердикт | Почему |
|---|---|---|---|---|
| gamedev-skills/awesome-gamedev-agent-skills | v2.0.0 `2ee8518` | Apache-2.0 | **ADOPT subset** (DEV-ENV-002b) | Godot 4.7.2 заявлен и проверен авторами; конкретные триггеры по ошибкам, «not for», runnable checks; типизированный GDScript |
| Skyrant/gamedev-agent-skills | `7eb1b53` | Apache-2.0 | **REJECT** | форк upstream без изменений по сути, отстаёт на 178 коммитов; брать upstream |
| revfactory/harness | `92d9f1b` | Apache-2.0 | **ADAPT** | генератор агентов/skills сам пишет в `.claude/`; перенесены идеи (см. [AGENT_EXECUTION §4](AGENT_EXECUTION.md)) |
| google-research/harness2 | `6868817` | Apache-2.0 | **REFERENCE-ONLY** | исследовательский фреймворк (Linux, Vertex, executors с открытой сетью); перенесена дисциплина оценки harness |
| studioigor/studioigor-skill | `14d9d09` | MIT | **ADAPT (checklists)** | полезные чеклисты; autopilot запускает агентов с обходом разрешений и меняет crontab — не устанавливать |
| studioigor/ref2game | `da2978f` | MIT | **REFERENCE-ONLY** | собственный WebGL2 runtime; применимы только метрики сравнения референсов для look-dev |
| haxqer/godot-skill | `037c03e` | MIT | **REFERENCE-ONLY** | 82 KB одной skill + исполняемые генераторы: дорого по контексту |

## Подмножество upstream (DEV-ENV-002b, установлено)

**Установлено (13)** в `.agents/skills/` командой `python scripts/dev/vendor_skills.py sync` (tarball по commit SHA, без git/инсталлеров; LICENSE + NOTICE рядом; `tree_sha256` в lock, CI сверяет офлайн через `scripts/validate_agent_skills.py`): `godot-gdscript`, `godot-gdscript-headless-testing`, `godot-resources`, `godot-signals-groups`, `godot-nodes-scenes`, `godot-2d-movement`, `godot-ui-control`, `save-systems`, `performance-optimization`, `game-ui-ux`, `input-systems`, `game-feel`, `create-game-assets`.

**Отложено до нужной фазы** (одобрены в аудите, но не загружаются в контекст сейчас — каждая skill добавляет ~100 always-on токенов): `godot-animation`, `godot-shaders`, `godot-audio` (P0-03+ presentation), `godot-export` (release). Добавление = строка в `vendor_sources.skills` + `sync` + PR.

Проверка: `python scripts/dev/vendor_skills.py sync --check` (сеть) → 13 × OK; `claude --plugin-dir ./.agents plugin details hip` → Skills (21), ~2 019 always-on токенов; коллизий имён с глобальными skills клиентов нет.

**Не берём:** `godot-csharp` (C# вне стека), `godot-3d-essentials` (только 2D), `godot-multiplayer` (одиночная игра), publish/jam workflows (не текущая фаза), maintainer-скрипт `run-trigger-evals.py` (вызывает CLI моделей).

**Конфликт с проектными правилами:** сторонние skills — справочник по Godot API. При расхождении действуют ADR и `.work` (например, тесты: GUT 9.7.1 по [toolchain lock](../tooling/toolchain.lock.json), архитектура симуляции — ADR-002, а не event-bus autoload по умолчанию).

## Чеклист проверки каждой сторонней skill

`repo / tag / commit` · лицензия и файл LICENSE рядом · размер SKILL.md · `scripts/` и что они делают (сеть, запись, subprocess) · команды установки (запрещены `curl|sh`, unpinned `npx`) · риск prompt-injection (инструкции, переопределяющие проект) · совместимость с Godot 4.7.2 / typed GDScript / 2D · вердикт ACCEPT / ADAPT / REJECT · `tree_sha256` в lock.

## Локальные пользовательские skills

На этой машине у клиентов есть глобальные skills пользователя (web/UI-дизайн и др.). Они не относятся к проекту, не коммитятся и не считаются проверенными для HEAVEN IS PREY; проектная работа опирается на `hip-*` и vendored subset.
