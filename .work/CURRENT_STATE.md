# CURRENT_STATE — проверяемый архитектурный снимок

- **Last verified HEAD:** `main: e662b158605df9fcf26889163b374f85fb400285` (merge PR #13; до служебного обновления данного снимка).
- **Current milestone:** ARCH — архитектура геймплея, тестируемые проектные модели и ускорение будущей разработки. **Никаких Godot-сцен, ассетов, движкового или игрового runtime.**
- **Current slice:** [CHOICE-VIEWMODEL-001](spec/v7/choice-viewmodel-001.md) — статическая модель source-grounded карточек, действия Reroll/Banish/Lock/Unlock, explicit Select/Skip, hand/focus revisions, input safety и [проверяемый отдельный DraftCheckpointOverlay](proposals/choice-viewmodel-001/README.md).
- **Open PR:** выполненный PR [#13](https://github.com/definitely-stable/HEAVENISPREY/pull/13) — MERGED `e662b158605df9fcf26889163b374f85fb400285`; незавершённых PR **этого среза** нет. Другие PR репозитория требуется проверять отдельно.
- **Last CI:** [#43094558727](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43094558727) — SUCCESS на GitHub-hosted Ubuntu и Windows-2022 для PR #13 HEAD `ac2e35f4de43bb684b260bc262367c1c493d070e`: **206/206** статических/design тестов. Отдельный post-merge push-run на `main` этим результатом не подтверждён.
- **Acceptance:** 39 новых тестов; детерминированная синтетическая рука выбора, корректный запрет списывать Reroll при отсутствии других legal offers, lock и banish без расходования уровня, повторный Select/Skip не списывает reward дважды, stale hand/focus исключён, held-confirm требует release/new press, card facts выводятся из RunBuild, отдельный overlay сохраняет hand/actions/charges/draw cursor и проверяет независимое воспроизведение. **Не** подтверждает реальные Godot RNG/GUI/accessibility.
- **Known blockers:** нет реального DraftService и weighted RNG policy; source bans пока не живут внутри полного RunSnapshot, offers cursor не синхронизирован с SAVE-CONTRACT-001; нет законной миграции схемы SaveEnvelope для draft hand; отсутствуют реальные UI/локализация/клавиатура/геймпад, auto-pick и human UX тесты. Взаимоисключающие ритуалы и Breakthrough пока не являются частью эталонной руки.
- **Next allowed action:** [DRAFT-CONTRACT-002](roadmap/NEXT_SLICES.md): версионированные RNG/anti-brick/fallback/offer-provenance и per-run bans; затем CHOICE-SAVE-002 (единый checkpoint/draft), ARCH-02 (reachability) и GAME-ARCH-02. Только архитектура и статические проверки.
- **Last updated from repository:** 2026-11-12.

**Governance:** DESIGN PROPOSAL после merge не означает утверждённый баланс. Не фиксировать в runtime лимиты трёх карточек, двух зарядов Reroll или одного Lock из синтетической fixture. Статусы HEAD/CI исторические, перед новым изменением сверять GitHub.

[Choice ViewModel](spec/v7/choice-viewmodel-001.md) · [Source tests](proposals/choice-viewmodel-001/README.md) · [Save Contract](spec/v7/save-contract-001.md) · [Roadmap](roadmap/NEXT_SLICES.md)
