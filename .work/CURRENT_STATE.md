# CURRENT_STATE — проверенный снимок

- **Last verified HEAD:** `main: 093346ecbd3d054a72bcdc95b1d3e849da375353` (после объединения двух архитектурных PR, до обновления этого снимка).
- **Current milestone:** ARCH — только архитектура контента, контракты и ускорение будущей разработки. Godot/runtime/арт-производство не начинать без отдельного изменения scope.
- **Current slice:** ARCH-01 — типизированная архитектура RunBuild/Skill/Passive/Power, гибкие политики, формальные фикстуры; продолжение ARCH-02 — достижимость трансформаций.
- **Open PR:** нет среди двух исходных PR. [#1](https://github.com/definitely-stable/HEAVENISPREY/pull/1) — MERGED, merge `697bb9461693a9634350468229e5bd93504bb139`; [#2](https://github.com/definitely-stable/HEAVENISPREY/pull/2) — MERGED, merge `093346ecbd3d054a72bcdc95b1d3e849da375353`. Новые PR проверять в GitHub при следующем отчёте.
- **Last CI:** [#43040620989](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43040620989) — SUCCESS на Ubuntu и Windows-2022, на HEAD PR #2 `01f5e8a8fcf4ccc8941219886e6df581f8967274`; итоговый push на `main` этим результатом **не** подтверждён.
- **Acceptance:** 51/51 дизайн-тестов, валидаторы миграции и контента, отдельные проверки ARCH-01 (24 теста билдов, 4 теста графа зависимостей). Это **статическая архитектура**, не работающая игра и не доказательство баланса/FPS.
- **Known blockers:** формальные схемы ещё не завершены; независимые экземпляры навыков, N→M-трансформации, Limit Break, полный решатель достижимости рецептов и вероятностный DraftService остаются проектными задачами.
- **Next allowed action:** ARCH-01 — формальные схемы и отрицательные фикстуры, затем ARCH-02. Обычные архитектурные PR после ревью и успешного CI интегрировать в `main` в рамках согласованной задачи без повторного запроса разрешения, не оставляя искусственно открытые цепочки. См. [WORKFLOW](guides/WORKFLOW.md).
- **Last updated from repository:** 2026-11-11.

**Принцип:** статусы PR и HEAD — исторический снимок. Перед отчётом об актуальном состоянии всегда перепроверять репозиторий и CI. Merge документа с меткой `design-proposal` не означает утверждения предложенного баланса или правил без соответствующего решения.

[BUILD-SKILL-001](spec/v7/build-skill-architecture-proposal.md) · [ARCH-01](spec/v7/build-skill-type-contract.md) · [FLEXIBILITY-FIRST](spec/v7/flexibility-first-build-policies.md)
