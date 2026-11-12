#!/usr/bin/env python3
"""ARCH-04 reference oracle: typed effect ops, damage provenance and finite reaction chains.

Design-only. For every skill root and capacity profile it computes:

* a static upper bound on logical events (acyclic recurrence, generation budget
  W(v,g), or a per-root resource that strictly decreases inside a cycle);
* the worst-case event tree of the model (every fanout at maximum, every
  condition true), with full provenance on every event;
* a verdict from FLEXIBILITY-FIRST-001 §9: VALID_FOR_PROFILE, BOUND_TOO_COARSE,
  PROFILE_EXCEEDED. Unbounded cycles are INVALID_SEMANTICS (ContractError).

Nothing is ever dropped to fit a profile: exceeding a profile is a verdict,
and an expansion that outgrows its own proven bound is a proof failure.
Stdlib only; no Godot runtime, no balance.
"""
from __future__ import annotations

import argparse
import copy
import json
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / ".work/proposals/arch-04-effect-chains/reference_effects.json"
CANONICAL = ROOT / ".work/config/v7"

EVENT_KINDS = {"CAST", "HIT", "STATUS_APPLIED", "STATUS_TICK", "REACTION"}
ORIGINS = {"primary", "echo", "proc", "zone", "summon", "dot", "reaction"}
TRIGGER_EMITS = {"CAST": {"echo"}, "HIT": {"proc"}, "REACTION": {"reaction"}}
DAMAGE_KINDS = {"HIT", "STATUS_TICK", "REACTION"}
OPS = {
    "CHAIN": {"jumps", "unique_targets", "damage_ref"},
    "PROJECTILE": {"count", "pierce", "damage_ref"},
    "ZONE": {"duration_ticks", "tick_interval_ticks", "max_targets_per_tick", "damage_ref"},
    "SUMMON": {"attacks", "targets_per_attack", "lifetime_ticks", "damage_ref"},
    "APPLY_STATUS": {"status_id", "stacks", "duration_ticks"},
}
TRIGGER_FIELDS = {"id", "on", "accepts_origins", "emits", "origin", "max_children"}
TRIGGER_OPTIONAL = {"consumes", "refunds", "status_id", "requires_status_on_target", "consumes_status"}


class ContractError(ValueError):
    pass


def must(cond: bool, code: str, message: str) -> None:
    if not cond:
        raise ContractError(code + ": " + message)


def nonneg(value, code, where):
    must(type(value) is int and value >= 0, code, where + " must be a non-negative integer")
    return value


def pos(value, code, where):
    must(type(value) is int and value > 0, code, where + " must be a positive integer")
    return value


