---
name: hip-orientation
description: Start-of-session orientation for the HEAVEN IS PREY repo. Use when beginning any task here, resuming after a break, or when unsure which spec governs a subsystem (ориентация, с чего начать, текущее состояние, какой документ главный). Not for writing code or specs.
---

# hip-orientation — вход в проект без загрузки архива

## Use when
- Новая сессия или продолжение чужой работы в этом репозитории.
- Нужно понять, какой документ нормативен для подсистемы, и что сейчас разрешено (фаза по CURRENT_STATE).

## Not for
- Реализация, правка спецификаций, ревью — после ориентации переходите к [hip-task-slice](../hip-task-slice/SKILL.md).

## Canonical sources
1. [AGENTS.md](../../../AGENTS.md) — общие правила (коротко, обязательно).
2. [CURRENT_STATE](../../../.work/CURRENT_STATE.md) — снимок; **не** живой факт.
3. [START_HERE](../../../.work/guides/START_HERE.md) → [AGENT_ROUTING](../../../.work/indexes/AGENT_ROUTING.md) — только релевантные документы.
4. [ADR](../../../.work/decisions/README.md) и [roadmap](../../../.work/roadmap/NEXT_SLICES.md).

## Procedure
1. Перепроверить live: `git fetch && git status`, `git rev-parse origin/main`, `gh pr list --state open`, `gh issue list`, `gh run list --limit 5`. Расхождение с CURRENT_STATE записать.
2. `python scripts/dev/doctor.py` — что реально установлено (installed ≠ configured ≠ verified).
3. По routing выбрать 1–3 governing документа; архив v6 не загружать без явной причины.
4. Фазу и разрешённые срезы взять из [CURRENT_STATE](../../../.work/CURRENT_STATE.md) и AGENTS.md п.8, а не из памяти и не из этого файла: скилл не хранит то, что меняется со временем.
5. Проверить, какой проектный скилл ведёт задачу ([AGENT_EXECUTION](../../../.work/development/AGENT_EXECUTION.md)), и прочитать его раздел «Уже случалось» до начала работы.

## Acceptance
- Названы: live HEAD, открытые PR/issues, последний CI run, governing specs, ведущий скилл, разрешённый следующий шаг.

## Evidence output
Короткий блок: `HEAD=<sha> · open PR=<n> · last CI=<run id/status> · governing=<links> · phase=<из CURRENT_STATE> · skill=<hip-*>`.
