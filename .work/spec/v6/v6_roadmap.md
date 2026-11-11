---
id: v6_roadmap
title: "AA. Пересмотр roadmap: теперь M1 — полный цикл с валютой и языками, а не демонстрация снарядов"
source: architecture-v6-2026-11-11
status: superseded-by-v7
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> **Правила частично переопределены:** [v7 — поздняя прогрессия](../v7/late-game-progression.md) и [ADR-003](../../decisions/ADR-003-late-game.md).

<a id="v6_roadmap"></a>
## AA. Пересмотр roadmap: теперь M1 — **полный цикл с валютой и языками**, а не демонстрация снарядов

| Slice | Реализация | Автоматическая приёмка | Зависит от |
|---|---|---|---|
| `P0-00` | Godot 4.7.2/2D, typed GDScript, GUT, CI Windows/Linux | clean import, unit+negative test, export smoke | нет |
| `P0-01` | Combat Semantics, EventQueue, fixed ticks, replay harness | golden states, no unbounded proc | P0-00 |
| `P0-02` | ContentRegistry и JSON schema validator; ID, localization key contract | unknown refs/keys/ranges fail CI | P0-00 |
| `P0-03` | LanguageService и RU/EN в тестовом меню, font QA | runtime switch, pseudo text, seed invariant | P0-02 |
| `P0-04` | PlayerCommand, 2–4 простых BotPolicy, headless runner | deterministic run output, same kernel | P0-01 |
| `M1-01` | Два класса: меч и гром; автоатаки; статусы; 5-минутная карта | полный игровой забег, boss/result | P0-01..04 |
| `M1-02` | ProfileSave v1, RunResultReceipt, SpiritStones, ранговые общие таланты | exactly-once reward, purchase/refund/migration | M1-01 |
| `M1-03` | Standard/Apprentice/Hard пресеты, простой StageDef/RewardDef, difficulty UI | один seed, разные mode rules; открытие hard, честная награда | M1-02 |
| `M1-04` | Class mastery/achievement unlock, первая специализация, RU/EN full first loop | победа → камни/XP → талант → новый забег; layout/screens | M1-03 |
| `M2-01` | Hurry, Frenzy, Ascetic, Training; mode combination/compatibility rules | replay+rewards+UI semantics | M1 |
| `M2-02` | ProgressionBot, FarmerBot, DifficultyBot, economy simulation reports | 20–100 sequential runs; no duplication/arbitrage | M1 |
| `M2-03` | Редактор контента/скрипты генерации QA, stage/wave presets | генерация новой карты/режима только данными | M2-01 |
| `M3-01` | 20–30 минут, несколько карт, полноразмерные боссы и Tribulation/Endless | full run states, memory/time cap, high-tier bots | M2 |
| `M3-02` | 3-й и 4-й классы, больше специализаций, испытания | каждое открытие/сейв/перевод/класс имеет tests | M3-01 |
| `M4` | Performance VFX polish, human playtests, контент, новые языки после QA | ship criteria, handoff report, no known P0 | M3 |

**Реальное требование первого playable:** интерфейс RU/EN, выбор одного из двух классов, выбор `standard` или `apprentice`, 5 минут игры с автоматическими атаками и уклонением, смерть/победа, экран наград, **покупка хотя бы одного общего таланта**, следующий забег с измеримым отличием, один бот проходит тот же путь headless. Это сильнее, чем старый MVP «1000 врагов в сером квадрате».

**Budget scope:** в M1 не требуются анимации 8 сторон для всех 4 классов, 20 талантов на персонажа, полноценный Endless и китайский перевод. Требуется **готовность архитектуры** к ним и отсутствие data/model lock-in. Реализация M1 даже с AI остаётся многоэтапным проектом; не объявлять его выполненным по наличию концепта или спецификации.
