"""DEV-ENV-002b: offline checks of the pinned skill vendoring script (network is stubbed)."""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_vendor_skills", ROOT / "scripts/dev/vendor_skills.py")
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)

COMMIT = "b" * 40


class VendorSkillsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.upstream = self.tmp / "upstream" / ("repo-" + COMMIT)
        skill = self.upstream / "skills" / "demo-skill"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: demo-skill\ndescription: demo\n---\nbody\n", encoding="utf-8")
        (self.upstream / "LICENSE").write_text("Apache-2.0 text", encoding="utf-8")
        self.lock_path = self.tmp / "skills.lock.json"
        self.dest = self.tmp / "skills"
        self.dest.mkdir()
        self.lock_path.write_text(json.dumps({
            "schema_version": 1, "kind": "skills-lock", "vendored": [],
            "vendor_sources": [{"repo": "org/repo", "commit": COMMIT, "license": "Apache-2.0",
                                "license_files": ["LICENSE"], "skills": ["skills/demo-skill"]}]}), encoding="utf-8")
        self.saved = (vendor.LOCK, vendor.DEST, vendor.fetch)
        vendor.LOCK, vendor.DEST = self.lock_path, self.dest
        vendor.fetch = lambda repo, commit, into: self.upstream

    def tearDown(self):
        vendor.LOCK, vendor.DEST, vendor.fetch = self.saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_sync(self, *flags):
        with redirect_stdout(StringIO()) as out:
            code = vendor.main(["sync", *flags])
        return code, out.getvalue()

    def test_sync_installs_skill_with_license_and_digest(self):
        self.assertEqual(self.run_sync()[0], 0)
        self.assertTrue((self.dest / "demo-skill" / "LICENSE").is_file())
        entry = json.loads(self.lock_path.read_text(encoding="utf-8"))["vendored"][0]
        self.assertEqual(entry["commit"], COMMIT)
        self.assertEqual(entry["tree_sha256"], vendor.tree_digest(self.dest / "demo-skill"))

    def test_check_detects_local_drift_without_writing(self):
        self.run_sync()
        (self.dest / "demo-skill" / "SKILL.md").write_text("tampered", encoding="utf-8")
        before = self.lock_path.read_text(encoding="utf-8")
        code, out = self.run_sync("--check")
        self.assertEqual(code, 1)
        self.assertIn("DIFF demo-skill", out)
        self.assertEqual(before, self.lock_path.read_text(encoding="utf-8"))

    def test_upstream_change_requires_explicit_update_lock(self):
        self.run_sync()
        (self.upstream / "skills" / "demo-skill" / "SKILL.md").write_text("new upstream", encoding="utf-8")
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertIn("differs from lock", out)
        self.assertEqual(self.run_sync("--update-lock")[0], 0)
        self.assertEqual(self.run_sync("--check")[0], 0)

    def test_unpinned_ref_is_refused(self):
        vendor.fetch = self.saved[2]
        with self.assertRaises(SystemExit):
            vendor.fetch("org/repo", "main", self.tmp)


if __name__ == "__main__":
    unittest.main()
