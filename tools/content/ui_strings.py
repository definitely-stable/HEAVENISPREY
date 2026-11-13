#!/usr/bin/env python3
"""RU/EN UI strings for the game runtime (P0-01 slice 5b, ADR-010 section 10).

Turns the Godot import CSV `.work/config/v7/translations.csv` (keys,en,ru) into
`game/content/locale/strings.json`, which `UiText` loads into TranslationServer at
startup so presentation code can use tr(KEY). Presentation only: the file is not part of
the ContentRegistry, content_digest or rules_hash, and no simulation code reads it.

Format strings use `%s` / `%d` (GDScript `%` operator); both locales of a key must carry
the same placeholders in the same order.

Usage:
  python tools/content/ui_strings.py           # write strings.json
  python tools/content/ui_strings.py --check   # CI: committed bytes == regenerated
Stdlib only.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / ".work" / "config" / "v7" / "translations.csv"
OUT = ROOT / "game" / "content" / "locale" / "strings.json"
SCHEMA_VERSION = 1
LOCALES = ("en", "ru")
KEY = re.compile(r"^[A-Z][A-Z0-9_]*$")
PLACEHOLDER = re.compile(r"%[sd%]")


class StringsError(ValueError):
    pass


def placeholders(text: str) -> list[str]:
    return [p for p in PLACEHOLDER.findall(text) if p != "%%"]


def load(source: Path = SOURCE) -> dict[str, dict[str, str]]:
    with source.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["keys", *LOCALES]:
            raise StringsError("translations.csv header must be keys,en,ru")
        table: dict[str, dict[str, str]] = {}
        for row in reader:
            key = row["keys"]
            if not KEY.match(key):
                raise StringsError("bad translation key %r" % key)
            if key in table:
                raise StringsError("duplicate translation key " + key)
            texts = {locale: row[locale] for locale in LOCALES}
            if any(not text.strip() for text in texts.values()):
                raise StringsError("missing translation for " + key)
            if placeholders(texts["en"]) != placeholders(texts["ru"]):
                raise StringsError("placeholders differ between en and ru for " + key)
            table[key] = texts
    return table


def build(source: Path = SOURCE) -> bytes:
    data = {
        "schema_version": SCHEMA_VERSION,
        "kind": "ui_strings",
        "source": ".work/config/v7/translations.csv",
        "locales": list(LOCALES),
        "strings": load(source),
    }
    text = json.dumps(data, ensure_ascii=False, sort_keys=True, indent=1)
    return (text + "\n").encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        data = build()
    except StringsError as exc:
        print("FAIL:", exc, file=sys.stderr)
        return 1
    where = OUT.relative_to(ROOT).as_posix()
    if args.check:
        if not OUT.exists() or OUT.read_bytes() != data:
            print("FAIL: %s differs from translations.csv; run tools/content/ui_strings.py" % where,
                  file=sys.stderr)
            return 1
        print("OK: %s matches translations.csv" % where)
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    print("written %s (%d bytes)" % (where, len(data)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
