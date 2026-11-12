# CHOICE-SAVE-002 — единый SaveEnvelope v2

**Статус:** design-proposal. Не игровая реализация и не канонический баланс.

- [Контракт](../../spec/v7/choice-save-002.md)
- [План фикстуры и golden-значения](reference_plan.json)
- [Эталонная модель](../../../scripts/validate_choice_save_proposal.py)
- [Тесты: reload, cursor, stale, focus, два слота, миграция](../../../tests/test_choice_save_proposal.py)

Сценарий начинается с checkpoint из [SAVE-CONTRACT-001](../save-contract-001/README.md), мигрирует его в v2, открывает руку по policy из [DRAFT-CONTRACT-002](../draft-contract-002/README.md), сохраняет посреди руки, загружает и доводит до ритуальной эволюции. Golden-значения в `expected` получены этой моделью и проверяются в CI.

```sh
python scripts/validate_choice_save_proposal.py
python -m unittest tests.test_choice_save_proposal -v
```
