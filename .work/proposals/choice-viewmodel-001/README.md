# CHOICE-VIEWMODEL-001 — эталонная рука выбора

**Статус:** DESIGN PROPOSAL; это не рабочий интерфейс и не игровой DraftService.

- [Полный контракт](../../spec/v7/choice-viewmodel-001.md)
- [Синтетическая последовательность LOCK → BANISH и сохранения](reference_plan.json)
- [Эталонный валидатор](../../../scripts/validate_choice_viewmodel_proposal.py)
- [Положительные/отрицательные тесты](../../../tests/test_choice_viewmodel_proposal.py)
- [SAVE-CONTRACT-001](../../spec/v7/save-contract-001.md) — связанный, но пока отдельный контракт сериализации.

## Что считается доказанным после зелёного CI

`sample.offer.echo` можно закрепить, `sample.offer.new_thunder` убрать из предложений, и оба вспомогательных действия не потребляют заработанный LEVEL_UP. История действий, hand, cursor и charges восстанавливаются из отдельного DraftCheckpointOverlay, привязанного к контрольной сумме сохранённого базового RunState. Ресурс нельзя повторно списать тем же InteractionUid. Повтор SELECT/SKIP возвращает подтверждённый результат. При отсутствии альтернатив Reroll не списывает charge. При наличии альтернатив Reroll обязан вывести хотя бы одну не показанную прежде карту.

```bash
python scripts/validate_choice_viewmodel_proposal.py
python -m unittest discover -s tests -p 'test_choice_viewmodel_proposal.py' -v
```

## Важные границы

Эталонная рука использует **синтетический** хеш-генератор SHA-256 с весами sample-каталога. Это не принятые вероятности и не Godot RNG. Настоящее сохранение пока не включает этот overlay внутри строгой схемы SAVE-CONTRACT-001; интеграция требует следующего versioned slice. Localized title и реальный damage delta отсутствуют намеренно, чтобы не выдавать придуманные свойства за достоверные. Никаких новых канонических навыков, валют или числовых лимитов в v7 не добавлено.
