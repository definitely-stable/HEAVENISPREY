# READINESS_AUDIT — готовность среды разработки (DEV-ENV-001…005)

- **Проверено:** 2026-11-12, Windows 11 (локально) и GitHub-hosted `ubuntu-latest` + `windows-2022`.
- **Принцип:** установлено ≠ настроено ≠ проверено smoke. Отсутствующий доступ — блокер с владельцем, не «работает».
- **Связанные:** [TOOLING_MATRIX](TOOLING_MATRIX.md) (генерируется из lock-файлов) · [RUNTIME_BOOTSTRAP_PLAN](RUNTIME_BOOTSTRAP_PLAN.md) · [SYSTEM_BINDING](SYSTEM_BINDING.md) · [CURRENT_STATE](../CURRENT_STATE.md)

Отдельные файлы `TOOLCHAIN_LOCK.md`, `PREP_ACCEPTANCE.md` и `AGENT_HANDOFF.md` не создавались: их роль выполняют [DEV-ENV-001](../spec/v7/dev-env-001-toolchain.md) + [toolchain.lock.json](../tooling/toolchain.lock.json), раздел 4 ниже и шаблон [AGENT_HANDOFF](../templates/AGENT_HANDOFF.md).

## 1. Инструменты (эта машина)

| Инструмент | Установлен | Настроен для проекта | Smoke |
|---|---|---|---|
| Python 3.13.17 | да | lock ≥ 3.11, CI 3.13 | `doctor.py` OK |
| git 2.56 / gh 2.103.3 | да | `gh` авторизован | `doctor.py` OK |
| Godot 4.7.2-stable | да, `.tools/godot/` через `godot_tool.py` (sha512) | lock + CI cache по hash lock | headless typed-GDScript smoke PASS локально и в CI на обеих ОС |
| GUT 9.7.1, gdtoolkit 4.5.0 | нет (фаза P0-00) | pin в lock | — |
| Node.js / npx | да | нужен для Context7 | `mcp_smoke.py context7` PASS |
| `codex_workflow` | **не найден** (нет CLI, `~/.codex/AGENTS.md`, skills, пакета uv/pip) | — | не применимо; второй harness не вводится |

## 2. Клиенты агентов

| Клиент | Skills проекта | MCP из примера | Статус |
|---|---|---|---|
| OpenCode 2.2.6 | `.agents/skills` нативно: перечислены `hip-*` и vendored | Context7 подключён; GitHub remote — не проверен | VERIFIED (skills), PARTIAL (MCP) |
| Claude Code 2.1.317 | плагин `hip`: Skills (21), ~2 019 always-on токенов | пример загружается (project scope); на этой машине дублирует пользовательские серверы | VERIFIED (load); интерактивный вызов не проверен (CLI не авторизован) |
| Codex CLI 0.167.0 | `.agents/skills` нативно | `codex mcp list`: context7 + github enabled | Skills **NOT VERIFIED** (лимит подписки до 2026-11-14); MCP config VERIFIED |

## 3. Блокеры и решения пользователя

