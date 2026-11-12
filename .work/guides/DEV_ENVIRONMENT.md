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
- Export templates (~1.3 ГБ) закреплены в lock как `deferred_assets` и понадобятся только в P0-00.

## 3. Проверки перед PR

```bash
python scripts/validate_work.py
python scripts/validate_toolchain.py
python -m unittest discover -s tests -v
```

Полный список шагов CI: [design-validation.yml](../../.github/workflows/design-validation.yml) и [toolchain-smoke.yml](../../.github/workflows/toolchain-smoke.yml). Локальный успех не заменяет hosted CI: в CURRENT_STATE записывается run ID.

## 4. Диагностика типовых проблем

| Симптом | Причина | Действие |
|---|---|---|
| `SHA-512 mismatch` | повреждённая загрузка или подмена | удалить `.tools/godot/<version>`, повторить; при повторе — не обходить, завести issue |
| `NOT INSTALLED` | бинарник не найден | `godot_tool.py install` или `GODOT_BIN` |
| `WRONG_VERSION` в doctor | в PATH/`GODOT_BIN` другая версия | использовать pinned из `.tools` |
| `unsupported architecture` | не x86_64 | lock содержит только Windows/Linux x86_64 (ADR-001 targets) |
| `validate_toolchain` про workflow | в YAML второй pin Godot | ставить через `godot_tool.py`, cache key — hash lock |

## 5. Обновление версии инструмента

`document → pin → smoke → regression → merge` (s21): изменить запись в lock (версия, URL, SHA-512 из официального `SHA512-SUMS.txt`), прогнать smoke локально, открыть отдельный PR. Godot — только с amendment [ADR-001](../decisions/ADR-001-stack.md).

[Предметная карта](START_HERE.md) · [Workflow](WORKFLOW.md)
