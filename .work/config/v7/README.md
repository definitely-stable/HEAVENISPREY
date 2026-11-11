# v7 — версионированные игровые конфиги

**Это дизайн-фикстуры, а не готовые ресурсы Godot**. Любые числовые значения — гипотезы до ботов и human playtest.

- [Сложности](difficulty_profiles.json) · [Открытия](unlock_rules.json)
- [Валюты](currencies.json) · [Награды](reward_contract.json)
- [Режимы](modes.json) · [Поздние таланты](late_talents.json)
- [Новые ключи локализации](localization_additions.csv)

Прежде чем вводить в проект, построить ContentRegistry, проверить уникальность ID, условия открытий, отсутствие циклов в talents, ключи перевода, idempotent settlement. При изменении schema_version нужна миграция и тесты. Команды: python scripts/validate_work.py и python -m unittest discover -s tests -v.
