# CURRENT_STATE — проверяемый архитектурный снимок

- **Last verified HEAD:** `main: fc1e273433539d18e840bb96107117fbcf50501a` (merge PR #24; до служебного обновления данного снимка).
- **Current milestone:** ARCH + DEV-ENV — архитектура, статические модели, воспроизводимая среда разработки и CI. Godot runtime, сцены, ассеты и игровой код **не созданы**; P0-00 — **NO-GO** до решения пользователя ([RUNTIME_BOOTSTRAP_PLAN](development/RUNTIME_BOOTSTRAP_PLAN.md)).
- **Completed slices (2026-11-12):** DEV-ENV-001 toolchain lock + Godot 4.7.2 install/smoke (PR #17) · ART-REF-001 каталог 63 референсов (PR #18) · DEV-ENV-002 8 `hip-*` skills + Claude-адаптер (PR #19) · DEV-ENV-002b 13 vendored Godot/gamedev skills (PR #20) · DEV-ENV-003 MCP registry (PR #21) · DEV-ENV-004a playability/art gates (PR #22) · DEV-ENV-004b system binding, 12 интерфейсов, реестр пробелов (PR #23) · DEV-ENV-005 readiness audit, tooling matrix, GO/NO-GO (PR #24).
- **Open PR:** нет открытых PR этих срезов на момент проверки; другие PR проверять live (`gh pr list`).
- **Last CI:** push `main` `fc1e273`: Design and knowledge validation [#43229635787](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43229635787) — SUCCESS; Toolchain smoke [#43229635673](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43229635673) — SUCCESS. Ubuntu + Windows-2022; **320** Python tests; Godot 4.7.2 headless typed-GDScript smoke на обеих ОС.
- **Acceptance:** все валидаторы PASS (`validate_*.py`, `system_binding.py`, `tooling_matrix.py`, `ref_catalog.py`); [READINESS_AUDIT §4](development/READINESS_AUDIT.md).
- **Known blockers:** репозиторий публичный, ruleset для `main` ещё не включён; пользовательский GitHub MCP — `Bad credentials`; Codex skills discovery не проверен (лимит до 2026-11-14); бинарники `ref/` не в git (решение пользователя); art bible — решение пользователя; концепции с референсов — только примеры ([REF-EXAMPLES-001](spec/v7/reference-concept-examples.md)). Архитектурные пробелы — [SYSTEM_BINDING](development/SYSTEM_BINDING.md) (14, с владельцами).
- **Next allowed action:** `CHOICE-SAVE-002` (draft RNG cursor + RunDraftState в одном versioned SaveEnvelope) → `ARCH-02` → `ARCH-04` → `GAME-ARCH-02`; параллельно закрыть GAP-SCHEMA-COVERAGE (валидатор `localization_context.json`, `settings.example.cfg`). Только архитектура и статические тесты.
- **Last updated from repository:** 2026-11-12.

**Governance:** DESIGN PROPOSAL после merge остаётся проектным предложением. Не переносить автоматически в игру SHA256-based RNG, pity-after-2 или sample caps. Перед новой работой перепроверить HEAD/CI/PR live. Не оставлять обычные готовые PR открытыми после зелёного CI/diff-review.

[Readiness](development/READINESS_AUDIT.md) · [System binding](development/SYSTEM_BINDING.md) · [Roadmap](roadmap/NEXT_SLICES.md) · [Draft contract](spec/v7/draft-contract-002.md) · [Choice ViewModel](spec/v7/choice-viewmodel-001.md)
