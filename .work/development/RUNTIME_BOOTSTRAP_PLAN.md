# RUNTIME_BOOTSTRAP_PLAN — GO/NO-GO пакет для P0-00 (DEV-ENV-005)

- **Статус:** **NO-GO до явного решения пользователя** начать разработку игры ([NEXT_SLICES](../roadmap/NEXT_SLICES.md): «Переход к P0-00 допустим только после отдельного решения»). Документ описывает первый runtime-срез; он не создаёт `project.godot`, сцены и ассеты.
- **Дата:** 2026-11-12 · **Стек:** Godot 4.7.2 2D + typed GDScript ([ADR-001](../decisions/ADR-001-stack.md)) · **Инструменты:** [toolchain.lock.json](../tooling/toolchain.lock.json)
- **Интерфейсы:** [INTERFACE-CONTRACTS-001](../spec/v7/interface-contracts-001.md) · **Привязка систем:** [SYSTEM_BINDING](SYSTEM_BINDING.md)

## 1. Условия GO

| # | Условие | Состояние на 2026-11-12 | Evidence |
|---|---|---|---|
| 1 | Явное решение пользователя начать P0-00 | **НЕТ** | — |
| 2 | Godot 4.7.2 воспроизводимо ставится и проходит headless typed-GDScript smoke на Windows и Linux | **ДА** | `toolchain-smoke.yml`, `godot_tool.py smoke` |
| 3 | GUT 9.7.1 и gdtoolkit 4.5.0 закреплены (установка в P0-00) | ДА (pin), установка отложена | toolchain lock `phase: P0-00` |
| 4 | Контракт ContentRegistry и canonical digest определены | ДА (контракт), генератора нет | [content-registry-contract](../spec/v7/content-registry-contract.md), GAP-REGISTRY-GEN |
| 5 | Python-фикстуры, которые станут golden tests, существуют | ДА | `.work/proposals/*`, `tests/test_run_loop_proposal.py`, `tests/test_save_contract_proposal.py` |
| 6 | Agent skills для Godot доступны и закреплены | ДА | 13 vendored + 8 `hip-*`, [SKILLS_AUDIT](SKILLS_AUDIT.md) |
| 7 | Godot MCP оценён, но выключен | ДА | [MCP_REGISTRY](MCP_REGISTRY.md) |
| 8 | Открытые пробелы, блокирующие P0-00 | нет блокирующих; GAP-CHOICE-SAVE и GAP-ARCH-04 желательно закрыть до P0-01 | [реестр](SYSTEM_BINDING.md) |

## 2. Структура (по [s26](../spec/core/s26.md), адаптировано к текущему repo)

`.work/`, `scripts/`, `tests/` остаются как есть (дизайн, Python-оракулы). Игра появляется только в `game/`:

```text
game/
  project.godot                 # 2D, Compatibility/Forward+ — решение в P0-00 ADR
  core/                         # типы, ID, RunRulesSnapshot, RNG adapter (без Node)
  content/generated/            # артефакты ContentRegistry из .work/config/v7 (не редактируются руками)
  simulation/                   # FixedTick, WorldState, CombatKernel, PlayerCommand (без presentation)
  presentation/                 # PresentationBridge, рендер, VFX, звук (только чтение)
  ui/                           # ChoiceViewModel и экраны
  tests/{unit,integration,replay,fixtures}/
  addons/gut/                   # pinned 9.7.1, ставится скриптом, не руками
tools/content/                  # генератор ContentRegistry (Python, stdlib)
```

## 3. Состав первого PR P0-00 (после GO)

1. ADR-007: renderer backend и формат generated content (`.tres` vs JSON + typed loader) — решение пользователя.
2. `game/project.godot` минимальный, без сцен геймплея; `scripts/dev/godot_tool.py` получает `gut install` из lock.
3. Генератор `tools/content/` → `game/content/generated/` + digest parity с `validate_content.py` (закрывает GAP-REGISTRY-GEN).
4. `game/core/`: `RunRulesSnapshot`, `RulesHash`, seeded RNG adapter — только типы и тесты.
5. GUT-тесты, повторяющие 2–3 Python-оракула побитно (первый шаг GAP-PY-GD-PARITY).
6. Placeholder-сцена — только если пользователь разрешит; production-ассеты — нет.

## 4. CI workflows (спецификация; не создавать фиктивно проходящие jobs)

| Workflow | Когда появляется | Шаги | Обязательные outputs |
|---|---|---|---|
| `design-validation` | есть | validators + unittest, Ubuntu + Windows-2022 | число тестов > 0 |
| `toolchain-smoke` | есть | install/smoke Godot по lock, doctor | версия, sha512 |
| `godot-import-and-tests` | P0-00 | `--headless --import`, GUT, проверка «найдено тестов > 0», ошибки ресурсов = fail | commit SHA, content digest, seed, логи как artifact при fail |
| `game-smoke` | P0-01 | headless запуск забега по bot-сценарию, golden replay hash | replay hash, event count |
| `build-artifacts` | P0-02 | export templates из lock (sha512), экспорт Windows/Linux | артефакты с SHA в имени |
| `perf-bench` | P0-02+ | exported build, сценарии из [s24](../spec/core/s24.md) | только измерения, без обещаний FPS |

## 5. Приёмка P0-00 (после GO)

Headless import на Windows и Linux без ошибок ресурсов · GUT обнаружил > 0 тестов и все зелёные · canonical content digest совпадает между Python и Godot · воспроизводимое критическое состояние (RulesHash, RNG) · нет расхождения семантики Python↔Godot в перенесённых оракулах · CURRENT_STATE обновлён по live CI.

## 6. Ограничения, которые остаются

Репозиторий публичный с 2026-11-12; ruleset для `main` (required checks) — по решению пользователя, до него merge flow держится на правилах [AGENTS.md](../../AGENTS.md) и CI. Производительность, «fun» и восприятие не подтверждаются до exported build и плейтеста.
