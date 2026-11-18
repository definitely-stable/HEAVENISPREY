"""Export the locked desktop build and replay the Python oracle in the native binary."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
from zipfile import ZipFile

import godot_tool


PRESETS = {
    "windows": ("Windows Desktop", "heaven-is-prey.exe", "heaven-is-prey.console.exe",
                ("windows_release_x86_64.exe", "windows_release_x86_64_console.exe")),
    "linux": ("Linux", "heaven-is-prey.x86_64", "heaven-is-prey.x86_64", ("linux_release.x86_64",)),
}


def install_templates(archive: Path, asset: dict, release: str, names: tuple[str, ...]) -> None:
    if archive.stat().st_size != asset["size"] or godot_tool.sha512_file(archive) != asset["sha512"]:
        raise godot_tool.ToolError("SHA-512 export template pin does not match")
    if sys.platform.startswith("win"):
        editor_data = Path(os.environ["APPDATA"]) / "Godot"
    else:
        editor_data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "godot"
    target = editor_data / "export_templates" / release.replace("-", ".")
    target.mkdir(parents=True, exist_ok=True)
    with ZipFile(archive) as incoming, tempfile.TemporaryDirectory(dir=target) as temporary:
        staging = Path(temporary)
        for name in names:
            member = incoming.getinfo("templates/" + name)
            partial = staging / name
            with incoming.open(member) as source, partial.open("wb") as out:
                shutil.copyfileobj(source, out, length=1 << 20)
            destination = target / name
            if destination.exists():
                if godot_tool.sha512_file(partial) != godot_tool.sha512_file(destination):
                    raise godot_tool.ToolError(f"Installed export template differs from the lock: {destination}")
            else:
                partial.replace(destination)
            if not sys.platform.startswith("win"):
                destination.chmod(destination.stat().st_mode | stat.S_IXUSR)
    print("Verified locked release templates:", target, flush=True)


def export(args) -> None:
    spec = godot_tool.load_spec()
    root = godot_tool.tools_root(None)
    engine = godot_tool.locate(spec, root)
    if engine is None:
        raise godot_tool.ToolError("Install the locked Godot editor with godot_tool.py first")
    asset = spec["deferred_assets"]["export-templates"]
    preset, filename, console, templates = PRESETS[args.platform]
    if args.template_archive is None:
        url = asset["url"]
        if not url.startswith(godot_tool.ALLOWED_PREFIX):
            raise godot_tool.ToolError("Export templates must come from the locked official release")
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as temporary:
            archive = Path(temporary) / asset["file"]
            print("Downloading locked release templates", flush=True)
            with urllib.request.urlopen(url, timeout=120) as source, archive.open("wb") as output:
                shutil.copyfileobj(source, output, length=1 << 20)
            install_templates(archive, asset, spec["version"], templates)
    else:
        install_templates(args.template_archive, asset, spec["version"], templates)

    path = args.output.resolve()
    path.mkdir(parents=True, exist_ok=True)
    base = [str(engine), "--headless", "--path", str(godot_tool.GAME)]
    subprocess.run([*base, "--import"], check=True, timeout=300)
    binary = path / filename
    subprocess.run([*base, "--export-release", preset, str(binary)], check=True, timeout=300)
    if not binary.is_file() or not binary.with_suffix(".pck").is_file():
        raise godot_tool.ToolError("Release export is missing its executable or pack")
    if args.fixture is not None:
        native = "windows" if sys.platform.startswith("win") else "linux"
        if native != args.platform:
            raise godot_tool.ToolError("Replay verification requires a native export runner")
        smoke = [str(path / console), "--headless", "--", "--verify-export-replay"]
        subprocess.run([*smoke, str(args.fixture.resolve())], cwd=path, check=True, timeout=360)
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "invalid.json"
            corrupted = json.loads(args.fixture.read_text(encoding="utf-8"))
            corrupted["traces"][0]["checkpoints"][-1]["digest"] = "0" * 64
            bad.write_text(json.dumps(corrupted), encoding="utf-8")
            result = subprocess.run([*smoke, str(bad)], cwd=path, check=False, timeout=360,
                                    capture_output=True, text=True, encoding="utf-8", errors="replace")
            if result.returncode != 1 or "World digest mismatch" not in result.stderr:
                raise godot_tool.ToolError("Corrupt digest was not rejected by the exported game")
            print("PASS: release replay rejected a corrupted world digest")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=PRESETS)
    parser.add_argument("output", type=Path)
    parser.add_argument("--template-archive", type=Path)
    parser.add_argument("--fixture", type=Path, help="Python bot traces to run in the native export")
    try:
        export(parser.parse_args())
    except (godot_tool.ToolError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
