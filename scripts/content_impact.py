#!/usr/bin/env python3
"""Read-only dependency impact report for canonical v7 design catalog IDs.

No game runtime and no modification to the canonical data. Intended for
small, focused change planning by coding agents.
"""
from __future__ import annotations
import argparse
import json
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V7 = ROOT / ".work/config/v7"


def load_json(path: Path):
    def reject_duplicates(pairs):
        d = {}
        for key, value in pairs:
            if key in d:
                raise ValueError(f"duplicate JSON key {key!r} in {path.name}")
            d[key] = value
        return d
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)


def walk_defs(node, filename, found):
    if isinstance(node, list):
        for child in node:
            walk_defs(child, filename, found)
    elif isinstance(node, dict):
        ident = node.get("id")
        if isinstance(ident, str) and "." in ident:
            if ident in found:
                raise ValueError(f"duplicate ID {ident!r} in {found[ident][0]} and {filename}")
            found[ident] = (filename, node)
            # Nested objects with their own IDs should not be attributed to parent.
            for key, value in node.items():
                if key != "id":
                    walk_defs(value, filename, found)
        else:
            for value in node.values():
                walk_defs(value, filename, found)


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for x in node:
            yield from strings(x)
    elif isinstance(node, dict):
        for value in node.values():
            yield from strings(value)


def build_graph(path: Path = V7) -> tuple[dict, dict]:
    definitions = {}
    for file in sorted(path.glob("*.json")):
        walk_defs(load_json(file), file.name, definitions)
    reverse = defaultdict(set)
    for source, (_, record) in definitions.items():
        for candidate in strings(record):
            if candidate in definitions and candidate != source:
                reverse[candidate].add(source)
    return definitions, reverse


def impact(ident: str, definitions: dict, reverse: dict) -> list[dict]:
    if ident not in definitions:
        raise ValueError(f"unknown content ID: {ident}")
    seen = {ident}
    queue = deque([(ident, 0)])
    result = []
    while queue:
        current, depth = queue.popleft()
        result.append({"id": current, "file": definitions[current][0],
                       "depth": depth, "role": "changed" if current == ident else "dependent"})
        for neighbor in sorted(reverse.get(current, ())):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, depth + 1))
    return result


def main():
    parser = argparse.ArgumentParser(description="Inspect dependent canonical v7 IDs; read-only")
    parser.add_argument("--id", required=True, help="Changed canonical ID, e.g. status.mark")
    parser.add_argument("--json", action="store_true", help="JSON report for agents")
    args = parser.parse_args()
    try:
        definitions, reverse = build_graph()
        affected = impact(args.id, definitions, reverse)
    except (ValueError, KeyError, OSError) as e:
        parser.exit(1, f"FAIL content impact: {e}\n")
    if args.json:
        print(json.dumps({"query": args.id, "affected": affected}, ensure_ascii=False, indent=2))
    else:
        print(f"Content impact: {args.id} ({len(affected)-1} dependent IDs)")
        for row in affected:
            print(f"{'  ' * row['depth']}{row['id']}  [{row['file']}]")
        print("Note: lexical exact-ID references only; dynamic/implicit dependencies require review.")


if __name__ == "__main__":
    main()
