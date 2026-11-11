# CURRENT_STATE — проверяемый архитектурный снимок

- **Last verified HEAD:** `main: 7a139a022c220ac1f872fe068a1d3012c3d732f2` (на момент завершения PR #7; до служебного обновления этого снимка).
- **Current milestone:** ARCH — архитектура геймплея, проверяемые статические модели и ускорение разработки. **Никакого Godot runtime, сцен, изображений или реальной игровой логики.**
- **Current slice:** [GAME-UX-001](spec/v7/game-ux-001-oct-2026.md) — ревизия существующих GAME-ARCH-00/01 и BUILD-SKILL относительно UX практик по **31 октября 2026 года**, интегрирована в `main`.
- **Open PR:** [#7](https://github.com/definitely-stable/HEAVENISPREY/pull/7) — MERGED `7a139a022c220ac1f872fe068a1d3012c3d732f2`; новых открытых PR данного изменения нет на момент снимка. Статусы перепроверять live.
- **Last CI:** [#43070365082](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43070365082) — SUCCESS на GitHub-hosted Ubuntu и Windows-2022, **113/113** статических/unit design tests для PR #7 `3b15b74509b8bf9adba30f7b229680ad31337e26`. Отдельный push-run итогового merge в `main` этим результатом **не подтверждён**.
- **Acceptance:** режимы представления выбора `IMMEDIATE/BANK_LEVELS` на уровне эталонной модели; вручную открываемые/откладываемые только обычные уровни; обязательные ритуалы ставят на паузу; единственный тик в одном event batch; XP-консолидация только для XP; сверка источника с авторитетным **синтетическим** манифестом; cross-layer проекция `XP → rank-up → evolution → BuildTransaction revision`. Новых тестов 20, всего 113.
- **Known blockers:** нет UX интерфейса, реального DraftService, настоящего Source/DropLedger, сохранения/восстановления посреди выборов, полного финального события смерти, формальной модели UI Focus/Input, фактического экрана карточек/контроллера, human playtests и метрик FPS. Auto-pick, cross-school N→M, сложная стоимость драфта остаются предложениями.
- **Next allowed action:** спецификация `ChoiceViewModel`/UX input/focus + корректные статические негативные сценарии, затем GAME-ARCH-02 (карты, boss encounters, POI). **Только архитектура и CI, без игры.**
- **Last updated from repository:** 2026-11-11.

**Важно:** `main` и CI указаны как исторический верифицированный снимок. Перед новым ответом читать GitHub. Документ `GAME-UX-001` остаётся `DESIGN PROPOSAL`, даже после merge; значения баланса и UX политики не объявляются утверждёнными.

[UX 2026](spec/v7/game-ux-001-oct-2026.md) · [Run event rules](spec/v7/game-arch-00-run-orchestration.md) · [XP contracts](spec/v7/game-arch-01-xp-pickups.md) · [Workflow](guides/WORKFLOW.md)
