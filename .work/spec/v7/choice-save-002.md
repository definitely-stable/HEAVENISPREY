# CHOICE-SAVE-002 — единый SaveEnvelope v2: забег, билд и драфт

- **ID:** CHOICE-SAVE-002 · **Дата:** 2026-11-12
- **Статус:** DESIGN PROPOSAL / STATIC REFERENCE ONLY. Не формат релизных сохранений, не Godot runtime и не утверждённый баланс (pity, число карт и зарядов остаются тестовой policy из [DRAFT-CONTRACT-002](draft-contract-002.md)).
- **Закрывает:** архитектурный долг из [SAVE-CONTRACT-001 §10](save-contract-001.md) и [DRAFT-CONTRACT-002 §7](draft-contract-002.md): отдельный overlay, второй offers cursor, отсутствие migration. Пробел GAP-CHOICE-SAVE в [SYSTEM_BINDING](../../development/SYSTEM_BINDING.md); интерфейсы IC-08 и IC-10 в [INTERFACE-CONTRACTS-001](interface-contracts-001.md).
- **Проверка:** [план фикстуры](../../proposals/choice-save-002/README.md) · [эталонная модель](../../../scripts/validate_choice_save_proposal.py) · [28 тестов](../../../tests/test_choice_save_proposal.py). Оракулы 001 и 002 не изменены; v2 переиспользует их функции.

## 1. Решения (предложение)

1. **Одна запись.** `run`, `build` и `draft` хранятся в одном запечатанном `SaveEnvelope v2` и описывают один коммит. Overlay поверх сохранения больше не нужен.
2. **Один авторитетный offers cursor.** Курсор живёт только в `rng_policy.streams.offers.cursor`; в `state.draft` копии нет (поле `rng` запрещено). Seed драфта и seed потока `offers` — одно значение. При загрузке курсор обязан совпасть с числом сырых draw, которые сделал независимый replay, включая отвергнутые блоки rejection sampling.
3. **Журнал вместо доверия к состоянию.** `receipts` (XP/события) + `legacy_choice_actions` (выборы v1, сделанные до драфта) + `draft_commands` (`OPEN/REROLL/BANISH/LOCK/UNLOCK/SELECT/SKIP` и `RESOLVE` для ритуала). Сохранённое состояние должно побитно совпасть с replay; подмена с пересчитанным checksum отклоняется.
4. **RulesHash v2** дополнительно включает хеш draft policy и алгоритм offers. Изменение числа зарядов, pity или размера руки = другая игра: resume отклоняется.
5. **RESOLVE** закрывает не-драфтовые награды (ритуал) своим доверенным резолвером и только при закрытой руке. `BREAKTHROUGH` по-прежнему не имеет резолвера и остаётся в очереди.

## 2. Миграция (fail-closed)

| Вход | Результат |
|---|---|
| v1 без overlay, offers cursor = 0 | v2 без потраченных draw; состояние билда и очереди то же |
| v1 + проверенный DRAFT-002 overlay | v2 с командами overlay; результат равен нативному v2 replay тех же команд, курсор = счётчик overlay |
| v1 с ненулевым offers cursor без журнала | **отказ**: RNG state не восстанавливается угадыванием |
| overlay другого базового сохранения, неизвестная версия, изменённая policy | **отказ** |

## 3. Focus и ввод после загрузки

Фокус сохраняется только как подсказка интерфейса (`presentation.focus_offer`): это должна быть видимая карта открытой руки, на геймплей она не влияет. После загрузки `confirm_armed = false` всегда: удерживаемая кнопка не подтверждает выбор, нужен новый release (протокол из [CHOICE-VIEWMODEL-001 §7](choice-viewmodel-001.md)). Любое изменение руки (Reroll, Lock, Unlock, Banish) делает старую focus-сессию недействительной.

## 4. Два слота и сбой во время выбора

Запись: сериализовать → провалидировать прочитанную копию → прежний `primary` становится `backup` → новый `primary`. Загрузка: `primary`, при ошибке `backup`, при двух ошибках — отказ без «пустого» сохранения. Сценарий «процесс упал во время записи SELECT»: из backup восстанавливается та же открытая рука, награда не потеряна; повтор той же команды даёт тот же результат, двойной оплаты нет. Реальные fsync/atomic rename — вопрос платформы в runtime ([SAVE-CONTRACT-001 §9](save-contract-001.md)).

## 5. Golden witness

От checkpoint SAVE-CONTRACT-001 (ревизия 7, в очереди LEVEL_UP, LEVEL_UP, RITUAL, BREAKTHROUGH): OPEN → LOCK echo → REROLL (показан новый вариант) → **сохранение посреди руки** (cursor 3) → загрузка → release → SELECT echo через focus → OPEN → BANISH thunder_conduit → SELECT echo → RESOLVE thousand_swords. Итог: ревизия 10, cursor 6, ban сохраняется, в очереди BREAKTHROUGH, XP bank 3 — тот же результат, что у непрерывного replay и у возобновления в SAVE-CONTRACT-001, но теперь через драфт.

## 6. Чего это не доказывает

Parity с Godot RNG и GDScript-сериализацией (GAP-PY-GD-PARITY), межъязыковую каноникализацию JSON (нужен JCS или типизированный формат), world-state боя, реальную атомарность записи на диск, качество pity и fallback для пустого пула.
