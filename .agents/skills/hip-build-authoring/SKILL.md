---
name: hip-build-authoring
description: Author or change HEAVEN IS PREY build content - active/passive techniques, Powers, statuses, Evolution/Union/Gift recipes, cultivation and class intrinsics - through the single v7 catalog with RU/EN keys, witnesses and impact graph. Use when adding or editing a skill, status, recipe, class or talent (техника, пассив, эволюция, Union, Gift, культивация, рецепт). Not for engine/runtime code.
---

# hip-build-authoring — контент билдов через единый каталог v7

## Use when
- Новая или изменённая техника, пассив, Power, статус, рецепт Evolution/Union/Gift, классовая черта, талант.

## Not for
- Изменение схемы/загрузчика каталога → [hip-content-registry](../hip-content-registry/SKILL.md). Боевая семантика → [hip-combat-contract](../hip-combat-contract/SKILL.md).

## Canonical sources
- [BUILD-SKILL-001 (proposal)](../../../.work/spec/v7/build-skill-architecture-proposal.md) · [Открытые решения](../../../.work/proposals/build-skill-001/OPEN_DECISIONS.md)
- [ARCH-01 type contract](../../../.work/spec/v7/build-skill-type-contract.md) · [FLEXIBILITY-FIRST](../../../.work/spec/v7/flexibility-first-build-policies.md)
- [Content authoring accelerator](../../../.work/guides/CONTENT_AUTHORING_ACCELERATOR.md) · [SKILL_SPEC template](../../../.work/templates/SKILL_SPEC.md)
- Данные: [config v7](../../../.work/config/v7/README.md) (`skills.json`, `statuses.json`, `classes.json`, `translations.csv`)

## Procedure
1. Заполнить SKILL_SPEC (ID, теги, acquisition, семантика, counterplay). Числа — **гипотезы**, не утверждённый баланс.
2. Править только `.work/config/v7/`; новые `name_key` добавить в `translations.csv` (RU и EN).
3. Сильные/«сломанные» билды допустимы; ограничения — именованные policy, не скрытые потолки.
4. Посмотреть влияние: `python scripts/content_impact.py --id <changed.id> --json`.
5. Добавить positive witness (рецепт достижим) и negative counterexample (недостижим/битая ссылка).

## Acceptance
- `python scripts/validate_content.py`, `python scripts/validate_build_proposal.py`, `python scripts/validate_work.py`, `python -m unittest discover -s tests` зелёные.

## Evidence output
ID изменённых сущностей, вывод content_impact, ссылки на witness-тесты; пометка PROPOSAL для неподтверждённых правил.
