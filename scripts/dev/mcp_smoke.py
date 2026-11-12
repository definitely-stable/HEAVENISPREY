#!/usr/bin/env python3
"""DEV-ENV-003: live MCP handshake smoke for servers in .work/tooling/mcp.lock.json.

Runs the server exactly as the example config pins it, performs `initialize` and
`tools/list`, and prints the tool names. Needs network; not part of the offline CI.

  python scripts/dev/mcp_smoke.py context7     # stdio via npx @upstash/context7-mcp@<locked>
  python scripts/dev/mcp_smoke.py github       # remote read-only, token from GITHUB_MCP_PAT

The token is only read from the environment and never printed.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / ".work" / "tooling" / "mcp.lock.json"
INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "hip-mcp-smoke", "version": "1"}}}
LIST = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
INITIALIZED = {"jsonrpc": "2.0", "method": "notifications/initialized"}


def server(sid: str) -> dict:
    for entry in json.loads(LOCK.read_text(encoding="utf-8"))["servers"]:
        if entry["id"] == sid:
            return entry
    raise SystemExit("unknown server " + sid)


def stdio_smoke(entry: dict) -> list[str]:
    pkg = entry["package"].split(":", 1)[1] + "@" + entry["version"]
    npx = shutil.which("npx") or shutil.which("npx.cmd")
    if not npx:
        raise SystemExit("BLOCKED: npx not found (install Node.js LTS)")
    proc = subprocess.Popen([npx, "-y", pkg], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8")
    try:
        replies = {}
        for msg in (INIT, INITIALIZED, LIST):
            proc.stdin.write(json.dumps(msg) + "\n")
            proc.stdin.flush()
            if "id" not in msg:
                continue
            while msg["id"] not in replies:
                line = proc.stdout.readline()
                if not line:
                    raise SystemExit("FAIL: server closed stdout")
                data = json.loads(line)
                if "id" in data:
                    replies[data["id"]] = data
        return [t["name"] for t in replies[2]["result"]["tools"]]
    finally:
        proc.kill()


def post(url: str, body: dict, headers: dict) -> tuple[dict, dict]:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
        info = dict(resp.headers)
    if raw.lstrip().startswith("{"):
        return json.loads(raw), info
    for line in raw.splitlines():  # text/event-stream
        if line.startswith("data:"):
            return json.loads(line[5:]), info
    return {}, info


def http_smoke(entry: dict) -> list[str]:
    var = entry["secrets_env"][0]
    token = os.environ.get(var)
    if not token:
        raise SystemExit("BLOCKED: set %s (%s)" % (var, entry.get("token_scope", "token")))
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "X-MCP-Toolsets": ",".join(entry.get("toolsets", []))}
    try:
        _, info = post(entry["url"], INIT, headers)
        session = {k: v for k, v in info.items() if k.lower() == "mcp-session-id"}
        headers.update(session)
        post(entry["url"], INITIALIZED, headers)
        reply, _ = post(entry["url"], LIST, headers)
    except urllib.error.HTTPError as exc:
        raise SystemExit("FAIL: HTTP %d from %s" % (exc.code, entry["url"]))
    return [t["name"] for t in reply["result"]["tools"]]


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 2
    entry = server(argv[0])
    tools = http_smoke(entry) if entry["transport"] == "http" else stdio_smoke(entry)
    if not tools:
        print("FAIL: no tools listed")
        return 1
    writes = [t for t in tools if t.startswith(("create_", "update_", "delete_", "merge_", "push_"))]
    if entry["access"] == "read-only" and writes:
        print("FAIL: read-only server exposes write tools:", ", ".join(writes))
        return 1
    print("PASS %s %s: %d tools: %s" % (entry["id"], entry["version"], len(tools), ", ".join(sorted(tools))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
