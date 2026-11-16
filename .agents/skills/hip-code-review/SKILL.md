---
name: hip-code-review
description: Independent diff review for HEAVEN IS PREY changes - scope, API and schema semantics, reward/RNG/XP exactly-once logic, determinism, tests with negative controls, security and supply chain, doc status honesty. Use when reviewing a branch, PR or own diff before merge (ревью, проверка diff, перед merge). Not for writing the change itself.
---

# hip-code-review — независимая проверка перед merge

## Use when
- Перед merge любого PR; при ревью чужой ветки; после крупного рефакторинга.

## Not for
- Создание изменения ([hip-task-slice](../hip-task-slice/SKILL.md)) и закрытие PR ([hip-ci-closeout](../hip-ci-closeout/SKILL.md)).

## Canonical sources
- [WORKFLOW — review & integrate](../../../.work/guides/WORKFLOW.md) · [Acceptance checklist s25.4](../../../.work/spec/core/s25.md)
- [DOC_STANDARDS](../../../.work/guides/DOC_STANDARDS.md) · [ADR index](../../../.work/decisions/README.md)

## Procedure
1. `git diff origin/main...HEAD --stat`, затем полный diff. Каждый файл в scope TASK_SPEC? Число строк по файлу соответствует замыслу: файл, переписанный целиком (переформатирование, смена переводов строк), — находка.
2. **Доказательство в словах владельца.** Взять критерии приёмки из задачи (жалоба, запрос) и для каждого найти evidence, которое проверяет именно его, а не соседнее свойство. «Львы не в плоскости карты» закрывается замером наклона и кадром из игры рядом с доской, а не тестом высоты. Визуальное без кадра — не проверено.
3. Семантика: stable IDs не переименованы без миграции; `schema_version` не сдвинут молча; награды по `run_uid`/`reward_event_id` однократны; RNG-потоки разделены; XP не теряется и не дублируется.
4. Тесты: есть позитивный и негативный (негативный — прежняя дефектная версия или мутация действительно падает); существующие не ослаблены и не удалены.
5. Честность статусов: нет `ACCEPTED`/`TESTED`/`CI_VERIFIED` без решения или evidence; гипотезы помечены PROPOSAL.
6. Безопасность: нет секретов/токенов, `curl | sh`, плавающих версий, `@main` actions; сторонний код pinned по SHA с лицензией.
7. Роли не закреплены за конкретными AI-моделями.

## Уже случалось
- **Ревью приняло тест высоты как доказательство посадки на пол.** Свойство, на которое жаловались (проекция), не проверялось ничем. Отсюда шаг 2.
- **Файл переформатирован целиком** ради двух новых строк; diff скрыл суть. Отсюда сверка `--stat` в шаге 1.

## Acceptance
- Список находок по серьёзности; блокирующие исправлены или merge остановлен с причиной.

## Evidence output
`Changed / Verified / Not verified / Risks` + commit SHA ревью.
