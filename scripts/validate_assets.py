#!/usr/bin/env python3
"""ART-01: game asset manifest checks (ADR-009 section 5, ADR-013). Stdlib only.

game/assets/manifest.json lists every game sprite and texture. For each entry:
- structure, a stable unique asset_id, a path under game/assets/<group>/<name>/<name>.png;
- the built file and its master in art_source/ match sha256/bytes: real content is hashed,
  a Git LFS pointer (CI checkout) must carry the same oid and size;
- a real PNG has the manifest size, RGBA for sprite atlases, and atlas = frames x directions
  of frame_size; the feet_anchor keeps the transparent margin;
- source.json names the same asset, its prompt.txt hashes to prompt_sha256, references
  exist in ref/catalog.json with the same sha256, content_ids exist in the v7 configs;
- the recorded style metrics meet the thresholds of the passport group
  (art_source/style_passport.json, ART-BIBLE-001 version 2);
- the LFS volume of the slice (built files + masters) stays within the budget.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "game" / "assets"
MANIFEST = ASSETS / "manifest.json"
SOURCE = ROOT / "art_source"
PASSPORT = SOURCE / "style_passport.json"
CATALOG = ROOT / "ref" / "catalog.json"
CONFIG = ROOT / ".work" / "config" / "v7"
LFS_HEADER = b"version https://git-lfs.github.com/spec/v1\n"
ASSET_ID = re.compile(r"^asset\.(char|enemy|tile)\.[a-z][a-z0-9_]*$")
GROUPS = {"char": "characters", "enemy": "enemies", "tile": "tiles"}
KINDS = {"sprite_atlas", "floor_texture"}
LFS_BUDGET_BYTES = 10 * 1024 * 1024
REQUIRED = ("asset_id", "kind", "path", "sha256", "bytes", "size", "asset_version", "art_bible_version",
            "content_ids", "layout", "source", "qa")


class AssetError(Exception):
    pass


def lfs_pointer(path: Path) -> tuple[str, int] | None:
    """(sha256, size) of a Git LFS pointer file, None for real content."""
    head = path.read_bytes()[:200]
    if not head.startswith(LFS_HEADER):
        return None
    fields = dict(line.split(" ", 1) for line in path.read_text(encoding="ascii").splitlines() if " " in line)
    oid = fields.get("oid", "")
    if not oid.startswith("sha256:") or not fields.get("size", "").isdigit():
        raise AssetError(path.as_posix() + ": malformed Git LFS pointer")
    return oid[len("sha256:"):], int(fields["size"])


def check_binary(path: Path, sha: str, size: int, label: str) -> bool:
    """True when real content was checked (False: an LFS pointer with the same identity)."""
    if not path.is_file():
        raise AssetError(f"{label}: missing {path.relative_to(ROOT).as_posix()}")
    pointer = lfs_pointer(path)
    if pointer is not None:
        if pointer != (sha, size):
            raise AssetError(f"{label}: LFS pointer oid/size differs from the manifest")
        return False
    data = path.read_bytes()
    if len(data) != size or hashlib.sha256(data).hexdigest() != sha:
        raise AssetError(f"{label}: sha256/bytes differ from the manifest")
    return True


def png_header(path: Path) -> tuple[int, int, int]:
    """(width, height, colour type) from the IHDR chunk."""
    data = path.read_bytes()[:33]
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise AssetError(path.as_posix() + ": not a PNG")
    width, height, _depth, colour = struct.unpack(">IIBB", data[16:26])
    return width, height, colour


def content_ids() -> set[str]:
    ids: set[str] = set()
    for name in ("classes.json", "enemies.json", "stages.json"):
        text = (CONFIG / name).read_text(encoding="utf-8")
        ids.update(re.findall(r'"id":\s*"([a-z]+\.[a-z0-9_]+)"', text))
    return ids


def check_qa(entry: dict, passport: dict) -> None:
    qa = entry["qa"]
    group = passport["groups"].get(qa.get("palette_group"))
    label = entry["asset_id"]
    if group is None:
        raise AssetError(f"{label}: unknown palette group {qa.get('palette_group')}")
    if qa["palette_mean_delta_e"] > group["max_palette_delta_e"]:
        raise AssetError(f"{label}: palette ΔE {qa['palette_mean_delta_e']} > {group['max_palette_delta_e']}")
    if "max_chroma" in group and qa["chroma"] > group["max_chroma"]:
        raise AssetError(f"{label}: chroma {qa['chroma']} > {group['max_chroma']}")
    if "max_lights_pct" in group and qa["tones_pct"][2] > group["max_lights_pct"]:
        raise AssetError(f"{label}: lights {qa['tones_pct'][2]} % > {group['max_lights_pct']} %")
    if "min_lights_pct" in group and qa["tones_pct"][2] < group["min_lights_pct"]:
        raise AssetError(f"{label}: lights {qa['tones_pct'][2]} % < {group['min_lights_pct']} %")
    if "max_threat_pct" in group and qa["threat_colour_pct"] > group["max_threat_pct"]:
        raise AssetError(f"{label}: threat colour {qa['threat_colour_pct']} % > {group['max_threat_pct']} %")
    if any(c.startswith("class.") for c in entry["content_ids"]) and qa["palette_group"] != "hero_sprite":
        raise AssetError(f"{label}: a hero asset must be measured against hero_sprite (no threat colour)")


def check_layout(entry: dict) -> None:
    """Layout rules that hold for the manifest alone (an LFS pointer checkout too)."""
    layout = entry["layout"]
    label = entry["asset_id"]
    width, height = entry["size"]
    if entry["kind"] == "sprite_atlas":
        frame = layout["frame_size"]
        anchor = layout["feet_anchor"]
        if (width, height) != (frame * layout["frames"], frame * len(layout["directions"])):
            raise AssetError(f"{label}: atlas size is not frames x directions of {frame} px")
        if not (2 <= anchor[0] <= frame - 2 and 2 <= anchor[1] <= frame - 2):
            raise AssetError(f"{label}: feet_anchor leaves no transparent margin")
        if len(set(layout["directions"])) != len(layout["directions"]):
            raise AssetError(f"{label}: duplicate directions")
    elif (width, height) != (layout["texture_px"], layout["texture_px"]):
        raise AssetError(f"{label}: floor texture is not texture_px square")


def check_png(entry: dict, path: Path) -> None:
    """A real PNG has the manifest size; sprite atlases are RGBA."""
    width, height, colour = png_header(path)
    if [width, height] != entry["size"]:
        raise AssetError(f"{entry['asset_id']}: PNG size differs from the manifest")
    if entry["kind"] == "sprite_atlas" and colour != 6:
        raise AssetError(f"{entry['asset_id']}: a sprite atlas must be RGBA")


def check_entry(entry: dict, passport: dict, ids: set[str], refs: dict[str, str]) -> tuple[int, bool]:
    for key in REQUIRED:
        if key not in entry:
            raise AssetError(f"{entry.get('asset_id', '?')}: missing {key}")
    asset_id = entry["asset_id"]
    match = ASSET_ID.match(asset_id)
    if match is None or entry["kind"] not in KINDS:
        raise AssetError(f"{asset_id}: bad asset_id or kind")
    name = asset_id.split(".", 2)[2]
    expected = f"game/assets/{GROUPS[match.group(1)]}/{name}/{name}.png"
    if entry["path"] != expected:
        raise AssetError(f"{asset_id}: path must be {expected}")
    if entry["art_bible_version"] != passport["passport_version"]:
        raise AssetError(f"{asset_id}: measured against passport v{entry['art_bible_version']}")
    for cid in entry["content_ids"]:
        if cid not in ids:
            raise AssetError(f"{asset_id}: unknown content id {cid}")
    check_layout(entry)
    built = ROOT / entry["path"]
    real = check_binary(built, entry["sha256"], entry["bytes"], asset_id)
    if real:
        check_png(entry, built)
    source = entry["source"]
    if source["path"] != f"art_source/{name}/" + Path(source["path"]).name:
        raise AssetError(f"{asset_id}: master must live in art_source/{name}/")
    check_binary(ROOT / source["path"], source["sha256"], source["bytes"], asset_id + " master")
    spec = json.loads((SOURCE / name / "source.json").read_text(encoding="utf-8"))
    if spec["asset_id"] != asset_id or spec["content_ids"] != entry["content_ids"]:
        raise AssetError(f"{asset_id}: source.json names another asset or content ids")
    prompt = (SOURCE / name / spec["generation"]["prompt_file"]).read_text(encoding="utf-8").strip()
    if hashlib.sha256(prompt.encode("utf-8")).hexdigest() != source["prompt_sha256"]:
        raise AssetError(f"{asset_id}: prompt.txt does not hash to prompt_sha256")
    if not spec["references"]:
        raise AssetError(f"{asset_id}: no reference anchors")
    for ref in spec["references"]:
        if refs.get(ref["id"]) != ref["sha256"]:
            raise AssetError(f"{asset_id}: reference {ref['id']} is not in ref/catalog.json with that sha256")
    if not (SOURCE / name / "ASSET_CARD.md").is_file():
        raise AssetError(f"{asset_id}: no ASSET_CARD.md")
    check_qa(entry, passport)
    return entry["bytes"] + source["bytes"], real


def validate() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    passport = json.loads(PASSPORT.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise AssetError("manifest schema_version must be 1")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = catalog["entries"] if isinstance(catalog, dict) else catalog
    refs = {e["id"]: e["sha256"] for e in entries}
    ids = content_ids()
    seen: set[str] = set()
    volume = real = 0
    for entry in manifest["assets"]:
        if entry.get("asset_id") in seen:
            raise AssetError(f"duplicate asset_id {entry.get('asset_id')}")
        seen.add(entry["asset_id"])
        size, checked = check_entry(entry, passport, ids, refs)
        volume += size
        real += checked
    if [e["asset_id"] for e in manifest["assets"]] != sorted(seen):
        raise AssetError("manifest assets must be sorted by asset_id")
    folders = sorted(p.name for p in SOURCE.iterdir() if (p / "source.json").exists())
    if folders != sorted(a.split(".", 2)[2] for a in seen):
        raise AssetError("art_source folders and manifest assets differ")
    if volume > LFS_BUDGET_BYTES:
        raise AssetError(f"LFS volume {volume} bytes exceeds {LFS_BUDGET_BYTES}")
    return {"assets": len(seen), "real_files_checked": real, "lfs_bytes": volume}


def main() -> int:
    try:
        report = validate()
    except (AssetError, KeyError, ValueError, OSError) as error:
        print("FAIL:", error)
        return 1
    print("OK:", json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
