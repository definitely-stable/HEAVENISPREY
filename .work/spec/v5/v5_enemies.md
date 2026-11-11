---
id: v5_enemies
title: "Дополнение E. Игрок, враги, элиты и боссы — недостающая игровая архитектура"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_enemies"></a>
## Дополнение E. Игрок, враги, элиты и боссы — недостающая **игровая архитектура**

Прежний текст проектировал мощный damage computer, но почти не отвечал, *во что игрок играет каждую секунду*. У Vampire Survivors и Soulstone Survivors атаки автоматические, но игрок обязан принимать непрерывные пространственные решения. Если враги бегут по прямой и не сообщают о своих атаках, получится технический демонстратор, не игра.

### 32E.1. Input и движения героя

`InputAdapter` читает клавиатуру/геймпад, выдаёт `MoveCommand(unit_direction, dodge_pressed, tick, sequence)`. С помощью `Input.get_vector()` применить выбранную deadzone, а для аналогового геймпада нормализовать диагональ. В M0 персонаж **не выбирает вручную, куда направить каждое умение**: target policy делает это автоматически. Dodge — отдельная короткая активная команда, не ручная атака. [R50](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)

`PlayerController` содержит `position`, `velocity`, `radius`, `move_speed`, `dodge_cooldown_end`, `dodge_duration_ticks`, `invulnerable_until_tick`, `stagger_until`, `input_disabled_until`, `health/shield`. Правила: запуск уклонения при готовом cooldown; направление уклонения — текущая движение или последнее ненулевое; `IFRAMES` применяются к категории вражеского урона, но не ко всем script events; не удалять отрицательные эффектов уклонения из пула, если это не прописано в design. Dodge имеет короткую восстановительную фазу только если игровыми тестами доказана её полезность.

`PlayerCollision`: на плоской арене M0 собственная геометрия границы + разрешение круга героя с простыми статическими препятствиями. Большая орда использует мягкое separation и ограничение вхождения врагов в героя, но **не** тысячи `CharacterBody2D`. При добавлении сложных препятствий вводится отдельная `ObstacleGrid`/navigation adapter; не запускать pathfinding для каждого врага каждый tick. [R51](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html)

### 32E.2. Enemy AI не должен быть одним алгоритмом Chase

Разделить enemy families:

| Семейство | Поведение | Параметры | Уязвимые места |
|---|---|---|---|
| `Swarm` | приближается и окружает | speed, separation, contact damage | плотность, contact damage spam |
| `Flanker` | заходит с края маршрута героя | flank direction, lead time | path replanning overhead |
| `Charger` | windup → lock direction → dash → recovery | lane width, lock tick, speed | телеграф нечитаем при VFX |
| `Ranged` | держит дистанцию, выпускает telegraphed projectile | preferred range, shot rhythm | нет безопасного маршрута |
| `Support` | временно усиливает орду, приоритетная цель | aura radius, duration | не дать бесконечный buff stacking |
| `Elite` | 2–3 паттерна с фазовым переходом | HP threshold, pattern weights | fps и screen clutter |
| `Boss` | строго авторская FSM, предсказуемые окна атаки | telegraph, recovery, arena rule | unfair hits, малозаметные предупреждения |

M0 достаточно `Swarm` + `Charger` + один `Elite`, но весь контракт `EnemyDefinition` должен допускать расширение без наследования огромного дерева `EnemyBase`.

### 32E.3. Spawn Director: сложность должна быть управляемой

`WaveDirector` формирует `spawn_intent(time_window, budget, archetype_weights, min_distance, max_onscreen_density, spawn_lanes, elite_reserved_slots)`. **Не спавнить у игрока за спиной на расстоянии одного касания**, если это не явная особая механика с телеграфом. Для группы выдаётся `spawn_group_id`; частоты волн зависят от run clock и сложности, а не FPS. `SpawnDirector` делает несколько воспроизводимых попыток найти подходящую позицию, затем откладывает spawn (а не помещает его внутрь препятствия).

При слишком высокой плотности орды **не** заменять 50 врагов невидимым mega-enemy без игрового сообщения. Допустимо делать новые волны сильнее, реже, использовать `DirectorBudget` и эстетически объединять дальние группы только если их столкновения/результаты остаются корректными или правило явно предусмотрено дизайном. Тест на спавн должен прогоняться при герое около края и вокруг препятствий.

### 32E.4. Телеграфы и честность боссов

Три фазы: `Tell` (без нанесения урона), `Commit` (закреплена геометрия/target lock), `Active` (точное окно получения урона), затем `Recovery`. Телеграф занимает **высший визуальный приоритет** и имеет свой semantic area shape, совпадающий с hit shape в заранее заданном допуске. Яркая xianxia вспышка игрока не вправе скрыть стрелку/линию опасной атаки. Настройка `player_effect_opacity` не изменяет `enemy_telegraph_opacity`.

Проверки: движение/уклонение реально позволяют избежать атаки в человечески осуществимом окне; нет мгновенного изменения направления после commit; при низком FPS поведение не становится непредсказуемым; визуальная рамка телеграфа не уступает анимации удара. Единицы времени в спецификации — `ticks`, не «кадры анимации». Проигрывание картинки и окно коллизии должны быть синхронизированы через contract, а не случайные `animation_finished` callbacks.

### 32E.5. Арена, камера и визуальный мир

В M0 **статичная арена**, без бесконечных chunked tiles. В M1 — choice `finite arena` vs `streamed repeating world` после playtest. Зависимые компоненты: `ArenaDef` хранит bounds, blocked polygons, spawn lanes, encounter anchors, loot limits; `CameraDirector` — follow smoothing, zoom cap, hit-shake envelope, clamp to bounds; `TileMapLayer` — покрытие земли и декор. **Не** генерировать pathfinding mesh на каждом мелком изменении карты; у TileMap navigation есть задокументированные ограничения. [R51](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html)

Для «изометрического» образа Godot 2D используем единое логическое 2D `Vector2` движение на плоскости, а графическую псевдоизометрию создаёт проекция/арт, а не переписываем всю физику. Если ассеты используют ромбическую сетку, выбрать одну обратимую матрицу `world→screen`, её inverse и протестировать. Обязательно разграничить `collision feet position` и изображаемый sprite root/pivot. В общем случае `depth` определяется `foot_y`, не верхом спрайта и не его текстурным bounding box.
