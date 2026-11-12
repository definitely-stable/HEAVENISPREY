---
name: hip-task-slice
description: Turn a HEAVEN IS PREY request into one bounded slice with a task contract, scope/non-goals, files, tests and evidence before editing. Use when starting any change, splitting a large request, or writing a handoff (срез, task spec, scope, non-goals, handoff, ветка/PR). Not for reviewing an existing diff.
---

# hip-task-slice — контракт среза до изменений

## Use when
- Любая правка файлов: спецификация, валидатор, конфиг, tooling.
- Большой запрос нужно разбить на небольшие последовательные PR.
- Передача работы другому исполнителю (handoff).

## Not for
- Ревью готового diff → [hip-code-review](../hip-code-review/SKILL.md). Закрытие PR → [hip-ci-closeout](../hip-ci-closeout/SKILL.md).

## Canonical sources
- [TASK_SPEC](../../../.work/templates/TASK_SPEC.md) · [AGENT_HANDOFF](../../../.work/templates/AGENT_HANDOFF.md) · [WORKFLOW](../../../.work/guides/WORKFLOW.md)
- [DOC_STANDARDS](../../../.work/guides/DOC_STANDARDS.md) — статусы `accepted / design-proposal / reference / superseded`.
- [Roadmap](../../../.work/roadmap/NEXT_SLICES.md) — порядок срезов и зависимости.

## Procedure
1. Взять stable slice ID из roadmap (или предложить новый, не переименовывая старые).
2. Заполнить TASK_SPEC: goal, **non-goals**, files allowed, dependencies, contracts (IDs, schema_version), acceptance, test commands.
3. Проверить границы: нет смешения ARCH и runtime; нет изменения нормативного баланса/ADR без отдельного решения пользователя; гипотеза маркируется PROPOSAL.
4. Одна ветка = один срез; не трогать несвязанные файлы.
5. Если работа передаётся — заполнить AGENT_HANDOFF.

## Acceptance
- Каждый изменяемый файл попадает в «files allowed»; есть хотя бы один позитивный и один негативный тест для нового правила.

## Evidence output
Заполненный TASK_SPEC (в описании PR или в `.work/proposals/<slice>/README.md`).
