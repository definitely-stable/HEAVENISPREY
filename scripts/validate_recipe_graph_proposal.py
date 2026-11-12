#!/usr/bin/env python3
"""ARCH-02 reference oracle: reachability of Evolution/Union/Gift/Mutation/Meridian recipes.

Design-only. Answers, per run profile and per recipe, either a witness path
(minimum draft picks, earliest second, replayable action list) or one
explainable reason the recipe cannot be reached:

  RANK_UNREACHABLE  a required rank exceeds max_rank + declared post-max growth
  NO_SOURCE         an input has no acquisition source and no recipe grants it
  CLASS_LOCKED      inputs exist only for other classes
  CAPACITY          reachable only with more simultaneous slots than the profile allows
  GATE_EXHAUSTED    needs more reward events (ritual, breakthrough...) than a run has
  PICK_BUDGET       needs more draft picks than the run schedule provides

Rarity changes odds, not possibility, and is deliberately not an input.
No Godot runtime, no balance claims. Stdlib only.
"""
from __future__ import annotations

import argparse
import copy
import heapq
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / ".work/proposals/arch-02-recipe-graph/reference_graph.json"
CANONICAL = ROOT / ".work/config/v7"
KINDS = {"EVOLUTION", "UNION", "GIFT", "MUTATION", "MERIDIAN"}
GRANTS = {"active", "passive", "gift", "capacity"}
REASONS = ("RANK_UNREACHABLE", "NO_SOURCE", "CLASS_LOCKED", "CAPACITY", "GATE_EXHAUSTED", "PICK_BUDGET")
UNLIMITED = 10 ** 6


class ContractError(ValueError):
    pass


def must(cond: bool, message: str) -> None:
    if not cond:
        raise ContractError(message)


def posint(value, where: str) -> int:
    must(type(value) is int and value > 0, where + ": expected positive integer")
    return value


def load(path: Path = FIXTURE) -> dict:
    def no_dup(pairs):
        out = {}
        for k, v in pairs:
            must(k not in out, "duplicate JSON key: " + k)
            out[k] = v
        return out
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_dup)


# ---------------------------------------------------------------- structure

def growth_steps(skill: dict) -> int:
    """Finite number of post-max rank steps. Unbounded growth must saturate at a declared cap."""
    g = skill["growth"]
    if g["kind"] == "none":
        return 0
    if g["kind"] == "limit_break":
        return posint(g["max_steps"], skill["id"] + ".growth.max_steps")
    if g["kind"] == "repeatable":
        must("value_cap" in g, skill["id"] + ": unbounded growth needs value_cap")
        return posint(g["value_cap"], skill["id"] + ".value_cap") // posint(g["per_step"], skill["id"] + ".per_step")
    raise ContractError(skill["id"] + ": unknown growth kind " + str(g["kind"]))


def tables(fx: dict) -> dict:
    t = {"skills": {}, "passives": {}, "gifts": {}, "recipes": {}, "profiles": {}}
    for group in t:
        for item in fx[group]:
            ident = item["id"]
            must(ident.startswith("sample."), group + ": proposal IDs must be sample.*: " + ident)
            must(ident not in t[group], group + ": duplicate id " + ident)
            t[group][ident] = item
    return t


def item_kind(t: dict, ident: str) -> str:
    for kind, group in (("active", "skills"), ("passive", "passives"), ("gift", "gifts")):
        if ident in t[group]:
            return kind
    raise ContractError("unknown item " + ident)


def max_reachable_rank(t: dict, ident: str) -> int:
    if ident in t["skills"]:
        return t["skills"][ident]["max_rank"] + growth_steps(t["skills"][ident])
    return t["passives"][ident]["max_rank"]


def consumers(t: dict) -> dict:
    out = defaultdict(set)
    for rid, r in t["recipes"].items():
        for c in r["consumes"]:
            out[c["id"]].add(rid)
    return out


