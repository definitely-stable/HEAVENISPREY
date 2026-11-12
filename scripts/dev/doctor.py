#!/usr/bin/env python3
"""Developer environment diagnostics for HEAVEN IS PREY (DEV-ENV-001).

Read-only. Reports what is installed versus the pinned toolchain lock, which
agent adapters/skills/MCP configs are present, and the git state. Exit code:
0 when every *required* tool is OK, 1 otherwise. Optional/deferred tools only
produce WARN lines. `--json` prints a machine-readable report.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / ".work" / "tooling" / "toolchain.lock.json"


def _module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


def version_tuple(text: str) -> tuple[int, ...]:
    numbers = re.findall(r"\d+", text)
    return tuple(int(x) for x in numbers[:3])


def probe(cmd: list[str]) -> str | None:
    exe = shutil.which(cmd[0])
    if not exe:
        return None
    try:
        out = subprocess.run([exe] + cmd[1:], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = (out.stdout or out.stderr).strip()
    return text.splitlines()[0] if text else None


def check_tools(lock: dict) -> list[dict]:
    rows = []
    for tool in lock["tools"]:
        row = {"id": tool["id"], "required": tool["required"], "phase": tool["phase"], "pinned": tool["version"]}
        found = None
        if tool["id"] == "tool.python":
            found = "%d.%d.%d" % sys.version_info[:3]
        elif tool["id"] == "tool.git":
            found = probe(["git", "--version"])
        elif tool["id"] == "tool.gh":
            found = probe(["gh", "--version"])
        elif tool["id"] == "tool.godot":
            godot = _module("hip_godot_tool", ROOT / "scripts" / "dev" / "godot_tool.py")
            try:
                exe = godot.locate(godot.load_spec(), godot.tools_root(None))
            except godot.ToolError as exc:
                exe, row["note"] = None, str(exc)
            if exe:
                found = probe([str(exe), "--headless", "--version"])
                row["path"] = str(exe)
        elif tool["id"] == "tool.gdtoolkit":
            found = probe(["gdlint", "--version"])
        row["found"] = found
        if found is None:
            row["status"] = "MISSING"
        elif version_tuple(found) >= version_tuple(tool["min_version"]):
            row["status"] = "OK"
        else:
            row["status"] = "TOO_OLD"
        if tool["id"] == "tool.godot" and found and not found.startswith(tool["version"].replace("-stable", ".stable")):
            row["status"] = "WRONG_VERSION"
        if tool["phase"] != "now" and row["status"] == "MISSING":
            row["status"] = "DEFERRED"
        rows.append(row)
    return rows


def check_files() -> list[dict]:
    paths = [
        ("AGENTS.md", True), ("CLAUDE.md", False), (".work/CURRENT_STATE.md", True),
        (".work/tooling/toolchain.lock.json", True), (".work/tooling/skills.lock.json", False),
        (".work/tooling/mcp.lock.json", False), (".agents/skills", False), (".claude/skills", False),
        (".mcp.json", False), (".codex/config.toml", False),
    ]
    return [{"path": p, "required": req, "status": "OK" if (ROOT / p).exists() else ("MISSING" if req else "ABSENT")}
            for p, req in paths]


def check_git() -> dict:
    head = probe(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
    branch = probe(["git", "-C", str(ROOT), "rev-parse", "--abbrev-ref", "HEAD"])
    return {"head": head, "branch": branch}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="HEAVEN IS PREY environment doctor")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    report = {"platform": sys.platform, "tools": check_tools(lock), "files": check_files(), "git": check_git()}
    failed = [t for t in report["tools"] if t["required"] and t["status"] != "OK"]
    failed += [f for f in report["files"] if f["required"] and f["status"] != "OK"]
    report["result"] = "FAIL" if failed else "PASS"
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("Platform:", report["platform"], "| git:", report["git"]["branch"], report["git"]["head"])
        for t in report["tools"]:
            level = "FAIL" if t in failed else ("OK  " if t["status"] == "OK" else "WARN")
            print("%s %-16s pinned=%-14s found=%s [%s]" % (level, t["id"], t["pinned"], t["found"], t["status"]))
        for f in report["files"]:
            level = "FAIL" if f in failed else ("OK  " if f["status"] == "OK" else "INFO")
            print("%s %s [%s]" % (level, f["path"], f["status"]))
        print(report["result"] + ": required tools/files", "missing" if failed else "present")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
