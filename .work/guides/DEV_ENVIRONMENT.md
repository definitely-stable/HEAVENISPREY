# Среда разработки — установка и диагностика

Нормативный контракт: [DEV-ENV-001](../spec/v7/dev-env-001-toolchain.md). Версии берутся **только** из [toolchain.lock.json](../tooling/toolchain.lock.json); этот файл описывает процедуру, а не дублирует pin.

## 1. Обязательное (текущая фаза ARCH)

| Шаг | Windows (PowerShell / Git Bash) | Linux |
|---|---|---|
| Python ≥ 3.11 (CI: 3.13) | `winget install Python.Python.3.13` | пакетный менеджер ОС |
| Git, GitHub CLI | `winget install Git.Git GitHub.cli` | пакетный менеджер ОС |
| Клон | `git clone https://github.com/definitely-stable/HEAVENISPREY.git` | то же |
| Проверка | `python scripts/dev/doctor.py` | то же |

Python-скрипты проекта используют только stdlib: `pip install` не нужен.

## 2. Godot 4.7.2 (pinned, проверяемый)

```bash
python scripts/dev/godot_tool.py install   # скачивает официальный архив, сверяет SHA-512, ставит в .tools/godot/4.7.2-stable/
python scripts/dev/godot_tool.py smoke     # --version, headless typed GDScript во временном каталоге, негативный контроль
python scripts/dev/godot_tool.py path      # путь к бинарнику (для IDE / MCP)
```

- `.tools/` игнорируется git. Другой каталог: `--root DIR` или `HIP_TOOLS_ROOT`.
- Уже установленный Godot: `GODOT_BIN=<path>`; smoke всё равно сверяет версию с lock.
- На Windows для CLI используется `*_console.exe` (stdout), для редактора — `gui_executable` из lock.
- Export templates (~1.3 ГБ) закреплены в lock как `deferred_assets`; нужны с первого экспорта (P0-02), не для тестов.

## 2a. Игровой проект `game/` (P0-00)

```bash
python tools/content/generate_registry.py          # .work/config/v7 -> game/content/generated (после validate_content.py)
python tools/content/generate_registry.py --check  # сгенерированные байты == источники (так же в CI)
python scripts/dev/godot_tool.py gut-install       # GUT 9.7.1 из pinned commit в game/addons/gut (git-ignored, tree digest)
python scripts/dev/godot_tool.py test              # headless --import, GUT по game/tests/{unit,integration,replay}, негативный контроль
```

- Решения о renderer, формате generated content, RNG `hip-rng-v1` и `rules_hash` — [ADR-007](../decisions/ADR-007-runtime-bootstrap.md).
- `game/content/generated/*` не редактируются руками и помечены `-text` в `.gitattributes`: digest считается по точным байтам.
- Редактор: `gui_executable` из lock, открыть `game/project.godot`.

## 3. Проверки перед PR

```bash
python scripts/validate_work.py
python scripts/validate_toolchain.py
python -m unittest discover -s tests -v
python scripts/dev/godot_tool.py test   # при изменениях в game/, tools/content/ или .work/config/v7/
```

Полный список шагов CI: [design-validation.yml](../../.github/workflows/design-validation.yml), [godot-tests.yml](../../.github/workflows/godot-tests.yml) и [toolchain-smoke.yml](../../.github/workflows/toolchain-smoke.yml). Локальный успех не заменяет hosted CI: в CURRENT_STATE записывается run ID.

## 4. Диагностика типовых проблем

| Симптом | Причина | Действие |
|---|---|---|
| `SHA-512 mismatch` | повреждённая загрузка или подмена | удалить `.tools/godot/<version>`, повторить; при повторе — не обходить, завести issue |
| `NOT INSTALLED` | бинарник не найден | `godot_tool.py install` или `GODOT_BIN` |
| `WRONG_VERSION` в doctor | в PATH/`GODOT_BIN` другая версия | использовать pinned из `.tools` |
| `unsupported architecture` | не x86_64 | lock содержит только Windows/Linux x86_64 (ADR-001 targets) |
| `GUT tree digest mismatch` | архив GitHub изменился или подмена | не обходить; сверить commit в lock, пересчитать digest только через ревью lock |
| `stale or hand-edited generated file` | правка v7 без регенерации или ручная правка | `python tools/content/generate_registry.py` |
| `validate_toolchain` про workflow | в YAML второй pin Godot | ставить через `godot_tool.py`, cache key — hash lock |

## 5. Обновление версии инструмента

`document → pin → smoke → regression → merge` (s21): изменить запись в lock (версия, URL, SHA-512 из официального `SHA512-SUMS.txt`), прогнать smoke локально, открыть отдельный PR. Godot — только с amendment [ADR-001](../decisions/ADR-001-stack.md).

[Предметная карта](START_HERE.md) · [Workflow](WORKFLOW.md)
