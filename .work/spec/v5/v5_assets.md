---
id: v5_assets
title: "Дополнение G. Codex/GPT imagegen: производственный AI-конвейер без иных сервисов"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_assets"></a>
## Дополнение G. Codex/GPT imagegen: производственный AI-конвейер без иных сервисов

### 32G.1. Ограничения, которые нужно честно принять

Официальный Codex imagegen SKILL предоставляет встроенную генерацию/редактирование raster assets для игр. `gpt-image-2` расходует лимиты существующей Codex подписки; отдельная API-оплата не нужна для встроенного режима, но объём массовых генераций ограничен доступностью и квотами. Нельзя требовать от агента «200 sprites одним API call»: такого договора по подписке нет. [R18](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md)[R47](https://learn.chatgpt.com/docs/image-generation)

**Генерация картинки ≠ создание готового анимированного героя.** Неизбежны ошибки пропорций, направления взгляда, оружия между кадрами, альфы и «плавающего» пивота. Для героя и 3–5 знаковых боссов допустим ручной арт-review и переработка кадров; для массовых врагов лучше ограниченные циклические 4–8 кадров, mirroring только если не вредит асимметричным деталям. Игровая система допускает 4 направления до полного обоснования необходимости 8, но художественный визуальный контракт остаётся единым.

### 32G.2. Каждый ассет — отдельная производственная единица

`asset_id`, `family`, `art_bible_rev`, `generator_mode`, `reference_ids`, `prompt_rev`, `source_png_sha256`, `source_resolution`, `runtime_size`, `direction`, `animation`, `frame_index`, `feet_anchor`, `hitbox_width`, `shadow_offset`, `palette_family`, `artist_qc_status`, `date`.

Файлы `assets_source/` хранят исходники на случай переделки; `game/assets/` — нормализованный runtime PNG с прозрачностью и manifest; `game/content/` — ресурсы/ссылки. Сигнатура `source hash → processing version → runtime hash` позволяет избежать повторной генерации, когда изменился только атлас.

### 32G.3. Конвейер на конкретный тип ассета

| Тип | Стратегия Codex | Обработка локально | Гейт качества |
|---|---|---|---|
| Концепт героя | 3–5 референсов и утверждение одного силуэта | crop/palette/size preview | визуальное совпадение с арт-библией |
| Runtime idle/walk | редактирование одного референса, кадры небольшими партиями | alignment/feet pivot/atlas | неподвижные ступни, силуэт, читаемые направления |
| Массовый враг | reusable family template, 1–2 уникальных акцента | batch strip/palette tint | различимость на уровне зума игрока |
| Босс | отдельная серия с размеченными телеграфами | hand key-frame inspection | морфология стабильна, hitbox соответствует изображению |
| Способность | ключевая форма + shader/particles через Godot | alpha extrusion, masks, overdraw | не скрывает enemy telegraphs |
| Окружение | tile/prop style-sheet и variation | edge tests, scale, anchor | повторяемый тайл без швов |
| UI | преимущественно Godot Control + code-native icons | resizable fonts, 9-slice | UI читаем и не содержит растровых мелких надписей |

Отдельный prompt на каждую миллисекунду анимации — плохая стратегия. Надёжнее использовать модель для **ключевых поз**, фиксировать геометрию/маску, промежуточные кадры дорабатывать обычными средствами (загрузка/сдвиг частей/интерполяция) и обязательно проверять на фоне игры. Не объявлять результаты исследовательских motion models production-ready без воспроизводимого smoke.

### 32G.4. Машинный QA (не подменяет человека)

Скрипт Pillow/Python проверяет `RGBA`, непустую alpha bbox, отсутствие почти сплошного opaque background, размер, число кадров, padding, frame-cell alignment, силуэтный overlap, footing drift, цветовую дистанцию от палитры, duplicate frames, orphan atlas entries, источники/hash. *Визуальная консистентность не полностью формализуема:* ручной QA героя обязателен, но может занимать 10 минут на кадры, а не полдня на поиски пропавших референсов.

### 32G.5. VRAM/RAM-практика

Ориентиры для RGBA8 без mipmaps: 2048² ≈16 MiB, 4096²≈64 MiB; с mipmaps ×≈1.33. Хранить исходные 2048/4096 PNG отдельно от более компактных runtime sprites; не держать сотни больших исходников во время игрового теста. Для 2D стартовый Lossless import обычно предпочтителен; VRAM Compression может существенно портить края и UI. Проверить масштабирование/фильтрацию на реальной сцене. [R57](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

### 32G.6. First-run validation

План AGENT_ART_001: Codex `$imagegen` создаёт **одного** xianxia героя в утверждённом стиле → 4 key poses → local Python normalize → scene `asset_qa_gallery.tscn` → screenshot comparison → статус pass/fail. Если конкретный клиент Codex не предоставляет встроенный tool, **не** подменять его платным API; использовать уже доступную генерацию в ChatGPT Plus или выполнить кодовую подготовку ассетов отдельно. Весь процесс должен быть запускаемым без других провайдеров.
