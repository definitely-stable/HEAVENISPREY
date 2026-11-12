#!/usr/bin/env python3
"""Static validation of the pinned developer toolchain (DEV-ENV-001).

Checks .work/tooling/toolchain.lock.json without network access:
- schema, unique IDs, dependency-budget fields from s21.2 for every tool;
- no floating pins ("latest", "*", ranges) and min_version <= version;
- Godot matches ADR-001 (4.7.x stable), assets come only from the official
  godotengine release URL of the same tag and carry a 128-hex SHA-512;
- GitHub workflows that install Godot use the lock (no second hard-coded pin);
- nothing in the lock is declared a game runtime dependency.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / ".work" / "tooling" / "toolchain.lock.json"
WORKFLOWS = ROOT / ".github" / "workflows"
BUDGET_FIELDS = ("reason", "install", "integration_test", "removal_plan", "ci_impact", "agent_compat")
PHASES = {"now", "P0-00", "P0-01", "later"}
FLOATING = re.compile(r"(latest|\*|\^|~|>|<|\bx\b)", re.I)
VERSION = re.compile(r"^\d+\.\d+(\.\d+)?(-[a-z0-9.]+)?$")


class ContractError(ValueError):
    pass


def load(path: Path = LOCK) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def vt(text: str) -> tuple[int, ...]:
    return tuple(int(x) for x in re.findall(r"\d+", text.split("-")[0])[:3])


def validate(lock: dict, workflows: dict[str, str] | None = None) -> dict:
    if lock.get("schema_version") != 1 or lock.get("kind") != "toolchain-lock":
        raise ContractError("unexpected schema_version/kind")
    seen = set()
    for tool in lock["tools"]:
        tid = tool.get("id", "")
        if not tid.startswith("tool.") or tid in seen:
            raise ContractError("bad or duplicate tool id: " + tid)
        seen.add(tid)
        for field in BUDGET_FIELDS:
            if not str(tool.get(field, "")).strip():
                raise ContractError(tid + ": missing dependency-budget field " + field)
        if tool.get("phase") not in PHASES:
            raise ContractError(tid + ": unknown phase " + str(tool.get("phase")))
        for key in ("version", "min_version"):
            value = str(tool.get(key, ""))
            if FLOATING.search(value) or not VERSION.match(value):
                raise ContractError(tid + ": floating or malformed " + key + " " + value)
        if vt(tool["min_version"]) > vt(tool["version"]):
            raise ContractError(tid + ": min_version above pinned version")
        if "runtime" in str(tool.get("kind", "")).lower():
            raise ContractError(tid + ": dev toolchain must not declare a game runtime dependency")
    if "tool.python" not in seen or "tool.godot" not in seen:
        raise ContractError("python and godot entries are mandatory")
    godot = next(t for t in lock["tools"] if t["id"] == "tool.godot")
    if not re.match(r"^4\.7\.\d+-stable$", godot["version"]):
        raise ContractError("Godot pin must be a 4.7.x stable release (ADR-001)")
    if godot["source_tag"] != godot["version"]:
        raise ContractError("Godot source_tag differs from version")
    if not re.fullmatch(r"[0-9a-f]{40}", godot.get("source_commit", "")):
        raise ContractError("Godot source_commit must be a full SHA")
    prefix = "https://github.com/godotengine/godot/releases/download/%s/" % godot["source_tag"]
    assets = dict(godot["assets"])
    if set(assets) != {"windows-x86_64", "linux-x86_64"}:
        raise ContractError("Godot needs exactly windows-x86_64 and linux-x86_64 assets")
    assets.update(godot.get("deferred_assets", {}))
    for key, asset in assets.items():
        if not asset["url"].startswith(prefix) or not asset["url"].endswith("/" + asset["file"]):
            raise ContractError("Godot asset %s not from official tag URL" % key)
        if godot["version"] not in asset["file"]:
            raise ContractError("Godot asset %s file does not carry the pinned version" % key)
        if not re.fullmatch(r"[0-9a-f]{128}", asset.get("sha512", "")):
            raise ContractError("Godot asset %s needs a SHA-512" % key)
        if int(asset.get("size", 0)) <= 0:
            raise ContractError("Godot asset %s needs a positive size" % key)
    if workflows is None:
        workflows = {p.name: p.read_text(encoding="utf-8") for p in WORKFLOWS.glob("*.y*ml")}
    godot_jobs = 0
    for name, text in workflows.items():
        if re.search(r"godot", text, re.I) and re.search(r"Godot_v\d|releases/download/\d", text):
            raise ContractError(name + ": hard-coded Godot download; use scripts/dev/godot_tool.py")
        if "godot_tool.py install" in text:
            godot_jobs += 1
            if "toolchain.lock.json" not in text:
                raise ContractError(name + ": Godot cache key must hash the toolchain lock")
        for line in text.splitlines():
            if re.search(r"uses:\s*\S+@(main|master|latest)\b", line):
                raise ContractError(name + ": floating action ref: " + line.strip())
    return {"tools": len(seen), "godot": godot["version"], "godot_ci_jobs": godot_jobs,
            "now": sum(1 for t in lock["tools"] if t["phase"] == "now")}


if __name__ == "__main__":
    try:
        summary = validate(load())
    except (ContractError, KeyError, json.JSONDecodeError) as exc:
        print("FAIL:", exc, file=sys.stderr)
        raise SystemExit(1)
    print("Toolchain:", json.dumps(summary, sort_keys=True))
    print("PASS: pinned toolchain lock, official Godot assets with SHA-512, workflows use the lock")