def recipe_cycles(t: dict) -> list[list[str]]:
    """Strongly connected components of the item graph input -> grant (Tarjan)."""
    edges = defaultdict(set)
    for r in t["recipes"].values():
        outs = {g["id"] for g in r["grants"] if g["kind"] != "capacity"}
        for i in r["consumes"] + r["requires"]:
            edges[i["id"]] |= outs
    index, low, stack, on, sccs, counter = {}, {}, [], set(), [], [0]

    def visit(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in sorted(edges[v]):
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
            if len(comp) > 1 or v in edges[v]:
                sccs.append(sorted(comp))
    for v in sorted(set(edges) | {w for ws in edges.values() for w in ws}):
        if v not in index:
            visit(v)
    return sccs


def validate_structure(fx: dict, canonical: Path = CANONICAL) -> dict:
    must(fx.get("schema_version") == 1 and fx.get("kind") == "recipe_graph_fixture", "unexpected fixture kind/version")
    must(fx.get("status") == "proposal-only-not-canonical", "fixture must stay proposal-only")
    t = tables(fx)
    every = [i for g in t.values() for i in g]
    must(len(every) == len(set(every)), "ID collision across groups")
    classes = {c["id"] for c in json.loads((canonical / "classes.json").read_text(encoding="utf-8"))["classes"]}
    gates = fx["event_gates"]
    for gid, g in gates.items():
        posint(g["max_per_run"], gid + ".max_per_run")
        must(type(g["first_second"]) is int and 0 <= g["first_second"] <= fx["run"]["duration_seconds"],
             gid + ": first_second outside run")
    last = (0, 0)
    for second, picks in fx["run"]["pick_schedule"]:
        must(second > last[0] and picks >= last[1], "pick_schedule must be strictly increasing in time")
        last = (second, picks)
    for p in t["profiles"].values():
        must(p["class_id"] in classes, p["id"] + ": unknown canonical class " + p["class_id"])
        for k in ("active_capacity", "passive_capacity", "gift_capacity"):
            posint(p[k], p["id"] + "." + k)
    for group in ("skills", "passives"):
        for ident, s in t[group].items():
            posint(s["max_rank"], ident + ".max_rank")
            for src in s["sources"]:
                must(src == "draft" or (src.startswith("starter:") and src[8:] in classes), ident + ": bad source " + src)
            must(all(c == "*" or c in classes for c in s["class_ids"]), ident + ": unknown class")
            if group == "skills":
                growth_steps(s)
    for rid, r in t["recipes"].items():
        kind = r["kind"]
        must(kind in KINDS, rid + ": unknown recipe kind " + str(kind))
        must(r["gate"] in gates, rid + ": unknown event gate " + r["gate"])
        must(r["grants"], rid + ": recipe grants nothing")
        ids = [x["id"] for x in r["consumes"]]
        must(len(ids) == len(set(ids)), rid + ": duplicate consumed input")
        for x in r["consumes"] + r["requires"]:
            must(x["id"] in t["skills"] or x["id"] in t["passives"], rid + ": unknown input " + x["id"])
            posint(x["min_rank"], rid + ".min_rank")
        for x in r["consumes"]:
            must(x["id"] in t["skills"], rid + ": only active skills are consumed: " + x["id"])
        need = {"EVOLUTION": (1, 1), "UNION": (2, UNLIMITED), "GIFT": (0, 0), "MUTATION": (1, UNLIMITED), "MERIDIAN": (0, 0)}[kind]
        must(need[0] <= len(ids) <= need[1], rid + ": " + kind + " input count out of contract")
        for g in r["grants"]:
            must(g["kind"] in GRANTS, rid + ": unknown grant kind " + str(g["kind"]))
            if g["kind"] == "capacity":
                must(g["slot"] in ("active", "passive", "gift"), rid + ": bad capacity slot")
                posint(g["amount"], rid + ".capacity.amount")
            else:
                must(item_kind(t, g["id"]) == g["kind"], rid + ": grant kind/id mismatch " + g["id"])
                if g["kind"] == "active" and kind in ("EVOLUTION", "UNION"):
                    must(not t["skills"][g["id"]]["sources"], rid + ": transformation result must not be draftable")
        if kind == "GIFT":
            must(all(g["kind"] == "gift" for g in r["grants"]), rid + ": GIFT grants gifts only")
        if kind == "MERIDIAN":
            must(all(g["kind"] == "capacity" for g in r["grants"]), rid + ": MERIDIAN grants route capacity only")
    # Overlapping consumers form one explicit exclusive choice; never resolved by JSON order.
    by_input = consumers(t)
    for item, rids in sorted(by_input.items()):
        if len(rids) > 1:
            groups = {t["recipes"][r]["exclusive_group"] for r in rids}
            must(len(groups) == 1 and None not in groups,
                 "implicit conflict: " + ", ".join(sorted(rids)) + " consume " + item + " without one exclusive_group")
    cycles = recipe_cycles(t)
    for comp in cycles:
        members = set(comp)
        for rid, r in t["recipes"].items():
            ins = {x["id"] for x in r["consumes"] + r["requires"]}
            outs = {g["id"] for g in r["grants"] if g["kind"] != "capacity"}
            if ins & members and outs & members:
                must(r.get("allow_cycle") is True,
                     "transformation cycle without allow_cycle: " + " -> ".join(comp) + " via " + rid)
    return t


# ---------------------------------------------------------------- transition model

def initial_state(t: dict, profile: dict) -> dict:
    starters = sorted(i for i, s in t["skills"].items() if "starter:" + profile["class_id"] in s["sources"])
    return {"active": {i: 1 for i in starters}, "passive": {}, "gifts": [],
            "bonus": {"active": 0, "passive": 0, "gift": 0}, "gates": {}, "picks": 0, "applied": []}


def class_ok(item: dict, profile: dict) -> bool:
    return "*" in item["class_ids"] or profile["class_id"] in item["class_ids"]


def capacity(profile: dict, state: dict, slot: str, relax: bool) -> int:
    if relax:
        return UNLIMITED
    return profile[slot + "_capacity"] + state["bonus"][slot]


def recipe_applicable(fx, t, profile, state, rid, relax_capacity=False, relax_gates=False) -> bool:
    r = t["recipes"][rid]
    gate = fx["event_gates"][r["gate"]]
    if not relax_gates and state["gates"].get(r["gate"], 0) >= gate["max_per_run"]:
        return False
    for x in r["consumes"]:
        if state["active"].get(x["id"], 0) < x["min_rank"]:
            return False
    for x in r["requires"]:
        pool = state["active"] if x["id"] in t["skills"] else state["passive"]
        if pool.get(x["id"], 0) < x["min_rank"]:
            return False
    after = apply_recipe_unchecked(t, state, rid)
    for slot, key in (("active", "active"), ("passive", "passive"), ("gift", "gifts")):
        if len(after[key]) > capacity(profile, after, slot, relax_capacity):
            return False
    for g in r["grants"]:
        if g["kind"] == "active" and g["id"] in state["active"] and g["id"] not in {x["id"] for x in r["consumes"]}:
            return False
        if g["kind"] == "passive" and g["id"] in state["passive"]:
            return False
        if g["kind"] == "gift" and g["id"] in state["gifts"]:
            return False
    return True


def apply_recipe_unchecked(t, state, rid):
    r = t["recipes"][rid]
    out = copy.deepcopy(state)
    for x in r["consumes"]:
        del out["active"][x["id"]]
    for g in r["grants"]:
        if g["kind"] == "active":
            out["active"][g["id"]] = 1
        elif g["kind"] == "passive":
            out["passive"][g["id"]] = 1
        elif g["kind"] == "gift":
            out["gifts"] = sorted(out["gifts"] + [g["id"]])
        else:
            out["bonus"][g["slot"]] += g["amount"]
    out["gates"][r["gate"]] = out["gates"].get(r["gate"], 0) + 1
    out["applied"] = out["applied"] + [rid]
    return out


def step(fx, t, profile, state, action, relax_capacity=False, relax_gates=False):
    """Apply one action with full validation (used by search and by independent replay)."""
    kind, ident = action
    out = copy.deepcopy(state)
    if kind == "recipe":
        must(recipe_applicable(fx, t, profile, state, ident, relax_capacity, relax_gates), "recipe not applicable: " + ident)
        return apply_recipe_unchecked(t, state, ident)
    group, pool, slot = (("skills", "active", "active") if ident in t["skills"] else ("passives", "passive", "passive"))
    item = t[group][ident]
    if kind == "acquire":
        must(ident not in out[pool], "already owned: " + ident)
        must("draft" in item["sources"] and class_ok(item, profile), "not draftable for class: " + ident)
        must(len(out[pool]) < capacity(profile, out, slot, relax_capacity), "no free " + slot + " slot")
        out[pool][ident] = 1
    elif kind == "rank":
        must(ident in out[pool], "rank-up of unowned " + ident)
        must(out[pool][ident] < max_reachable_rank(t, ident), "rank cap reached: " + ident)
        out[pool][ident] += 1
    else:
        raise ContractError("unknown action " + kind)
    out["picks"] += 1
    return out


def time_for(fx: dict, picks: int):
    if picks == 0:
        return 0
    for second, total in fx["run"]["pick_schedule"]:
        if total >= picks:
            return second
    return None


def path_second(fx, t, path) -> int | None:
    picks = sum(1 for kind, _ in path if kind != "recipe")
    base = time_for(fx, picks)
    if base is None:
        return None
    gates = [fx["event_gates"][t["recipes"][i]["gate"]]["first_second"] for k, i in path if k == "recipe"]
    return max([base] + gates)


def relevant(t: dict, target: str):
    """Backward closure: recipes and inputs that can matter for target, with the highest rank each needs."""
    producers = defaultdict(set)
    for rid, r in t["recipes"].items():
        for g in r["grants"]:
            if g["kind"] != "capacity":
                producers[g["id"]].add(rid)
    recipes, ranks, todo = set(), defaultdict(int), [target]
    while todo:
        rid = todo.pop()
        if rid in recipes:
            continue
        recipes.add(rid)
        for x in t["recipes"][rid]["consumes"] + t["recipes"][rid]["requires"]:
            ranks[x["id"]] = max(ranks[x["id"]], x["min_rank"])
            todo.extend(sorted(producers[x["id"]]))
    recipes |= {rid for rid, r in t["recipes"].items() if all(g["kind"] == "capacity" for g in r["grants"])}
    return recipes, dict(ranks)


def freeze(state):
    return (tuple(sorted(state["active"].items())), tuple(sorted(state["passive"].items())), tuple(state["gifts"]),
            tuple(sorted(state["bonus"].items())), tuple(sorted(state["gates"].items())))


def search(fx, t, profile, target, relax_capacity=False, relax_gates=False):
    """0-1 shortest path on draft picks; recipe applications cost no picks."""
    recipes, ranks = relevant(t, target)
    start = initial_state(t, profile)
    seen, heap, tie = {}, [(0, 0, start, [])], 1
    while heap:
        picks, _, state, path = heapq.heappop(heap)
        key = freeze(state)
        if key in seen:
            continue
        seen[key] = picks
        if target in state["applied"]:
            return path, state
        actions = []
        for ident, need in sorted(ranks.items()):
            pool = "active" if ident in t["skills"] else "passive"
            if ident in state[pool]:
                if state[pool][ident] < min(need, max_reachable_rank(t, ident)):
                    actions.append(("rank", ident))
            else:
                actions.append(("acquire", ident))
        for rid in sorted(recipes):
            if recipe_applicable(fx, t, profile, state, rid, relax_capacity, relax_gates):
                if rid != target and rid in state["applied"] and not t["recipes"][rid].get("allow_cycle"):
                    continue
                actions.append(("recipe", rid))
        for action in actions:
            try:
                nxt = step(fx, t, profile, state, action, relax_capacity, relax_gates)
            except ContractError:
                continue
            if freeze(nxt) in seen:
                continue
            heapq.heappush(heap, (nxt["picks"], tie, nxt, path + [list(action)]))
            tie += 1
    return None, None


def obtainable(t: dict, profile, use_class: bool) -> set[str]:
    """Fixed point of ids obtainable ignoring capacity, gates and budget."""
    have = {i for g in ("skills", "passives") for i, s in t[g].items()
            if "draft" in s["sources"] and (not use_class or class_ok(s, profile))}
    have |= {i for i, s in t["skills"].items() if "starter:" + profile["class_id"] in s["sources"]}
    changed = True
    while changed:
        changed = False
        for r in t["recipes"].values():
            if all(x["id"] in have for x in r["consumes"] + r["requires"]):
                for g in r["grants"]:
                    if g["kind"] != "capacity" and g["id"] not in have:
                        have.add(g["id"])
                        changed = True
    return have


def classify(fx, t, profile, rid) -> dict:
    r = t["recipes"][rid]
    for x in r["consumes"] + r["requires"]:
        if x["min_rank"] > max_reachable_rank(t, x["id"]):
            return {"result": "RANK_UNREACHABLE", "detail": x["id"]}
    inputs = {x["id"] for x in r["consumes"] + r["requires"]}
    if not inputs <= obtainable(t, profile, use_class=False):
        return {"result": "NO_SOURCE", "detail": sorted(inputs - obtainable(t, profile, False))}
    if not inputs <= obtainable(t, profile, use_class=True):
        return {"result": "CLASS_LOCKED", "detail": sorted(inputs - obtainable(t, profile, True))}
    path, state = search(fx, t, profile, rid)
    if path is None:
        if search(fx, t, profile, rid, relax_capacity=True)[0] is not None:
            return {"result": "CAPACITY"}
        if search(fx, t, profile, rid, relax_gates=True)[0] is not None:
            return {"result": "GATE_EXHAUSTED"}
        if search(fx, t, profile, rid, relax_capacity=True, relax_gates=True)[0] is not None:
            return {"result": "CAPACITY+GATE_EXHAUSTED"}
        raise ContractError(rid + ": unreachable for an unexplained reason")
    second = path_second(fx, t, path)
    if second is None or second > fx["run"]["duration_seconds"]:
        return {"result": "PICK_BUDGET", "picks": state["picks"]}
    return {"result": "REACHABLE", "picks": state["picks"], "second": second, "path": path}


def replay(fx, t, profile, path) -> dict:
    """Independent check of a witness: every action re-validated from the starting build."""
    state = initial_state(t, profile)
    for kind, ident in path:
        state = step(fx, t, profile, state, (kind, ident))
    return state


def report(fx: dict) -> dict:
    t = validate_structure(fx)
    out = {}
    for pid, profile in t["profiles"].items():
        out[pid] = {rid: classify(fx, t, profile, rid) for rid in sorted(t["recipes"])}
    return out


def verify(fx: dict | None = None) -> dict:
    fx = load() if fx is None else fx
    t = validate_structure(fx)
    results = report(fx)
    checked = 0
    for pid, expected in fx["expected"].items():
        for rid, want in expected.items():
            got = results[pid][rid]
            if isinstance(want, str):
                must(got["result"] == want, f"{pid} {rid}: expected {want}, got {got['result']}")
            else:
                must(got["result"] == "REACHABLE" and {"picks": got["picks"], "second": got["second"]} == want,
                     f"{pid} {rid}: expected {want}, got {got}")
                final = replay(fx, t, t["profiles"][pid], got["path"])
                must(rid in final["applied"], f"{pid} {rid}: witness replay does not apply the recipe")
            checked += 1
    reach = sum(1 for p in results.values() for r in p.values() if r["result"] == "REACHABLE")
    return {"profiles": len(results), "recipes": len(t["recipes"]), "expectations": checked,
            "reachable": reach, "unreachable": sum(len(p) for p in results.values()) - reach,
            "cycles": len(recipe_cycles(t))}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    parser.add_argument("--report", action="store_true", help="print every profile x recipe verdict")
    args = parser.parse_args(argv)
    try:
        fx = load(args.fixture)
        summary = verify(fx)
        if args.report:
            for pid, rows in report(fx).items():
                for rid, row in rows.items():
                    print(pid, rid, row["result"], row.get("picks", ""), row.get("second", ""))
    except (ContractError, KeyError, TypeError, ValueError) as exc:
        print("FAIL ARCH-02:", exc)
        return 1
    print("PASS ARCH-02 recipe reachability", json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
