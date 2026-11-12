# MCP_REGISTRY — серверы MCP для разработки HEAVEN IS PREY (DEV-ENV-003, 2026-11-12)

Машинный источник: [mcp.lock.json](../tooling/mcp.lock.json). Примеры конфигураций клиентов без секретов: [Claude Code](../tooling/mcp/claude.mcp.example.json) · [Codex](../tooling/mcp/codex.config.example.toml) · [OpenCode](../tooling/mcp/opencode.example.json). Проверки: `python scripts/validate_mcp.py` (офлайн, CI) и `python scripts/dev/mcp_smoke.py <id>` (живое рукопожатие, нужна сеть).

## Правила

1. В репозитории только `*.example`; живые `.mcp.json`, `.codex/config.toml`, `opencode.json` в `.gitignore`. Токены — только из переменных окружения (`${VAR}`, `{env:VAR}`, `bearer_token_env_var`).
2. Версии — точные (`@upstash/context7-mcp@4.6.0`, тег релиза); `latest`, `^`, `~` запрещены валидатором. Обновление — PR с повторным smoke.
3. По умолчанию включены только серверы фазы `now` с доступом read-only. Серверы с записью или выполнением кода (Godot MCP) выключены и имеют `enable_gate`.
4. MCP — инструмент любого исполнителя; сервер не закрепляется за моделью. Запись в GitHub (PR, merge) идёт через `gh` по правилам [AGENTS.md](../../AGENTS.md), а не через MCP.

## Реестр

| ID | Приоритет / фаза | Pin | Доступ | Статус проверки |
|---|---|---|---|---|
| context7 | P0 / now | npm `@upstash/context7-mcp@4.6.0` (4.7.0 вышел 2026-11-12 — выдерживаем паузу) | read-only, ключ необязателен | **VERIFIED**: `mcp_smoke.py context7` → 2 tools; пример загружается в Codex и Claude Code; OpenCode подключил tools context7 |
| github | P0 / now | github-mcp-server v2.1.0 `7c48164`, remote `…/mcp/readonly`, toolsets repos, pull_requests, issues, actions | read-only, `GITHUB_MCP_PAT` | **VERIFIED** endpoint: `mcp_smoke.py github` → 25 read-only tools, write-tools нет; пример загружается в Codex и Claude Code. OpenCode remote — **NOT VERIFIED** |
| godot-ai | P1 / P0-00 | PyPI `godot-ai==4.4.1` `643c64f`, MIT | read-write, `game_eval` исполняет GDScript; телеметрия по умолчанию | **NOT RUN** — нет Godot-проекта; выключен |
| godot-mcp-hybridindie | P1 / P0-00 | `2026.11.04` `d061451`, MIT | inspection-only по умолчанию, dry-run/confirm | **NOT RUN** — выключен |
| codebase-memory | P2 / later | user-global | read-only | не часть проектного контракта; оценить после P0-02 |
| roslyn-codelens | REJECT | — | — | C# вне стека |

Отклонены: Coding-Solo/godot-mcp npm 0.1.1 (до исправления RCE, PR #99), ee0pdt и bradypp (без модели безопасности для записи), архивный `@modelcontextprotocol/server-github`.

## Сравнение Godot MCP (решение — в срезе DEV-MCP-GODOT после P0-00)

| Критерий | hi-godot/godot-ai 4.4.1 | hybridindie/godot-mcp 2026.11.04 |
|---|---|---|
| Godot | 4.7+ | заявлена проверка на 4.7.2 |
| Объём | 46 tools | 201 tool, по умолчанию только inspection |
| Риск записи | `editor_manage op=game_eval` — произвольный GDScript | dry-run / confirm для записи |
| Приватность | телеметрия включена: `GODOT_AI_DISABLE_TELEMETRY=true` | телеметрии нет |
| Установка | `uvx` из PyPI, по умолчанию user scope → только project scope | git по commit |
| Поддержка | 3.5k★, активные релизы | 58★, один мейнтейнер |

Предварительно: godot-ai для чтения scene tree, ошибок и скриншотов с отключённой телеметрией и запретом `game_eval` в разрешениях клиента; hybridindie как запасной вариант с более строгим режимом по умолчанию. Включение требует трёх условий: merged `project.godot` (P0-00), явное разрешение пользователя, оценочный срез с фиксированными задачами (propose → probe → compose, см. [AGENT_EXECUTION](AGENT_EXECUTION.md)).

## Состояние на этой машине (не часть контракта)

- В Codex и Claude Code уже настроены пользовательские серверы через `C:\AIHub\mcp\launchers\run.py` с теми же именами `context7` и `github`. Claude Code при копировании проектного `.mcp.json` предупреждает о дублировании имени в двух scope — на этой машине проектный пример копировать не нужно; он предназначен для чистой машины.
- Пользовательский `github` (AIHub) отвечает `Bad credentials` — устаревший токен. **Владелец: пользователь** (обновить токен в AIHub или перейти на пример с `GITHUB_MCP_PAT`). Fallback — `gh` CLI.
- OpenCode: глобально MCP не настроены; проектный пример даёт context7.

## Установка на чистой машине

1. Node.js LTS (для `npx`), `gh auth login`.
2. Создать fine-grained PAT только на этот репозиторий, read-only: contents, pull requests, issues, actions, metadata; `setx GITHUB_MCP_PAT …` (Windows) или `export GITHUB_MCP_PAT=…`.
3. Скопировать нужный пример: `.work/tooling/mcp/claude.mcp.example.json` → `.mcp.json`; `codex.config.example.toml` → `.codex/config.toml` (доверенный проект) или `~/.codex/config.toml`; `opencode.example.json` → `opencode.json`.
4. Проверить: `python scripts/validate_mcp.py`, `python scripts/dev/mcp_smoke.py context7`, `python scripts/dev/mcp_smoke.py github`.
