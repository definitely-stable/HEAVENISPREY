# Матрица требований → спецификация → доказательства

**Проверено по состоянию на 11.11.2026.** Здесь фиксируются *требования и наличие реализационных доказательств*, а не субъективные оценки готовности.

| ID | Требование | Нормативная спецификация | Проверка | Фактический статус |
|---|---|---|---|---|
| ENGINE-001 | Godot 4.7.2 2D, typed GDScript | [ADR-001](../decisions/ADR-001-stack.md) | Clean import + headless smoke | ACCEPTED DESIGN; NOT IMPLEMENTED |
| COMBAT-001 | Автоатаки, multicast, hit/status/proc | [ADR-002](../decisions/ADR-002-combat.md), [Combat Semantics](../spec/v5/v5_semantics.md) | Golden tests, replay-diff | DESIGN ONLY |
| HORDE-001 | Массовые враги, пространственная сетка | [Spawn](../spec/core/s11.md), [Spatial](../spec/core/s10.md) | Сценарии нагрузки, FPS/p95 | DESIGN ONLY |
| CLASS-001 | Классы и мастерство | [Классы](../spec/v6/v6_classes.md) | Unlock/class replay | DESIGN ONLY |
| META-001 | Общее дерево секты, ресет талантов | [Экономика](../spec/v7/economy-and-talent-sinks.md) | Settlement/respec tests | DESIGN FIXTURES ONLY |
| MODE-001 | Поздние Небесная кара / Бездна Дао | [ADR-003](../decisions/ADR-003-late-game.md), [Late game](../spec/v7/late-game-progression.md) | Unlock/profile validation | CONFIG TESTS PASS; GAME NOT RUN |
| ECON-001 | Духовные камни и Печати Дао, антифарм | [Экономика v7](../spec/v7/economy-and-talent-sinks.md), [reward config](../config/v7/reward_contract.json) | Static invariants now; bot economy later | STATIC CHECKS ONLY |
| I18N-001 | RU/EN, key-based translations | [I18N v6](../spec/v6/v6_i18n.md), [CSV](../config/v7/localization_additions.csv) | CSV keys/empty strings + UI screenshot | CSV CHECKS ONLY |
| BOT-001 | Несколько политик ботов и серия забегов | [BOT-QA](../spec/v7/bot-acceptance.md) | Repeated simulation runs | NOT IMPLEMENTED |
| ART-001 | 2D-ассеты и единый стиль | [Art factory](../spec/core/s16.md), [visual QA](../spec/v5/v5_assets.md) | Атласы + визуальный review | NOT IMPLEMENTED |
| RE-001 | Code/data-first анализ референсов | [RE](../spec/core/s23.md) | Build-specific methods and observations | PLANNED; NO BINARIES |
| SAVE-001 | Save profile, версии, exactly-once rewards | [Save](../spec/core/s20.md), [экономика](../spec/v7/economy-and-talent-sinks.md) | Atomicity, replay, migrations | CONTRACT ONLY |
| DOC-001 | История решений, ссылки, происхождение | [INDEX](../INDEX.md), [Manifest](../MANIFEST.json), [Migration](../guides/MIGRATION_AUDIT.md) | Linux+Windows Python CI | CI-VERIFIED (documentation only) |

## Как обновлять

Изменение одной подсистемы сопровождается обновлением **её ID**, актуального документа, фикстур и evidence. При подтверждённом тесте добавляют commit/CI URL в [EVIDENCE](../templates/EVIDENCE.md); не заменяют `DESIGN ONLY` на `TESTED` без реального запуска.

[Рабочий процесс](../guides/WORKFLOW.md) · [Roadmap](../roadmap/NEXT_SLICES.md) · [CURRENT_STATE](../CURRENT_STATE.md).
