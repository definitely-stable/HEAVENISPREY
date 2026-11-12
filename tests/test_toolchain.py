"""DEV-ENV-001: pinned toolchain lock, Godot installer safety and doctor.

Network-free. The real download/smoke runs in .github/workflows/toolchain-smoke.yml.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


lockcheck = module("hip_validate_toolchain", ROOT / "scripts/validate_toolchain.py")
godot_tool = module("hip_godot_tool_test", ROOT / "scripts/dev/godot_tool.py")
doctor = module("hip_doctor_test", ROOT / "scripts/dev/doctor.py")


def godot(lock):
    return next(t for t in lock["tools"] if t["id"] == "tool.godot")


class ToolchainLockTests(unittest.TestCase):
    def setUp(self):
        self.lock = lockcheck.load()

    def test_repository_lock_is_valid_and_pins_adr001_engine(self):
        summary = lockcheck.validate(self.lock)
        self.assertEqual(summary["godot"], "4.7.2-stable")
        self.assertGreaterEqual(summary["godot_ci_jobs"], 1)

    def test_floating_latest_pin_fails(self):
        bad = copy.deepcopy(self.lock)
        bad["tools"][0]["version"] = "latest"
        with self.assertRaisesRegex(lockcheck.ContractError, "floating"):
            lockcheck.validate(bad)

    def test_engine_upgrade_outside_adr001_fails(self):
        bad = copy.deepcopy(self.lock)
        godot(bad)["version"] = "4.8.0-beta3"
        with self.assertRaisesRegex(lockcheck.ContractError, "4.7.x stable"):
            lockcheck.validate(bad)

    def test_unofficial_download_host_fails(self):
        bad = copy.deepcopy(self.lock)
        godot(bad)["assets"]["linux-x86_64"]["url"] = "https://example.com/Godot_v4.7.2-stable_linux.x86_64.zip"
        with self.assertRaisesRegex(lockcheck.ContractError, "official"):
            lockcheck.validate(bad)

    def test_missing_checksum_fails(self):
        bad = copy.deepcopy(self.lock)
        godot(bad)["assets"]["windows-x86_64"]["sha512"] = "abc"
        with self.assertRaisesRegex(lockcheck.ContractError, "SHA-512"):
            lockcheck.validate(bad)

    def test_missing_dependency_budget_field_fails(self):
        bad = copy.deepcopy(self.lock)
        del bad["tools"][1]["removal_plan"]
        with self.assertRaisesRegex(lockcheck.ContractError, "removal_plan"):
            lockcheck.validate(bad)

    def test_duplicate_tool_id_fails(self):
        bad = copy.deepcopy(self.lock)
        bad["tools"].append(copy.deepcopy(bad["tools"][0]))
        with self.assertRaisesRegex(lockcheck.ContractError, "duplicate"):
            lockcheck.validate(bad)

    def test_runtime_dependency_claim_fails(self):
        bad = copy.deepcopy(self.lock)
        bad["tools"][0]["kind"] = "game-runtime"
        with self.assertRaisesRegex(lockcheck.ContractError, "runtime"):
            lockcheck.validate(bad)

    def test_workflow_with_second_hardcoded_godot_pin_fails(self):
        flows = {"x.yml": "run: curl -L https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip"}
        with self.assertRaisesRegex(lockcheck.ContractError, "hard-coded"):
            lockcheck.validate(self.lock, flows)

    def test_workflow_cache_not_keyed_by_lock_fails(self):
        flows = {"x.yml": "run: python scripts/dev/godot_tool.py install\nkey: godot-${{ runner.os }}"}
        with self.assertRaisesRegex(lockcheck.ContractError, "cache key"):
            lockcheck.validate(self.lock, flows)

    def test_floating_action_ref_fails(self):
        flows = {"x.yml": "      - uses: actions/checkout@main"}
        with self.assertRaisesRegex(lockcheck.ContractError, "floating action"):
            lockcheck.validate(self.lock, flows)


class GodotInstallerSafetyTests(unittest.TestCase):
    def test_zip_slip_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "evil.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                zf.writestr("../escape.txt", "x")
            with self.assertRaisesRegex(godot_tool.ToolError, "escapes"):
                godot_tool.safe_extract(archive, Path(tmp) / "out")
            self.assertFalse((Path(tmp) / "escape.txt").exists())

    def test_sha512_helper_matches_hashlib(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "blob"
            path.write_bytes(b"heaven-is-prey" * 1000)
            self.assertEqual(godot_tool.sha512_file(path), hashlib.sha512(path.read_bytes()).hexdigest())

    def test_install_refuses_non_official_url_before_network(self):
        spec = copy.deepcopy(godot_tool.load_spec())
        key = godot_tool.platform_key()
        spec["assets"][key]["url"] = "https://example.com/" + spec["assets"][key]["file"]
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(godot_tool.ToolError, "non-official"):
                godot_tool.install(spec, Path(tmp))

    def test_install_dir_is_versioned_and_outside_tracked_tree(self):
        spec = godot_tool.load_spec()
        path = godot_tool.install_dir(spec, godot_tool.tools_root(None))
        self.assertIn(spec["version"], str(path))
        self.assertIn(".tools/", (ROOT / ".gitignore").read_text(encoding="utf-8"))

    def test_smoke_script_is_typed_gdscript(self):
        self.assertIn("Array[int]", godot_tool.SMOKE_SCRIPT)
        self.assertIn("-> void", godot_tool.SMOKE_SCRIPT)


class DoctorTests(unittest.TestCase):
    def test_version_tuple_parses_tool_banners(self):
        self.assertEqual(doctor.version_tuple("git version 2.56.0.windows.4"), (2, 56, 0))
        self.assertEqual(doctor.version_tuple("4.7.2.stable.official.ed1daf0bf"), (4, 7, 2))

    def test_doctor_passes_required_tools_in_this_environment(self):
        lock = lockcheck.load()
        rows = {r["id"]: r for r in doctor.check_tools(lock)}
        self.assertEqual(rows["tool.python"]["status"], "OK")
        for row in rows.values():
            if not row["required"]:
                self.assertIn(row["status"], {"OK", "MISSING", "DEFERRED", "TOO_OLD", "WRONG_VERSION"})


if __name__ == "__main__":
    unittest.main()
