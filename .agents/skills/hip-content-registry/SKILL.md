---
name: hip-content-registry
description: Keep HEAVEN IS PREY game data in one versioned source - v7 catalogs, stable IDs, schema_version, ID migrations, digests and generated parity for the future Godot ContentRegistry. Use when changing catalog structure, renaming IDs, adding a catalog, or planning Resource/.tres generation (ContentRegistry, schema, миграция ID, digest, parity). Not for editing a single technique's numbers.
---

# hip-content-registry — единственный источник контента

## Use when
- Новая таблица/поле, переименование ID, изменение `schema_version`, связи между каталогами.
- Проектирование загрузки в Godot (typed defs, `.tres` как производный артефакт).

## Not for
- Обычное добавление техники/статуса → [hip-build-authoring](../hip-build-authoring/SKILL.md).

## Canonical sources
- [ADR-006 единый источник](../../../.work/decisions/ADR-006-content-catalog.md) · [ADR-005 контент и i18n](../../../.work/decisions/ADR-005-config-contract.md)
- [ContentRegistry contract](../../../.work/spec/v7/content-registry-contract.md) · [config v7 README](../../../.work/config/v7/README.md)
- [id_compatibility.json](../../../.work/config/v7/id_compatibility.json) · [PACKAGE_RECONCILIATION](../../../.work/guides/PACKAGE_RECONCILIATION.md)

## Procedure
1. Изменение только в `.work/config/v7/`; v5/v6 и Config Starter — evidence, не активный конфиг.
2. Переименование ID — запись в `id_compatibility.json`; неэквивалентные ID не сливать молча.
3. Нет исполняемого кода в JSON — только известные effect opcodes.
4. Любой генерируемый артефакт (будущие `.tres`) должен иметь digest и parity-проверку против источника; ручных чисел в нём нет.
5. Fail-closed: неизвестный ID, дубликат ключа, отсутствующий перевод → ошибка валидатора.

## Acceptance
- `python scripts/validate_content.py`, `python scripts/validate_work.py`, `python scripts/validate_migration.py`, `python -m unittest discover -s tests` зелёные.

## Evidence output
Список изменённых каталогов/ID, миграции, результаты валидаторов; что **не** проверено (Godot typed parity до P0-00).
