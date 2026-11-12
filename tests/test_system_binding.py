"""DEV-ENV-004b: system binding map, gap register and schema coverage."""
from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_system_binding", ROOT / "scripts/system_binding.py")
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)


class SystemBindingTests(unittest.TestCase):
    def setUp(self):
        self.data = binding.load()

    def mutate(self):
        return copy.deepcopy(self.data)

    def system(self, data, sid):
        return next(s for s in data["systems"] if s["id"] == sid)

    def test_repository_binding_is_valid_and_view_is_fresh(self):
        self.assertEqual(binding.main(["validate"]), 0)
        summary = binding.validate(self.data)
        self.assertGreaterEqual(summary["systems"], 17)
        self.assertEqual(summary["interfaces"], 12)

    def test_missing_required_system_fails(self):
        data = self.mutate()
        data["systems"] = [s for s in data["systems"] if s["id"] != "boss"]
        with self.assertRaisesRegex(binding.ContractError, "boss"):
            binding.validate(data)

    def test_broken_canonical_path_fails(self):
        data = self.mutate()
        self.system(data, "combat")["canonical"].append(".work/spec/v7/does-not-exist.md")
        with self.assertRaisesRegex(binding.ContractError, "does not exist"):
            binding.validate(data)

    def test_unknown_skill_fails(self):
        data = self.mutate()
        self.system(data, "save")["skill"] = "hip-nonexistent"
        with self.assertRaisesRegex(binding.ContractError, "unknown skill"):
            binding.validate(data)

    def test_roadmap_slice_must_exist(self):
        data = self.mutate()
        self.system(data, "xp")["roadmap"] = "GAME-ARCH-99"
        with self.assertRaisesRegex(binding.ContractError, "NEXT_SLICES"):
            binding.validate(data)

    def test_unbound_interface_fails(self):
        data = self.mutate()
        for s in data["systems"]:
            s["interfaces"] = [i for i in s["interfaces"] if i != "IC-12"] or ["IC-01"]
        with self.assertRaisesRegex(binding.ContractError, "IC-12"):
            binding.validate(data)

    def test_gap_without_owner_fails(self):
        data = self.mutate()
        data["gaps"][0]["owner"] = ""
        with self.assertRaisesRegex(binding.ContractError, "owner"):
            binding.validate(data)

    def test_undefined_gap_reference_fails(self):
        data = self.mutate()
        self.system(data, "stage")["gaps"].append("GAP-UNKNOWN")
        with self.assertRaisesRegex(binding.ContractError, "undefined gap"):
            binding.validate(data)

    def test_new_config_file_without_coverage_fails(self):
        data = self.mutate()
        data["schema_coverage"] = data["schema_coverage"][1:]
        with self.assertRaisesRegex(binding.ContractError, "schema coverage differs"):
            binding.validate(data)

    def test_declared_validator_must_mention_file(self):
        data = self.mutate()
        entry = next(c for c in data["schema_coverage"] if c["file"].endswith("bosses.json"))
        entry["validators"] = ["scripts/validate_toolchain.py"]
        with self.assertRaisesRegex(binding.ContractError, "does not mention"):
            binding.validate(data)

    def test_uncovered_file_needs_open_gap(self):
        data = self.mutate()
        gap = next(g for g in data["gaps"] if g["id"] == "GAP-SCHEMA-COVERAGE")
        gap["status"] = "CLOSED"
        with self.assertRaisesRegex(binding.ContractError, "no validator and no open gap"):
            binding.validate(data)

    def test_render_lists_every_system_and_gap(self):
        text = binding.render(self.data)
        for s in self.data["systems"]:
            self.assertIn(s["name"], text)
        for g in self.data["gaps"]:
            self.assertIn(g["id"], text)


if __name__ == "__main__":
    unittest.main()
