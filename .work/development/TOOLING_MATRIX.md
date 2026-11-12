# TOOLING_MATRIX — инструменты, skills и MCP проекта

> Сгенерировано `python scripts/tooling_matrix.py render` из [toolchain.lock.json](../tooling/toolchain.lock.json), [skills.lock.json](../tooling/skills.lock.json) и [mcp.lock.json](../tooling/mcp.lock.json). Не редактировать вручную; статус клиентов и машины — [READINESS_AUDIT](READINESS_AUDIT.md).

## Инструменты

| ID | Версия | Фаза | Обязателен | Проверка |
|---|---|---|---|---|
| tool.python | 3.13 | now | да | python scripts/dev/doctor.py |
| tool.git | 2.40 | now | да | python scripts/dev/doctor.py |
| tool.gh | 2.60 | now | нет | python scripts/dev/doctor.py |
| tool.godot | 4.7.2-stable | now | нет | python scripts/dev/godot_tool.py smoke |
| tool.gdtoolkit | 4.5.0 | P0-00 | нет | gdlint --version; gdformat --check game/ |
| tool.gut | 9.7.1 | P0-00 | нет | python scripts/dev/godot_tool.py test (GUT finds >0 tests; an intentionally failing test makes the run exit non-zero) |

## Agent skills (vendored, pinned)

| Skill | Источник | Commit | Лицензия |
|---|---|---|---|
| `create-game-assets` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `game-feel` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `game-ui-ux` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-2d-movement` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-gdscript` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-gdscript-headless-testing` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-nodes-scenes` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-resources` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-signals-groups` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `godot-ui-control` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `input-systems` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `performance-optimization` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |
| `save-systems` | gamedev-skills/awesome-gamedev-agent-skills | `2ee8518` | Apache-2.0 |

Проектные `hip-*` skills — [AGENT_EXECUTION](AGENT_EXECUTION.md).

## MCP

| ID | Приоритет | Фаза | Версия | Доступ | Вкл. по умолчанию | Проверка |
|---|---|---|---|---|---|---|
| context7 | P0 | now | 4.6.0 | read-only | да | VERIFIED |
| github | P0 | now | v2.1.0 | read-only | да | VERIFIED |
| godot-ai | P1 | P0-00 | 4.4.1 | read-write | нет | NOT RUN |
| godot-mcp-hybridindie | P1 | P0-00 | 2026.11.04 | read-only-default | нет | NOT RUN |
| codebase-memory | P2 | later | user-managed | read-only | нет | NOT RUN |
| roslyn-codelens | REJECT | never | user-managed | read-only | нет | NOT RUN |
