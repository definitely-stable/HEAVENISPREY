#!/usr/bin/env python3
"""DEV-ENV-005: render the tooling matrix from the three locks (no hand-maintained copy).

  python scripts/tooling_matrix.py validate   # CI: TOOLING_MATRIX.md equals the rendered locks
  python scripts/tooling_matrix.py render     # rewrite .work/development/TOOLING_MATRIX.md
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLING = ROOT / ".work" / "tooling"
VIEW = ROOT / ".work" / "development" / "TOOLING_MATRIX.md"


def load(name: str) -> dict:
    return json.loads((TOOLING / name).read_text(encoding="utf-8"))


def render() -> str:
    tool_lock, skills, mcp = load("toolchain.lock.json"), load("skills.lock.json"), load("mcp.lock.json")
    out = ["# TOOLING_MATRIX — инструменты, skills и MCP проекта",
           "",
           "> Сгенерировано `python scripts/tooling_matrix.py render` из "
           "[toolchain.lock.json](../tooling/toolchain.lock.json), "
           "[skills.lock.json](../tooling/skills.lock.json) и [mcp.lock.json](../tooling/mcp.lock.json). "
           "Не редактировать вручную; статус клиентов и машины — [READINESS_AUDIT](READINESS_AUDIT.md).",
           "",
           "## Инструменты",
           "",
           "| ID | Версия | Фаза | Обязателен | Проверка |",
           "|---|---|---|---|---|"]
    for t in tool_lock["tools"]:
        out.append("| %s | %s | %s | %s | %s |" % (t["id"], t.get("version", ""), t.get("phase", ""),
                                                 "да" if t.get("required") else "нет",
                                                 t.get("integration_test", "").replace("|", "/")))
    out += ["", "## Agent skills (vendored, pinned)", "",
            "| Skill | Источник | Commit | Лицензия |", "|---|---|---|---|"]
    for v in skills["vendored"]:
        out.append("| `%s` | %s | `%s` | %s |" % (v["name"], v["source"], v["commit"][:7], v["license"]))
    out += ["", "Проектные `hip-*` skills — [AGENT_EXECUTION](AGENT_EXECUTION.md).",
            "", "## MCP", "", "| ID | Приоритет | Фаза | Версия | Доступ | Вкл. по умолчанию | Проверка |",
            "|---|---|---|---|---|---|---|"]
    for s in mcp["servers"]:
        out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            s["id"], s["priority"], s["phase"], s["version"], s["access"],
            "да" if s["default_enabled"] else "нет", s["verification"]["status"]))
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    text = render()
    if argv and argv[0] == "render":
        VIEW.write_text(text, encoding="utf-8", newline="\n")
    elif not VIEW.is_file() or VIEW.read_text(encoding="utf-8") != text:
        print("FAIL: TOOLING_MATRIX.md is stale: run python scripts/tooling_matrix.py render", file=sys.stderr)
        return 1
    print("PASS: tooling matrix matches toolchain, skills and MCP locks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
