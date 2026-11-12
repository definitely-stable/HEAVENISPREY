#!/usr/bin/env python3
"""DEV-ENV-002: static validation of repo-local agent skills and their adapters.

Canonical skills live in .agents/skills/<name>/SKILL.md (read natively by Codex and
OpenCode). Claude Code reads the same directory through the repo-local plugin
manifest .agents/.claude-plugin/plugin.json, so no skill file is duplicated (OpenCode
requires unique skill names across .agents/ and .claude/ skill directories).

Checks (stdlib only, no network):
- frontmatter: name == directory, kebab-case, description with trigger ("Use when")
  and boundary ("Not for"); project skills use the hip- prefix;
- required sections; every relative link resolves; at least one link into .work/;
- no link to the archived v6 original as active canon; no model-exclusive roles;
- every `scripts/....py` command mentioned exists (no undefined tools);
- no `.claude/skills` copy of a canonical skill (duplicate IDs), no secrets;
- vendored third-party skills match .work/tooling/skills.lock.json (path, SHA-256,
  license file, pinned commit); unlisted skills fail.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / ".agents" / "skills"
LOCK = ROOT / ".work" / "tooling" / "skills.lock.json"
REQUIRED_SECTIONS = ("## Use when", "## Not for", "## Canonical sources", "## Procedure", "## Acceptance")
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MODEL_ROLE = re.compile(r"\b(Codex|Claude|Opus|Sonnet|OpenCode|GPT-\d)\b")
SECRET = re.compile(r"(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})")
LINK = re.compile(r"\]\(([^)\s]+)\)")
SCRIPT_REF = re.compile(r"\b(scripts/[\w./-]+\.py)\b")


class ContractError(ValueError):
    pass


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        raise ContractError("missing YAML frontmatter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise ContractError("unterminated frontmatter")
    meta = {}
    for line in text[4:end].splitlines():
        if not line.strip() or line.startswith((" ", "\t")):
            continue
        key, sep, value = line.partition(":")
        if not sep:
            raise ContractError("bad frontmatter line: " + line)
        meta[key.strip()] = value.strip().strip('"').strip("'")
    return meta, text[end + 5:]


def load_lock(path: Path = LOCK) -> dict:
    if not path.is_file():
        return {"schema_version": 1, "kind": "skills-lock", "vendored": []}
    return json.loads(path.read_text(encoding="utf-8"))


def tree_digest(folder: Path) -> str:
    digest = hashlib.sha256()
    # Sort by the POSIX relative path string: Path ordering is case-insensitive on
    # Windows and case-sensitive on Linux, which would give different digests.
    files = sorted((p.relative_to(folder).as_posix(), p) for p in folder.rglob("*") if p.is_file())
    for rel, file in files:
        digest.update(rel.encode() + b"\0")
        digest.update(file.read_bytes().replace(b"\r\n", b"\n") + b"\0")
    return digest.hexdigest()


def check_project_skill(folder: Path, root: Path) -> dict:
    text = (folder / "SKILL.md").read_text(encoding="utf-8")
    meta, body = parse_frontmatter(text)
    name, desc = meta.get("name", ""), meta.get("description", "")
    where = folder.name
    if name != folder.name or not NAME.match(name) or len(name) > 64:
        raise ContractError(where + ": name must equal directory and be kebab-case")
    if not name.startswith("hip-"):
        raise ContractError(where + ": project skills use the hip- prefix")
    if not (40 <= len(desc) <= 1024):
        raise ContractError(where + ": description length must be 40..1024")
    if "Use when" not in desc or "Not for" not in desc:
        raise ContractError(where + ": description needs a 'Use when' trigger and a 'Not for' boundary")
    for section in REQUIRED_SECTIONS:
        if section not in body:
            raise ContractError(where + ": missing section " + section)
    if MODEL_ROLE.search(text):
        raise ContractError(where + ": project skills must not name or assign AI models")
    if SECRET.search(text):
        raise ContractError(where + ": secret-like token")
    work_links = 0
    for target in LINK.findall(body):
        if "://" in target or target.startswith("#"):
            continue
        ref = target.split("#")[0]
        resolved = (folder / ref).resolve()
        if not resolved.exists():
            raise ContractError(where + ": broken link " + target)
        rel = resolved.relative_to(root.resolve()).as_posix() if resolved.is_relative_to(root.resolve()) else ""
        if not rel:
            raise ContractError(where + ": link escapes repository " + target)
        if rel.startswith(".work/archive/"):
            raise ContractError(where + ": archived v6 is not active canon: " + target)
        if rel.startswith(".work/"):
            work_links += 1
    if work_links == 0:
        raise ContractError(where + ": no link to canonical .work documents")
    for script in SCRIPT_REF.findall(body):
        if not (root / script).is_file():
            raise ContractError(where + ": references missing tool " + script)
    return {"name": name, "lines": len(text.splitlines())}


STOP = {"the", "and", "for", "with", "this", "что", "как", "для", "это", "the", "before", "into"}


def stems(text: str) -> set[str]:
    words = re.findall(r"[^\W\d_]{3,}", text.lower())
    return {w[:5] for w in words if w not in STOP}


def route(prompt: str, descriptions: dict[str, str]) -> tuple[str | None, int]:
    wanted = stems(prompt)
    scored = sorted(((len(wanted & stems(d)), n) for n, d in descriptions.items()), reverse=True)
    if not scored or scored[0][0] == 0 or (len(scored) > 1 and scored[0][0] == scored[1][0]):
        return None, scored[0][0] if scored else 0
    return scored[0][1], scored[0][0]


def check_triggers(skills_dir: Path, cases_path: Path) -> int:
    if not cases_path.is_file():
        return 0
    cases = json.loads(cases_path.read_text(encoding="utf-8"))["cases"]
    descriptions = {}
    for folder in skills_dir.iterdir():
        if (folder / "SKILL.md").is_file() and folder.name.startswith("hip-"):
            meta, _ = parse_frontmatter((folder / "SKILL.md").read_text(encoding="utf-8"))
            descriptions[folder.name] = meta.get("description", "")
    for case in cases:
        if case["expect"] not in descriptions:
            raise ContractError("trigger case expects unknown skill " + case["expect"])
        got, score = route(case["prompt"], descriptions)
        if got != case["expect"]:
            raise ContractError("ambiguous trigger: %r -> %s (expected %s, score %d)"
                                % (case["prompt"], got, case["expect"], score))
    covered = {c["expect"] for c in cases}
    if covered != set(descriptions):
        raise ContractError("skills without trigger cases: " + ", ".join(sorted(set(descriptions) - covered)))
    return len(cases)


def validate(skills_dir: Path = SKILLS, root: Path = ROOT, lock: dict | None = None) -> dict:
    lock = load_lock() if lock is None else lock
    if lock.get("schema_version") != 1 or lock.get("kind") != "skills-lock":
        raise ContractError("unexpected skills lock schema")
    vendored = {v["name"]: v for v in lock.get("vendored", [])}
    names, project = set(), []
    for folder in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        if not (folder / "SKILL.md").is_file():
            raise ContractError(folder.name + ": missing SKILL.md (must be upper-case)")
        if folder.name in names:
            raise ContractError("duplicate skill " + folder.name)
        names.add(folder.name)
        if folder.name in vendored:
            entry = vendored[folder.name]
            if not re.fullmatch(r"[0-9a-f]{40}", entry.get("commit", "")):
                raise ContractError(folder.name + ": vendored skill needs a pinned commit SHA")
            if not entry.get("license") or not (folder / entry.get("license_file", "LICENSE")).is_file():
                raise ContractError(folder.name + ": vendored skill needs a license file")
            if tree_digest(folder) != entry.get("tree_sha256"):
                raise ContractError(folder.name + ": vendored content drifted from skills.lock.json")
            continue
        project.append(check_project_skill(folder, root))
    missing = set(vendored) - names
    if missing:
        raise ContractError("locked vendored skills missing on disk: " + ", ".join(sorted(missing)))
    claude_copy = root / ".claude" / "skills"
    if claude_copy.is_dir():
        dup = names & {p.name for p in claude_copy.iterdir() if p.is_dir()}
        if dup:
            raise ContractError(".claude/skills duplicates canonical skills (OpenCode needs unique names): "
                                + ", ".join(sorted(dup)))
    manifest = root / ".agents" / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        raise ContractError("missing Claude Code adapter .agents/.claude-plugin/plugin.json")
    plugin = json.loads(manifest.read_text(encoding="utf-8"))
    if plugin.get("skills") not in (None, "./skills", "./skills/"):
        raise ContractError("Claude adapter must expose .agents/skills, not another directory")
    if len(project) < 8:
        raise ContractError("expected the 8 core hip-* project skills, found %d" % len(project))
    triggers = check_triggers(skills_dir, root / ".work" / "tooling" / "skill_trigger_cases.json")
    return {"skills": len(names), "project": len(project), "vendored": len(vendored),
            "max_lines": max(p["lines"] for p in project), "trigger_cases": triggers}


if __name__ == "__main__":
    try:
        summary = validate()
    except (ContractError, KeyError, ValueError) as exc:
        print("FAIL:", exc, file=sys.stderr)
        raise SystemExit(1)
    print("Agent skills:", json.dumps(summary, sort_keys=True))
    print("PASS: unique triggered skills with canonical .work links, pinned vendored skills, single Claude adapter")
