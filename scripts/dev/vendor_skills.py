#!/usr/bin/env python3
"""Reproducible vendoring of pinned third-party agent skills (DEV-ENV-002b).

Reads `vendor_sources` from .work/tooling/skills.lock.json, downloads each source
repository at its pinned commit from codeload.github.com (tarball, no git, no
installers), extracts it safely into a temp dir, copies only the listed skill
folders plus the upstream LICENSE/NOTICE into .agents/skills/<name>/, and writes
or checks the tree_sha256 recorded in `vendored`.

  python scripts/dev/vendor_skills.py sync          # install/refresh pinned skills
  python scripts/dev/vendor_skills.py sync --check  # fail if disk != lock (no writes)
  python scripts/dev/vendor_skills.py sync --update-lock  # record digests after review

Network is required only for `sync`; CI verifies digests offline through
scripts/validate_agent_skills.py.
"""
from __future__ import annotations

import argparse
import importlib.util
import io
import json
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / ".work" / "tooling" / "skills.lock.json"
DEST = ROOT / ".agents" / "skills"

_spec = importlib.util.spec_from_file_location("hip_skills_validator", ROOT / "scripts" / "validate_agent_skills.py")
_validator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_validator)
tree_digest = _validator.tree_digest


def fetch(repo: str, commit: str, into: Path) -> Path:
    url = "https://codeload.github.com/%s/tar.gz/%s" % (repo, commit)
    if len(commit) != 40:
        raise SystemExit("refusing unpinned ref for " + repo)
    with urllib.request.urlopen(url, timeout=120) as resp:
        data = resp.read()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        tar.extractall(into, filter="data")
    roots = [p for p in into.iterdir() if p.is_dir()]
    if len(roots) != 1:
        raise SystemExit("unexpected archive layout for " + repo)
    return roots[0]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="vendor pinned agent skills")
    parser.add_argument("command", choices=["sync"])
    parser.add_argument("--check", action="store_true", help="compare only, write nothing")
    parser.add_argument("--update-lock", action="store_true", help="record new tree digests")
    args = parser.parse_args(argv)
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    vendored = {v["name"]: v for v in lock.get("vendored", [])}
    problems = 0
    for source in lock.get("vendor_sources", []):
        with tempfile.TemporaryDirectory() as tmp:
            src_root = fetch(source["repo"], source["commit"], Path(tmp))
            for skill in source["skills"]:
                name = Path(skill).name
                staged = Path(tmp) / "staged" / name
                shutil.copytree(src_root / skill, staged)
                for extra in source.get("license_files", ["LICENSE"]):
                    shutil.copy(src_root / extra, staged / extra)
                digest = tree_digest(staged)
                entry = vendored.get(name)
                if args.check:
                    on_disk = tree_digest(DEST / name) if (DEST / name).is_dir() else None
                    ok = entry and entry["tree_sha256"] == digest == on_disk
                    print(("OK   " if ok else "DIFF ") + name)
                    problems += 0 if ok else 1
                    continue
                if entry and entry["tree_sha256"] != digest and not args.update_lock:
                    print("FAIL: upstream content for %s differs from lock; review and use --update-lock" % name)
                    problems += 1
                    continue
                if (DEST / name).exists():
                    shutil.rmtree(DEST / name)
                shutil.copytree(staged, DEST / name)
                vendored[name] = {"name": name, "source": source["repo"], "commit": source["commit"],
                                  "upstream_path": skill, "license": source["license"],
                                  "license_file": source.get("license_files", ["LICENSE"])[0],
                                  "tree_sha256": digest}
                print("Installed", name, digest[:12])
    if args.update_lock or not args.check:
        lock["vendored"] = [vendored[k] for k in sorted(vendored)]
        LOCK.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
