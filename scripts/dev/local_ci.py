#!/usr/bin/env python3
"""Run every CI step of .github/workflows locally, with one exit code (DEV-ENV-001).

The steps are read from the workflow files themselves, so the local run cannot fall behind CI:
each `run:` command (one line or a `run: |` block) becomes a step, a command that two
workflows share runs once, and only the steps listed in SKIP (installs and LFS fetches the
local checkout already has) are left out, each with its reason. `python` runs as this
interpreter; `gdlint` is taken from --gdlint, then $GDLINT, then PATH. A tool that cannot be
found is a failure, not a silent skip.

    python scripts/dev/local_ci.py              # all steps, 4 at a time, then GUT alone
    python scripts/dev/local_ci.py --list       # what would run and what is skipped
    python scripts/dev/local_ci.py -k assets -k skills
    python scripts/dev/local_ci.py --gdlint path/to/venv/Scripts/gdlint.exe
"""
from __future__ import annotations

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
# Workflows that run checks (toolchain-smoke only installs and reports versions).
CHECKED = ("design-validation.yml", "godot-tests.yml")
# Command prefix -> why it does not run locally.
SKIP = {
    "git lfs pull": "the local checkout already holds the LFS files; validate_assets checks their content",
    "python -m pip install gdtoolkit": "gdlint is taken from --gdlint, $GDLINT or PATH",
    "python scripts/dev/godot_tool.py install": "install step; the test step fails if Godot is missing",
    "python scripts/dev/godot_tool.py gut-install": "install step; the test step fails if GUT is missing",
}
# Steps that run alone after the others: GUT has a 300 s budget inside godot_tool and misses it
# when the validators load every core at the same time.
SERIAL = ("python scripts/dev/godot_tool.py test",)
TAIL_LINES = 30


@dataclass
class Step:
    workflow: str
    name: str
    command: str


def parse_workflow(text: str, workflow: str = "") -> list[Step]:
    """The `run:` commands of a workflow in order, each with the name of its step. A block
    (`run: |`) yields one step per non-empty line, as the CI shell runs them one after another
    and stops at the first failure."""
    steps: list[Step] = []
    lines = text.splitlines()
    name = ""
    i = 0
    while i < len(lines):
        line = lines[i]
        named = re.match(r"^\s*-?\s*name:\s*(.+?)\s*$", line)
        if named:
            name = named.group(1).strip("'\"")
        run = re.match(r"^(\s*)-?\s*run:\s*(.*?)\s*$", line)
        if run:
            indent, value = len(run.group(1)), run.group(2)
            if value in ("|", ">", "|-", ">-"):
                i += 1
                while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
                    if lines[i].strip():
                        steps.append(Step(workflow, name, lines[i].strip()))
                    i += 1
                continue
            steps.append(Step(workflow, name, value))
        i += 1
    return steps


def workflow_steps() -> list[Step]:
    steps: list[Step] = []
    for file in CHECKED:
        steps += parse_workflow((WORKFLOWS / file).read_text(encoding="utf-8"), file)
    return steps


def skip_reason(command: str) -> str:
    return next((why for prefix, why in SKIP.items() if command.startswith(prefix)), "")


def plan(steps: list[Step]) -> tuple[list[Step], list[tuple[Step, str]]]:
    """Steps to run (first occurrence of each command) and the skipped ones with reasons."""
    run, skipped, seen = [], [], set()
    for step in steps:
        reason = skip_reason(step.command)
        if reason:
            skipped.append((step, reason))
        elif step.command not in seen:
            seen.add(step.command)
            run.append(step)
    return run, skipped


def argv_of(command: str, gdlint: str | None) -> list[str] | None:
    """The command as an argument list for this machine, or None when its tool is missing."""
    args = shlex.split(command)
    if args[0] == "python":
        args[0] = sys.executable
    elif args[0] == "gdlint":
        if not gdlint:
            return None
        args[0] = gdlint
    return args


def run_step(step: Step, gdlint: str | None) -> tuple[str, float, str]:
    args = argv_of(step.command, gdlint)
    if args is None:
        return "MISSING", 0.0, "gdlint not found: pass --gdlint, set GDLINT or install gdtoolkit==4.5.0"
    start = time.monotonic()
    done = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = (done.stdout or "") + (done.stderr or "")
    return ("PASS" if done.returncode == 0 else "FAIL"), time.monotonic() - start, output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true", help="print the plan and exit")
    parser.add_argument("-k", dest="patterns", action="append", default=[],
                        help="run only steps whose command or name contains this text (repeatable)")
    parser.add_argument("--gdlint", default=os.environ.get("GDLINT") or shutil.which("gdlint"))
    parser.add_argument("--jobs", type=int, default=4, help="steps run at the same time")
    args = parser.parse_args(argv)

    steps, skipped = plan(workflow_steps())
    if args.patterns:
        steps = [s for s in steps if any(p in s.command or p in s.name for p in args.patterns)]
    if args.list:
        for step in steps:
            print(f"RUN   {step.workflow}: {step.command}")
        for step, reason in skipped:
            print(f"SKIP  {step.workflow}: {step.command}  ({reason})")
        return 0

    parallel = [s for s in steps if not s.command.startswith(SERIAL)]
    serial = [s for s in steps if s.command.startswith(SERIAL)]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda s: run_step(s, args.gdlint), parallel))
    results += [run_step(s, args.gdlint) for s in serial]
    steps = parallel + serial
    failed = 0
    for step, (status, seconds, output) in zip(steps, results):
        print(f"{status:7} {seconds:6.1f}s  {step.command}")
        if status != "PASS":
            failed += 1
            for line in output.rstrip().splitlines()[-TAIL_LINES:]:
                print(f"          | {line}")
    for step, reason in skipped:
        print(f"SKIP             {step.command}  ({reason})")
    print(f"\n{len(steps) - failed} passed, {failed} failed, {len(skipped)} skipped of {len(steps) + len(skipped)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
