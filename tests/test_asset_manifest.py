"""ART-01: game asset manifest, LFS identity, provenance and style thresholds (ADR-013)."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import shutil
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_validate_assets", ROOT / "scripts/validate_assets.py")
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)

HERO = "asset.char.hero_sword"


def tiny_png(width: int, height: int, colour: int = 6) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
            + chunk(b"IEND", b""))


def pointer(sha: str, size: int) -> bytes:
    return f"version https://git-lfs.github.com/spec/v1\noid sha256:{sha}\nsize {size}\n".encode("ascii")


class AssetManifestTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        shutil.copytree(ROOT / "game" / "assets", self.root / "game" / "assets",
                        ignore=shutil.ignore_patterns("*.import"))
        shutil.copytree(ROOT / "art_source", self.root / "art_source")
        (self.root / "ref").mkdir()
        shutil.copyfile(ROOT / "ref" / "catalog.json", self.root / "ref" / "catalog.json")
        config = self.root / ".work" / "config" / "v7"
        config.mkdir(parents=True)
        for name in ("classes.json", "enemies.json", "stages.json"):
            shutil.copyfile(ROOT / ".work" / "config" / "v7" / name, config / name)
        self.saved = {k: getattr(assets, k) for k in ("ROOT", "ASSETS", "MANIFEST", "SOURCE", "PASSPORT",
                                                      "CATALOG", "CONFIG")}
        assets.ROOT = self.root
        assets.ASSETS = self.root / "game" / "assets"
        assets.MANIFEST = assets.ASSETS / "manifest.json"
        assets.SOURCE = self.root / "art_source"
        assets.PASSPORT = assets.SOURCE / "style_passport.json"
        assets.CATALOG = self.root / "ref" / "catalog.json"
        assets.CONFIG = config
        self.manifest = json.loads(assets.MANIFEST.read_text(encoding="utf-8"))

    def tearDown(self):
        for key, value in self.saved.items():
            setattr(assets, key, value)

    def entry(self, asset_id: str = HERO) -> dict:
        return next(e for e in self.manifest["assets"] if e["asset_id"] == asset_id)

    def write(self):
        assets.MANIFEST.write_text(json.dumps(self.manifest), encoding="utf-8")

    def fails(self, fragment: str):
        self.write()
        with self.assertRaises(assets.AssetError) as caught:
            assets.validate()
        self.assertIn(fragment, str(caught.exception))

    def test_repository_manifest_is_valid(self):
        report = assets.validate()
        self.assertEqual(report["assets"], 4)
        self.assertLessEqual(report["lfs_bytes"], assets.LFS_BUDGET_BYTES)

    def test_lfs_pointer_with_the_same_identity_passes(self):
        for entry in self.manifest["assets"]:
            (self.root / entry["path"]).write_bytes(pointer(entry["sha256"], entry["bytes"]))
            source = entry["source"]
            (self.root / source["path"]).write_bytes(pointer(source["sha256"], source["bytes"]))
        self.assertEqual(assets.validate()["real_files_checked"], 0)

    def test_lfs_pointer_with_another_oid_fails(self):
        entry = self.entry()
        (self.root / entry["path"]).write_bytes(pointer("0" * 64, entry["bytes"]))
        self.fails("LFS pointer oid/size")

    def test_changed_file_fails(self):
        path = self.root / self.entry()["path"]
        path.write_bytes(path.read_bytes() + b"x")
        self.fails("sha256/bytes differ")

    def atlas(self, data: bytes) -> None:
        entry = self.entry()
        (self.root / entry["path"]).write_bytes(data)
        entry.update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))

    def test_atlas_must_be_frames_by_directions(self):
        self.atlas(tiny_png(768, 576))
        self.entry()["size"] = [768, 576]
        self.fails("frames x directions")

    def test_atlas_must_be_rgba(self):
        self.atlas(tiny_png(768, 768, colour=2))
        self.fails("RGBA")

    def test_png_size_must_equal_the_manifest(self):
        self.atlas(tiny_png(768, 768))
        self.entry()["size"] = [768, 384]
        self.fails("PNG size differs")

    def test_feet_anchor_keeps_the_margin(self):
        self.entry()["layout"]["feet_anchor"] = [96, 191]
        self.fails("transparent margin")

    def test_prompt_must_hash_to_the_recorded_value(self):
        prompt = self.root / "art_source" / "hero_sword" / "prompt.txt"
        prompt.write_text(prompt.read_text(encoding="utf-8") + "more\n", encoding="utf-8")
        self.fails("prompt_sha256")

    def test_reference_must_be_in_the_catalog(self):
        source = self.root / "art_source" / "hero_sword" / "source.json"
        data = json.loads(source.read_text(encoding="utf-8"))
        data["references"][0]["sha256"] = "1" * 64
        source.write_text(json.dumps(data), encoding="utf-8")
        self.fails("ref/catalog.json")

    def test_unknown_content_id_fails(self):
        self.entry()["content_ids"] = ["class.unknown"]
        self.fails("unknown content id")

    def test_hero_has_no_threat_colour(self):
        self.entry()["qa"]["threat_colour_pct"] = 0.5
        self.fails("threat colour")

    def test_hero_must_use_the_hero_passport(self):
        self.entry()["qa"]["palette_group"] = "characters"
        self.fails("hero_sprite")

    def test_palette_threshold(self):
        self.entry("asset.enemy.yin_corpse")["qa"]["palette_mean_delta_e"] = 15.5
        self.fails("palette ΔE")

    def test_floor_stays_muted(self):
        floor = self.entry("asset.tile.jade_grove_floor")
        floor["qa"]["chroma"] = 0.2
        self.fails("chroma")
        floor["qa"]["chroma"] = 0.02
        floor["qa"]["tones_pct"] = [80.0, 14.0, 6.0]
        self.fails("lights")

    def test_hero_is_lighter_than_the_world(self):
        self.entry()["qa"]["tones_pct"] = [70.0, 20.0, 10.0]
        self.fails("lights")

    def test_passport_version_must_match(self):
        self.entry()["art_bible_version"] = 1
        self.fails("passport v1")

    def test_duplicate_and_order(self):
        self.manifest["assets"].append(copy.deepcopy(self.entry()))
        self.fails("duplicate asset_id")
        self.manifest["assets"].pop()
        self.manifest["assets"].reverse()
        self.fails("sorted")

    def test_path_follows_the_asset_id(self):
        self.entry()["path"] = "game/assets/enemies/hero_sword/hero_sword.png"
        self.fails("path must be")

    def test_lfs_budget(self):
        saved = assets.LFS_BUDGET_BYTES
        assets.LFS_BUDGET_BYTES = 1000
        self.addCleanup(setattr, assets, "LFS_BUDGET_BYTES", saved)
        self.fails("exceeds")


if __name__ == "__main__":
    unittest.main()
