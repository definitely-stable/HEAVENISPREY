---
id: v5_tests
title: "Дополнение L. Тестирование и бенчмарки v5: не только 5000 врагов и не только FPS"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_tests"></a>
## Дополнение L. Тестирование и бенчмарки v5: не только 5000 врагов и не только FPS

### 32L.1. Пять слоёв проверок

| Уровень | Что запускать | Условия успеха |
|---|---|---|
| Schema/content | JSON/Resource definitions, cross-reference validator | нет отсутствующих IDs, запрещённых циклов, отрицательных TTL |
| Deterministic unit/golden | Combat kernel 1–30 entities, точные тик-события | reference transcript совпадает; failing sentinel останавливает CI |
| Property/metamorphic | тысячи seeded random builds, противоречивые upgrades | отсутствие NaN, дубликатов OnKill, stale-target hits, unbounded queue |
| Headless simulation load | 500/1000/2500/5000 врагов, 0/20k statuses, burst | p50/p95/p99 sim tick; determinism; нет роста памяти без границы |
| Exported graphical smoke | Windows/Linux build с VFX_LOW/HIGH, 1080p/1440p и ultrawide | реально измерен FPS/frametime, все угрозы видны, звук не прерывается |

CI не делает GPU performance benchmark автоматически, если у hosted runner нет соответствующего графического окружения. **Headless не равен 60 FPS в релизной игре**; реальный тест графики запускается на отдельном стенде и прикладывается как артефакт. Для native optional — отдельный benchmark без зависимости основного unit suite.

### 32L.2. Лучшие тесты против самых опасных багов

```text
combat/golden/
  001_two_weapons_same_target.json
  002_aura_repeat_hit_interval.json
  003_target_reused_slot_generation.json
  004_dot_refresh_at_expiry_tick.json
  005_status_source_attribution.json
  006_multicast_no_recursive_echo.json
  007_reaction_cycle_validation_error.json
  008_simulation_identical_vfx_off_on.json
  009_boss_telegraph_safe_escape.json
  010_upgrade_draft_no_dead_end.json
  011_pause_does_not_advance_sim_ticks.json
  012_save_reload_replay_same_digest.json
```

**Метаморфные тесты** сильнее простого `assert_damage==10`: если тот же seed и input запустить с `fx_quality=LOW/HIGH`, результаты должны быть одинаковыми; сортировка candidate inputs перед `TargetSelector` не должна менять цель; 100 мелких шагов и их точный референс не должны зависеть от смены fps presentation. Для сложных непереупорядочиваемых hits специально тестировать порядок «щит снят → следующий удар бьёт по HP».

### 32L.3. Статистическое тестирование механик

`MulticastPolicy`: при `N=100_000` независимых проверок с фиксированными seeds убедиться, что среднее количество echoes соответствует математическому ожиданию в статистическом доверительном коридоре; проверить, что одни и те же `Crit RNG` результаты не меняются при отключении аудио. `SpawnDirector`: для 1000 random run seeds измерить расстояние до игрока, количество успешных/отложенных спавнов, долю перекрытия препятствий, максимальную плотность. `UpgradeDraft`: строить heatmap недостижимых билдов, а не только максимальный DPS. Точные приемочные пороги утвердить после первых базовых данных.

### 32L.4. Протокол производительности

Фикстура хранит `fixture_id`, `engine_sha`, `git_head`, `runner_os`, `CPU/GPU model`, `resolution`, `renderer`, `vsync`, `export_type`, `seed`, `duration_s`, `enemy_count`, `active_status_count`, `events/sec`, `sim_p50/p95/p99`, `frame_p50/p95/p99`, `draw_calls`, `VRAM/RAM peak`, `notes`. Разогрев 20–60 секунд (предложение); отдельно записать cold-start/shader stutter. На каждый кандидат минимально три прогона. Результаты графических tests и headless tests **не смешивать в один график**.

**Критерий GDExtension:** профиль **экспортированной** сборки показывает CPU hotspot внутри конкретной функции ≥ заранее выбранного budget; переписаны алгоритмы/память, но проблема осталась; batch FFI прототип превосходит typed GDScript на том же hardware/seed и проходит golden parity; Windows/Linux проходят CI. Отдельно сравнить с ускорением через `Packed*Array` и изменением grid. Нельзя выбирать C++ или Rust по званию «быстрее» до теста реальной границы данных.

### 32L.5. Детерминизм и обновления Godot

Официальная документация `RandomNumberGenerator` подчёркивает, что PCG32 — деталь реализации и **не гарантируется как неизменный алгоритм**. Для replay хранить `engine_version`, `game_build`, `content_hash`, `rng_state`; при обновлении движка проводить replay migration A/B. Для долгосрочно переносимых по версиям повторов лучше небольшой собственный тестируемый integer PRNG, но M0 может использовать встроенный `RandomNumberGenerator` с ограниченным обещанием reproducibility одной версии. [R07](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)