| ID | Блокер | Владелец | Обход |
|---|---|---|---|
| B1 | ~~Защита `main`~~ — **закрыт 2026-11-12:** ruleset 27123627 «main: PR + CI» (active): только через PR, обязательны `Validate (ubuntu-latest)` и `Validate (windows-2022)`, запрет force-push и удаления. Toolchain smoke не обязателен (path-filter на PR), но идёт на каждый push в `main` | — | — |
| B2 | Пользовательский GitHub MCP (AIHub) → `Bad credentials` | пользователь (обновить токен), **не блокирует** | вся работа с GitHub идёт через `gh` CLI; замена токена — [MCP_REGISTRY](MCP_REGISTRY.md) §«Обновление токена GitHub» |
| B3 | ~~Codex skills discovery~~ — **снят пользователем 2026-11-12** (WAIVED, Codex не используется) | — | OpenCode/Claude проверены на тех же файлах |
| B4 | ~~Бинарники `ref/` не в git~~ — **закрыт 2026-11-12:** 63 файла в Git LFS (PR #29); CI сверяет oid/size LFS-указателей с `ref/catalog.json` без скачивания (`lfs_pointers_checked: 63` на обеих ОС) | — | локально `git lfs pull` для просмотра |
| B5 | ~~Art bible~~ — **закрыт 2026-11-12** по делегированию: [ART-BIBLE-001](../spec/v7/art-bible-001.md) (измеренные палитры, семантические цвета, пороги ART-REF-002) | — | концепции с референсов — только примеры: [REF-EXAMPLES-001](../spec/v7/reference-concept-examples.md) |
| B6 | ~~Старт P0-00~~ — **GO 2026-11-12** по делегированию (раздел 5) | — | [RUNTIME_BOOTSTRAP_PLAN](RUNTIME_BOOTSTRAP_PLAN.md) §3 |

## 4. Acceptance gates подготовки

| Gate | Статус | Evidence |
|---|---|---|
| HEAD, открытые PR/issues, push CI перепроверены; CURRENT_STATE по факту | ✔ | [CURRENT_STATE](../CURRENT_STATE.md) |
| Inventory: установлено / настроено / smoke раздельно | ✔ | разделы 1–2 |
| `codex_workflow` проверен фактами, второго harness нет | ✔ (не найден) | раздел 1 |
| Shortlist skills: лицензия, версия, безопасность, совместимость; 8 `hip-*` с триггерами и gates | ✔ | [SKILLS_AUDIT](SKILLS_AUDIT.md), `validate_agent_skills.py` (16 trigger cases) |
| Discovery smoke в доступных клиентах, недоступные помечены | ✔ / Codex NOT VERIFIED | раздел 2 |
| Context7 и GitHub минимально и по факту; Godot MCP только как будущая опция; ключей в repo нет | ✔ | [MCP_REGISTRY](MCP_REGISTRY.md), `validate_mcp.py` |
| Version lock Godot 4.7.2 / GUT 9.7.1 / Python / tools с sha/tag | ✔ | [toolchain.lock.json](../tooling/toolchain.lock.json) |
| CI: skills + Python tests на Ubuntu и Windows-2022, результаты привязаны к commit | ✔ | `design-validation.yml`, `toolchain-smoke.yml` |
| Gap register и bootstrap plan привязаны к roadmap, без runtime | ✔ | [SYSTEM_BINDING](SYSTEM_BINDING.md), [RUNTIME_BOOTSTRAP_PLAN](RUNTIME_BOOTSTRAP_PLAN.md) |
| Каждый PR: diff review → CI → merge → post-merge CI | ✔ | PR #17–#23 |
| Нет игровых файлов, платных зависимостей, заявлений о perf/fun | ✔ | нет `game/`, `project.godot` |

## 5. Повторный readiness review и GO/NO-GO P0-00 (2026-11-12)

**Открытые пробелы после ARCH-02, ARCH-04, GAME-ARCH-02 и SCHEMA-COVERAGE** ([SYSTEM_BINDING](SYSTEM_BINDING.md)):

| Пробел | Статус | Блокирует P0-00? | Почему |
|---|---|---|---|
| GAP-BLD-OPEN | OPEN, решения пользователя по BUILD-SKILL-001 | нет | P0-00 не содержит билдов; оракулы ARCH-01/02/04 держат политику параметрами, а не жёсткими правилами |
| GAP-PRECEDENCE | OPEN → GAME-ARCH-05 | нет | нужен до P0-01 (смерть и level-up в одном тике); в P0-00 нет симуляции боя |
| GAP-UX-INPUT | OPEN → GAME-UX-002 | нет | нужен до первого играбельного экрана |
| GAP-REGISTRY-GEN | BLOCKED-BY-RUNTIME | — | закрывается самим P0-00 (п.3 §3 плана) |
| GAP-PY-GD-PARITY | BLOCKED-BY-RUNTIME | — | первый шаг в P0-00, полностью в P0-01 |

Конфигов без валидатора: 0 из 24 (`python scripts/system_binding.py validate`).

**Маршрутизация агентов на реальных задачах.** Пять задач (новый рецепт Union, атака врага с замедлением, порядок наград босса в одном тике, proc-цепочка нового навыка, настройка интенсивности VFX) прошли по [START_HERE](../guides/START_HERE.md) → [AGENT_ROUTING](../indexes/AGENT_ROUTING.md) примерно за 4 документа каждая и пришли к правильной спецификации. Найдено 6 неточностей: строки «монстры/телеграфы», «цикл забега/боссы» и «автоатаки/proc» не вели к GAME-ARCH-02 и ARCH-04; строка RunBuild и START_HERE не вели к ARCH-02; AGENTS.md п.6 не упоминал валидаторы областей и статус P0-00. Все исправлены и закреплены регрессионным тестом [test_agent_routing.py](../../tests/test_agent_routing.py).

**Решение: GO для P0-00.** Условия 1–8 [RUNTIME_BOOTSTRAP_PLAN](RUNTIME_BOOTSTRAP_PLAN.md) выполнены; решение о старте делегировано пользователем. Границы: только состав §3 плана (ADR-007, минимальный `project.godot`, генератор ContentRegistry, типы `game/core/`, GUT-паритет 2–3 оракулов), без геймплейных сцен и production-ассетов. Решение возвращается в NO-GO, если P0-00 потребует сменить стек, добавить платный сервис или изменить канонический баланс.
