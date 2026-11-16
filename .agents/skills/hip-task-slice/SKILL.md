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
2. **Критерии приёмки — до правок.** Из слов запроса или жалобы записать 3–5 проверяемых критериев: свойство, чем меряется (команда, тест, кадр), порог. Каждое слово жалобы покрыто хотя бы одним критерием («не по плоскости карты» → наклон основания 0,5 ± 0,06 по `measure_base` и кадр в игре). Работа «готова», только когда по каждому критерию есть сохранённое доказательство.
3. Заполнить TASK_SPEC: goal, **non-goals**, files allowed, dependencies, contracts (IDs, schema_version), acceptance (критерии шага 2), test commands.
4. Проверить границы: нет смешения ARCH и runtime; нет изменения нормативного баланса/ADR без отдельного решения пользователя; гипотеза маркируется PROPOSAL.
5. Одна ветка = один срез; не трогать несвязанные файлы.
6. Если работа передаётся — заполнить AGENT_HANDOFF.

## Уже случалось
- **Критерий взяли не тот, на который жаловались:** проверили рост пропа, а жалоба была на проекцию. Отсюда шаг 2 — критерии из слов владельца.
- **Срез ассета без кадра в игре** выглядел готовым по тестам. Для визуального среза кадр — обязательный критерий.

## Acceptance
- Критерии шага 2 записаны до первой правки, у каждого есть способ проверки.
- Каждый изменяемый файл попадает в «files allowed»; есть хотя бы один позитивный и один негативный тест для нового правила.

## Evidence output
Заполненный TASK_SPEC (в описании PR или в `.work/proposals/<slice>/README.md`).
