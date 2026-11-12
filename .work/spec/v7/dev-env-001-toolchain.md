---
id: DEV-ENV-001
status: IMPLEMENTED (tooling only; no game runtime)
date: 2026-11-12
supersedes: none (makes s21 pin matrix executable for the engine)
dependencies: ADR-001, ADR-004, s21, s25, FOUNDATION-2026 FND-11
acceptance: scripts/validate_toolchain.py, tests/test_toolchain.py, .github/workflows/toolchain-smoke.yml
evidence: PR and CI run recorded in CURRENT_STATE after merge
---

# DEV-ENV-001 — воспроизводимая среда разработки и pinned toolchain

**Цель:** любой исполнитель (человек или AI-агент любого поставщика) одной командой ставит **тот же** Godot 4.7.2, проверяет окружение и получает одинаковый результат на Windows и Linux, включая GitHub-hosted CI. Срез не создаёт `game/`, сцены, ассеты или игровой код.

**Non-goals:** Godot проект/импорт, GUT, экспорт, editor MCP, ассеты. Они начинаются в P0-00 и используют этот же lock.

## Контракт

| Элемент | Канонический источник | Проверка |
|---|---|---|
| Версии инструментов, SHA-512, URL, фаза, dependency budget (s21.2) | [toolchain.lock.json](../../tooling/toolchain.lock.json) | [validate_toolchain.py](../../../scripts/validate_toolchain.py) |
| Установка Godot | [godot_tool.py](../../../scripts/dev/godot_tool.py) `install` → `.tools/godot/<version>/` (git-ignored) | SHA-512 до распаковки, zip-slip защита, только официальный URL тега |
| Smoke движка | `godot_tool.py smoke`: `--version`, headless typed GDScript во **временном** проекте, негативный контроль (несуществующий скрипт → non-zero) | [toolchain-smoke.yml](../../../.github/workflows/toolchain-smoke.yml) Ubuntu + Windows-2022 |
| Диагностика | [doctor.py](../../../scripts/dev/doctor.py) (`--json`) | exit 1 только при отсутствии обязательного |
| Процедура для людей | [DEV_ENVIRONMENT](../../guides/DEV_ENVIRONMENT.md) | ссылки проверяются validate_migration |

## Инварианты

1. Нет плавающих pin (`latest`, диапазоны) ни в lock, ни в `uses:` workflows (`@main/@master/@latest` запрещены).
2. Godot = 4.7.x **stable** (ADR-001); смена версии — только через amendment ADR-001 и обновление одного lock.
3. Workflow не содержит второго hard-coded URL/версии Godot; cache key = hash lock-файла.
4. Ни один инструмент lock не является runtime-зависимостью игры (s21: игра запускается без агента, MCP, Python).
5. Smoke доказывает только работоспособность бинарника и парсер typed GDScript, **не** импорт проекта, FPS или игровую логику.

## Подсрезы программы подготовки (по зависимостям)

| Slice | Результат | Gate |
|---|---|---|
| **DEV-ENV-001** | Этот документ: lock, install, smoke, doctor, CI | validate_toolchain + 18 unit tests + hosted smoke |
| DEV-ENV-002 | Адаптеры агентов без второй системы инструкций, проектные и проверенные сторонние skills | validator skills: триггеры, ссылки на `.work`, parity зеркал, pin SHA/лицензия |
| DEV-ENV-003 | MCP-стек (Context7, GitHub) и сравнительный аудит Godot MCP, интеграция отложена до P0-00 | validator MCP: без секретов, pin версий, Godot MCP выключен до runtime |
| DEV-ENV-004 | Карта связи skills/контрактов с системами игры, недостающие контракты | каждая система → канонический контракт → skill → gate |
| ART-REF-001 | Классифицированный каталог `ref/` | каждый файл учтён, ссылки валидны, статус «референс, не production» |

[Roadmap](../../roadmap/NEXT_SLICES.md) · [CURRENT_STATE](../../CURRENT_STATE.md) · [ADR-001](../../decisions/ADR-001-stack.md)
