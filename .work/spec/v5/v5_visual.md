---
id: v5_visual
title: "Дополнение F. Godot 2D presentation: от декларации «MultiMesh» к работающей схеме"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_visual"></a>
## Дополнение F. Godot 2D presentation: от декларации «MultiMesh» к работающей схеме

### 32F.1. Три класса отображаемых объектов

- **Unique actors:** Player, elites, bosses, важные summon — `Sprite2D/AnimatedSprite2D/AnimationPlayer` с ручным/заданным `z_index`, `y_sort_enabled` по дереву. Стандартный SceneTree облегчает контекстные анимации и QA.
- **Bulk enemy families:** подходящие толпы с общей текстурой/атласом, материалом и совместимой схемой глубины → `MultiMeshInstance2D` *в пределах depth band или эквивалентной bucket policy*. Не ожидать индивидуального Y-sort внутри одного multimesh; нужно проверять порядок фронта/задника на сцене.
- **Transient visual effects:** большие волны, aura, мечи, числа урона, телеграфы — отдельные render queues. Ударные вычисления не создают автоматически `Node` или particle на каждый event.

Godot уже выполняет 2D batching в разных рендерах. Значит, `MultiMesh` не следует выбирать по интуиции: сравнить `AnimatedSprite2D` и `MultiMeshInstance2D` **с одинаковой анимацией, альфа-площадью и Z-order**, измеряя draw calls, CPU submissions, visible objects, overdraw и корректность. Официальное описание `MultiMeshInstance2D` прямо отмечает компромисс между снижением fill rate и повышением vertex processing. [R09](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html)[R40](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)[R44](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html)

### 32F.2. Атлас и индивидуальная анимация внутри инстансинга

`MultiMesh` поддерживает per-instance `INSTANCE_CUSTOM`; конкретное упаковочное представление выбирается после теста с shader `CanvasItem`. *Важная проверка:* у режима Compatibility custom data может иметь меньшую точность (16-bit components), поэтому нельзя кодировать произвольные огромные целочисленные frame/atlas IDs с ожиданием точного восстановления. Нужны нормализованные frame indexes и тест round-trip на выбранных рендерах. [R08](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html)[R52](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html)

Не использовать `AtlasTexture`/`SpriteFrames` как магический GPU-animation path: это удобные resource abstractions, но для batched per-instance frames нужна явная UV-логика шейдера и согласованный `atlas_frame_grid`, у ассетов — padding/extrusion. При различной ширине/высоте и развороте персонажа требуется shader или предварительная нормализация canvas sizes, иначе кадры будут смещаться. Не менять случайно per-instance data каждую миллисекунду, если frame rate sprite анимации только 10–15 fps.

### 32F.3. Y-order и culling

Существуют два решения: (A) несколько depth strips/buckets по мировой y-координате и отдельные draw items для actor/boss, (B) `RenderingServer` canvas_items для индивидуального sort на горячих группах. Вариант A проще и потенциально быстрее, но может порождать ошибки «ноги проходят сквозь тело» и много draw calls. Реальный выбор по тесту `occlusion_gauntlet`: герой пересекает диагональную колонну врагов и оказывается за/перед каждым из них согласно feet_y. Нельзя принимать визуальную ошибку за «не важную оптимизацию»: для изометрии глубина — основа воспринимаемого пространства.

Для отдельных multimesh chunks задавать корректные bounds и не простирать один mesh на весь мир: multimesh culling как цельного объекта делает рендер всех инстансов частично видимого chunk. Visible sets составлять *через camera query*, а симуляция offscreen делает работу по собственной политике; это не одно и то же. [R08](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html)

### 32F.4. Временная интерполяция

`prev_position` и `curr_position` — snapshot во время `tick`. Presentation движется с `alpha=accumulator/fixed_dt`; для телепорта и respawn интерполяцию сбрасывать. Интерполяция Godot 2D имеет особые правила для server-side objects, а GPU particles не обязаны двигаться по той же временной модели. Сопоставить частоту анимации спрайтов (10–15 fps как предложенный художественный ориентир), physics tick 60Hz и монитор 60–180Hz без зависимости состояния игры от FPS. [R06](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html)[R53](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html)

### 32F.5. Эффекты и нагрузка на фрагменты

Каждый FX имеет `criticality`: `enemy_warning`, `impact_key`, `aura_information`, `decorative`. VFX-budget зависит не только от количества частиц, но и от суммарной площади прозрачных объектов, слоя сложения/фильтрации, material/shader cost и размера окна. На 3440×1440 GPU fillrate может стать важнее, чем на 1920×1080. Не считать `12 GB VRAM` обещанием скорости: VRAM capacity и вычислительные возможности GPU — разные факторы. Официальная статья Godot от 15.09.2026 отдельно показывает, что ускорение CPU батчинга может ухудшать GPU-работу — нужны оба профиля. [R54](https://godotengine.org/article/rendering-cpu-optimizations/)

### 32F.6. Quality settings, но независимая симуляция

`FX_LOW`: меньше декоративных particles/blur/glow, компактные damage labels; `FX_HIGH`: больше вторичного свечения/декора. В обоих режимах **одинаковые** `hits/DoT/crit/XP`, `telegraph bounds`, цвет/геометрия угроз. Нужен автоматический `state_digest(FX_LOW)==state_digest(FX_HIGH)` на нескольких seeds и частотах кадров. Раздельные регуляторы эффектов **игрока**, **врагов** и **постобработки**; отключение эффектов игрока не убирает предупреждения боссов. Этот контракт отражает зафиксированные проблемы Soulstone со стоимостью/настройкой собственных эффектов. [R55](https://steamdb.info/patchnotes/16793333/)[R56](https://steamdb.info/patchnotes/23706374/)
