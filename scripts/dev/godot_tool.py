#!/usr/bin/env python3
"""Reproducible Godot install/locate/smoke for HEAVEN IS PREY (DEV-ENV-001).

Stdlib only. Reads the pinned release from .work/tooling/toolchain.lock.json,
downloads the official archive, verifies SHA-512 before extracting and installs
into <install_root>/godot/<version>/ (default .tools/, git-ignored).

The smoke test runs the binary headless against a throw-away project in a temp
directory; it never creates files inside the repository (no game runtime yet).

From P0-00 it also installs the pinned GUT addon into game/addons/gut (git-ignored,
verified by a tree digest because GitHub archive bytes are not a stable contract)
and runs the Godot project: headless import plus the GUT suite.

Usage:
  python scripts/dev/godot_tool.py install     [--root DIR]
  python scripts/dev/godot_tool.py path        [--root DIR]
  python scripts/dev/godot_tool.py smoke       [--root DIR] [--godot PATH]
  python scripts/dev/godot_tool.py gut-install
  python scripts/dev/godot_tool.py test        [--root DIR] [--godot PATH]
Environment: GODOT_BIN overrides discovery; HIP_TOOLS_ROOT overrides --root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / ".work" / "tooling" / "toolchain.lock.json"
ALLOWED_PREFIX = "https://github.com/godotengine/godot/releases/download/"
GUT_PREFIX = "https://codeload.github.com/bitwes/Gut/zip/"
GAME = ROOT / "game"
GUT_TARGET = GAME / "addons" / "gut"
GUT_TEST_DIRS = ("unit", "integration", "replay")
# Committed, intentionally failing suite: the runner must report it as a failure.
GUT_NEGATIVE_DIR = "negative_control"


class ToolError(RuntimeError):
    pass


def load_spec(lock_path: Path = LOCK, tool_id: str = "tool.godot") -> dict:
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    for tool in data["tools"]:
        if tool["id"] == tool_id:
            return tool
    raise ToolError(tool_id + " missing from toolchain lock")


def platform_key() -> str:
    machine = platform.machine().lower()
    if machine not in ("amd64", "x86_64"):
        raise ToolError("unsupported architecture: " + machine)
    if sys.platform.startswith("win"):
        return "windows-x86_64"
    if sys.platform.startswith("linux"):
        return "linux-x86_64"
    raise ToolError("unsupported OS for pinned assets: " + sys.platform)


def tools_root(cli_root: str | None) -> Path:
    raw = cli_root or os.environ.get("HIP_TOOLS_ROOT") or str(ROOT / ".tools")
    return Path(raw).resolve()


def install_dir(spec: dict, root: Path) -> Path:
    return root / "godot" / spec["version"]


def sha512_file(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(archive: Path, target: Path) -> None:
    target = target.resolve()
    with zipfile.ZipFile(archive) as zf:
        for member in zf.infolist():
            dest = (target / member.filename).resolve()
            if not dest.is_relative_to(target):
                raise ToolError("archive path escapes target: " + member.filename)
        zf.extractall(target)


def locate(spec: dict, root: Path) -> Path | None:
    override = os.environ.get("GODOT_BIN")
    if override:
        path = Path(override)
        return path if path.is_file() else None
    asset = spec["assets"][platform_key()]
    candidate = install_dir(spec, root) / asset["executable"]
    return candidate if candidate.is_file() else None


def install(spec: dict, root: Path) -> Path:
    asset = spec["assets"][platform_key()]
    existing = install_dir(spec, root) / asset["executable"]
    if existing.is_file():
        print("Already installed:", existing)
        return existing
    url = asset["url"]
    if not url.startswith(ALLOWED_PREFIX):
        raise ToolError("refusing non-official download URL: " + url)
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        archive = Path(tmp) / asset["file"]
        print("Downloading", url)
        with urllib.request.urlopen(url, timeout=120) as resp, archive.open("wb") as out:
            shutil.copyfileobj(resp, out, length=1 << 20)
        actual = sha512_file(archive)
        if actual != asset["sha512"]:
            raise ToolError("SHA-512 mismatch for %s: %s" % (asset["file"], actual))
        print("SHA-512 verified:", asset["file"])
        staging = Path(tmp) / "x"
        safe_extract(archive, staging)
        target = install_dir(spec, root)
        target.mkdir(parents=True, exist_ok=True)
        for item in staging.iterdir():
            shutil.move(str(item), str(target / item.name))
    exe = install_dir(spec, root) / asset["executable"]
    if not exe.is_file():
        raise ToolError("expected executable missing after extract: " + str(exe))
    if not sys.platform.startswith("win"):
        exe.chmod(exe.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print("Installed:", exe)
    return exe


def tree_digest(files: dict[str, bytes]) -> str:
    """sha256 over sorted '<relative path>\0<sha256 hex>\n' lines (lock tree_digest_policy)."""
    digest = hashlib.sha256()
    for rel in sorted(files):
        digest.update((rel + "\0" + hashlib.sha256(files[rel]).hexdigest() + "\n").encode("utf-8"))
    return digest.hexdigest()


def directory_files(base: Path) -> dict[str, bytes]:
    return {p.relative_to(base).as_posix(): p.read_bytes() for p in base.rglob("*") if p.is_file()}


def gut_installed(spec: dict, target: Path = GUT_TARGET) -> bool:
    if not target.is_dir():
        return False
    files = directory_files(target)
    return len(files) == spec["file_count"] and tree_digest(files) == spec["tree_sha256"]


def gut_install(spec: dict, target: Path = GUT_TARGET) -> Path:
    if gut_installed(spec, target):
        print("Already installed (tree digest verified):", target)
        return target
    url = spec["archive_url"]
    if not url.startswith(GUT_PREFIX) or not url.endswith("/" + spec["source_commit"]):
        raise ToolError("refusing GUT archive not pinned to the locked commit: " + url)
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "gut.zip"
        print("Downloading", url)
        with urllib.request.urlopen(url, timeout=120) as resp, archive.open("wb") as out:
            shutil.copyfileobj(resp, out, length=1 << 20)
        with zipfile.ZipFile(archive) as zf:
            top = zf.infolist()[0].filename.split("/")[0] + "/"
            prefix = top + spec["subtree"].strip("/") + "/"
            files = {}
            for member in zf.infolist():
                if member.is_dir() or not member.filename.startswith(prefix):
                    continue
                rel = member.filename[len(prefix):]
                if rel.startswith("/") or ".." in Path(rel).parts:
                    raise ToolError("archive path escapes subtree: " + member.filename)
                files[rel] = zf.read(member)
    actual = tree_digest(files)
    if len(files) != spec["file_count"] or actual != spec["tree_sha256"]:
        raise ToolError("GUT tree digest mismatch: files=%d digest=%s" % (len(files), actual))
    print("GUT tree digest verified:", actual)
    if target.exists():
        shutil.rmtree(target)
    for rel, data in files.items():
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    print("Installed GUT", spec["version"], "->", target)
    return target


GUT_COUNT_KEYS = ("Errors", "Tests", "Passing Tests", "Failing Tests", "Risky/Pending", "Asserts")


def parse_gut_counts(log: str) -> dict[str, int]:
    counts = {}
    for key in GUT_COUNT_KEYS:
        # GUT prints "Asserts 12" on success and "Asserts 10/12" (passed/total) on failure.
        found = re.findall(r"^\s*" + re.escape(key) + r"\s+(\d+)(?:/\d+)?\s*$", log, re.M)
        if found:
            counts[key] = int(found[-1])
    return counts


def error_lines(log: str) -> list[str]:
    return [line for line in log.splitlines()
            if re.search(r"SCRIPT ERROR|Parse Error|GUT ERROR|^\s*ERROR:", line)]


def gut_run(exe: Path, dirs: list[str]) -> tuple[int, str]:
    cmd = [str(exe), "--headless", "--path", str(GAME), "-s", "res://addons/gut/gut_cmdln.gd",
           "-gexit", "-glog=1", "-gdisable_colors", "-ginclude_subdirs",
           "-gprefix=test_", "-gsuffix=.gd"]
    cmd += ["-gdir=res://tests/" + d for d in dirs]
    proc = run(cmd, GAME)
    return proc.returncode, proc.stdout + proc.stderr


def suite_problems(rc: int, counts: dict[str, int], errors: list[str]) -> list[str]:
    """Why a GUT run is not a clean pass; empty means pass.

    Every discovered test must pass with at least one assert overall; pending/risky tests
    (no asserts, pending()) and summaries without counts are failures, not green.
    """
    problems = []
    if rc != 0:
        problems.append("GUT exit code %d" % rc)
    tests = counts.get("Tests", 0)
    if tests <= 0:
        problems.append("no tests discovered")
    if counts.get("Passing Tests", -1) != tests:
        problems.append("passing tests != discovered tests")
    for key in ("Failing Tests", "Risky/Pending", "Errors"):
        if counts.get(key, 0) != 0:
            problems.append("%s: %d" % (key, counts[key]))
    if counts.get("Asserts", 0) <= 0:
        problems.append("no asserts executed")
    if errors:
        problems.append("script/engine errors in log")
    return problems


def run_tests(exe: Path, gut: dict, godot: dict | None = None) -> dict:
    """Headless import, then GUT; anything but a clean, non-empty pass is a hard error."""
    if not (GAME / "project.godot").is_file():
        raise ToolError("game/project.godot missing")
    if godot is not None:
        expected = godot["version"].replace("-stable", "") + ".stable"
        version = run([str(exe), "--headless", "--version"], GAME).stdout.strip()
        if not version.startswith(expected):
            raise ToolError("Godot binary is %r, lock requires %s" % (version, godot["version"]))
    if not gut_installed(gut):
        raise ToolError("GUT missing or tampered: run python scripts/dev/godot_tool.py gut-install")
    imported = run([str(exe), "--headless", "--path", str(GAME), "--import"], GAME)
    import_log = imported.stdout + imported.stderr
    result = {"import_rc": imported.returncode, "import_errors": error_lines(import_log)[:20]}
    if imported.returncode != 0 or result["import_errors"]:
        print(import_log[-4000:], file=sys.stderr)
        raise ToolError("headless import failed: " + json.dumps(result))
    dirs = [d for d in GUT_TEST_DIRS if (GAME / "tests" / d).is_dir()]
    rc, log = gut_run(exe, dirs)
    print(log[-6000:])
    counts = parse_gut_counts(log)
    errors = error_lines(log)
    problems = suite_problems(rc, counts, errors)
    result.update({"gut_dirs": dirs, "gut_rc": rc, "counts": counts, "script_errors": errors[:20],
                   "problems": problems})
    if problems:
        raise ToolError("GUT run failed: " + json.dumps(result))
    neg_rc, neg_log = gut_run(exe, [GUT_NEGATIVE_DIR])
    neg_counts = parse_gut_counts(neg_log)
    result["negative_control"] = {"rc": neg_rc, "counts": neg_counts}
    if neg_rc == 0 or neg_counts.get("Failing Tests", 0) <= 0:
        print(neg_log[-3000:], file=sys.stderr)
        raise ToolError("negative control: an intentionally failing GUT test did not fail the run")
    return result


SMOKE_SCRIPT = """extends SceneTree

