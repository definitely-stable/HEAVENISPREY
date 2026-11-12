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
| B1 | ~~Защита `main` недоступна (private, Free → 403)~~ — репозиторий сделан публичным 2026-11-12; `main` пока не защищён (API → 404 Not protected) | пользователь: разрешить ruleset | правила [AGENTS.md](../../AGENTS.md) + зелёный CI перед merge |
| B2 | Пользовательский GitHub MCP (AIHub) → `Bad credentials` | пользователь (обновить токен) | `gh` CLI; проектный пример с `GITHUB_MCP_PAT` проверен |
| B3 | Codex skills discovery не проверен | ожидание лимита до 2026-11-14 | OpenCode/Claude проверены на тех же файлах |
| B4 | Бинарники `ref/` (162 MB) не в git | пользователь: LFS / git / локально | метаданные и sha256 в `ref/catalog.json` |
| B5 | Art bible | пользователь | ART-BIBLE-001; концепции с референсов оформлены как примеры: [REF-EXAMPLES-001](../spec/v7/reference-concept-examples.md) |
| B6 | Старт P0-00 | пользователь | [RUNTIME_BOOTSTRAP_PLAN](RUNTIME_BOOTSTRAP_PLAN.md) |

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