def load(path: Path = FIXTURE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_statuses(path: Path = CANONICAL) -> dict:
    return {s["id"]: s for s in json.loads((path / "statuses.json").read_text(encoding="utf-8"))["statuses"]}


# ---------------------------------------------------------------- schema

def validate_op(op: dict, statuses: dict) -> None:
    kind = op.get("op")
    must(kind in OPS, "E_OP_KIND", str(kind))
    fields = set(op) - {"op", "id"}
    must(isinstance(op.get("id"), str) and op["id"].startswith("sample.op."), "E_OP_ID", str(op.get("id")))
    must(not OPS[kind] - fields, "E_OP_FIELD_MISSING", op["id"] + " lacks " + ", ".join(sorted(OPS[kind] - fields)))
    must(not fields - OPS[kind], "E_OP_FIELD_UNKNOWN", op["id"] + " has " + ", ".join(sorted(fields - OPS[kind])))
    if "damage_ref" in OPS[kind]:
        must(isinstance(op["damage_ref"], str) and op["damage_ref"], "E_OP_VALUE", op["id"] + ".damage_ref")
    if kind == "CHAIN":
        pos(op["jumps"], "E_OP_VALUE", op["id"] + ".jumps")
        must(type(op["unique_targets"]) is bool, "E_OP_VALUE", op["id"] + ".unique_targets")
    elif kind == "PROJECTILE":
        pos(op["count"], "E_OP_VALUE", op["id"] + ".count")
        nonneg(op["pierce"], "E_OP_VALUE", op["id"] + ".pierce")
    elif kind == "ZONE":
        pos(op["duration_ticks"], "E_OP_VALUE", op["id"] + ".duration_ticks")
        pos(op["tick_interval_ticks"], "E_OP_VALUE", op["id"] + ".tick_interval_ticks")
        pos(op["max_targets_per_tick"], "E_OP_VALUE", op["id"] + ".max_targets_per_tick")
    elif kind == "SUMMON":
        for f in ("attacks", "targets_per_attack", "lifetime_ticks"):
            pos(op[f], "E_OP_VALUE", op["id"] + "." + f)
    else:
        status = statuses.get(op["status_id"])
        must(status is not None, "E_STATUS_REF", op["status_id"])
        must(status.get("target", "enemy") == "enemy", "E_STATUS_TARGET", op["status_id"] + " targets the player")
        pos(op["stacks"], "E_OP_VALUE", op["id"] + ".stacks")
        must(op["stacks"] <= status["max_stacks"], "E_OP_VALUE", op["id"] + ".stacks above status max_stacks")
        pos(op["duration_ticks"], "E_OP_VALUE", op["id"] + ".duration_ticks")


def validate_trigger(tr: dict, fx: dict, statuses: dict) -> None:
    tid = tr.get("id", "?")
    must(not TRIGGER_FIELDS - set(tr), "E_TRIGGER_FIELD_MISSING", tid)
    must(not set(tr) - TRIGGER_FIELDS - TRIGGER_OPTIONAL, "E_TRIGGER_FIELD_UNKNOWN", tid)
    must(tr["on"] in EVENT_KINDS, "E_TRIGGER_EVENT", tid + ".on")
    must(set(tr["accepts_origins"]) <= ORIGINS and tr["accepts_origins"], "E_TRIGGER_ORIGIN", tid)
    must(tr["emits"] in TRIGGER_EMITS, "E_TRIGGER_EMITS", tid + " cannot emit " + str(tr["emits"]))
    must(tr["origin"] != "primary", "E_ORIGIN_PRIMARY", tid + ": a proc can never claim primary origin")
    must(tr["origin"] in TRIGGER_EMITS[tr["emits"]], "E_TRIGGER_ORIGIN", tid + " emits " + tr["emits"] + "/" + tr["origin"])
    pos(tr["max_children"], "E_TRIGGER_FANOUT", tid)
    for key in ("consumes", "refunds"):
        if key in tr:
            must(tr[key]["resource"] in fx["resources"], "E_RESOURCE_REF", tid + "." + key)
            pos(tr[key]["amount"], "E_RESOURCE_REF", tid + "." + key + ".amount")
    for key in ("status_id", "requires_status_on_target", "consumes_status"):
        if key in tr:
            must(tr[key] in statuses, "E_STATUS_REF", tid + "." + key)


def validate_structure(fx: dict, canonical: Path = CANONICAL) -> dict:
    must(fx.get("schema_version") == 1 and fx.get("kind") == "effect_chain_fixture", "E_FIXTURE", "kind/version")
    must(fx.get("status") == "proposal-only-not-canonical", "E_FIXTURE", "must stay proposal-only")
    statuses = canonical_statuses(canonical)
    skills_v7 = {s["id"] for s in json.loads((canonical / "skills.json").read_text(encoding="utf-8"))["skills"]}
    for rid, r in fx["resources"].items():
        must(r["scope"] == "per_root", "E_RESOURCE_SCOPE", rid)
        pos(r["initial"], "E_RESOURCE_REF", rid + ".initial")
    for p in fx["profiles"]:
        pos(p["event_capacity"], "E_PROFILE", p["id"])
        if p["max_generation"] is not None:
            pos(p["max_generation"], "E_PROFILE", p["id"] + ".max_generation")
    seen = set()
    for s in fx["skills"]:
        must(s["id"] not in seen, "E_DUPLICATE_ID", s["id"])
        seen.add(s["id"])
        must(s["canonical_ref"] is None or s["canonical_ref"] in skills_v7, "E_CANONICAL_REF", s["id"])
        must(bool(s["ops"]), "E_OP_KIND", s["id"] + " has no ops")
        for op in s["ops"]:
            must(op.get("id") not in seen, "E_DUPLICATE_ID", str(op.get("id")))
            validate_op(op, statuses)
            seen.add(op["id"])
    for tr in fx["triggers"]:
        must(tr.get("id") not in seen, "E_DUPLICATE_ID", str(tr.get("id")))
        validate_trigger(tr, fx, statuses)
        seen.add(tr["id"])
    return statuses


# ---------------------------------------------------------------- graph

def op_children(op: dict, origin: str, statuses: dict) -> list:
    """Events one op produces for a cast of the given origin: (node, count, label)."""
    k = op["op"]
    if k == "CHAIN":
        return [(("HIT", origin, ""), op["jumps"], op["id"])]
    if k == "PROJECTILE":
        return [(("HIT", origin, ""), op["count"] * (op["pierce"] + 1), op["id"])]
    if k == "ZONE":
        ticks = op["duration_ticks"] // op["tick_interval_ticks"]
        return [(("HIT", "zone", ""), ticks * op["max_targets_per_tick"], op["id"])]
    if k == "SUMMON":
        return [(("HIT", "summon", ""), op["attacks"] * op["targets_per_attack"], op["id"])]
    out = [(("STATUS_APPLIED", origin, op["status_id"]), 1, op["id"])]
    period = statuses[op["status_id"]]["tick_period_ticks"]
    if period:
        out.append((("STATUS_TICK", "dot", op["status_id"]), op["duration_ticks"] // period, op["id"]))
    return out


class Model:
    def __init__(self, fx: dict, statuses: dict):
        self.fx, self.statuses = fx, statuses
        self.skills = {s["id"]: s for s in fx["skills"]}
        self.triggers = sorted(fx["triggers"], key=lambda t: t["id"])

    def matching(self, node):
        kind, origin, tag = node
        for tr in self.triggers:
            if tr["on"] == kind and origin in tr["accepts_origins"] and tr.get("status_id", tag) == tag:
                yield tr

    def children(self, node):
        """[(child_node, count, label, trigger_or_None)] in deterministic order."""
        kind, origin, tag = node
        out = []
        if kind == "CAST":
            for op in self.skills[tag]["ops"]:
                out += [(c, n, lbl, None) for c, n, lbl in op_children(op, origin, self.statuses)]
        for tr in self.matching(node):
            child_tag = tag if tr["emits"] == "CAST" else ""
            out.append(((tr["emits"], tr["origin"], child_tag), tr["max_children"], tr["id"], tr))
        return out

    def graph(self):
        nodes, todo = set(), [("CAST", "primary", s) for s in sorted(self.skills)]
        while todo:
            n = todo.pop()
            if n in nodes:
                continue
            nodes.add(n)
            todo += [c for c, *_ in self.children(n)]
        return nodes

    def sccs(self):
        nodes = sorted(self.graph())
        index, low, stack, on, comp_of, counter = {}, {}, [], set(), {}, [0]

        def visit(v):
            index[v] = low[v] = counter[0]
            counter[0] += 1
            stack.append(v)
            on.add(v)
            for w, *_ in self.children(v):
                if w not in index:
                    visit(w)
                    low[v] = min(low[v], low[w])
                elif w in on:
                    low[v] = min(low[v], index[w])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                frozen = frozenset(comp)
                for w in comp:
                    comp_of[w] = frozen
        for v in nodes:
            if v not in index:
                visit(v)
        return comp_of

    def cycle_edges(self, comp):
        return [(n, c, cnt, tr) for n in sorted(comp) for c, cnt, _, tr in self.children(n) if c in comp]

    def resource_measure(self, comp):
        """K = total internal children a root can create in this cycle, or None if no decreasing resource."""
        edges = self.cycle_edges(comp)
        if not edges:
            return 0
        if any(tr is None or "consumes" not in tr for *_, tr in edges):
            return None
        used = {tr["consumes"]["resource"] for *_, tr in edges}
        for n in comp:
            for *_, tr in self.children(n):
                must(not (tr and tr.get("refunds", {}).get("resource") in used), "E_CYCLE_REFUND",
                     "resource " + str(tr and tr.get("refunds")) + " is replenished inside a cycle")
        total = 0
        for res in sorted(used):
            amount = min(tr["consumes"]["amount"] for *_, tr in edges if tr["consumes"]["resource"] == res)
            total += self.fx["resources"][res]["initial"] // amount
        return total


def static_bound(model: Model, profile: dict, root: tuple) -> int:
    comp_of = model.sccs()
    g0 = profile["max_generation"]
    memo = {}

    def cyclic(comp):
        return len(comp) > 1 or any(c in comp for n in comp for c, *_ in model.children(n))

    def W(node, g):
        key = (node, g)
        if key in memo:
            return memo[key]
        comp = comp_of[node]
        if cyclic(comp):
            k = model.resource_measure(comp)
            if k is not None:
                tail = max(sum(cnt * W(c, g) for c, cnt, _, tr in model.children(n) if c not in comp) for n in comp)
                memo[key] = (1 + k) * (1 + tail)
                return memo[key]
            must(g is not None, "E_UNBOUNDED_CYCLE",
                 "cycle through " + ", ".join(sorted(f"{a}/{b}/{c}" for a, b, c in comp))
                 + " has no decreasing resource and the profile has no generation budget")
        total = 1
        for c, cnt, _, tr in model.children(node):
            if tr is not None and g is not None:
                if g > 0:
                    total += cnt * W(c, g - 1)
            else:
                total += cnt * W(c, g)
        memo[key] = total
        return total

    return W(root, g0)


def expand(model: Model, profile: dict, skill_id: str, world: dict | None = None, limit: int | None = None) -> list:
    """Worst-case event tree with provenance. world maps status_id -> owning skill already on targets;
    None means every target condition is assumed true (worst case)."""
    pool = {r: v["initial"] for r, v in model.fx["resources"].items()}
    root = {"uid": 0, "parent": None, "root": 0, "node": ("CAST", "primary", skill_id), "generation": 0,
            "via": skill_id, "credited_skill": skill_id, "contributors": [skill_id]}
    queue, events = deque([root]), []
    g_max = profile["max_generation"]
    while queue:
        ev = queue.popleft()
        events.append(ev)
        must(limit is None or len(events) <= limit, "E_BOUND_PROOF", f"expansion of {skill_id} exceeded its proven bound {limit}")
        for child, count, label, tr in model.children(ev["node"]):
            gen = ev["generation"] + (1 if tr is not None else 0)
            if tr is not None:
                if g_max is not None and gen > g_max:
                    continue
                need = tr.get("requires_status_on_target")
                if need and world is not None and need not in world:
                    continue
                if "consumes" in tr:
                    res, amount = tr["consumes"]["resource"], tr["consumes"]["amount"]
                    count = min(count, pool[res] // amount)
                    pool[res] -= count * amount
            credited = ev["credited_skill"]
            contributors = [credited]
            if tr is not None and tr.get("consumes_status"):
                owner = (world or {}).get(tr["consumes_status"], "unknown-owner")
                contributors = sorted({credited, owner})
            for _ in range(count):
                uid = len(events) + len(queue)
                queue.append({"uid": uid, "parent": ev["uid"], "root": 0, "node": child, "generation": gen,
                              "via": label, "credited_skill": credited, "contributors": contributors})
    return events


def check_provenance(model: Model, events: list) -> dict:
    by_uid = {}
    for ev in events:
        must(ev["uid"] not in by_uid, "E_PROVENANCE", "duplicate uid")
        by_uid[ev["uid"]] = ev
        kind, origin, _ = ev["node"]
        if ev["parent"] is None:
            must(ev["uid"] == ev["root"] and kind == "CAST" and origin == "primary", "E_PROVENANCE", "bad root")
            continue
        parent = by_uid.get(ev["parent"])
        must(parent is not None, "E_PROVENANCE", "child before parent")
        must(ev["root"] == parent["root"], "E_PROVENANCE", "root changed along a chain")
        trig = ev["via"] in {t["id"] for t in model.triggers}
        must(ev["generation"] == parent["generation"] + (1 if trig else 0), "E_PROVENANCE", "generation skipped")
        must(ev["credited_skill"] in model.skills, "E_PROVENANCE", "damage without owning skill")
        if origin == "primary":
            must(parent["node"] == ("CAST", "primary", ev["credited_skill"]) and not trig, "E_PROVENANCE",
                 "only direct ops of the primary cast may carry primary origin")
        if kind == "STATUS_TICK":
            must(origin == "dot" and not trig, "E_PROVENANCE", "DoT tick must come from its status op")
    damage = sum(1 for e in events if e["node"][0] in DAMAGE_KINDS)
    return {"events": len(events), "damage_events": damage}


def verdict(model: Model, profile: dict, skill_id: str) -> dict:
    bound = static_bound(model, profile, ("CAST", "primary", skill_id))
    events = expand(model, profile, skill_id, limit=bound)
    check_provenance(model, events)
    cap = profile["event_capacity"]
    if bound <= cap:
        v = "VALID_FOR_PROFILE"
    elif len(events) <= cap:
        v = "BOUND_TOO_COARSE"
    else:
        v = "PROFILE_EXCEEDED"
    return {"static_bound": bound, "worst_case_events": len(events), "verdict": v}


def report(fx: dict) -> dict:
    statuses = validate_structure(fx)
    model = Model(fx, statuses)
    return {p["id"]: {s: verdict(model, p, s) for s in sorted(model.skills)} for p in fx["profiles"]}


def verify(fx: dict | None = None) -> dict:
    fx = load() if fx is None else fx
    results = report(fx)
    checked = 0
    for pid, rows in fx["expected"].items():
        for sid, want in rows.items():
            must(results[pid][sid] == want, "E_GOLDEN", f"{pid} {sid}: expected {want}, got {results[pid][sid]}")
            checked += 1
    flat = [r["verdict"] for rows in results.values() for r in rows.values()]
    return {"profiles": len(results), "skills": len(fx["skills"]), "expectations": checked,
            "verdicts": {v: flat.count(v) for v in sorted(set(flat))}}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)
    try:
        fx = load(args.fixture)
        if args.report:
            print(json.dumps(report(fx), indent=1, sort_keys=True))
        summary = verify(fx)
    except (ContractError, KeyError, TypeError, ValueError) as exc:
        print("FAIL ARCH-04:", exc)
        return 1
    print("PASS ARCH-04 effect chains", json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
