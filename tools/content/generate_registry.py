#!/usr/bin/env python3
"""ContentRegistry generator (P0-00, closes GAP-REGISTRY-GEN; ADR-007).

Turns the canonical design catalog `.work/config/v7/*.json` into the runtime
artifacts the Godot project loads:

  game/content/generated/registry.json   canonical JSON bytes + "\\n"
  game/content/generated/manifest.json   digests, sources, policy

Canonical bytes (digest policy `hip-canonical-json-v1`):
  json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
             allow_nan=False).encode("utf-8") + b"\\n"
`content_digest` is the SHA-256 hex of the *whole file bytes*. Godot verifies
the same bytes with HashingContext; it never re-serializes JSON (Godot's JSON
parser returns every number as float, so re-serialization cannot be byte-exact).

Fail-closed: `scripts/validate_content.py` must pass first; duplicate JSON keys,
NaN/Infinity, wrong schema_version, duplicate IDs (also across catalogs) abort.
Localization (translations.csv, localization_context.json) is not content and
never changes the digest.

Usage:
  python tools/content/generate_registry.py           # write artifacts
  python tools/content/generate_registry.py --check   # CI: committed bytes == regenerated
  python tools/content/generate_registry.py --digest  # print content_digest only
Stdlib only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / ".work" / "config" / "v7"
OUT_DIR = ROOT / "game" / "content" / "generated"
REGISTRY_FILE = "registry.json"
MANIFEST_FILE = "manifest.json"
DIGEST_POLICY = "hip-canonical-json-v1"
REGISTRY_SCHEMA_VERSION = 1
SOURCE_SCHEMA_VERSION = 2
# Localization-only sources: presentation, never part of the content digest.
EXCLUDED_SOURCES = frozenset({"localization_context.json"})
GENERATOR = "tools/content/generate_registry.py"
# Godot parses every JSON number as a double: integers beyond this lose exactness.
MAX_SAFE_INTEGER = 2**53 - 1


class RegistryError(ValueError):
    pass


def canonical_bytes(value) -> bytes:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)
    return text.encode("utf-8") + b"\n"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _reject_constant(token: str):
    raise RegistryError("non-finite number in source: " + token)


def load_source(path: Path) -> dict:
    def no_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise RegistryError("duplicate JSON key %r in %s" % (key, path.name))
            result[key] = value
        return result
    obj = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicates,
                     parse_constant=_reject_constant)
    if type(obj) is not dict:
        raise RegistryError(path.name + ": root must be an object")
    if obj.get("schema_version") != SOURCE_SCHEMA_VERSION:
        raise RegistryError(path.name + ": schema_version must be %d" % SOURCE_SCHEMA_VERSION)
    check_numbers(obj, path.stem)
    return obj


def check_numbers(value, where: str) -> None:
    """Every number must survive Godot's float JSON parse: finite, |int| <= 2^53-1."""
    if type(value) is bool or value is None or type(value) is str:
        return
    if type(value) is int:
        if abs(value) > MAX_SAFE_INTEGER:
            raise RegistryError("%s: integer beyond +/-(2^53-1): %d" % (where, value))
    elif type(value) is float:
        if not math.isfinite(value):
            raise RegistryError("%s: non-finite number" % where)
    elif type(value) is dict:
        for key, item in value.items():
            check_numbers(item, where + "." + key)
    elif type(value) is list:
        for i, item in enumerate(value):
            check_numbers(item, "%s[%d]" % (where, i))
    else:
        raise RegistryError("%s: unsupported JSON value" % where)


def definition_list_key(stem: str, obj: dict) -> str | None:
    """The single top-level list whose items are objects with an `id`."""
    keys = [k for k, v in obj.items()
            if type(v) is list and v and all(type(x) is dict and "id" in x for x in v)]
    if len(keys) > 1:
        raise RegistryError("%s: ambiguous definition lists %s" % (stem, sorted(keys)))
    return keys[0] if keys else None


