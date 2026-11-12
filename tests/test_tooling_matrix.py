"""DEV-ENV-005: the tooling matrix is generated from the locks and kept in parity."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_tooling_matrix", ROOT / "scripts/tooling_matrix.py")
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class ToolingMatrixTests(unittest.TestCase):
    def test_view_matches_locks(self):
        self.assertEqual(matrix.main(["validate"]), 0)

    def test_every_locked_item_is_rendered(self):
        text = matrix.render()
        for name in ("toolchain.lock.json", "skills.lock.json", "mcp.lock.json"):
            data = matrix.load(name)
            items = data.get("tools") or data.get("vendored") or data.get("servers")
            for item in items:
                self.assertIn(item.get("id") or item.get("name"), text)

    def test_stale_view_is_detected(self):
        original = matrix.VIEW
        try:
            matrix.VIEW = ROOT / "does-not-exist.md"
            self.assertEqual(matrix.main(["validate"]), 1)
        finally:
            matrix.VIEW = original


if __name__ == "__main__":
    unittest.main()
