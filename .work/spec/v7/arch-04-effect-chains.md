# ARCH-04 — типы эффектов, происхождение урона, конечность цепочек реакций

- **ID:** ARCH-04 · **Дата:** 2026-11-12
- **Статус:** DESIGN PROPOSAL / STATIC REFERENCE ONLY. Fanout, заряды и ёмкости профилей — гипотезы для тестов; профиль ёмкости — цель проверки, **не** правило отбрасывания в runtime.
- **Основа:** [ARCH-01 §7](build-skill-type-contract.md), [FLEXIBILITY-FIRST-001 §6 и §9](flexibility-first-build-policies.md), BLD-11/18/25 в [OPEN_DECISIONS](../../proposals/build-skill-001/OPEN_DECISIONS.md), канонические [statuses.json](../../config/v7/statuses.json).
- **Проверка:** [фикстура](../../proposals/arch-04-effect-chains/reference_effects.json) · [эталонная модель](../../../scripts/validate_effect_chain_proposal.py) · [18 тестов](../../../tests/test_effect_chain_proposal.py). Закрывает GAP-ARCH-04 в [SYSTEM_BINDING](../../development/SYSTEM_BINDING.md).

## 1. Типы эффектов (discriminated union)

| `op` | Обязательные поля | Порождает событие |
|---|---|---|
| `CHAIN` | `jumps`, `unique_targets`, `damage_ref` | `HIT` × jumps, origin каста |
| `PROJECTILE` | `count`, `pierce`, `damage_ref` | `HIT` × count·(pierce+1), origin каста |
| `ZONE` | `duration_ticks`, `tick_interval_ticks`, `max_targets_per_tick`, `damage_ref` | `HIT/zone` × тики·цели |
| `SUMMON` | `attacks`, `targets_per_attack`, `lifetime_ticks`, `damage_ref` | `HIT/summon` |
| `APPLY_STATUS` | `status_id`, `stacks`, `duration_ticks` | `STATUS_APPLIED` + `STATUS_TICK/dot` по `tick_period_ticks` статуса |

Неизвестный вид, отсутствующее или лишнее поле, неверное значение, статус не из v7, статус игрока на врага, стаки выше `max_stacks` отклоняются с кодами `E_OP_KIND`, `E_OP_FIELD_MISSING`, `E_OP_FIELD_UNKNOWN`, `E_OP_VALUE`, `E_STATUS_REF`, `E_STATUS_TARGET`. Новые механики добавляются новым видом op с собственной схемой и тестами, а не произвольным кодом.

## 2. Происхождение (provenance) и атрибуция

Каждое событие несёт `uid`, `parent`, `root`, `generation`, `origin`, `via` (op или триггер), `credited_skill`, `contributors`.

- **origin:** `primary` (только прямые op основного каста), `echo` (multicast), `proc`, `zone`, `summon`, `dot`, `reaction`. Триггер не может выдать `primary` (`E_ORIGIN_PRIMARY`).
- **DoT-тик** — не `HIT`: его порождает только op статуса, он атрибутирован наложившему умению и сам по себе ничего не триггерит. Триггер не может порождать тики (`E_TRIGGER_EMITS`).
- **Зоны и призывы** атрибутированы создавшему умению; on-hit эффекты срабатывают от них только при явном `accepts_origins` (opt-in меняет доказанную оценку, а не скрыто).
- **Реакция** атрибутирована триггеру-источнику, `contributors` — владельцы обоих статусов (например, шок молнии + горение талисмана); без нужного статуса на цели реакция не возникает.
- **Echo-каст** сохраняет владельца и тратит одно поколение; echo от echo — только явный opt-in с доказанной конечностью.

## 3. Конечность: три способа доказательства

1. **Ациклический граф:** `W(v) = 1 + Σ fanout·W(child)` — точная оценка худшего случая.
2. **Бюджет поколений профиля:** `W(v,g)`, каждое ребро триггера тратит поколение (как в ARCH-01).
3. **Убывающий ресурс на корень:** каждое ребро внутри цикла тратит ≥1 единицу ресурса с конечным начальным запасом, никакое ребро цикла его не восполняет (`E_CYCLE_REFUND`). Оценка SCC: `(1 + K)·(1 + max_tail)`.

Цикл без любого из способов — `E_UNBOUNDED_CYCLE` (INVALID_SEMANTICS). Рекурсия **не запрещена** глобально: ограниченная цепочка «Резонанс» (6 зарядов) проходит в любом профиле.

## 4. Вердикты профиля и запрет скрытого отбрасывания

Модель строит дерево худшего случая (все fanout максимальны, условия истинны) с provenance. Если раскрытие превышает собственную доказанную оценку — это ошибка доказательства (`E_BOUND_PROOF`), а не повод обрезать события.

| Вердикт | Условие | Действие |
|---|---|---|
| `VALID_FOR_PROFILE` | доказанная оценка ≤ ёмкости | принять для профиля |
| `BOUND_TOO_COARSE` | оценка > ёмкости, худший случай модели ≤ | нужна точнее оценка/сценарий, не бан |
| `PROFILE_EXCEEDED` | худший случай > ёмкости | не для этого профиля; другой режим или оптимизация с паритетом |

Golden: Spirit Sword с multicast и резонансом — оценка 147 и худший случай 45 (`BOUND_TOO_COARSE` для 128); Talisman Seal — 96 (`PROFILE_EXCEEDED` для 64, валиден для 128). Это логические события, не CPU и не FPS.

## 5. Чего это не доказывает

Реальную стоимость кадра, формулы урона и квантизацию, стаки/обновление статусов во времени, сериализацию цепочки в save (GAP-PY-GD-PARITY), удовольствие от комбо. Ресурс общий на корень; ресурсы, переживающие корень (заряды на умении), — следующее расширение.