def source_paths(source_dir: Path = SOURCE_DIR) -> list[Path]:
    return sorted((p for p in source_dir.glob("*.json") if p.name not in EXCLUDED_SOURCES),
                  key=lambda p: p.name)


def build(source_dir: Path = SOURCE_DIR) -> tuple[bytes, bytes]:
    """Return (registry_bytes, manifest_bytes); pure function of the sources."""
    catalogs, index, sources = {}, {}, []
    seen_ids: dict[str, str] = {}
    paths = source_paths(source_dir)
    if not paths:
        raise RegistryError("no content sources in " + str(source_dir))
    for path in paths:
        stem = path.stem
        obj = load_source(path)
        catalogs[stem] = obj
        key = definition_list_key(stem, obj)
        if key is not None:
            index[stem] = key
            for item in obj[key]:
                def_id = item["id"]
                if type(def_id) is not str or not def_id:
                    raise RegistryError("%s: definition id must be nonblank text" % stem)
                if def_id in seen_ids:
                    raise RegistryError("duplicate definition id %s in %s and %s"
                                        % (def_id, seen_ids[def_id], stem))
                seen_ids[def_id] = stem
        rel = path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else path.name
        sources.append({"path": rel, "sha256": sha256_hex(path.read_bytes())})
    registry = {
        "registry_schema_version": REGISTRY_SCHEMA_VERSION,
        "digest_policy": DIGEST_POLICY,
        "catalogs": catalogs,
        "index": index,
    }
    registry_bytes = canonical_bytes(registry)
    manifest = {
        "schema_version": 1,
        "kind": "content-registry-manifest",
        "digest_policy": DIGEST_POLICY,
        "generator": GENERATOR,
        "registry_file": REGISTRY_FILE,
        "registry_sha256": sha256_hex(registry_bytes),
        "registry_bytes": len(registry_bytes),
        "definition_count": len(seen_ids),
        "sources": sources,
    }
    return registry_bytes, canonical_bytes(manifest)


def content_digest(source_dir: Path = SOURCE_DIR) -> str:
    return sha256_hex(build(source_dir)[0])


def validate_sources() -> None:
    proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validate_content.py")],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RegistryError("validate_content.py failed; refusing to generate:\n"
                            + (proc.stdout + proc.stderr)[-2000:])


def check(out_dir: Path = OUT_DIR) -> list[str]:
    registry_bytes, manifest_bytes = build()
    problems = []
    if out_dir.is_dir():
        expected_names = {REGISTRY_FILE, MANIFEST_FILE}
        for stray in sorted(p.name for p in out_dir.iterdir() if p.name not in expected_names):
            problems.append("unexpected file in generated/: " + stray)
    for name, expected in ((REGISTRY_FILE, registry_bytes), (MANIFEST_FILE, manifest_bytes)):
        path = out_dir / name
        if not path.is_file():
            problems.append("missing generated file " + name)
        elif path.read_bytes() != expected:
            problems.append("stale or hand-edited generated file " + name
                            + " (run python " + GENERATOR + ")")
    return problems


def write(out_dir: Path = OUT_DIR) -> str:
    registry_bytes, manifest_bytes = build()
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / REGISTRY_FILE).write_bytes(registry_bytes)
    (out_dir / MANIFEST_FILE).write_bytes(manifest_bytes)
    return sha256_hex(registry_bytes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--digest", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.digest:
            print(content_digest())
            return 0
        validate_sources()
        if args.check:
            problems = check()
            for msg in problems:
                print("FAIL:", msg, file=sys.stderr)
            if problems:
                return 1
            print("PASS: generated ContentRegistry matches v7 sources; content_digest",
                  content_digest())
            return 0
        print("Wrote", OUT_DIR.relative_to(ROOT).as_posix(), "content_digest", write())
    except RegistryError as exc:
        print("FAIL:", exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
