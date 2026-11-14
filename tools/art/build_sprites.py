#!/usr/bin/env python3
"""ART-01: build game sprites and floor textures from master sheets (ADR-013, ADR-014).

art_source/<name>/source.json describes one master image (Git LFS) and how it becomes a
game asset: a sprite atlas (chroma key, grid slicing, one scale per asset, a fixed
feet_anchor) or a seamless floor texture. The builder writes game/assets/<group>/<name>/
<name>.png and the matching entry of game/assets/manifest.json, including the style
metrics of ART-BIBLE-001 section 6 measured on the built file.

Needs Pillow (local tool, like ref look-dev). CI does not rebuild: scripts/validate_assets.py
checks the manifest, the LFS pointers and the recorded metrics without Pillow.

usage: python tools/art/build_sprites.py [name ...]   (no names: every art_source entry)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source"
ASSETS = ROOT / "game" / "assets"
MANIFEST = ASSETS / "manifest.json"
## Machine-readable ART-BIBLE-001 passport: palette groups, thresholds, the threat colour.
PASSPORT = SOURCE / "style_passport.json"
MANIFEST_SCHEMA = 1
## A pixel counts as opaque for bounding boxes and metrics above this alpha.
SOLID_ALPHA = 200
EDGE_ALPHA = 16


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# --- colour metrics (CIE76 on sRGB D65, Rec.709 luma as in ART-BIBLE-001 section 2) ---

def _lin(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lab(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    r, g, b = (_lin(v) for v in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))


def delta_e(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.dist(a, b)


def hex_rgb(text: str) -> tuple[int, int, int]:
    text = text.lstrip("#")
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def style_metrics(image: Image.Image, palette: list[str], threat_hex: str, threat_delta_e: float) -> dict:
    """Metrics of opaque pixels after a 256 px thumbnail (ART-BIBLE-001 section 2 method)."""
    small = image.convert("RGBA")
    small.thumbnail((256, 256), Image.Resampling.LANCZOS)
    pixels = [p[:3] for p in small.get_flattened_data() if p[3] > SOLID_ALPHA]
    if not pixels:
        raise ValueError("no opaque pixels")
    refs = [lab(hex_rgb(c)) for c in palette]
    threat = lab(hex_rgb(threat_hex))
    total_de = 0.0
    shadows = lights = threat_px = 0
    chroma = 0.0
    for rgb in pixels:
        point = lab(rgb)
        total_de += min(delta_e(point, ref) for ref in refs)
        luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        shadows += luma < 85
        lights += luma >= 170
        chroma += (max(rgb) - min(rgb)) / 255.0
        threat_px += delta_e(point, threat) <= threat_delta_e
    n = len(pixels)
    return {
        "opaque_px": n,
        "palette_mean_delta_e": round(total_de / n, 2),
        "tones_pct": [round(100 * shadows / n, 1), round(100 * (n - shadows - lights) / n, 1), round(100 * lights / n, 1)],
        "chroma": round(chroma / n, 3),
        "threat_colour_pct": round(100 * threat_px / n, 3),
        "median_l": round(sorted(luma_of(rgb) for rgb in pixels)[n // 2], 1),
    }


def luma_of(rgb: tuple[int, int, int]) -> float:
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


# --- chroma key ---

def key_out(image: Image.Image, key: tuple[int, int, int], low: int, high: int) -> Image.Image:
    """Alpha from how much a pixel leans to the key colour, then the key is unmixed out.

    For a green key the lean is g - max(r, b): the flat background and its baked shadows
    lean far, the painted figure does not lean at all. Half-transparent edge pixels get
    their colour back by c = (p - (1 - a) * key) / a.
    """
    rgb = image.convert("RGB")
    channel = max(range(3), key=lambda i: key[i])
    others = [i for i in range(3) if i != channel]
    out = Image.new("RGBA", rgb.size)
    src = rgb.load()
    dst = out.load()
    width, height = rgb.size
    for y in range(height):
        for x in range(width):
            p = src[x, y]
            lean = p[channel] - max(p[others[0]], p[others[1]])
            if lean <= low:
                alpha = 1.0
            elif lean >= high:
                alpha = 0.0
            else:
                alpha = 1.0 - (lean - low) / (high - low)
            if alpha <= 0.0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            colour = [p[i] if alpha >= 1.0 else (p[i] - (1.0 - alpha) * key[i]) / alpha for i in range(3)]
            # Despill: the keyed channel never exceeds the larger of the other two.
            colour[channel] = min(colour[channel], max(colour[others[0]], colour[others[1]]))
            dst[x, y] = tuple(max(0, min(255, round(c))) for c in colour) + (round(alpha * 255),)
    return out


def bbox(image: Image.Image, threshold: int = EDGE_ALPHA) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").point(lambda a: 255 if a > threshold else 0).getbbox()


def feet_x(cell: Image.Image, box: tuple[int, int, int, int]) -> float:
    """Median x of solid pixels in the lowest 12 % of the figure (the feet, not the sword)."""
    left, top, right, bottom = box
    band = max(2, round((bottom - top) * 0.12))
    alpha = cell.getchannel("A").load()
    xs = sorted(x for y in range(bottom - band, bottom) for x in range(left, right) if alpha[x, y] > SOLID_ALPHA)
    return float(xs[len(xs) // 2]) if xs else (left + right) / 2.0


def torso_x(cell: Image.Image, box: tuple[int, int, int, int]) -> float:
    """Median x of solid pixels between 30 % and 60 % of the figure height from the top: the
    torso stays put while legs, sword and hair swing (ADR-014 section 3)."""
    left, top, right, bottom = box
    height = bottom - top
    alpha = cell.getchannel("A").load()
    xs = sorted(x for y in range(top + round(height * 0.30), top + round(height * 0.60))
                for x in range(left, right) if alpha[x, y] > SOLID_ALPHA)
    return float(xs[len(xs) // 2]) if xs else (left + right) / 2.0


ANCHORS = {"feet": feet_x, "torso": torso_x}


def check_margin(atlas: Image.Image, frame: int, cols: int, rows: int, margin: int, label: str) -> None:
    for index in range(cols * rows):
        col, row = index % cols, index // cols
        frame_img = atlas.crop((col * frame, row * frame, (col + 1) * frame, (row + 1) * frame))
        inner = bbox(frame_img, 0)
        if inner is None or min(inner[0], inner[1], frame - inner[2], frame - inner[3]) < margin:
            raise ValueError(f"{label}: frame {index} breaks the {margin} px transparent margin")


def add_rim(atlas: Image.Image, rim: dict) -> Image.Image:
    """A light cold rim just outside the silhouette, under the sprite (ADR-014 section 2): an
    ink outline does not read on the dark floor."""
    alpha = atlas.getchannel("A")
    solid = alpha.point(lambda a: 255 if a > EDGE_ALPHA else 0)
    grown = solid.filter(ImageFilter.MaxFilter(2 * rim["width_px"] + 1)).filter(ImageFilter.GaussianBlur(0.6))
    ring = ImageChops.subtract(grown, alpha).point(lambda v: round(v * rim["alpha"]))
    out = Image.new("RGBA", atlas.size, hex_rgb(rim["colour"]) + (0,))
    out.putalpha(ring)
    out.alpha_composite(atlas)
    return out


def resize_premultiplied(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def build_atlas(spec: dict, master: Image.Image) -> tuple[Image.Image, dict]:
    sheet = spec["sheet"]
    keyed = key_out(master, hex_rgb(sheet["key_colour"]), sheet["key_low"], sheet["key_high"])
    cols, rows = sheet["grid"]
    cw, ch = keyed.width / cols, keyed.height / rows
    frame = spec["frame_size"]
    anchor_x, anchor_y = spec["feet_anchor"]
    margin = spec["margin_px"]
    cells = []
    for row in range(rows):
        for col in range(cols):
            box = (round(col * cw), round(row * ch), round((col + 1) * cw), round((row + 1) * ch))
            cell = keyed.crop(box)
            inner = bbox(cell)
            if inner is None:
                raise ValueError(f"{spec['asset_id']}: empty cell {row},{col}")
            left, top, right, bottom = inner
            if left == 0 or top == 0 or right == cell.width or bottom == cell.height:
                raise ValueError(f"{spec['asset_id']}: figure touches the edge of cell {row},{col}")
            anchor_of = ANCHORS.get(spec.get("anchor_x", "feet"))
            centre = anchor_of(cell, inner) if anchor_of else (left + right) / 2.0
            cells.append((cell, inner, centre))
    # One scale for the whole asset: the tallest figure gets figure_height_px, and nothing
    # may leave the frame minus its transparent margin.
    max_h = max(b[3] - b[1] for _, b, _ in cells)
    scale = spec["figure_height_px"] / max_h
    for _, (left, top, right, bottom), fx in cells:
        scale = min(scale, (anchor_x - margin) / max(fx - left, 1), (frame - margin - anchor_x) / max(right - fx, 1),
                    (anchor_y - margin) / max(bottom - top, 1))
    atlas = Image.new("RGBA", (frame * cols, frame * rows), (0, 0, 0, 0))
    for index, (cell, (left, top, right, bottom), fx) in enumerate(cells):
        figure = cell.crop((left, top, right, bottom))
        size = (max(1, round(figure.width * scale)), max(1, round(figure.height * scale)))
        figure = resize_premultiplied(figure, size)
        ox = round(anchor_x - (fx - left) * scale)
        oy = anchor_y - size[1]
        col, row = index % cols, index // cols
        atlas.alpha_composite(figure, (col * frame + ox, row * frame + oy))
    if spec.get("rim"):
        # The rim grows the silhouette: the margin must still hold after it.
        check_margin(atlas, frame, cols, rows, margin + spec["rim"]["width_px"], spec["asset_id"])
    check_margin(atlas, frame, cols, rows, margin, spec["asset_id"])
    layout = {"anchor_x": spec.get("anchor_x", "feet"), "frame_size": frame, "directions": spec["directions"], "frames": cols,
              "feet_anchor": [anchor_x, anchor_y], "scale": round(scale, 4)}
    if rows != len(spec["directions"]):
        raise ValueError(f"{spec['asset_id']}: {rows} rows for {len(spec['directions'])} directions")
    return atlas, layout


def build_floor(spec: dict, master: Image.Image) -> tuple[Image.Image, dict]:
    """A seamless square texture: centre crop, cross-faded with its half-offset copy."""
    rgb = master.convert("RGB")
    side = min(rgb.size)
    rgb = rgb.crop(((rgb.width - side) // 2, (rgb.height - side) // 2, (rgb.width + side) // 2, (rgb.height + side) // 2))
    shifted = Image.new("RGB", rgb.size)
    half = side // 2
    for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
        shifted.paste(rgb.crop((dx, dy, dx + half, dy + half)), ((dx + half) % side, (dy + half) % side))
    # Mask: 1 in the middle of the original (its seams are at the border), 0 near the border,
    # where the shifted copy has no seam.
    mask = Image.new("L", rgb.size)
    m = mask.load()
    for y in range(side):
        for x in range(side):
            d = min(x, y, side - 1 - x, side - 1 - y) / half
            m[x, y] = round(255 * min(1.0, max(0.0, (d - 0.15) / 0.5)))
    seamless = Image.composite(rgb, shifted, mask.filter(ImageFilter.GaussianBlur(4)))
    size = spec["texture_px"]
    texture = seamless.resize((size, size), Image.Resampling.LANCZOS)
    gain = spec.get("tone_gain", 1.0)
    if gain != 1.0:
        texture = texture.point(lambda v: min(255, round(v * gain)))
    return texture, {"texture_px": size, "cells": spec["cells"], "tone_gain": gain}


def build(name: str, passport: dict) -> dict:
    folder = SOURCE / name
    spec = json.loads((folder / "source.json").read_text(encoding="utf-8"))
    master_path = folder / spec["master"]
    master_bytes = master_path.read_bytes()
    master = Image.open(master_path)
    if spec["kind"] == "sprite_atlas":
        image, layout = build_atlas(spec, master)
    elif spec["kind"] == "floor_texture":
        image, layout = build_floor(spec, master)
    else:
        raise ValueError(f"{name}: unknown kind {spec['kind']}")
    # Style metrics describe the painted figure; the rim is measured on its own.
    group = passport["groups"][spec["palette_group"]]
    metrics = style_metrics(image, group["colours"], passport["threat_colour"], passport["threat_delta_e"])
    if spec.get("rim"):
        image = add_rim(image, spec["rim"])
        layout["rim"] = spec["rim"]
        metrics["rim_l"] = round(luma_of(hex_rgb(spec["rim"]["colour"])), 1)
    out = ASSETS / spec["group"] / name / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out, optimize=True)
    data = out.read_bytes()
    return {
        "asset_id": spec["asset_id"],
        "kind": spec["kind"],
        "path": out.relative_to(ROOT).as_posix(),
        "sha256": sha256(data),
        "bytes": len(data),
        "size": list(image.size),
        "asset_version": spec["asset_version"],
        "art_bible_version": passport["passport_version"],
        "content_ids": spec["content_ids"],
        "layout": layout,
        "source": {"path": master_path.relative_to(ROOT).as_posix(), "sha256": sha256(master_bytes),
                   "bytes": len(master_bytes), "prompt_sha256": spec["generation"]["prompt_sha256"]},
        "qa": {"palette_group": spec["palette_group"], **metrics},
    }


def render_card(name: str, entry: dict) -> str:
    """ASSET_CARD (.work/templates/ASSET_CARD.md) generated from source.json and the manifest."""
    spec = json.loads((SOURCE / name / "source.json").read_text(encoding="utf-8"))
    gen = spec["generation"]
    layout = entry["layout"]
    qa = entry["qa"]
    refs = " · ".join(f"`{r['id']}` `{r['sha256'][:12]}`" for r in spec["references"])
    if entry["kind"] == "sprite_atlas":
        geometry = (f"кадр {layout['frame_size']}×{layout['frame_size']} px · {layout['frames']} кадра × "
                    f"{len(layout['directions'])} направления ({', '.join(layout['directions'])}) · feet_anchor "
                    f"{layout['feet_anchor']} (якорь по x: {layout['anchor_x']}) · масштаб мастера {layout['scale']}")
        kind = "spritesheet"
    else:
        geometry = f"бесшовная текстура {layout['texture_px']}×{layout['texture_px']} px на {layout['cells']}×{layout['cells']} клеток"
        kind = "tile"
    lines = [
        f"# ASSET_CARD: {entry['asset_id']}",
        "",
        "> Сгенерировано `python tools/art/build_sprites.py` из `source.json` и `game/assets/manifest.json`. Не редактировать вручную.",
        "",
        f"- **asset_id (stable):** `{entry['asset_id']}` · версия ассета {entry['asset_version']}",
        f"- **Content IDs:** {', '.join('`' + c + '`' for c in entry['content_ids'])}",
        f"- **Type / layer:** {kind}",
        f"- **Reference anchors:** {refs}",
        f"- **Style passport version:** ART-BIBLE-001 v{entry['art_bible_version']}, группа `{qa['palette_group']}`",
        f"- **Generation:** {gen['capability']} · {gen['tool_version']} · prompt sha256 `{gen['prompt_sha256'][:16]}` "
        f"([prompt.txt](prompt.txt)) · {gen['created']} · мастер [{spec['master']}]({spec['master']}) `{entry['source']['sha256'][:12]}`",
        f"- **Geometry:** {geometry}",
        "- **Rules:** без запечённых свечения, теней и текста; фон снят хромакеем, тень — слой сцены"
        + (f"; кант `{layout['rim']['colour']}` {layout['rim']['width_px']} px (L {qa['rim_l']})" if layout.get("rim") else ""),
        f"- **Metrics:** palette ΔE {qa['palette_mean_delta_e']} · tones {qa['tones_pct']} · хрома {qa['chroma']} · "
        f"цвет угрозы {qa['threat_colour_pct']} %",
        f"- **Build:** [{Path(entry['path']).name}](../../{entry['path']}) · {entry['size'][0]}×{entry['size'][1]} · "
        f"{entry['bytes']} байт · sha256 `{entry['sha256'][:12]}`",
        "- **Decision:** approved для P0 (ADR-013, ADR-014 A0), до перегенерации под ракурс 30° (A4, A5)",
        "- **License / provenance:** сгенерировано утверждённой GPT imagegen capability (AGENTS.md п.3) по референсам проекта",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    passport = json.loads(PASSPORT.read_text(encoding="utf-8"))
    names = args.names or sorted(p.name for p in SOURCE.iterdir() if (p / "source.json").exists())
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {
        "schema_version": MANIFEST_SCHEMA, "assets": []}
    entries = {e["asset_id"]: e for e in manifest["assets"]}
    for name in names:
        entry = build(name, passport)
        entries[entry["asset_id"]] = entry
        (SOURCE / name / "ASSET_CARD.md").write_text(render_card(name, entry), encoding="utf-8", newline="\n")
        print(json.dumps({"asset_id": entry["asset_id"], "bytes": entry["bytes"], **entry["qa"]}, ensure_ascii=False))
    manifest["assets"] = [entries[k] for k in sorted(entries)]
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
