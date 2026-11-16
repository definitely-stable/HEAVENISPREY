---
name: hip-ci-closeout
description: Close a HEAVEN IS PREY slice - all CI steps locally in one command, diff against intent, CURRENT_STATE in the same PR, GitHub-hosted CI on Ubuntu and Windows-2022, evidence from logs, squash merge to main within agreed scope, chained PRs and post-merge CI. Use when a change is ready to integrate or a PR is waiting on CI (закрыть срез, CI, merge, CURRENT_STATE, evidence). Not for designing the change.
---

# hip-ci-closeout — интеграция и подтверждённый статус

## Use when
- Изменение прошло локальные проверки и ревью; нужно PR → CI → merge → статус.

## Not for
- Изменения нормативных решений, scope, destructive-миграций — такие PR не мержить без пользователя.

## Canonical sources
- [WORKFLOW](../../../.work/guides/WORKFLOW.md) · [CURRENT_STATE](../../../.work/CURRENT_STATE.md) · [EVIDENCE](../../../.work/templates/EVIDENCE.md)
- [design-validation.yml](../../../.github/workflows/design-validation.yml) · [godot-tests.yml](../../../.github/workflows/godot-tests.yml) · [toolchain-smoke.yml](../../../.github/workflows/toolchain-smoke.yml)

## Procedure
1. **Локально — все шаги CI одной командой:** `python scripts/dev/local_ci.py` (шаги читаются из workflow, общий код выхода; gdlint — `--gdlint <venv>/gdlint` с `gdtoolkit==4.5.0`). Пропуск шага — только из списка `SKIP` в скрипте, с причиной. До зелёного дальше не идти.
2. **Diff против замысла.** `git diff origin/main...HEAD --stat`: каждый файл назван в задаче; файл, переформатированный целиком ради пары строк, вернуть и править точечно.
3. **CURRENT_STATE — в этом же PR:** HEAD до merge, номер PR, что сделано, acceptance, blockers, next action, дата из `date`. Отдельный PR ради статуса не открывать.
4. `git push -u origin <branch>`; `gh pr create` с Summary / Evidence / Non-goals.
5. CI ждать без ручного опроса (`gh pr checks <n> --watch` или уведомление). При падении: `gh run view <id> --log-failed`, чинить причину, не отключать проверку. Каждый новый тип падения — в «Уже случалось» нужного скилла.
6. Из логов взять фактические строки (число тестов, PASS-маркеры) для обеих ОС.
7. Обычный согласованный PR после зелёного CI и ревью — `gh pr merge <n> --squash --delete-branch` (история `main` линейная, по коммиту на PR); не оставлять открытым и не включать auto-merge.
8. **Цепочка PR.** Ветка, начатая от ещё не смерженной ветки, после squash родителя конфликтует. Влить `origin/main` (`git merge origin/main`, конфликтные файлы сверить с `main`) или `git rebase --onto origin/main <старая вершина родителя>`; force-push только в свою ветку и только если владелец не против.
9. Проверить push-CI на `main`.

## Уже случалось
- **Вывод тестов съедал итог.** `unittest | tail` показывал печать тестов вместо итога, а код выхода был от `tail`. Итог брать из stderr: `python -m unittest discover -s tests 2>&1 >/dev/null | tail -3`.
- **Скрипт CI без аргументов** (`content_impact.py`, `ref_catalog.py`) падает локально. Запускать с аргументами из workflow.
- **Python-тест импортировал numpy.** Job Validate ставит только stdlib, и тест упал на импорте, хотя локально был зелёным. Тесты в `tests/` пишутся на stdlib, а Pillow и numpy нужны только под `skipUnless`.
- **Новый ассет или трасса меняют счётчики в тестах.** Grep по ID до пуша, а не после красного CI.
- **Шаги CI запускали по памяти** и пропускали то GUT, то gdlint, то аргументы скрипта. Отсюда `local_ci.py`, который читает workflow сам.
- **Скилл ссылался на устаревший порядок** (`--merge`, статус отдельным PR), а репозиторий жил иначе. Процедуру сверять с `git log origin/main` и править скилл тем же PR, где практика изменилась.
- **Цепочка PR после squash родителя** дала конфликт в общих документах. Вливать `origin/main` сразу после merge родителя.

## Acceptance
- `local_ci.py` — 0 failed до push; PR смержен squash'ем; post-merge run на `main` SUCCESS; CURRENT_STATE в том же PR соответствует live-фактам.

## Evidence output
`PR #n → merge SHA → run IDs (PR и main) → tests count Ubuntu/Windows`.
