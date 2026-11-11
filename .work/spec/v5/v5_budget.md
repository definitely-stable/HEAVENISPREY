---
id: v5_budget
title: "Дополнение D. Экономика событий (главный архитектурный риск): как не получить бесконечные проки"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_budget"></a>
## Дополнение D. Экономика событий (главный архитектурный риск): как не получить бесконечные проки

### 32D.1. Отличать игровую силу от стоимости вычислений

В Soulstone-подобной механике `casts/sec` не определяет нагрузку само по себе: одна аура может сделать 1 visual pulse и 200 logical hits; один статус имеет 1 instance и 20 stack instances; реакция может породить новые события. **Сложность графа навыков** описывается `E_root ≈ Σ(path_factor × target_count × repeats × proc_probability)` — математическое ожидание полезно для дизайна, но для безопасности нужен worst-case bound.

У каждого `EffectOp` обязательны `max_targets`, `max_repeat`, `max_child_events`, `can_proc_from_proc`, `max_generation`, `hit_cooldown`, `duration_ticks`, `source` и `kill/death` flags. Компилятор content definitions строит ориентированный граф порождаемых типов событий. Для безусловных циклов `A→B→A` возвращать validation error, если нет доказуемого убывания счётчика/generation и лимита. Для ограниченных цепочек вычислять верхнюю оценку `max_events_per_root` и `max_active_attack_instances`.

### 32D.2. Почему `if queue.size() > K: drop()` — недопустимо

Простое ограничение числа событий за tick незаметно уменьшает урон сильного билда и вносит зависимость геймплея от FPS. Вместо потери событий предусмотрены **разные семантически корректные механизмы**:

1. **Ограниченные определения:** запрет unbounded skill combinations на этапе анализа контента; не «наказывать» игрока скрытой оптимизацией во время боя.
2. **Batch identical arithmetic:** сумма `n` независимых неизменных уронов при отсутствии per-hit crit/procs, shield transitions, armor rounding и on-hit policy заменяется одним `TotalDamage`. Для сложных событий — НЕ объединять без доказанной эквивалентности.
3. **Event coalescing:** VFX и numbers можно объединять всегда, когда это не меняет combat state; для gameplay требуется метаморфный oracle.
4. **Work deferral:** только для эффектов, у которых **по дизайну** допустим delay (например, волны спавна, косметические импульсы); не для срочных hit/dodge/boss telegraphs.
5. **Admission control:** если proc graph однозначно нарушает установленную способность симуляции, definition или upgrade отклоняется до публикации. Лимиты должны быть видимыми и предсказуемыми.

### 32D.3. Конкретный пример

Техника `Thousand Sword Rain`: каждые 24 тика наносит 2 удара по максимум 16 целям и накладывает Sword Mark. С upgrade `multicast.max_echoes=2`, каждый root cast максимум 3×2×16=96 candidate hits. Реакция `Mark+Thunder` максимум одна на цель на один root cast. **Upper bound** `hits + reactions ≤ 96+16` только при заданной дедупликации реакции и отсутствии реакции, создающей дополнительные прямые удары. Если техника может поражать уже поражённую цель, этот bound не годится и требуется новая формула. Конкретные числа — **синтетический тестовый пример**, не свойства реальных игр.

### 32D.4. Пакетные расчёты и memory pressure

Вместо создания нового `CombatEvent` (Object/Dictionary) на каждый hit в production-hot path использовать SoA-поля/typed packed staging buffers: `kind`, `tick`, `source`, `target`, `root_id`, `payload_idx`, `sequence`, `flags`. `Array[CombatEvent]` допустим как ясный reference implementation для golden tests, но должен быть сравним с packed approach по CPU allocations/memory. `EventView` строится только по запросу инспектора. Для таймеров statuses сравнить binary heap vs timing wheel; для grid — hash buckets vs CSR/flat counting-sort; переключать только после одинакового seeded workload.

### 32D.5. Непрерывные свойства для CI

`event_seq` монотонен внутри session; stale targets не получают hits; `OnKill` ровно один; отсутствуют отрицательные TTL; общее количество root reactions ограничено контрактом; отключение VFX не меняет `state_digest`; любой runtime timeout в тесте — failing test, а не silent success. Изменение запретов proc graph требует ADR + обновления справки игроку.
