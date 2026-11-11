---
id: v5_ux
title: "Дополнение I. UI, звук, управление и доступность: почему это архитектура, а не декор"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_ux"></a>
## Дополнение I. UI, звук, управление и доступность: почему это архитектура, а не декор

### 32I.1. Combat feedback data pipeline

`PresentationEvent` имеет `importance`, `category`, `screen_anchor`, `source_skill`, `target_id`, `damage_summary`, `timestamp`. На каждый `HitResolved` НЕ появляется обязательный `Label`. Агрегация damage numbers — по `(target_id, damage_category, time_bucket)` с ограниченным window (например, визуальные 100–200 ms, это **параметр для A/B**, не скрытая потеря урона). Убийство элиты и прорыв культивации имеют отдельный «крупный» feedback, а не сотню одинаковых вспышек.

`DangerOverlay`: `EnemyAttackTell` рисуется в отдельном верхнем слое до UI и имеет независимый цвет/контур. При перекрытии одной угрозы другой требуется приоритет/формы, а не аддитивный выбеливающий свет. Экран смерти показывает `last damaging attack`, `last 10 damage sources`, активные статусы, stage, seed и build summary; это полезно и разработчику.

### 32I.2. SoundManager для тысяч ударов

Не привязывать `AudioStreamPlayer` к каждому попаданию. `SoundEvent` поступает в `AudioBudgeter`: приоритет `boss_warning > player_hurt > elite_death > major_skill > routine_hits`; рядом и почти одновременно срабатывающие одинаковые эффекты объединяются, ограничивается polyphony, соблюдается приоритет музыки и предупреждений. Godot поддерживает audio buses и полифонию; раздельные `Master/Music/Ambient/SFX/Hits/UI/Warnings` позволяют независимо изменять параметры. В M0 достаточно минимального набора оригинальных звуков, необязательно сторонний AI аудиогенератор. [R59](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html)

`ducking` для telegraph/warning не должен обрывать музыкальную тему резко; предусмотреть cooldown «heavy hit sound» на один root cast вместо 200 звуков на 200 hits. Звук — также канал чтения опасности для пользователя, поэтому настройка всех спецэффектов не должна ненамеренно скрывать предупреждения без отдельной пользовательской опции.

### 32I.3. Controls и качество интерфейса

M0: WASD/стрелки, gamepad left stick, dodge (Space/shoulder), Pause, UI Accept/Cancel, full keyboard focus для menus. `Input.get_vector` deadzone настраивается (базовое значение проверять на геймпаде); при потере фокуса окна не отправлять неподтверждённые новые gameplay commands. `ui_up/down` reserved для UI, не использовать в коде движения. Экран на 16:9 и ultrawide; HUD anchors, не растровый текст внутри генераций, опции масштабирования интерфейса. [R50](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)[R60](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html)

### 32I.4. Content readability

Одни цвета не определяют стихии. `Fire` — тепло/форма языков, `Sword` — резкие секущие линии, `Thunder` — сегменты/полосы, `Doom` — замыкающаяся маркировка; силуэты работают и при сниженной насыщенности. `Quality_LOW` отключает вторичный bloom/particles, но не полосы опасности и не инфографику урона. Показать, какая техника автоматически активировалась, не заставляя читать 6 иконок в бою — использовать ненавязчивые cooldown ring / critical triggers и post-run contribution.
