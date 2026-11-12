# ARCH-04 — эффекты, provenance и конечные цепочки

**Статус:** design-proposal. Fanout, заряды и ёмкости профилей — тестовые гипотезы, не баланс.

- [Контракт](../../spec/v7/arch-04-effect-chains.md)
- [Фикстура и golden-вердикты](reference_effects.json)
- [Эталонная модель](../../../scripts/validate_effect_chain_proposal.py)
- [Тесты: схема op, provenance, циклы, вердикты профиля](../../../tests/test_effect_chain_proposal.py)

```sh
python scripts/validate_effect_chain_proposal.py --report
python -m unittest tests.test_effect_chain_proposal -v
```
