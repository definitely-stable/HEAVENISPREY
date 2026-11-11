# CURRENT_STATE — проверяемый снимок

- **Last verified HEAD:** `main: f07466876f166f2d66b0dd76b77631765e96fca5` (после PR #9, до обновления этого снимка).
- **Current milestone:** ARCH — формализация архитектуры, исследований и инструментов будущей разработки. **Без Godot runtime, сцен, ассетов или реализации игры**.
- **Current slice:** [FOUNDATION-2026](spec/v7/foundation-research-2026.md) — адаптация инженерных и научных практик 2024–2026; [evidence gates](proposals/foundation-2026/README.md) для 15 архитектурных решений и 15 источников, 29 явных зависимостей. `GAME-UX-001`, `GAME-ARCH-00/01`, `BUILD-SKILL` не отменены.
- **Open PR:** [#9](https://github.com/definitely-stable/HEAVENISPREY/pull/9) — MERGED `f07466876f166f2d66b0dd76b77631765e96fca5`. По этому архитектурному пакету после merge нет незавершённых PR. Открытое состояние других PR обязательно перепроверять в GitHub.
- **Last CI:** [#43076013456](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43076013456) — SUCCESS на GitHub-hosted Ubuntu и Windows-2022 для HEAD PR #9 `8adbc493349dca4d1d45fe33a4c54f6e4e2b787d`. **125/125** Python design tests. Отдельный post-merge push-run этого HEAD не подтверждён этим результатом.
- **Acceptance:** 12 новых тестов, включая seeded metamorphic-проверки XP при объединении объектов, детерминированного порядка событий и авторизованных source values; негативные мутации foundation gate отклоняются; 15/15 source и gate references валидируются. Реальной производительности/баланса/погружения это **не доказывает**.
- **Known blockers:** нет Godot runtime; нет реальных replay/RunSnapshot migration, авторитетного DropLedger, полного ChoiceViewModel/InputFocus, автоматического DraftService, достижимости N→M recipes, Godot profiler измерений и человеческого playtest. RL/PCG и нативные расширения преднамеренно отложены.
- **Next allowed action:** `SAVE-CONTRACT-001` (schema versions, RunRulesHash, RNG streams, receipt snapshots/replay); `CHOICE-VIEWMODEL-001` (карточки, focus, reroll, banish, lock); `ARCH-02` reachability; `GAME-ARCH-02` stage/encounters. Всё **только архитектурные контракты и статические тесты**.
- **Last updated from repository:** 2026-11-11.

**Scope:** простые архитектурные PR после успешного CI и diff-review интегрировать в `main`. Статус `design-proposal` после merge не равен `approved gameplay`. Статусы HEAD/PR/CI — исторический снимок, для нового ответа перечитывать GitHub.

[Фундамент](spec/v7/foundation-research-2026.md) · [Gates](proposals/foundation-2026/README.md) · [Roadmap](roadmap/NEXT_SLICES.md) · [UX](spec/v7/game-ux-001-oct-2026.md)
