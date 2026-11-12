# ARCH-02 — граф достижимости рецептов

**Статус:** design-proposal. `sample.*` контент и все числа — тестовые гипотезы.

- [Контракт](../../spec/v7/arch-02-recipe-graph.md)
- [Фикстура и golden-вердикты](reference_graph.json)
- [Эталонная модель](../../../scripts/validate_recipe_graph_proposal.py)
- [Тесты: witness/replay, ёмкость, Limit Break, циклы, конфликты](../../../tests/test_recipe_graph_proposal.py)

```sh
python scripts/validate_recipe_graph_proposal.py --report
python -m unittest tests.test_recipe_graph_proposal -v
```
