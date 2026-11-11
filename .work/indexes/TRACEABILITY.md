# Матрица требований → спецификация → доказательства

**Проверено по состоянию на 11.11.2026.** Здесь фиксируются *требования и наличие реализационных доказательств*, а не субъективные оценки готовности.

| ID | Требование | Нормативная спецификация | Проверка | Фактический статус |
|---|---|---|---|---|
| ENGINE-001 | Godot 4.7.2 2D, typed GDScript | [ADR-001](../decisions/ADR-001-stack.md) | Clean import + headless smoke | ACCEPTED DESIGN; NOT IMPLEMENTED |
| COMBAT-001 | Автоатаки, multicast, hit/status/proc | [ADR-002](../decisions/ADR-002-combat.md), [Combat Semantics](../spec/v5/v5_semantics.md) | Golden tests, replay-diff | DESIGN ONLY |
| ENEMY-001 | 12 показанных существ + осквернённый культиватор — 13 обычных монстров | [Бестиарий](../spec/v7/ordinary-enemy-bestiary.md) · [JSON](../config/v7/enemies.json) | [Перекрёстные проверки](../../scripts/validate_content.py), [негативные тесты](../../tests/test_enemy_catalog.py) | DATA ONLY; NO GAMEPLAY |
| ENEMY-002 | Честные телеграфы, корни без ловушек, статусные атаки | [Контракт угроз](../spec/v7/enemy-threat-contract.md) · [Атаки](../config/v7/enemy_attacks.json) | Статические проверки + будущие бот-прогоны | STATIC VALIDATED; RUNTIME NOT TESTED |
| ENEMY-003 | Состав волн и late-game варианты | [Распределение](../config/v7/enemy_rosters.json) · [варианты](../config/v7/enemy_variants.json) | Проверка ссылок, интервалов, caps; баланс позднее | INITIAL HYPOTHESES |
| DRAFT-CONTRACT-002 | Domain-separated RNG, целочисленная weighted draw, постоянные Banish, soft pity, empty-pool fallback, replay | [Design contract](../spec/v7/draft-contract-002.md) | [Fixture](../proposals/draft-contract-002/README.md) · [negative tests](../../tests/test_draft_contract_proposal.py) | DESIGN-ONLY STATIC ORACLE; NO GODOT |
| CHOICE-VIEWMODEL-001 | Типизированные факты карточек, действия драфта, безопасное подтверждение и draft overlay | [Choice contract](../spec/v7/choice-viewmodel-001.md) | [Fixture](../proposals/choice-viewmodel-001/README.md) · [negative tests](../../tests/test_choice_viewmodel_proposal.py) | DESIGN-ONLY; NO UI OR GODOT |
| SAVE-CONTRACT-001 | Версионированный checkpoint/RulesHash/RNG streams, source ledger и однозначный restore mid-choice | [Save contract](../spec/v7/save-contract-001.md) | [Fixture](../proposals/save-contract-001/README.md) · [Save tests](../../tests/test_save_contract_proposal.py) | DESIGN-ONLY REPLAY ORACLE; NO GODOT/SAVE I/O |
| FOUNDATION-2026 | Перед разработкой: replay, versions, proc semantic bounds, UX, data-oriented Godot, property testing, PCG readiness, agent-verification | [2026 research adaptation](../spec/v7/foundation-research-2026.md) | [15 gates](../proposals/foundation-2026/README.md) · [seeded tests](../../tests/test_foundation_2026.py) | DESIGN GATES VERIFIED WHEN CI GREEN; NO RUNTIME/PLAYER EVIDENCE |
| GAME-UX-001 | Пользовательский выбор улучшений, bank-levels, safe XP, card ViewModel, визуальные приоритеты, связь Draft/Build | [UX audit Oct 2026](../spec/v7/game-ux-001-oct-2026.md) | [Choice bridge](../../scripts/validate_choice_bridge_proposal.py) · [negative tests](../../tests/test_choice_bridge_proposal.py) · [run-level tests](../../tests/test_run_loop_proposal.py) | DESIGN-ONLY STATIC PROOF / NO UI GAME |
| GAME-ARCH-00 | RunOrchestrator, порядок событий, ChoiceCoordinator и пауза | [Контракт](../spec/v7/game-arch-00-run-orchestration.md) | [Fixture](../proposals/game-arch-00-01/README.md) + [negative tests](../../tests/test_run_loop_proposal.py) | DESIGN REFERENCE CHECKS; NO GAME IMPLEMENTATION |
| GAME-ARCH-01 | Drop/Pickup/XP и сохранение опыта при консолидации | [Контракт](../spec/v7/game-arch-01-xp-pickups.md) | [Reference oracle](../../scripts/validate_run_loop_proposal.py) + negative tests | DESIGN REFERENCE CHECKS; NO GAME IMPLEMENTATION |
| GAMEPLAY-GAP-001 | Сквозная архитектура игрового цикла: XP, события, POI, босс-режиссура, предзабеговые обеты, классовые задачи, UX | [Аудит v7 (proposal)](../spec/v7/gameplay-loop-gap-audit.md) | Рецензия полноты и определение будущих статических фикстур; без gameplay-test | AUDITED; NOT ACCEPTED/NOT IMPLEMENTED |
| HORDE-001 | Массовые враги, пространственная сетка | [Spawn](../spec/core/s11.md), [Spatial](../spec/core/s10.md) | Сценарии нагрузки, FPS/p95 | DESIGN ONLY |
| BUILD-SKILL-001 | Приобретаемые активные/пассивные техники, Powers, классовые intrinsic, драфт, эволюции/Union/Gift, Qi/meridian, proc safety | [Предложение v7](../spec/v7/build-skill-architecture-proposal.md) · [ARCH-01 type contract](../spec/v7/build-skill-type-contract.md) · [Authoring](../guides/CONTENT_AUTHORING_ACCELERATOR.md) | Design-only [reference fixture](../proposals/build-skill-001/README.md), negative tests and CI; runtime tests deferred | STATIC DESIGN CHECKS; SCHEMA/RUNTIME NOT IMPLEMENTED |
| CLASS-001 | Классы и мастерство | [Классы](../spec/v6/v6_classes.md) | Unlock/class replay | DESIGN ONLY |
| META-001 | Общее дерево секты, ресет талантов | [Экономика](../spec/v7/economy-and-talent-sinks.md) | Settlement/respec tests | DESIGN FIXTURES ONLY |
| MODE-001 | Поздние Небесная кара / Бездна Дао | [ADR-003](../decisions/ADR-003-late-game.md), [Late game](../spec/v7/late-game-progression.md) | Unlock/profile validation | CONFIG TESTS PASS; GAME NOT RUN |
| ECON-001 | Духовные камни и Печати Дао, антифарм | [Экономика v7](../spec/v7/economy-and-talent-sinks.md), [reward config](../config/v7/reward_contract.json) | Static invariants now; bot economy later | STATIC CHECKS ONLY |
| I18N-001 | RU/EN, key-based translations | [I18N v6](../spec/v6/v6_i18n.md), [CSV](../config/v7/localization_additions.csv) | CSV keys/empty strings + UI screenshot | CSV CHECKS ONLY |
| BOT-001 | Несколько политик ботов и серия забегов | [BOT-QA](../spec/v7/bot-acceptance.md) | Repeated simulation runs | NOT IMPLEMENTED |
| ART-001 | 2D-ассеты и единый стиль | [Art factory](../spec/core/s16.md), [visual QA](../spec/v5/v5_assets.md) | Атласы + визуальный review | NOT IMPLEMENTED |
| RE-001 | Code/data-first анализ референсов | [RE](../spec/core/s23.md) | Build-specific methods and observations | PLANNED; NO BINARIES |
| SAVE-001 | Save profile, версии, exactly-once rewards | [Save](../spec/core/s20.md), [экономика](../spec/v7/economy-and-talent-sinks.md) | Atomicity, replay, migrations | CONTRACT ONLY |
| CONTENT-001 | Канонические классы/навыки/статусы/карты/боссы/таланты/боты | [ContentRegistry](../spec/v7/content-registry-contract.md), [каталоги](../config/v7/README.md) | [Static refs](../../scripts/validate_content.py) + [negative tests](../../tests/test_content_catalog.py) | STATIC-CI ONLY; NO GODOT RUNTIME |
| SOURCE-001 | Дедупликация v5 и интеграция schema v1→2 | [Reconciliation](../guides/PACKAGE_RECONCILIATION.md), [инвентарь](../archive/package-source-inventory.json) | [v6 migration](../../scripts/validate_migration.py), [v7 validator](../../scripts/validate_content.py) | DOCUMENTED; original ZIPs not in Git |
| DOC-001 | История решений, ссылки, происхождение | [INDEX](../INDEX.md), [Manifest](../MANIFEST.json), [Migration](../guides/MIGRATION_AUDIT.md) | Linux+Windows Python CI | CI-VERIFIED (documentation only) |

## Как обновлять

Изменение одной подсистемы сопровождается обновлением **её ID**, актуального документа, фикстур и evidence. При подтверждённом тесте добавляют commit/CI URL в [EVIDENCE](../templates/EVIDENCE.md); не заменяют `DESIGN ONLY` на `TESTED` без реального запуска.

[Рабочий процесс](../guides/WORKFLOW.md) · [Roadmap](../roadmap/NEXT_SLICES.md) · [CURRENT_STATE](../CURRENT_STATE.md).
