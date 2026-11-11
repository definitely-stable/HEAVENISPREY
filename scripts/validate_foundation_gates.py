#!/usr/bin/env python3
"""Architecture foundation evidence/compatibility gate (DESIGN ONLY).

Checks governance consistency of a small curated foundation backlog.
It cannot prove Godot runtime performance, player enjoyment, or the truth
of external research. Stdlib-only for existing Windows/Linux CI.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / ".work/proposals/foundation-2026/gates.json"
FIELDS = {"id", "priority", "owner", "status", "horizon", "depends_on",
          "existing_docs", "evidence_ids", "capability", "acceptance", "anti_goal"}
PRIORITIES = {"P0", "P1", "P2"}
HORIZONS = {"contract_now", "fixture_now", "experiment_later", "research_after_playtest"}
STATUSES = {"existing_partial", "planned", "deferred"}
EVIDENCE_TYPES = {"documentation", "standard", "tooling", "research",
                  "preprint", "guidelines", "benchmark", "research_report"}


class ContractError(ValueError):
    pass


def check(cond: bool, reason: str) -> None:
    if not cond:
        raise ContractError(reason)


def nonblank(x) -> bool:
    return isinstance(x, str) and bool(x.strip())


def load(path: Path = CATALOG) -> dict:
    def keys_unique(pairs):
        d = {}
        for k, v in pairs:
            check(k not in d, f"duplicate JSON property: {k}")
            d[k] = v
        return d
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=keys_unique)


def validate(doc: dict, *, root: Path = ROOT) -> dict:
    check(type(doc) is dict, "catalog must be object")
    check(doc.get("schema_version") == 1 and type(doc.get("schema_version")) is int,
          "unsupported schema_version")
    check(doc.get("kind") == "architecture_foundation_gate_catalog",
          "wrong architecture gate kind")
    check(doc.get("status") == "design-proposal-not-canonical",
          "cannot silently promote unaccepted design proposal")
    check(doc.get("scope") == "architecture_only", "game runtime not in scope")
    cutoff = doc.get("cutoff_date")
    check(isinstance(cutoff, str), "date missing")
    try:
        cutoff_dt = date.fromisoformat(cutoff)
    except ValueError as ex:
        raise ContractError("invalid cutoff_date") from ex
    check(cutoff_dt <= date(2026, 11, 11), "evidence date beyond snapshot")
    check(doc.get("lifecycle") == sorted(STATUSES) or
          set(doc.get("lifecycle", [])) == STATUSES, "invalid status set")
    check(set(doc.get("horizons", [])) == HORIZONS, "invalid horizon set")
    check(set(doc.get("evidence_types", [])) == EVIDENCE_TYPES,
          "invalid evidence type set")
    sources = doc.get("sources")
    gates = doc.get("gates")
    check(isinstance(sources, list) and bool(sources), "evidence sources missing")
    check(isinstance(gates, list) and bool(gates), "architecture gates missing")
    source_ids, seen_urls = set(), set()
    for source in sources:
        check(type(source) is dict and set(source) == {"id", "type", "url", "use"},
              "source fields invalid")
        sid = source["id"]
        check(nonblank(sid) and sid.startswith("SRC-"), "invalid source id")
        check(sid not in source_ids, f"duplicate evidence source: {sid}")
        check(source["type"] in EVIDENCE_TYPES, f"invalid evidence type: {sid}")
        check(isinstance(source["url"], str) and source["url"].startswith("https://"),
              f"non-HTTPS evidence link: {sid}")
        check(source["url"] not in seen_urls, f"duplicate evidence URL: {sid}")
        check(nonblank(source["use"]), f"no transferability limitation: {sid}")
        source_ids.add(sid)
        seen_urls.add(source["url"])
    ids = set()
    ordered_ids = []
    for gate in gates:
        check(type(gate) is dict and set(gate) == FIELDS, "architecture gate fields invalid")
        ident = gate["id"]
        check(isinstance(ident, str) and re.fullmatch(r"FND-\d\d", ident) is not None,
              "invalid foundation ID")
        check(ident not in ids, f"duplicate gate: {ident}")
        ids.add(ident)
        ordered_ids.append(ident)
        check(gate["priority"] in PRIORITIES, f"invalid gate priority: {ident}")
        check(nonblank(gate["owner"]), f"missing gate owner: {ident}")
        check(gate["status"] in STATUSES, f"invalid gate status: {ident}")
        check(gate["horizon"] in HORIZONS, f"invalid gate horizon: {ident}")
        check((gate["status"] != "deferred" or
               gate["horizon"] == "research_after_playtest"),
              f"deferred gate cannot be runtime-approved: {ident}")
        check(gate["priority"] != "P0" or gate["horizon"] in {"contract_now", "fixture_now"},
              f"P0 cannot be postponed until playtest: {ident}")
        for key in ("capability", "acceptance", "anti_goal"):
            check(nonblank(gate[key]) and len(gate[key]) >= 20,
                  f"gate {ident} lacks meaningful {key}")
        for field in ("depends_on", "existing_docs", "evidence_ids"):
            check(isinstance(gate[field], list), f"gate {ident}: {field} must be list")
            check(all(nonblank(x) for x in gate[field]),
                  f"gate {ident}: empty {field} entry")
            check(len(gate[field]) == len(set(gate[field])),
                  f"gate {ident}: duplicated {field}")
        check(len(gate["existing_docs"]) >= 1, f"gate {ident}: no integration docs")
        check(len(gate["evidence_ids"]) >= 1, f"gate {ident}: no source")
        for e in gate["evidence_ids"]:
            check(e in source_ids, f"gate {ident}: unknown evidence {e}")
        for path in gate["existing_docs"]:
            check(not path.startswith("/") and ".." not in Path(path).parts,
                  f"gate {ident}: path traversal")
            check((root / path).is_file(),
                  f"gate {ident}: missing dependency doc {path}")
    check(ordered_ids == sorted(ordered_ids),
          "gates must be stably sorted by ID")
    # If gate A depends on B, both appear in the catalog. Order of graph
    # declaration is arbitrary, cycles are not allowed.
    adj = {}
    for gate in gates:
        ident = gate["id"]
        deps = gate["depends_on"]
        check(ident not in deps, f"gate {ident}: self-dependency")
        for dep in deps:
            check(dep in ids, f"gate {ident}: unknown gate dependency {dep}")
        adj[ident] = deps
    active, visited = set(), set()
    def visit(node: str):
        check(node not in active, f"dependency cycle: {node}")
        if node in visited:
            return
        active.add(node)
        for dep in adj[node]:
            visit(dep)
        active.remove(node)
        visited.add(node)
    for ident in sorted(ids):
        visit(ident)
    check({"FND-01", "FND-02", "FND-03", "FND-04", "FND-05",
           "FND-06", "FND-09", "FND-11"} <= ids,
          "missing foundation coverage for core product")
    return {
        "gate_count": len(gates),
        "evidence_count": len(sources),
        "P0": sum(g["priority"] == "P0" for g in gates),
        "deferred": sum(g["status"] == "deferred" for g in gates),
        "critical_dependencies": sum(len(g["depends_on"]) for g in gates),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    args = parser.parse_args()
    try:
        result = validate(load(args.catalog))
    except (ContractError, OSError, KeyError, ValueError, TypeError) as ex:
        parser.exit(1, f"FAIL FOUNDATION-2026 architecture gates: {ex}\n")
    print("PASS FOUNDATION-2026 architecture gates", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
