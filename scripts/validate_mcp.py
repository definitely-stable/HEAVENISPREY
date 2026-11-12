#!/usr/bin/env python3
"""DEV-ENV-003: static validation of the MCP registry and example client configs.

Machine source: .work/tooling/mcp.lock.json. Example configs live in
.work/tooling/mcp/ and are copied by the developer into the client location;
the repository never stores a live config with secrets.

Checks (stdlib only, no network):
- lock schema, unique ids, known priority/phase, exact pinned versions;
- only phase "now" servers may be enabled by default; write-capable or
  code-executing servers stay disabled with an explicit enable gate;
- verification status is one of VERIFIED / BLOCKED / NOT RUN, BLOCKED has an owner;
- every example config parses, mentions only default-enabled servers from the lock,
  pins npx packages to the locked version, uses the locked (read-only) URL, takes
  tokens from environment variables and contains no secret-like literal;
- optional live client files (.mcp.json, .codex/config.toml, opencode.json), if
  present, contain no secret-like literal and no enabled Godot server before P0-00.
"""
from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / ".work" / "tooling" / "mcp.lock.json"
PRIORITIES = {"P0", "P1", "P2", "REJECT"}
PHASES = {"now", "P0-00", "later", "never"}
STATUSES = {"VERIFIED", "BLOCKED", "NOT RUN"}
EXACT = re.compile(r"^v?\d+\.\d+\.\d+$")
SECRET = re.compile(r"(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}"
                    r"|sk-[A-Za-z0-9]{20,}|ctx7sk[-_][A-Za-z0-9-]{8,}|AKIA[0-9A-Z]{16})")
ENV_REF = re.compile(r"(\$\{[A-Z0-9_]+\}|\{env:[A-Z0-9_]+\})")
LIVE_FILES = (".mcp.json", ".codex/config.toml", "opencode.json")


class ContractError(ValueError):
    pass


def load(path: Path = LOCK) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def check_lock(lock: dict) -> dict:
    if lock.get("schema_version") != 1 or lock.get("kind") != "mcp-lock":
        raise ContractError("unexpected mcp lock schema")
    servers, seen = {}, set()
    for s in lock.get("servers", []):
        sid = s.get("id", "")
        if not sid or sid in seen:
            raise ContractError("missing or duplicate server id " + repr(sid))
        seen.add(sid)
        if s.get("priority") not in PRIORITIES or s.get("phase") not in PHASES:
            raise ContractError(sid + ": unknown priority or phase")
        version, package = s.get("version", ""), s.get("package", "")
        if package.startswith(("npm:", "pypi:")) and not EXACT.match(version):
            raise ContractError(sid + ": package must be pinned to an exact version, got " + repr(version))
        if package == "remote" and not EXACT.match(version):
            raise ContractError(sid + ": remote server needs the audited release tag")
        if version in ("", "latest") or "^" in version or "~" in version:
            raise ContractError(sid + ": floating version")
        enabled = s.get("default_enabled")
        if not isinstance(enabled, bool):
            raise ContractError(sid + ": default_enabled must be boolean")
        if enabled and s["phase"] != "now":
            raise ContractError(sid + ": only phase 'now' servers may be enabled by default")
        if s.get("access") not in ("read-only", "read-only-default") and enabled:
            raise ContractError(sid + ": write-capable server cannot be enabled by default")
        if not enabled and not s.get("enable_gate"):
            raise ContractError(sid + ": disabled server needs an enable_gate")
        if s.get("secret_required") and not s.get("secrets_env"):
            raise ContractError(sid + ": secret_required needs secrets_env variable names")
        status = s.get("verification", {}).get("status")
        if status not in STATUSES:
            raise ContractError(sid + ": verification status must be one of " + ", ".join(sorted(STATUSES)))
        if status == "BLOCKED" and not s["verification"].get("owner"):
            raise ContractError(sid + ": BLOCKED verification needs an owner")
        if SECRET.search(json.dumps(s)):
            raise ContractError(sid + ": secret-like literal in lock")
        servers[sid] = s
    if not any(s["priority"] == "P0" and s["default_enabled"] for s in servers.values()):
        raise ContractError("no enabled P0 server")
    return servers


