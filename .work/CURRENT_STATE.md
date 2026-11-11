# CURRENT_STATE — снимок проверки по репозиторию

- **Last verified HEAD:** `main: e2b19d98a38fbdc090b3ad5d4a1e87c9a554ecb7` (до служебного обновления этого снимка).
- **Current milestone:** ARCH — только архитектура геймплея, проверяемые контракты и ускорение будущей разработки. **Godot / game runtime / ассеты не создавались и не разрешены текущим scope.**
- **Current slice:** [GAME-ARCH-00](spec/v7/game-arch-00-run-orchestration.md) и [GAME-ARCH-01](spec/v7/game-arch-01-xp-pickups.md) — новые проектные контракты событий/паузы/XP; [GAMEPLAY-GAP-001](spec/v7/gameplay-loop-gap-audit.md) — карта пробелов. ARCH-01/BUILD-SKILL остаётся параллельной архитектурной зависимостью.
- **Open PR:** по текущему выполненному пакету нет: [#4](https://github.com/definitely-stable/HEAVENISPREY/pull/4) — MERGED `4280c9d7470ff2305fe22829bc88152a7686461c`; [#5](https://github.com/definitely-stable/HEAVENISPREY/pull/5) — MERGED `e2b19d98a38fbdc090b3ad5d4a1e87c9a554ecb7`. Новые PR проверяются отдельно, это исторический снимок.
- **Last CI:** [#43048905916](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43048905916) — SUCCESS на Windows-2022 и Ubuntu для HEAD PR #5 `908180cb21420fef454b67f161a79908e56a12aa`. Push-commit `main` этим прогоном **не подтверждается**.
- **Acceptance:** 93/93 Python design/static tests, в том числе 42 новых теста GAME-ARCH-00/01; эталонный пример: пять исходных предметов → три логических объекта без потери 52 XP-единиц, подбираются 40 XP, +3 уровня с остатком 3 XP, в очередь входят 5 решений, `build_revision` 1→6. Это **проверка проектной модели**, а не game/runtime.
- **Known blockers:** нормативный приоритет конкурирующих источников наград, правила смерти/победы в том же тике, сохранение в паузе, точный этап XP-модификатора, мировая геометрия подбираемых объектов и интеграция с реальными DraftService/BuildTransaction. GAME-ARCH-02 (encounter/boss/stage) пока не специфицирован полностью.
- **Next allowed action:** архитектурный GAME-ARCH-02 (режиссура волн, боссы, StageTopology, POI, reward gates) и закрытие открытых RLOOP-01/02/03 и XP-01/02/03; статические контракты/негативные фикстуры, **без** Godot/runtime.
- **Last updated from repository:** 2026-11-11.

**Правило CI-first:** обычные архитектурные PR после зелёного CI и проверки diff интегрировать в `main`, не оставлять открытыми по инерции. [Workflow](guides/WORKFLOW.md). Статус `DESIGN PROPOSAL` не превращается в `ACCEPTED DESIGN` от факта merge.

[Reference fixtures](proposals/game-arch-00-01/README.md) · [Навигация](guides/START_HERE.md)
