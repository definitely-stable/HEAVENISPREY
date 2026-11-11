# SAVE-CONTRACT-001 — проверяемый эталон сохранения забега

**Статус:** DESIGN PROPOSAL. Не сохраняет файлы Godot и не реализует реальную игру.

- [Контракт и архитектурные границы](../../spec/v7/save-contract-001.md)
- [Исходный план и ожидаемые переходы](reference_plan.json)
- [Python reference oracle](../../../scripts/validate_save_contract_proposal.py)
- [42 отрицательных и положительных теста](../../../tests/test_save_contract_proposal.py)
- [Связанный выбор и эволюция](../../../scripts/validate_choice_bridge_proposal.py)
- [SOURCE-UX bridge](../../spec/v7/game-ux-001-oct-2026.md)

## Reproduce (stdlib, no local game)

```bash
python scripts/validate_save_contract_proposal.py
python -m unittest discover -s tests -p 'test_save_contract_proposal.py' -v
```

## Synthetic witness

Отдельный существующий каталог навыков и событие XP связываются через `RunBuild.revision`. В середине пяти стратегических решений после первого повышения ранга (rev=7) создаётся снимок. Он хранит versioned header, Python reference `content_digest` и `rules_hash`, четыре явно названных RNG-потока с нулевыми cursor, полный ledger доверенных синтетических reward receipts, source_manifest, историю выборов, состояние очереди и синтетического билда. После JSON roundtrip сравнивается восстановленный state с независимым повторным применением тех же receipt/choice actions. Два Powers и ритуальная эволюция доводят ревизию до 10, оставляя прорыв в очереди.

### Обязательные ограничения доказательства

- Хэш `SHA-256` нужен для обнаружения порчи, **не** для скрытой защиты от редактирования пользователем.
- `hash_json` использует Python `sort_keys=True`, **не** RFC 8785; переносимость к GDScript/ECMAScript требует отдельной проверки vectors.
- Потоки RNG не порождают настоящих случайных значений; имитации draw нет.
- Данные world-state/physics/realtime/DoT/EnemyStore и атомарная запись файла не симулируются.
- Проверки receipt source основаны на **доверенной фикстуре**, а не реальном `DropLedger`.
- Форматная миграция v0→v1 — **искусственный пример**, а не утверждение поддержки старого сохранения реальной игры.
- Нельзя интерпретировать успешный CI как автоматическое утверждение новых игровых правил.

Изменяя replay-семантику, обновляйте связанный скрипт, `reference_plan.json`, негативные тесты, основной контракт и traceability **одним** PR с успешным Windows/Linux CI.