def example_servers(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if SECRET.search(text):
        raise ContractError(path.name + ": secret-like literal")
    if path.suffix == ".toml":
        return tomllib.loads(text).get("mcp_servers", {})
    data = json.loads(text)
    return data.get("mcpServers", data.get("mcp", {}))


def is_enabled(cfg: dict) -> bool:
    if "enabled" in cfg:
        return bool(cfg["enabled"])
    return cfg.get("disabled") is not True


def check_server_entry(where: str, sid: str, cfg: dict, lock_entry: dict | None) -> None:
    if lock_entry is None:
        raise ContractError(where + ": server %r is not in mcp.lock.json" % sid)
    if not lock_entry["default_enabled"]:
        if is_enabled(cfg):
            raise ContractError(where + ": %r is gated (%s) and must not be enabled"
                                % (sid, lock_entry.get("enable_gate")))
        return
    command = cfg.get("command")
    argv = ([command] if isinstance(command, str) else list(command or [])) + list(cfg.get("args", []))
    if argv and argv[0] in ("npx", "npx.cmd"):
        pkg = lock_entry["package"].split(":", 1)[1]
        wanted = "%s@%s" % (pkg, lock_entry["version"])
        if wanted not in argv:
            raise ContractError(where + ": %r must run %s (pinned), got %s" % (sid, wanted, argv))
    url = cfg.get("url")
    if url and lock_entry.get("url") and url != lock_entry["url"]:
        raise ContractError(where + ": %r url must be %s" % (sid, lock_entry["url"]))
    headers = cfg.get("headers") or {}
    auth = headers.get("Authorization")
    if auth is not None and not ENV_REF.search(auth):
        raise ContractError(where + ": %r Authorization must reference an environment variable" % sid)
    if lock_entry.get("secret_required") and url and auth is None and "bearer_token_env_var" not in cfg:
        raise ContractError(where + ": %r needs a token from %s" % (sid, lock_entry["secrets_env"]))


def check_examples(servers: dict, lock: dict, root: Path) -> int:
    count = 0
    for client, info in sorted(lock.get("clients", {}).items()):
        path = root / info["example"]
        if not path.is_file():
            raise ContractError("missing example config for " + client + ": " + info["example"])
        entries = example_servers(path)
        if not entries:
            raise ContractError(path.name + ": no servers")
        for sid, cfg in entries.items():
            check_server_entry(path.name, sid, cfg, servers.get(sid))
        missing = {sid for sid, s in servers.items() if s["default_enabled"]} - set(entries)
        if missing:
            raise ContractError(path.name + ": missing default servers " + ", ".join(sorted(missing)))
        count += 1
    return count


def check_live_files(servers: dict, root: Path) -> int:
    found = 0
    for rel in LIVE_FILES:
        path = root / rel
        if not path.is_file():
            continue
        found += 1
        for sid, cfg in example_servers(path).items():
            entry = servers.get(sid)
            if entry and not entry["default_enabled"] and is_enabled(cfg):
                raise ContractError(rel + ": %r must stay disabled until %s" % (sid, entry.get("enable_gate")))
    return found


def validate(lock: dict | None = None, root: Path = ROOT) -> dict:
    lock = load() if lock is None else lock
    servers = check_lock(lock)
    examples = check_examples(servers, lock, root)
    live = check_live_files(servers, root)
    return {"servers": len(servers), "enabled": sorted(s for s in servers if servers[s]["default_enabled"]),
            "examples": examples, "live_configs": live,
            "blocked": sorted(s for s in servers if servers[s]["verification"]["status"] == "BLOCKED")}


if __name__ == "__main__":
    try:
        summary = validate()
    except (ContractError, KeyError, ValueError, tomllib.TOMLDecodeError) as exc:
        print("FAIL:", exc, file=sys.stderr)
        raise SystemExit(1)
    print("MCP registry:", json.dumps(summary, sort_keys=True))
    print("PASS: pinned servers, gated Godot MCP, secret-free example configs")
