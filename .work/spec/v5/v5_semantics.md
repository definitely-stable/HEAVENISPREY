---
id: v5_semantics
title: "Дополнение C. Полный Combat Semantics Contract: хит, иммунитет, исход и владение эффектом"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_semantics"></a>
## Дополнение C. Полный Combat Semantics Contract: хит, иммунитет, исход и владение эффектом

### 32C.1. Единица симуляции — не визуальный снаряд

Объекты `SkillDef`, `SkillRuntime`, `CastAttempt`, `CastCommit`, `AttackInstance`, `HitCandidate`, `HitResolved`, `StatusApply`, `StatusTick`, `Reaction`, `Death` — разные смысловые типы. Нельзя генерировать `OnHit`, когда аура лишь пересеклась с зоной, но сработал `HitCooldown`; нельзя считать каждую частицу отдельным попаданием. Для массовых атак один `AttackInstance` способен выдать сотни `HitResolved`; на экране это могут быть 3 изображения.

### 32C.2. Состояние `EntityHandle`

`EntityHandle=(slot:int32, generation:uint32)`. Массив слотов допускает повторное использование только после увеличения `generation`; каждый боевой event хранит полный handle. `is_valid` проверяет both. `target=dead` после регистрации кандидата не означает повторное нанесение урона в следующей фазе.

Снимки состояния источника (`CastSnapshot`) сохраняют параметры, которые по контракту должны пережить смерть героя/суммона и изменение билдов. Ссылки на `Node` или mutable `.tres` недопустимы в `CombatEvent`.

### 32C.3. Порядок обработки одного попадания

```text
HitCandidate(attack_id, source, target, collision_time, contact_seq)
   -> Reject invalid target handle / immune attack family / outside active phase
   -> Consult HitLedger(target, attack_id, next_eligible_tick)
   -> Apply dodge/guard/invulnerability (separate bypass flags)
   -> Compute damage before shields and resistance
   -> Apply shield; carry optional overflow to HP; clamp HP and damage
   -> Emit resolved DamageResult(actual_shield, actual_hp, blocked, crit, overkill)
   -> Apply status if permitted, not conflating actual damage with contact
   -> Enqueue admissible OnHit/OnDamage/OnCrit reactions with provenance
   -> Mark killed once, schedule Death/OnKill/Loot once after phase barrier
```

`HitLedger` нужен для *одного attack instance* и цели, но **не может** быть общим `last_hit_at[target]`: две разные техники должны попадать независимо. Запись `(attack_instance_id, target_handle)` содержит `next_eligible_tick`; `AttackInstance` предоставляет `pierce_remaining`, `hit_interval_ticks`, `max_distinct_targets`, `hit_policy=ONCE|PER_INTERVAL|PER_ENTRY`, `life_end_tick`. Для `PER_ENTRY` дополнительно хранить enter/exit transition, иначе каждое обновление формы будет считаться новым входом.

**T1 golden:** два одинаковых клинка и одна цель: каждый попадает независимо ровно один раз. **T2:** вращающаяся аура на 90 тиков, интервал урона 30 тиков: фактические удары должны соответствовать зафиксированному включительному/исключительному правилу первого тика. **T3:** target slot освободился и занят новой целью: stale hit token не поражает нового врага.

### 32C.4. DamageResult: логическое значение вместо цифры на экране

`DamageResult` хранит `requested`, `after_armor`, `absorbed_by_shield`, `hp_lost`, `overkill`, `was_crit`, `was_blocked`, `source_root_cast`, `source_skill_id`, `target_handle`. Урон DoT может `crit=false` или `crit=true` только по явному `StatusDef.allow_crit`; `can_trigger_on_hit=false` по умолчанию. Внутри ядра *не должно* быть случайных значений для визуальных цифр: красивые шумовые колебания damage number имеют собственный presentation RNG. Для `OnDamage` стоит условие `hp_lost > 0`; `OnContact` разрешён и при нулевом уроне, если система это предусматривает.

### 32C.5. Таймеры и порядок «одновременно в один тик»

**Предлагаемый контракт M0:** кадр с `tick=k` сначала применяет запланированные команды/инпут, затем перемещение, касты, хиты, накопленные статусы, их due-tick, смерти, XP, запись digest. Если в `k` одновременно `status_apply`, `status_tick` и `status_expire`, `status_apply` видит обновление, затем `tick` по valid active status, затем `expire`; правило оформляется одним таблицным golden test. Нет мирового `Timer` на каждый стак. Все `deadline` — целые simulation ticks.

### 32C.6. Переменные принципиальные для RNG

Игровые RNG-стримы: `targeting`, `crit`, `multicast`, `upgrade`, `spawn`, `drop`. Стримы заводятся с именованными seed derivations из `run_seed`; не использовать `randomize()` в gameplay subsystems или `randi()` в UI. Сортировать одинаково равные candidate targets по `(distance_sq, entity_id)`; порядок обхода `Dictionary` не использовать как тай-брейк. **Межплатформенный byte-perfect replay не обещать**, пока не подтверждена арифметическая идентичность на обоих runner: внутренняя стабильность одной версии + одного backend является целью M0, cross-platform check — отдельный тест.

### 32C.7. Минимальная машинная проверка

Артефакт `combat_semantics.jsonl` — golden records `{tick,root_cast_id,kind,source_id,target_id,status_id,damage_hp,damage_shield,proc_depth}`. Тестовый runner сравнивает точные *целочисленные* исходы и последовательности. Для float внутренней арифметики не сравнивать platform-specific битовые представления как обязательный критерий без профиля воспроизводимости. Последовательность внешнего пользователя и game ticks сериализуются отдельно. [R07](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)[R40](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)
