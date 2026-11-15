#!/usr/bin/env python3
"""ART-01: game asset manifest checks (ADR-009 section 5, ADR-013, ADR-014). Stdlib only.

game/assets/manifest.json lists every game sprite and texture. For each entry:
- structure, a stable unique asset_id, a path under game/assets/<group>/<name>/<name>.png;
- the built file and its master in art_source/ match sha256/bytes: real content is hashed,
  a Git LFS pointer (CI checkout) must carry the same oid and size;
- a real PNG has the manifest size, RGBA for sprite atlases, and atlas = frames x directions
  of frame_size; the feet_anchor keeps the transparent margin;
- source.json names the same asset, its prompt.txt hashes to prompt_sha256, references
  exist in ref/catalog.json with the same sha256, content_ids exist in the v7 configs;
- the recorded style metrics meet the thresholds of the passport group
  (art_source/style_passport.json, ART-BIBLE-001 version 3); the rim of characters is not
  baked but drawn by the scene shader (ADR-014 section 4), so no asset may carry one;
- every asset drawn in the lit scene has a normal map <name>_n.png next to it (ADR-014
  section 4) with the method of its kind, the same size, and the same identity rules as the
  built file; the HUD kit (ui_atlas) and the effects atlas (vfx_atlas) are drawn unlit over
  the scene and have none;
- a HUD kit or an effects atlas has uniquely named pieces inside the atlas, frame windows
  inside their piece and stretch caps narrower than the piece (ADR-014 sections 15 and 18);
- the LFS volume of the art (built files, normal maps and masters) stays within the budget.
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
ASSET_ID = re.compile(r"^asset\.(char|enemy|tile|prop|ui|vfx)\.[a-z][a-z0-9_]*$")
GROUPS = {"char": "characters", "enemy": "enemies", "tile": "tiles", "prop": "props", "ui": "ui", "vfx": "vfx"}
KINDS = {"sprite_atlas", "anim_atlas", "floor_texture", "prop_atlas", "decal_texture", "strip_texture", "ui_atlas",
         "vfx_atlas"}
## Kinds drawn with transparency: their PNG must be RGBA.
ALPHA_KINDS = {"sprite_atlas", "anim_atlas", "prop_atlas", "decal_texture", "ui_atlas", "vfx_atlas"}
## ADR-014 section 8: the P0 art budget (ADR-009 had 10 MiB for the first slice).
LFS_BUDGET_BYTES = 48 * 1024 * 1024
REQUIRED = ("asset_id", "kind", "path", "sha256", "bytes", "size", "asset_version", "art_bible_version",
            "content_ids", "layout", "normal", "source", "qa")
NORMAL_METHODS = {"sprite_atlas": "silhouette_pillow", "anim_atlas": "silhouette_pillow",
                  "floor_texture": "luminance_sobel",
                  "prop_atlas": "silhouette_pillow", "decal_texture": "luminance_sobel",
                  "strip_texture": "luminance_sobel", "ui_atlas": None,
                  "vfx_atlas": None}
## ADR-014 sections 7 and 13, A4: the loop seam against the median and the largest step between
## frames inside the loop, the body height of a clip across its directions, the torso against
## feet_anchor.x (atlas px).
ANIM_LOOP_SEAM_MAX = 1.35
ANIM_LOOP_SEAM_TO_MAX = 1.2
ANIM_HEIGHT_SPREAD_PCT = 2.0
ANIM_TORSO_DRIFT_PX = 2.0


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


def check_qa(entry: dict, passport: dict, floor_l: float | None) -> None:
    qa = entry["qa"]
    group = passport["groups"].get(qa.get("palette_group"))
    label = entry["asset_id"]
    if group is None:
        raise AssetError(f"{label}: unknown palette group {qa.get('palette_group')}")
    if any(c.startswith("class.") for c in entry["content_ids"]) and qa["palette_group"] != "hero_sprite":
        raise AssetError(f"{label}: a hero asset must be measured against hero_sprite (no threat colour)")
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
    if "rim_l" in qa:
        raise AssetError(f"{label}: the rim is drawn by the scene shader, not baked")
    if entry["kind"] == "anim_atlas":
        if qa["loop_seam_ratio"] > ANIM_LOOP_SEAM_MAX:
            raise AssetError(f"{label}: loop seam {qa['loop_seam_ratio']} > {ANIM_LOOP_SEAM_MAX} x the median step")
        if qa["loop_seam_to_max"] > ANIM_LOOP_SEAM_TO_MAX:
            raise AssetError(f"{label}: loop seam {qa['loop_seam_to_max']} > {ANIM_LOOP_SEAM_TO_MAX} x the largest step")
        if qa["height_spread_pct"] > ANIM_HEIGHT_SPREAD_PCT:
            raise AssetError(f"{label}: figure height spread {qa['height_spread_pct']} % > {ANIM_HEIGHT_SPREAD_PCT} %")
        if qa["torso_drift_px"] > ANIM_TORSO_DRIFT_PX:
            raise AssetError(f"{label}: torso drift {qa['torso_drift_px']} px > {ANIM_TORSO_DRIFT_PX} px")


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
    elif entry["kind"] == "anim_atlas":
        frame = layout["frame_size"]
        anchor = layout["feet_anchor"]
        directions = layout["directions"]
        clips = sorted(layout["clips"].items(), key=lambda item: item[1]["row"])
        row = 0
        for name, clip in clips:
            if clip["row"] != row:
                raise AssetError(f"{label}: clip {name} does not start at row {row}")
            if not 1 <= clip["frames"] <= layout["frames"] or clip["fps"] <= 0:
                raise AssetError(f"{label}: clip {name} has a bad frame count or fps")
            if not clip["directions"] or any(d not in directions for d in clip["directions"]):
                raise AssetError(f"{label}: clip {name} has unknown directions")
            row += len(clip["directions"])
        if (width, height) != (frame * layout["frames"], frame * row):
            raise AssetError(f"{label}: atlas size is not frames x clip rows of {frame} px")
        if not (2 <= anchor[0] <= frame - 2 and 2 <= anchor[1] <= frame - 2):
            raise AssetError(f"{label}: feet_anchor leaves no transparent margin")
        if len(set(directions)) != len(directions):
            raise AssetError(f"{label}: duplicate directions")
        for mirrored, source in layout["mirror"].items():
            if source not in directions or mirrored in directions:
                raise AssetError(f"{label}: mirror {mirrored} <- {source} is not a generated direction")
    elif entry["kind"] == "prop_atlas":
        names = [p["name"] for p in layout["props"]]
        if not names or len(set(names)) != len(names):
            raise AssetError(f"{label}: props need unique names")
        for prop in layout["props"]:
            x, y, w, h = prop["region"]
            fx, fy = prop["feet"]
            if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
                raise AssetError(f"{label}: {prop['name']} region leaves the atlas")
            if not (x <= fx <= x + w and y <= fy <= y + h):
                raise AssetError(f"{label}: {prop['name']} anchor is outside its region")
    elif entry["kind"] in ("ui_atlas", "vfx_atlas"):
        names = [p["name"] for p in layout["pieces"]]
        if not names or len(set(names)) != len(names):
            raise AssetError(f"{label}: HUD pieces need unique names")
        for piece in layout["pieces"]:
            x, y, w, h = piece["region"]
            if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
                raise AssetError(f"{label}: {piece['name']} region leaves the atlas")
            if "inner" in piece:
                ix, iy, iw, ih = piece["inner"]
                if iw <= 0 or ih <= 0 or ix < x or iy < y or ix + iw > x + w or iy + ih > y + h:
                    raise AssetError(f"{label}: {piece['name']} window is outside its piece")
            if "slice" in piece and (min(piece["slice"]) <= 0 or sum(piece["slice"]) >= w):
                raise AssetError(f"{label}: {piece['name']} stretch caps must be narrower than the piece")
    elif entry["kind"] == "strip_texture":
        if [width, height] != layout["texture_size"]:
            raise AssetError(f"{label}: strip size differs from texture_size")
    elif (width, height) != (layout["texture_px"], layout["texture_px"]):
        raise AssetError(f"{label}: texture is not texture_px square")


def check_png(entry: dict, path: Path) -> None:
    """A real PNG has the manifest size; sprite atlases are RGBA."""
    width, height, colour = png_header(path)
    if [width, height] != entry["size"]:
        raise AssetError(f"{entry['asset_id']}: PNG size differs from the manifest")
    if entry["kind"] in ALPHA_KINDS and colour != 6:
        raise AssetError(f"{entry['asset_id']}: a {entry['kind']} must be RGBA")


def check_entry(entry: dict, passport: dict, ids: set[str], refs: dict[str, str],
                floor_l: float | None) -> tuple[int, bool]:
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
    normal = entry["normal"]
    method = NORMAL_METHODS[entry["kind"]]
    if method is None:
        if normal is not None:
            raise AssetError(f"{asset_id}: a {entry['kind']} is drawn unlit and has no normal map")
    elif normal is None or normal["path"] != expected[:-len(".png")] + "_n.png" or normal.get("method") != method:
        raise AssetError(f"{asset_id}: normal map must be {name}_n.png made by {method}")
    elif check_binary(ROOT / normal["path"], normal["sha256"], normal["bytes"], asset_id + " normal map"):
        width, height, _colour = png_header(ROOT / normal["path"])
        if [width, height] != entry["size"]:
            raise AssetError(f"{asset_id}: normal map size differs from the texture")
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
    check_qa(entry, passport, floor_l)
    return entry["bytes"] + (normal["bytes"] if normal else 0) + source["bytes"], real


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
    floors = [e["qa"]["median_l"] for e in manifest["assets"] if e.get("kind") == "floor_texture"]
    floor_l = max(floors) if floors else None
    for entry in manifest["assets"]:
        if entry.get("asset_id") in seen:
            raise AssetError(f"duplicate asset_id {entry.get('asset_id')}")
        seen.add(entry["asset_id"])
        size, checked = check_entry(entry, passport, ids, refs, floor_l)
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
