---
id: v5_decisions
title: "Дополнение B. Непересматриваемые решения и таблица доказательств"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_decisions"></a>
## Дополнение B. Непересматриваемые решения и таблица доказательств

**Зафиксировано по требованиям:** Godot 4.7.2 2D, typed GDScript, локальная работа на Windows 11 и GPU NVIDIA с 12 ГБ VRAM/32 ГБ RAM, Codex `$imagegen` через имеющуюся подписку, Claude Pro/Claude Code и OpenCode Go, GitHub-hosted CI. Дополнительные платные API не предполагаются; многопользовательский режим, онлайн-бэкенд и локальные нейросетевые генераторы изображений не входят в план. Игра не должна зависеть от доступности AI инструмента для запуска на ПК. [R01](https://godotengine.org/article/maintenance-release-godot-4-7-2/)[R18](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md)[R47](https://learn.chatgpt.com/docs/image-generation)

| Вопрос | Решение v5 | Основание | Пересмотр допустим при |
|---|---|---|---|
| Game engine | Godot **4.7.2 stable**, 2D | Требование пользователя + стабильный релиз [R01](https://godotengine.org/article/maintenance-release-godot-4-7-2/) | Отдельное явное решение пользователя |
| Primary language | Typed GDScript + packed arrays | Хорошая интеграция, typed opcodes [R20](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html)[R40](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) | Профиль CPU показывает неприемлемую стоимость конкретного ядра |
| Native | `godot-cpp 10.0.0` **или** `gdext 0.5.5` | Релизы доступны [R27](https://github.com/godotengine/godot-cpp/releases)[R28](https://github.com/godot-rust/gdext/blob/master/Changelog.md) | Только отдельный ADR, parity test и measured gain |
| Rendering backend | **Compatibility для первичного smoke**, отдельный Forward+ art/FX gate | Низкий baseline cost vs HDR/features [R04](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)[R41](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | A/B экспортированных сборок; не архитектурное голосование |
| Enemy storage | SoA/Packed arrays, stable entity handles | Cost модели и пользовательские кейсы [R42](https://www.reddit.com/r/godot/comments/1upc3g3/lessons_from_4_months_building_a_horde_survivor/)[R43](https://forum.godotengine.org/t/thousands-of-2d-enemies-in-plain-gdscript-flat-arrays-a-counting-sort-grid-and-multimesh/146378) | Если реальный benchmark простых Node/Area2D выигрывает |
| Presentation | Sprite2D/AnimatedSprite2D для героя и боссов; массовая орда — MultiMesh/CanvasItem buckets | Возможности и ограничения [R08](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html)[R09](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html)[R44](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html) | Visual accuracy/profiler на реальной сцене |
| Simulation tick | 60 Hz логика; независимые AI decision schedules | Точное управление боем/уклонением | Воспроизводимый 30 Hz A/B с идентичной отзывчивостью |
| Tests | Один Godot test framework после smoke, по умолчанию GUT | Предпочтение проекта | gdUnit4 6.2.3 выигрывает на чистом CI [R45](https://github.com/godot-gdunit-labs/gdUnit4/releases) |
| MCP | hi-godot/godot-ai v4.4.1 **кандидат**, необязателен | Заявлено Godot 4.7+ и Codex/Claude [R46](https://github.com/hi-godot/godot-ai/releases) | Проверка реального подключения и сохранения сцен |
| RE | Source/metadata-first → runtime trace → experiment | IL2CPP interop не раскрывает native арифметику [R49](https://github.com/lukeod/vampiresurvivors-modding/blob/main/il2cpp-guide.md) | Смена версии игры/новый технический артефакт |

**Методологическое правило:** `source verified` ≠ `behavior measured`; `feature exists` ≠ `works in this build`; `published benchmark` ≠ `target FPS`. Релизы/пакеты подтверждаются источниками, а совокупность именно нашей игры — только CI и воспроизводимым экспортом. Не путать личную NVIDIA 12 ГБ с «минимальными системными требованиями игроков»: это машина разработки и один тестовый стенд.
