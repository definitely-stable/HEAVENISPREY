# CURRENT_STATE — проверяемый снимок репозитория

- **Last verified HEAD:** `main: d9765f0f98e9ed9afbb5fb0d5264153e954fbb9f` (merge SAVE-CONTRACT-001, **до** текущего обновления этого статуса).
- **Current milestone:** ARCH — проектирование архитектуры, проверяемые статические модели и инструменты будущей разработки. **Godot runtime, сцены, ассеты и gameplay-код не создавались.**
- **Current slice:** [SAVE-CONTRACT-001](spec/v7/save-contract-001.md) — проектные контракт и синтетическая эталонная модель versioned snapshot / RulesHash / RNG / replay mid-choice. Связано с [GAME-ARCH-00/01](spec/v7/game-arch-00-run-orchestration.md), [GAME-UX-001](spec/v7/game-ux-001-oct-2026.md) и [ARCH-01](spec/v7/build-skill-type-contract.md).
- **Open PR:** выполненный пакет [#11](https://github.com/definitely-stable/HEAVENISPREY/pull/11) — MERGED, merge `d9765f0f98e9ed9afbb5fb0d5264153e954fbb9f`. Статус остальных PR следует перепроверять live; снимок не утверждает, что все остальные PR отсутствуют.
- **Last CI:** [#43087439639](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43087439639) — SUCCESS, **167/167 тестов** на GitHub-hosted Ubuntu и Windows-2022 для HEAD PR #11 `cdf9d40ac9c32dc3f97eb00cd072e5bb9180f8ee`. Отдельная CI-проверка итогового merge-коммита `main` данным прогоном **не подтверждена**.
- **Acceptance:** 42 новых теста + 125 старых; сохранение после первого повышения ранга (rev 7) → JSON roundtrip/checksum/content/rules verification → две Power upgrades + ритуальная эволюция (rev 10), при этом остаётся одно решение прорыва, а XP/claimed sources сохраняются. Результат равен эталонному непрерывному replay. Проверены отказы при повреждении receipt, source claims, XP, очереди, Build, RNG policy, версий и v0 header migration.
- **Known blockers:** Python reference digest не RFC 8785, реальные Godot save files и физика/AI/RNG draws не реализованы; авторитетный runtime DropLedger и DraftService отсутствуют, `BREAKTHROUGH` resolver, mid-run UI focus, атомарная запись на диск, реальные миграции и мета settlement не смоделированы. Игровых FPS/UX измерений нет.
- **Next allowed action:** `CHOICE-VIEWMODEL-001` (карточки, focus/input, reroll, banish, lock), `ARCH-02` (reachability/N→M evolutions), `GAME-ARCH-02` (stage/encounters/POI); при необходимости SAVE-02 (world snapshot + bounded journal). **Только архитектурные контракты и CI, без создания игры.**
- **Last updated from repository:** 2026-11-12.

**Scope:** `design-proposal` после merge не означает утверждённую игровую механику. В ответах всегда перепроверять HEAD, PR и CI live. Не оставлять готовые архитектурные PR открытыми после успешного CI/diff review.

[Save contract](spec/v7/save-contract-001.md) · [Fixtures](proposals/save-contract-001/README.md) · [Foundation](spec/v7/foundation-research-2026.md) · [Roadmap](roadmap/NEXT_SLICES.md)
