"""ART-REF-001: reference catalog classification, provenance and README parity."""
from __future__ import annotations

import copy
import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_ref_catalog", ROOT / "scripts/ref_catalog.py")
refcat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refcat)


def tiny_png(width: int, height: int) -> bytes:
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = b"".join(b"\x00" + b"\x00\x00\x00\x00" * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class RefCatalogTests(unittest.TestCase):
    def setUp(self):
        self.cat = refcat.load()
        self.empty = Path(tempfile.mkdtemp())

    def check(self, catalog, ref_dir=None):
        return refcat.validate(catalog, ref_dir or self.empty, readme=refcat.render(catalog))

    def test_repository_catalog_is_valid(self):
        summary = refcat.validate(self.cat)
        self.assertEqual(summary["entries"], 63)
        self.assertEqual(summary["duplicates"], 2)
        self.assertEqual(summary["categories"], len(refcat.CATEGORIES))

    def test_every_canonical_class_has_a_visual_reference(self):
        linked = {c for e in self.cat["entries"] for c in e["content_ids"]}
        for cid in ("class.sword", "class.thunder", "class.talisman", "class.body"):
            self.assertIn(cid, linked)

    def test_unknown_content_id_fails(self):
        bad = copy.deepcopy(self.cat)
        bad["entries"][0]["content_ids"] = ["stage.sect_ruins"]
        with self.assertRaisesRegex(refcat.ContractError, "unknown content id"):
            self.check(bad)

    def test_reference_cannot_be_marked_production_ready(self):
        bad = copy.deepcopy(self.cat)
        bad["entries"][3]["production_ready"] = True
        with self.assertRaisesRegex(refcat.ContractError, "never production"):
            self.check(bad)

    def test_prototype_candidate_requires_alpha(self):
        bad = copy.deepcopy(self.cat)
        entry = next(e for e in bad["entries"] if e["category"] == "environment")
        entry["readiness"] = "R1-prototype-candidate"
        with self.assertRaisesRegex(refcat.ContractError, "transparent"):
            self.check(bad)

    def test_undeclared_duplicate_fails(self):
        bad = copy.deepcopy(self.cat)
        dup = next(e for e in bad["entries"] if e.get("duplicate_of"))
        del dup["duplicate_of"]
        with self.assertRaisesRegex(refcat.ContractError, "undeclared duplicate"):
            self.check(bad)

    def test_entry_without_system_link_fails(self):
        bad = copy.deepcopy(self.cat)
        bad["entries"][5]["systems"] = []
        with self.assertRaisesRegex(refcat.ContractError, "no linked game system"):
            self.check(bad)

    def test_stale_readme_fails(self):
        with self.assertRaisesRegex(refcat.ContractError, "stale"):
            refcat.validate(self.cat, self.empty, readme="# old\n")

    def test_unlisted_binary_and_hash_drift_fail(self):
        cat = {"schema_version": 1, "kind": "reference-catalog", "entries": [], "findings": [], "usage_rules": []}
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "new.png").write_bytes(tiny_png(4, 3))
            with self.assertRaisesRegex(refcat.ContractError, "catalog differ"):
                self.check(cat, Path(tmp))
            cat["entries"].append({"id": "REF-900", "file": "new.png", "category": "ui-kit", "summary": "x",
                                   "width": 4, "height": 3, "has_alpha": True, "sha256": "0" * 64,
                                   "content_ids": [], "systems": ["UX/HUD"], "readiness": "R0-reference"})
            with self.assertRaisesRegex(refcat.ContractError, "sha256 mismatch"):
                self.check(cat, Path(tmp))

    def test_png_header_size_parser(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            path.write_bytes(tiny_png(7, 5))
            self.assertEqual(refcat.image_size(path), (7, 5))


if __name__ == "__main__":
    unittest.main()
