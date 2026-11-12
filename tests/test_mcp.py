"""DEV-ENV-003: MCP registry and example client configs."""
from __future__ import annotations

import copy
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_validate_mcp", ROOT / "scripts/validate_mcp.py")
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


class McpRegistryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        shutil.copytree(ROOT / ".work" / "tooling", self.tmp / ".work" / "tooling")
        self.lock = mcp.load()
        self.examples = self.tmp / ".work" / "tooling" / "mcp"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def server(self, lock, sid):
        return next(s for s in lock["servers"] if s["id"] == sid)

    def check(self, lock=None):
        return mcp.validate(self.lock if lock is None else lock, self.tmp)

    def test_repository_registry_is_valid(self):
        summary = mcp.validate()
        self.assertEqual(summary["enabled"], ["context7", "github"])
        self.assertEqual(summary["examples"], 3)

    def test_floating_version_fails(self):
        lock = copy.deepcopy(self.lock)
        self.server(lock, "context7")["version"] = "latest"
        with self.assertRaisesRegex(mcp.ContractError, "pinned|floating"):
            self.check(lock)

    def test_godot_mcp_cannot_be_enabled_before_runtime(self):
        lock = copy.deepcopy(self.lock)
        self.server(lock, "godot-ai")["default_enabled"] = True
        with self.assertRaisesRegex(mcp.ContractError, "phase 'now'"):
            self.check(lock)

    def test_write_capable_server_cannot_be_default(self):
        lock = copy.deepcopy(self.lock)
        entry = self.server(lock, "godot-ai")
        entry["phase"], entry["default_enabled"] = "now", True
        with self.assertRaisesRegex(mcp.ContractError, "write-capable"):
            self.check(lock)

    def test_blocked_without_owner_fails(self):
        lock = copy.deepcopy(self.lock)
        self.server(lock, "github")["verification"] = {"status": "BLOCKED", "evidence": "x"}
        with self.assertRaisesRegex(mcp.ContractError, "owner"):
            self.check(lock)

    def test_secret_literal_in_example_fails(self):
        path = self.examples / "claude.mcp.example.json"
        path.write_text(path.read_text(encoding="utf-8").replace("${GITHUB_MCP_PAT}", "ghp_" + "x" * 36),
                        encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "secret"):
            self.check()

    def test_literal_authorization_without_env_fails(self):
        path = self.examples / "opencode.example.json"
        path.write_text(path.read_text(encoding="utf-8").replace("{env:GITHUB_MCP_PAT}", "PLACEHOLDER"),
                        encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "environment variable"):
            self.check()

    def test_unpinned_npx_in_example_fails(self):
        path = self.examples / "codex.config.example.toml"
        path.write_text(path.read_text(encoding="utf-8").replace("@4.6.0", ""), encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "pinned"):
            self.check()

    def test_write_capable_github_url_fails(self):
        path = self.examples / "claude.mcp.example.json"
        path.write_text(path.read_text(encoding="utf-8").replace("/mcp/readonly", "/mcp/"), encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "url must be"):
            self.check()

    def test_enabled_godot_server_in_example_fails(self):
        path = self.examples / "opencode.example.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["mcp"]["godot-ai"] = {"type": "local", "command": ["uvx", "godot-ai==4.4.1"], "enabled": True}
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "gated"):
            self.check()
        data["mcp"]["godot-ai"]["enabled"] = False
        path.write_text(json.dumps(data), encoding="utf-8")
        self.assertEqual(self.check()["examples"], 3)

    def test_unknown_server_in_example_fails(self):
        path = self.examples / "claude.mcp.example.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["mcpServers"]["random"] = {"command": "npx", "args": ["random-mcp"]}
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "not in mcp.lock.json"):
            self.check()

    def test_live_config_with_enabled_godot_fails(self):
        (self.tmp / "opencode.json").write_text(json.dumps(
            {"mcp": {"godot-ai": {"type": "local", "command": ["uvx", "godot-ai"]}}}), encoding="utf-8")
        with self.assertRaisesRegex(mcp.ContractError, "disabled"):
            self.check()


if __name__ == "__main__":
    unittest.main()
