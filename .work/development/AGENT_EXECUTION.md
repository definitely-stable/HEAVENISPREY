---
id: DEV-ENV-002
status: IMPLEMENTED (agent tooling only; no game runtime)
date: 2026-11-12
dependencies: ADR-004, WORKFLOW, FOUNDATION-2026 FND-11, DEV-ENV-001
acceptance: scripts/validate_agent_skills.py, tests/test_agent_skills.py, client discovery smoke below
---

# Исполнение задач агентами: skills, адаптеры клиентов, цикл среза

Это **не** вторая система инструкций. Правила — только в [AGENTS.md](../../AGENTS.md) и `.work/`; skills — короткие процедуры со ссылками на канон; клиентские файлы — тонкие адаптеры. Исполнитель не закрепляется за моделью ([ADR-004](../decisions/ADR-004-agent-context.md)).

## 1. Цикл среза (один для любого исполнителя)

`task contract → scoped context → design → change → validators → independent review → evidence → CI → merge → post-merge status`

| Шаг | Skill | Канон |
|---|---|---|
| Ориентация, live HEAD/PR/CI | `hip-orientation` | [START_HERE](../guides/START_HERE.md) · [CURRENT_STATE](../CURRENT_STATE.md) |
| Контракт среза, handoff | `hip-task-slice` | [TASK_SPEC](../templates/TASK_SPEC.md) · [AGENT_HANDOFF](../templates/AGENT_HANDOFF.md) |
| Бой / AutoCast / Status / Enemy | `hip-combat-contract` | [ADR-002](../decisions/ADR-002-combat.md) |
| Build / Evolution / Union / Gift / Cultivation | `hip-build-authoring` | [BUILD-SKILL-001](../spec/v7/build-skill-architecture-proposal.md) |
| Каталог, ID, схемы, parity | `hip-content-registry` | [ADR-006](../decisions/ADR-006-content-catalog.md) |
| Seed / Replay / Save / негативные контроли | `hip-deterministic-qa` | [FOUNDATION-2026](../spec/v7/foundation-research-2026.md) |
| Ревью diff | `hip-code-review` | [WORKFLOW](../guides/WORKFLOW.md) |
| PR → CI → merge → статус | `hip-ci-closeout` | [EVIDENCE](../templates/EVIDENCE.md) |

Режимы усилия (лёгкий вопрос / исследование / ограниченная реализация с независимым ревью) выбираются по задаче, а не по модели; параллельные агенты — только для независимых частей с отдельными файлами.

## 2. Где живут skills и как их видят клиенты

| Клиент | Механизм | Состояние на 2026-11-12 |
|---|---|---|
| OpenCode 2.2.6 | читает `.agents/skills` нативно; требует **уникальные имена** во всех каталогах skills | **VERIFIED**: `opencode run` перечислил все 8 `hip-*` |
| Claude Code 2.1.317 | читает только `.claude/skills` или плагины → `.agents` объявлен плагином `hip` ([plugin.json](../../.agents/.claude-plugin/plugin.json), [marketplace](../../.claude-plugin/marketplace.json), [settings](../../.claude/settings.json)) | **VERIFIED (load)**: `claude --plugin-dir ./.agents plugin details hip` → Skills (8), ~735 always-on токенов. Интерактивный вызов в новой сессии — **NOT VERIFIED** (CLI в этом окружении не авторизован) |
| Codex CLI 0.167.0 | читает `.agents/skills` нативно | **NOT VERIFIED**: `codex exec` остановлен лимитом подписки до 2026-11-14 |

Почему не копия в `.claude/skills`: OpenCode загружает и `.claude/skills`, и `.agents/skills`, и при одинаковых именах skill может не загрузиться. Валидатор запрещает такие копии. `CLAUDE.md` содержит только `@AGENTS.md`.

Локальная разработка skills в Claude Code: `claude --plugin-dir ./.agents`. В обычной сессии проект предлагает плагин `hip@heavenisprey` после доверия к папке (источник — GitHub `main`).

## 3. Проверяемые триггеры

- Каждый `hip-*` имеет `Use when` и `Not for` в description, обязательные разделы и ссылки на `.work`.
- [skill_trigger_cases.json](../tooling/skill_trigger_cases.json): RU/EN запросы → ожидаемый skill; детерминированная лексическая маршрутизация должна выбрать его однозначно (ничья = ошибка). Это smoke различимости описаний, а не оценка модели.
- Новая проектная skill без trigger case не проходит CI.

## 4. Принятые идеи внешних «harness»-проектов (без установки)

Источники и вердикты: [skills.lock.json](../tooling/skills.lock.json), подробности — [SKILLS_AUDIT](SKILLS_AUDIT.md).

1. **Harness = версионированное целое** (google-research/harness2): AGENTS.md, skills, адаптеры, валидаторы и CI меняются через PR и проверяются вместе, а не правятся «на лету» в одном клиенте.
2. **Propose → probe → compose**: изменение harness (новая skill, правило) сравнивается на фиксированных задачах до/после; без измеримого эффекта — не принимается. Повторяемость: одинаковые задачи, seed, конфигурация; непройденная оценка = «не оценено», не «0».
3. **Уроки только с evidence**: вывод из ретроспективы попадает в `.work` (ADR, guide, skill) обычным PR со ссылкой на CI/diff. Отдельного «журнала памяти» нет.
4. **Агент = кто, skill = как** (revfactory/harness); progressive disclosure: короткий SKILL.md → ссылки на канон.
5. **Producer → independent reviewer**: автор изменения не единственный проверяющий; `hip-code-review` выполняется отдельным проходом.
6. **Изоляция оценок**: при оценке harness агент не видит эталонных ответов/фикстур проверки.

## 5. Безопасность

Секреты не в repo (deny-правила в `.claude/settings.json`, проверка токенов в skills). Сторонние skills — только pinned SHA, с LICENSE и tree digest. Без `curl | sh`, без скриптов, обходящих разрешения. Нормативные игровые решения меняются только через ADR и решение пользователя.
