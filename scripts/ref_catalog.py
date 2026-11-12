#!/usr/bin/env python3
"""ART-REF-001: reference image catalog for ref/ (validate | render | inventory).

ref/catalog.json is the single source. ref/README.md is generated from it
(`render`) and must stay byte-identical (`validate`). Image binaries live in
Git LFS: a checkout without LFS content (CI) holds pointer files, whose oid and
size must equal the catalog's sha256/bytes. With real content, every file must
be listed and its SHA-256/dimensions must match. With no images at all, only
structure, content-ID links and README parity are checked.

Stdlib only (PNG/JPEG header parsing, no Pillow).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "ref"
CATALOG = REF / "catalog.json"
README = REF / "README.md"
CONFIG = ROOT / ".work" / "config" / "v7"
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp"}
CATEGORIES = {
    "screen-mockup": "Макеты экранов (UX-референс, текст запечён)",
    "character-player": "Классы игрока: листы персонажей и анимаций",
    "character-enemy": "Обычные враги: листы персонажей и анимаций",
    "environment": "Окружение, арены, тайлы и пропсы",
    "key-art": "Key art и настроение",
    "branding": "Логотип и эмблемы",
    "skill-icons": "Иконки техник и эффектов",
    "ui-kit": "UI-киты, атласы рамок, кнопок и панелей",
}
READINESS = {
    "R0-reference": "только визуальный ориентир; не нарезается в игру",
    "R1-prototype-candidate": "прозрачный атлас; после нарезки, provenance и QA (s17/v5_assets) допустим как placeholder P0",
}
CONTENT_FILES = {"class": "classes.json", "enemy": "enemies.json", "stage": "stages.json",
                 "boss": "bosses.json", "mode": "modes.json", "status": "statuses.json"}


class ContractError(ValueError):
    pass


def known_ids() -> set[str]:
    ids = set()
    for name in CONTENT_FILES.values():
        data = json.loads((CONFIG / name).read_text(encoding="utf-8"))
        for value in data.values():
            if isinstance(value, list):
                ids.update(e["id"] for e in value if isinstance(e, dict) and "id" in e)
    return ids


def image_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    raise ContractError("unsupported image header: " + path.name)


LFS_HEADER = b"version https://git-lfs.github.com/spec/v1\n"


def lfs_pointer(path: Path) -> tuple[str, int] | None:
    """Return (sha256, size) for a Git LFS pointer file, None for real content."""
    if path.stat().st_size > 1024:
        return None
    data = path.read_bytes()
    if not data.startswith(LFS_HEADER):
        return None
    fields = dict(line.split(" ", 1) for line in data.decode("ascii").splitlines()[1:] if " " in line)
    oid = fields.get("oid", "")
    if not oid.startswith("sha256:") or not fields.get("size", "").isdigit():
        raise ContractError(path.name + ": malformed Git LFS pointer")
    return oid[len("sha256:"):], int(fields["size"])


def load() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def validate(catalog: dict, ref_dir: Path = REF, ids: set[str] | None = None, readme: str | None = None) -> dict:
    if catalog.get("schema_version") != 1 or catalog.get("kind") != "reference-catalog":
        raise ContractError("unexpected schema_version/kind")
    ids = known_ids() if ids is None else ids
    entries = catalog["entries"]
    seen_ids, seen_files, by_sha = set(), set(), {}
    for e in entries:
        rid = e["id"]
        if rid in seen_ids or not rid.startswith("REF-"):
            raise ContractError("bad or duplicate id " + rid)
        seen_ids.add(rid)
        if e["file"] in seen_files:
            raise ContractError("file listed twice " + e["file"])
        seen_files.add(e["file"])
        if e["category"] not in CATEGORIES:
            raise ContractError(rid + ": unknown category " + e["category"])
        if e["readiness"] not in READINESS:
            raise ContractError(rid + ": unknown readiness " + e["readiness"])
        if e.get("production_ready", False):
            raise ContractError(rid + ": references are never production assets (ART-REF-001)")
        if e["readiness"] == "R1-prototype-candidate" and not e.get("has_alpha"):
            raise ContractError(rid + ": prototype candidate must be a transparent atlas")
        for cid in e.get("content_ids", []):
            if cid not in ids:
                raise ContractError(rid + ": unknown content id " + cid)
        for hyp in e.get("hypotheses", []):
            if hyp.split(":")[0] in ("class", "enemy", "stage", "boss", "mode") and hyp in ids:
                raise ContractError(rid + ": hypothesis duplicates canonical id " + hyp)
        if not e.get("systems"):
            raise ContractError(rid + ": no linked game system")
        if e["sha256"] in by_sha and e.get("duplicate_of") != by_sha[e["sha256"]]:
            raise ContractError(rid + ": undeclared duplicate of " + by_sha[e["sha256"]])
        by_sha.setdefault(e["sha256"], rid)
    present = sorted(p for p in ref_dir.iterdir() if p.suffix.lower() in IMAGE_EXT) if ref_dir.is_dir() else []
    checked = pointers = 0
    if present:
        names = {p.name for p in present}
        if names != seen_files:
            raise ContractError("ref/ and catalog differ: missing=%s extra=%s"
                                % (sorted(names - seen_files)[:5], sorted(seen_files - names)[:5]))
        for e in entries:
            path = ref_dir / e["file"]
            pointer = lfs_pointer(path)
            if pointer is not None:
                # CI checks out Git LFS pointers only: verify identity without downloading.
                if pointer != (e["sha256"], e["bytes"]):
                    raise ContractError(e["id"] + ": LFS pointer oid/size differs from catalog")
                pointers += 1
                continue
            if hashlib.sha256(path.read_bytes()).hexdigest() != e["sha256"]:
                raise ContractError(e["id"] + ": sha256 mismatch")
            if list(image_size(path)) != [e["width"], e["height"]]:
                raise ContractError(e["id"] + ": dimensions mismatch")
            checked += 1
    expected = render(catalog)
    actual = README.read_text(encoding="utf-8") if readme is None else readme
    if actual != expected:
        raise ContractError("ref/README.md is stale: run python scripts/ref_catalog.py render")
    return {"entries": len(entries), "binaries_checked": checked, "lfs_pointers_checked": pointers,
            "categories": len({e["category"] for e in entries}),
            "duplicates": sum(1 for e in entries if e.get("duplicate_of"))}


def link(name: str) -> str:
    return quote(name)


def render(catalog: dict) -> str:
    entries = catalog["entries"]
    out = ["# Каталог визуальных референсов HEAVEN IS PREY (ART-REF-001)", "",
           "> Сгенерировано из [catalog.json](catalog.json) командой `python scripts/ref_catalog.py render`. "
           "Не редактировать вручную.", "",
           "**Статус всех файлов:** визуальные референсы и концепты, **не** production-ассеты и **не** утверждённые "
           "игровые правила. Текст на изображениях запечён и не заменяет ключи RU/EN (ADR-005). "
           "Арт-контракт: [s17](../.work/spec/core/s17.md) · [v5_assets](../.work/spec/v5/v5_assets.md) · "
           "[2D презентация s14](../.work/spec/core/s14.md).", "",
           "## Уровни готовности", ""]
    out += ["- **%s** — %s" % (k, v) for k, v in READINESS.items()]
    out += ["", "## Сводка", "", "| Категория | Файлов | R1 |", "|---|---:|---:|"]
    for cat, title in CATEGORIES.items():
        group = [e for e in entries if e["category"] == cat]
        out.append("| [%s](#%s) | %d | %d |" % (title, cat, len(group),
                   sum(1 for e in group if e["readiness"].startswith("R1"))))
    for cat, title in CATEGORIES.items():
        group = [e for e in entries if e["category"] == cat]
        if not group:
            continue
        out += ["", '<a id="%s"></a>' % cat, "## %s" % title, "",
                "| ID | Превью | Файл | Размер | Содержание | Связь с контентом / системами | Готовность |",
                "|---|---|---|---|---|---|---|"]
        for e in group:
            links = ", ".join("`%s`" % c for c in e.get("content_ids", []))
            hyp = ", ".join("*%s*" % h for h in e.get("hypotheses", []))
            systems = ", ".join(e["systems"])
            rel = " · ".join(x for x in (links, ("гипотезы: " + hyp) if hyp else "", systems) if x)
            dup = " (дубликат %s)" % e["duplicate_of"] if e.get("duplicate_of") else ""
            alpha = ", alpha" if e.get("has_alpha") else ""
            out.append('| %s | <img src="%s" width="160" alt="%s"> | [%s](<%s>)%s | %d×%d%s | %s | %s | %s |' % (
                e["id"], link(e["file"]), e["id"], e["file"], e["file"], dup, e["width"], e["height"], alpha,
                e["summary"], rel, e["readiness"]))
    out += ["", "## Наблюдения и расхождения с каноном", ""]
    out += ["- " + x for x in catalog.get("findings", [])]
    out += ["", "## Применение", ""]
    out += ["- " + x for x in catalog.get("usage_rules", [])]
    out.append("")
    return "\n".join(out)


def inventory(ref_dir: Path = REF) -> list[dict]:
    rows = []
    for path in sorted(p for p in ref_dir.iterdir() if p.suffix.lower() in IMAGE_EXT):
        w, h = image_size(path)
        rows.append({"file": path.name, "width": w, "height": h, "bytes": path.stat().st_size,
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return rows


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="ART-REF-001 reference catalog")
    parser.add_argument("command", choices=["validate", "render", "inventory"])
    args = parser.parse_args(argv)
    if args.command == "inventory":
        print(json.dumps(inventory(), ensure_ascii=False, indent=1))
        return 0
    catalog = load()
    if args.command == "render":
        README.write_text(render(catalog), encoding="utf-8", newline="\n")
        print("Rendered", README.relative_to(ROOT))
        return 0
    try:
        summary = validate(catalog)
    except (ContractError, KeyError) as exc:
        print("FAIL:", exc, file=sys.stderr)
        return 1
    print("Reference catalog:", json.dumps(summary, sort_keys=True))
    print("PASS: every reference classified, linked to canonical IDs/systems, never production-ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
