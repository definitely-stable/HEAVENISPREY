#!/usr/bin/env python3
"""DEV-ENV-004b: game system -> contract -> skill -> gate binding, gap register, schema coverage.

Source: .work/tooling/system_binding.json. Rendered view: .work/development/SYSTEM_BINDING.md.

  python scripts/system_binding.py validate   # CI: links, skills, gates, coverage, render parity
  python scripts/system_binding.py render     # rewrite SYSTEM_BINDING.md from the JSON

Checks (stdlib, no network):
- every required system exists once and has canonical docs, a skill, a validator, a test
  and a roadmap slice that appears in NEXT_SLICES.md; all referenced paths exist;
- every interface IC-01..IC-12 is bound to at least one system;
- every gap referenced by a system is defined and has owner, spec, test, non_goals, status;
- schema coverage lists exactly the files in .work/config/v7; each declared validator
  mentions the file; a file without validators must point to an OPEN gap;
- the Markdown view equals the rendered JSON (no second hand-written source).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".work" / "tooling" / "system_binding.json"
VIEW = ROOT / ".work" / "development" / "SYSTEM_BINDING.md"
REQUIRED = {"combat", "autocast", "status", "build", "draft", "save", "replay", "xp", "reward", "cultivation",
            "evolution", "stage", "enemy", "boss", "ux", "localization", "asset-pipeline"}
GAP_STATUS = {"OPEN", "NEEDS-USER", "BLOCKED-BY-RUNTIME", "CLOSED"}


class ContractError(ValueError):
    pass


def load(path: Path = SOURCE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def validate(data: dict, root: Path = ROOT) -> dict:
    if data.get("schema_version") != 1 or data.get("kind") != "system-binding":
        raise ContractError("unexpected system binding schema")
    roadmap = (root / ".work" / "roadmap" / "NEXT_SLICES.md").read_text(encoding="utf-8")
    skills = root / ".agents" / "skills"
    gaps = {g["id"]: g for g in data.get("gaps", [])}
    for gid, gap in gaps.items():
        for field in ("title", "owner", "spec", "test", "non_goals", "status"):
            if not gap.get(field):
                raise ContractError(gid + ": gap needs " + field)
        if gap["status"] not in GAP_STATUS:
            raise ContractError(gid + ": unknown status " + gap["status"])
        if not (root / gap["spec"]).exists():
            raise ContractError(gid + ": spec path does not exist: " + gap["spec"])
    seen, bound = set(), set()
    for system in data.get("systems", []):
        sid = system["id"]
        if sid in seen:
            raise ContractError("duplicate system " + sid)
        seen.add(sid)
        for field in ("canonical", "validators", "tests", "interfaces"):
            if not system.get(field):
                raise ContractError(sid + ": needs at least one " + field)
        for rel in system["canonical"] + system.get("config", []) + system["validators"] + system["tests"]:
            if not (root / rel).exists():
                raise ContractError(sid + ": path does not exist: " + rel)
        if not (skills / system["skill"] / "SKILL.md").is_file():
            raise ContractError(sid + ": unknown skill " + system["skill"])
        if system["roadmap"] not in roadmap:
            raise ContractError(sid + ": roadmap slice not in NEXT_SLICES.md: " + system["roadmap"])
        for ic in system["interfaces"]:
            if ic not in data["interfaces"]:
                raise ContractError(sid + ": unknown interface " + ic)
            bound.add(ic)
        for gid in system.get("gaps", []):
            if gid not in gaps:
                raise ContractError(sid + ": undefined gap " + gid)
    missing = REQUIRED - seen
    if missing:
        raise ContractError("systems without binding: " + ", ".join(sorted(missing)))
    unbound = set(data["interfaces"]) - bound
    if unbound:
        raise ContractError("interfaces not bound to any system: " + ", ".join(sorted(unbound)))
    coverage = {c["file"]: c for c in data.get("schema_coverage", [])}
    on_disk = {p.relative_to(root).as_posix() for p in (root / ".work" / "config" / "v7").iterdir()
               if p.is_file() and p.suffix in (".json", ".csv", ".cfg")}
    if set(coverage) != on_disk:
        raise ContractError("schema coverage differs from config/v7: missing %s, stale %s"
                            % (sorted(on_disk - set(coverage)), sorted(set(coverage) - on_disk)))
    uncovered = 0
    for rel, entry in coverage.items():
        name = Path(rel).name
        for script in entry["validators"]:
            text = (root / script).read_text(encoding="utf-8")
            if name not in text and Path(rel).stem not in text:
                raise ContractError("%s does not mention %s" % (script, name))
        if not entry["validators"]:
            uncovered += 1
            gap = gaps.get(entry.get("gap", ""))
            if not gap or gap["status"] == "CLOSED":
                raise ContractError(rel + ": no validator and no open gap")
    return {"systems": len(seen), "interfaces": len(bound), "gaps": len(gaps),
            "config_files": len(coverage), "config_without_validator": uncovered}


def link(rel: str) -> str:
    target = "../../" + rel
    return "[%s](%s)" % (Path(rel).name, target)


def render(data: dict) -> str:
    out = ["# SYSTEM_BINDING — игровая система → контракт → skill → проверка",
           "",
           "> Сгенерировано `python scripts/system_binding.py render` из "
           "[system_binding.json](../tooling/system_binding.json). Не редактировать вручную.",
           "",
           "- **Статус:** " + data["status"],
           "- **Срез / дата:** %s · %s" % (data["slice"], data["date"]),
           "- **Интерфейсы:** [INTERFACE-CONTRACTS-001](../spec/v7/interface-contracts-001.md)",
           "",
           "## Системы",
           "",
           "| Система | Канон | Конфиг | Skill | Проверка | Интерфейсы | Срез | Пробелы |",
           "|---|---|---|---|---|---|---|---|"]
    for s in data["systems"]:
        out.append("| %s | %s | %s | `%s` | %s | %s | %s | %s |" % (
            s["name"], "<br>".join(link(p) for p in s["canonical"]),
            "<br>".join(link(p) for p in s.get("config", [])) or "—", s["skill"],
            "<br>".join(link(p) for p in s["validators"] + s["tests"]),
            ", ".join(s["interfaces"]), s["roadmap"], ", ".join(s.get("gaps", [])) or "—"))
    out += ["", "## Интерфейсы", "", "| ID | Контракт |", "|---|---|"]
    out += ["| %s | %s |" % (k, v) for k, v in data["interfaces"].items()]
    out += ["", "## Реестр пробелов", "",
            "| ID | Пробел | Владелец | Спецификация | Проверка / witness | Non-goals | Статус |",
            "|---|---|---|---|---|---|---|"]
    for g in data["gaps"]:
        out.append("| %s | %s | %s | %s | %s | %s | **%s** |" % (
            g["id"], g["title"], g["owner"], link(g["spec"]), g["test"], g["non_goals"], g["status"]))
    out += ["", "## Покрытие схем `.work/config/v7`", "", "| Файл | Валидаторы |", "|---|---|"]
    for c in data["schema_coverage"]:
        cell = "<br>".join(link(v) for v in c["validators"]) or "**нет** → " + c.get("gap", "")
        out.append("| %s | %s |" % (link(c["file"]), cell))
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    command = argv[0] if argv else "validate"
    data = load()
    try:
        summary = validate(data)
        if command == "render":
            VIEW.write_text(render(data), encoding="utf-8", newline="\n")
        elif VIEW.read_text(encoding="utf-8") != render(data):
            raise ContractError("SYSTEM_BINDING.md is stale: run python scripts/system_binding.py render")
    except (ContractError, KeyError, FileNotFoundError) as exc:
        print("FAIL:", exc, file=sys.stderr)
        return 1
    print("System binding:", json.dumps(summary, sort_keys=True))
    print("PASS: every system bound to contract, skill, validator, test and roadmap slice; gaps owned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
