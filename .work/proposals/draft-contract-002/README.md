# DRAFT-CONTRACT-002 — воспроизводимая рука драфта

**Статус:** design-proposal. Не игровая реализация и не канонический баланс.

- [Подробный контракт](../../spec/v7/draft-contract-002.md)
- [План синтетического забега](reference_plan.json)
- [Самостоятельная Python-модель](../../../scripts/validate_draft_contract_proposal.py)
- [Негативные и воспроизводимые тесты](../../../tests/test_draft_contract_proposal.py)

Проверяется один непрерывный **RunDraftState**, который создаёт две руки по двум заработанным уровням из [SAVE-CONTRACT-001](../../spec/v7/save-contract-001.md). Глобальные Banish, charge, pity и RNG cursor сохраняются между ними. Точный replay восстанавливает из журнала команд результат выбора и карт, включая проверку подмены cursor при пересчитанной контрольной сумме.

```sh
python scripts/validate_draft_contract_proposal.py
python -m unittest discover -s tests -p 'test_draft_contract_proposal.py' -v
```

**Ограничения:** отдельный checkpoint overlay, не модифицирует строгий SAVE envelope; нет реального Godot RNG, UI, экономики и игры. Soft pity и fallback EXPLICIT_SKIP — **только тестовая policy**. Full schema migration и единственный authoritative offers cursor требуют CHOICE-SAVE-002.
