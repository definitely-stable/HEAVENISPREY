---
name: hip-deterministic-qa
description: Design and verify deterministic tests for HEAVEN IS PREY - seeds, RNG streams, replay journals, save/restore, golden fixtures, property and metamorphic tests with negative controls. Use when adding a validator, fixture or test, or touching Save, Replay, Draft RNG, XP or Reward settlement (детерминизм, seed, replay, сохранения, golden, property, негативный контроль). Not for UI look-and-feel.
---

# hip-deterministic-qa — воспроизводимость и негативные контроли

## Use when
- Новый валидатор/фикстура/тест; изменения Save, Replay, Draft RNG, XP, Reward, exactly-once выплаты.

## Not for
- Визуальные и UX-оценки (требуют человека/скриншотов после P0).

## Canonical sources
- [FOUNDATION-2026](../../../.work/spec/v7/foundation-research-2026.md) · [gates](../../../.work/proposals/foundation-2026/README.md)
- [SAVE-CONTRACT-001](../../../.work/spec/v7/save-contract-001.md) · [DRAFT-CONTRACT-002](../../../.work/spec/v7/draft-contract-002.md) · [CHOICE-VIEWMODEL-001](../../../.work/spec/v7/choice-viewmodel-001.md)
- [XP/Pickups GAME-ARCH-01](../../../.work/spec/v7/game-arch-01-xp-pickups.md) · [BOT-QA](../../../.work/spec/v7/bot-acceptance.md)
- [EVIDENCE template](../../../.work/templates/EVIDENCE.md)

## Procedure
1. Зафиксировать seed, версии алгоритмов и content/rules digest в фикстуре.
2. Каждое правило: эталон проходит **и** заведомо неверная мутация падает (negative control). «Зелень» без негативного контроля недостаточна.
3. Metamorphic: перестановка независимых событий, разные позиции/радиусы → тот же результат и те же source IDs.
4. Persisted state: roundtrip JSON, восстановление посередине выбора, отклонение подменённого cursor/stale action.
5. Тесты — stdlib Python (unittest), без сети; Godot-паритет только после P0-00.

## Acceptance
- Новые тесты обнаруживаются `python -m unittest discover -s tests -v` (число тестов выросло), все валидаторы `scripts/validate_*.py` зелёные.

## Evidence output
Seed/fixture, команда, счётчик тестов до/после, что тест **не** доказывает (реальный Godot RNG, FPS, UX).
