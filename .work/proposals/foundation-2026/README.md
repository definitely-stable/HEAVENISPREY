# FOUNDATION-2026 — исследовательские источники и проверяемые архитектурные ограничения

**Scope:** design-only; `gates.json` — перечень проектных требований, НЕ канонические игровые параметры и НЕ доказательство работающей игры.

- [Сводный анализ и применимость](../../spec/v7/foundation-research-2026.md)
- [JSON-реестр foundation gates](gates.json)
- [Validator](../../../scripts/validate_foundation_gates.py)
- [Seeded/metamorphic/negative tests](../../../tests/test_foundation_2026.py)

### Проверка без Godot

```sh
python scripts/validate_foundation_gates.py
python -m unittest discover -s tests -p 'test_foundation_2026.py' -v
```

### Что реально проверяется

15 проектных пунктов и 15 привязанных источников, отсутствие дублирующих/отсутствующих/циклических зависимостей, сохранение `design-proposal` и `architecture_only`, ссылки на существующие repo docs, запрет преждевременного перевода `deferred` в немедленный runtime. Рандомизированные, но фиксированно seed-овые тесты на существующие модельные функции: pickup XP equivalence при пространственной консолидации, deterministic event reorder и проверка кредитуемой суммы по синтетическому манифесту.

### Не проверяется

Истинность стороннего исследования, реальная физика Godot, FPS, экономический баланс, качество PCG, UX/retention, работоспособность будущего DraftService. Статус каждого foundation gate — проектный, до отдельного решения.

### Правило работы агентов

Изменение foundation gate требует обновить связанный документ, `gates.json`, доказательство и негативный тест, затем GitHub CI. Не менять `.work/config/v7` и не начинать игровой runtime этим срезом.