func _init() -> void:
\tvar info: Dictionary = Engine.get_version_info()
\tvar typed: Array[int] = [1, 2, 3]
\tvar total: int = 0
\tfor value: int in typed:
\t\ttotal += value
\tprint("HIP_SMOKE version=%s.%s.%s status=%s typed_sum=%d" % [info.major, info.minor, info.patch, info.status, total])
\tquit(0 if total == 6 else 3)
"""


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300,
                          encoding="utf-8", errors="replace")


def smoke(exe: Path, spec: dict) -> dict:
    expected = spec["version"].replace("-stable", "")
    result = {"godot": str(exe), "expected": spec["version"]}
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        version = run([str(exe), "--headless", "--version"], tmp_path)
        result["version_output"] = version.stdout.strip()
        if version.returncode != 0 or not version.stdout.strip().startswith(expected + ".stable"):
            raise ToolError("unexpected --version output: %r (rc=%d)" % (version.stdout, version.returncode))
        (tmp_path / "project.godot").write_text("config_version=5\n\n[application]\nconfig/name=\"hip_smoke\"\n", encoding="utf-8")
        (tmp_path / "smoke.gd").write_text(SMOKE_SCRIPT, encoding="utf-8")
        script = run([str(exe), "--headless", "--path", str(tmp_path), "--script", "res://smoke.gd"], tmp_path)
        output = script.stdout + script.stderr
        result["script_rc"] = script.returncode
        marker = [line for line in output.splitlines() if line.startswith("HIP_SMOKE")]
        result["script_output"] = marker[0] if marker else output.strip()[-400:]
        if script.returncode != 0 or not marker or "typed_sum=6" not in marker[0]:
            raise ToolError("headless typed GDScript smoke failed: " + json.dumps(result))
        bad = run([str(exe), "--headless", "--path", str(tmp_path), "--script", "res://missing.gd"], tmp_path)
        result["negative_control_rc"] = bad.returncode
        if bad.returncode == 0:
            raise ToolError("negative control: missing script must exit non-zero")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["install", "path", "smoke", "gut-install", "test"])
    parser.add_argument("--root", default=None)
    parser.add_argument("--godot", default=None, help="explicit binary for smoke")
    args = parser.parse_args(argv)
    try:
        spec = load_spec()
        root = tools_root(args.root)
        if args.command == "gut-install":
            gut_install(load_spec(tool_id="tool.gut"))
            return 0
        if args.command == "test":
            exe = Path(args.godot) if args.godot else locate(spec, root)
            if not exe or not exe.is_file():
                print("NOT INSTALLED: run python scripts/dev/godot_tool.py install", file=sys.stderr)
                return 2
            print(json.dumps(run_tests(exe, load_spec(tool_id="tool.gut"), spec), indent=2))
            print("PASS: headless import and GUT suite")
            return 0
        if args.command == "install":
            install(spec, root)
        elif args.command == "path":
            exe = locate(spec, root)
            if not exe:
                print("NOT INSTALLED: run python scripts/dev/godot_tool.py install", file=sys.stderr)
                return 2
            print(exe)
        else:
            exe = Path(args.godot) if args.godot else locate(spec, root)
            if not exe or not exe.is_file():
                print("NOT INSTALLED: run python scripts/dev/godot_tool.py install", file=sys.stderr)
                return 2
            print(json.dumps(smoke(exe, spec), indent=2))
            print("PASS: Godot", spec["version"], "headless smoke (version, typed GDScript, negative control)")
    except ToolError as exc:
        print("FAIL:", exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
