---
name: hip-ci-closeout
description: Close a HEAVEN IS PREY slice - push, PR, GitHub-hosted CI on Ubuntu and Windows-2022, evidence from logs, merge to main within agreed scope, post-merge CI and CURRENT_STATE update. Use when a change is ready to integrate or a PR is waiting on CI (закрыть срез, CI, merge, CURRENT_STATE, evidence). Not for designing the change.
---

# hip-ci-closeout — интеграция и подтверждённый статус

## Use when
- Изменение прошло локальные проверки и ревью; нужно PR → CI → merge → статус.

## Not for
- Изменения нормативных решений, scope, destructive-миграций — такие PR не мержить без пользователя.

## Canonical sources
- [WORKFLOW](../../../.work/guides/WORKFLOW.md) · [CURRENT_STATE](../../../.work/CURRENT_STATE.md) · [EVIDENCE](../../../.work/templates/EVIDENCE.md)
- [design-validation.yml](../../../.github/workflows/design-validation.yml) · [toolchain-smoke.yml](../../../.github/workflows/toolchain-smoke.yml)

## Procedure
1. Локально: `python scripts/validate_work.py`, `python scripts/validate_agent_skills.py`, `python -m unittest discover -s tests -v`.
2. `git push -u origin <branch>`; `gh pr create` с Summary / Evidence / Non-goals.
3. `gh pr checks <n> --watch`; при падении читать лог (`gh run view <id> --log-failed`), чинить причину, не отключать проверку.
4. Из логов взять фактические строки (число тестов, PASS-маркеры) для обеих ОС.
5. Обычный согласованный PR после зелёного CI и ревью — `gh pr merge <n> --merge --delete-branch`; не оставлять открытым.
6. Проверить push-CI на `main` и обновить CURRENT_STATE отдельным маленьким PR: HEAD, PR, run ID, acceptance, blockers, next action, дата.

## Acceptance
- PR merged, post-merge run на `main` SUCCESS, CURRENT_STATE соответствует live-фактам.

## Evidence output
`PR #n → merge SHA → run IDs (PR и main) → tests count Ubuntu/Windows`.
