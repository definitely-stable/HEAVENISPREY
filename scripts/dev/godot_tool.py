#!/usr/bin/env python3
"""Reproducible Godot install/locate/smoke for HEAVEN IS PREY (DEV-ENV-001).

Stdlib only. Reads the pinned release from .work/tooling/toolchain.lock.json,
downloads the official archive, verifies SHA-512 before extracting and installs
into <install_root>/godot/<version>/ (default .tools/, git-ignored).

The smoke test runs the binary headless against a throw-away project in a temp
directory; it never creates files inside the repository (no game runtime yet).

Usage:
  python scripts/dev/godot_tool.py install [--root DIR]
  python scripts/dev/godot_tool.py path    [--root DIR]
  python scripts/dev/godot_tool.py smoke   [--root DIR] [--godot PATH]
Environment: GODOT_BIN overrides discovery; HIP_TOOLS_ROOT overrides --root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
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


class ToolError(RuntimeError):
    pass


def load_spec(lock_path: Path = LOCK) -> dict:
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    for tool in data["tools"]:
        if tool["id"] == "tool.godot":
            return tool
    raise ToolError("tool.godot missing from toolchain lock")


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
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300)


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
    parser.add_argument("command", choices=["install", "path", "smoke"])
    parser.add_argument("--root", default=None)
    parser.add_argument("--godot", default=None, help="explicit binary for smoke")
    args = parser.parse_args(argv)
    try:
        spec = load_spec()
        root = tools_root(args.root)
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
