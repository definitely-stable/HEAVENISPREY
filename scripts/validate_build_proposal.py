#!/usr/bin/env python3
"""Architecture-only reference oracle for BUILD-SKILL-001.

Validates an isolated proposal fixture. This does NOT load the game, balance
skill values, or make proposal content canonical in .work/config/v7.
Stdlib only; intended for repeatable Linux/Windows design CI.
"""
from __future__ import annotations

import argparse
import copy
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / ".work/proposals/build-skill-001/reference_catalog.json"
CANONICAL = ROOT / ".work/config/v7"


class ContractError(ValueError):
    pass


def must(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_json(path: Path) -> dict:
    def no_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            must(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_keys)


def index(items: list, group: str) -> dict:
    result = {}
    for item in items:
        must(isinstance(item, dict), f"{group}: expected object")
        value = item.get("id")
        must(isinstance(value, str) and value.startswith("sample."), f"{group}: invalid sample ID: {value}")
        must(value not in result, f"{group}: duplicate ID: {value}")
        result[value] = item
    return result


def posint(value, where):
    must(type(value) is int and value > 0, f"{where}: expected positive integer")


def validate_build(build: dict, tables: dict, policy: dict) -> None:
    posint(build["revision"], "build.revision")
    for group, table, capacity in (
        ("active", tables["skills"], policy["active_capacity"]),
        ("passive", tables["passives"], policy["passive_capacity"]),
    ):
        contents = build[group]
        must(len(contents) <= capacity, f"{group}: slots overflow")
        seen = set()
        for x in contents:
            ident = x["id"]
            must(ident in table, f"{group}: unknown ID: {ident}")
            must(ident not in seen, f"{group}: duplicate owned ID: {ident}")
            seen.add(ident)
            posint(x["rank"], f"{group}.{ident}.rank")
            must(x["rank"] <= table[ident]["max_rank"], f"{group}: rank cap exceeded for {ident}")
    must(len(build["gifts"]) <= policy["gift_capacity"], "gifts: capacity exceeded")
    must(len(set(build["gifts"])) == len(build["gifts"]), "gifts: duplicate")
    must(all(v in tables["gifts"] for v in build["gifts"]), "gifts: unknown ID")
    seen_powers = set()
    for entry in build["powers"]:
        ident = entry["id"]
        must(ident in tables["powers"], f"power: unknown {ident}")
        must(ident not in seen_powers, f"power: duplicate {ident}")
        seen_powers.add(ident)
        posint(entry["stacks"], f"power.{ident}.stacks")
        must(entry["stacks"] <= tables["powers"][ident]["max_stacks"], "power: cap exceeded")


def skill_rank(build, ident):
    return next((x["rank"] for x in build["active"] if x["id"] == ident), 0)


def passive_rank(build, ident):
    return next((x["rank"] for x in build["passive"] if x["id"] == ident), 0)


def eligible_offers(catalog: dict, build: dict) -> list[str]:
    """Reference eligibility set, NOT the weighted RNG or presentation service."""
    tables = tables_for(catalog)
    policy = catalog["policy"]
    validate_build(build, tables, policy)
    results = []
    for offer in catalog["offers"]:
        kind = offer["kind"]
        target = offer["target_id"]
        if kind == "rank_up_active":
            rank = skill_rank(build, target)
            valid = 0 < rank < tables["skills"][target]["max_rank"]
        elif kind == "acquire_active":
            valid = (skill_rank(build, target) == 0
                     and len(build["active"]) < policy["active_capacity"]
                     and tables["skills"][target]["acquisition"] == "general")
        elif kind == "acquire_passive":
            valid = (passive_rank(build, target) == 0
                     and len(build["passive"]) < policy["passive_capacity"])
        elif kind == "add_power":
            stacks = next((x["stacks"] for x in build["powers"] if x["id"] == target), 0)
            valid = stacks < tables["powers"][target]["max_stacks"]
        else:
            raise ContractError(f"unsupported offer kind: {kind}")
        if valid:
            results.append(offer["id"])
    return sorted(results)


def is_applicable(recipe: dict, build: dict, policy: dict, event_gate: str) -> bool:
    if recipe["event_gate"] != event_gate:
        return False
    if any(skill_rank(build, r["id"]) < r["min_rank"] for r in recipe["required_skills"]):
        return False
    if any(passive_rank(build, r["id"]) < r["min_rank"] for r in recipe["required_passives"]):
        return False
    if any(skill_rank(build, x) == 0 for x in recipe["consumes_skill_ids"]):
        return False
    if any(passive_rank(build, x) == 0 for x in recipe["preserves_passive_ids"]):
        return False
    grant = recipe["grants"]
    if grant["kind"] == "active":
        if skill_rank(build, grant["id"]) > 0:
            return False
        result_count = len(build["active"]) - len(recipe["consumes_skill_ids"]) + recipe["slot_cost"]
        if result_count > policy["active_capacity"]:
            return False
    else:
        if grant["id"] in build["gifts"] or len(build["gifts"]) + recipe["slot_cost"] > policy["gift_capacity"]:
            return False
    return True


def applicable_recipes(catalog: dict, build: dict, event_gate: str) -> list[str]:
    tables = tables_for(catalog)
    validate_build(build, tables, catalog["policy"])
    return sorted(
        recipe["id"] for recipe in catalog["transformations"]
        if is_applicable(recipe, build, catalog["policy"], event_gate)
    )


def conflicting_choices(catalog: dict, applicable: list[str]) -> dict[str, list[str]]:
    recipes = tables_for(catalog)["transformations"]
    groups = defaultdict(list)
    for ident in applicable:
        group = recipes[ident]["exclusive_group"]
        if group is not None:
            groups[group].append(ident)
    return {k: sorted(v) for k, v in groups.items() if len(v) > 1}


def apply_recipe(catalog: dict, build: dict, recipe_id: str, expected_revision: int, event_gate: str) -> dict:
    """Static transition model with optimistic revision guard; no game/runtime."""
    tables = tables_for(catalog)
    must(build["revision"] == expected_revision, "stale build revision")
    must(recipe_id in tables["transformations"], "unknown recipe")
    recipe = tables["transformations"][recipe_id]
    must(is_applicable(recipe, build, catalog["policy"], event_gate), "recipe not eligible")
    result = copy.deepcopy(build)
    consumed = set(recipe["consumes_skill_ids"])
    result["active"] = [x for x in result["active"] if x["id"] not in consumed]
    if recipe["grants"]["kind"] == "active":
        result["active"].append({"id": recipe["grants"]["id"], "rank": 1})
    else:
        result["gifts"].append(recipe["grants"]["id"])
    result["revision"] += 1
    validate_build(result, tables, catalog["policy"])
    return result


def tables_for(catalog: dict) -> dict:
    return {group: index(catalog[group], group)
            for group in ("skills", "passives", "powers", "gifts", "offers", "transformations", "witnesses")}


def max_proc_events(catalog: dict) -> int:
    """Conservative logical-event bound, optionally for a declared finite generation policy.

    Without max_generation, every cycle is rejected. With max_generation,
    *every* parent-to-child edge spends exactly one generation token, including
    acyclic paths; a future runtime must implement precisely this contract.
    This does not silently discard previously promised events for performance.
    """
    edges = defaultdict(list)
    for edge in catalog["proc_rules"]:
        posint(edge["max_children"], "proc max_children")
        edges[edge["source"]].append((edge["target"], edge["max_children"]))
    nodes = set(edges) | {target for rules in edges.values() for target, _ in rules}
    max_generation = catalog["policy"].get("max_generation")
    if max_generation is not None:
        posint(max_generation, "policy.max_generation")
        memo_depth = {}

        def count_bounded(node: str, remaining: int) -> int:
            if remaining == 0:
                return 1
            key = (node, remaining)
            if key not in memo_depth:
                memo_depth[key] = 1 + sum(
                    fanout * count_bounded(child, remaining - 1)
                    for child, fanout in edges[node]
                )
            return memo_depth[key]

        # All component roots, even if isolated from DIRECT_CAST, must have
        # a finite bound and must fit the declared profile's event budget.
        upper = max(
            (count_bounded(node, max_generation) for node in nodes | {"DIRECT_CAST"}),
            default=1,
        )
    else:
        visiting, memo = set(), {}

        def count(node: str) -> int:
            must(node not in visiting, f"proc cycle detected at {node}")
            if node in memo:
                return memo[node]
            visiting.add(node)
            result = 1 + sum(max_count * count(target) for target, max_count in edges[node])
            visiting.remove(node)
            memo[node] = result
            return result

        for node in sorted(nodes | {"DIRECT_CAST"}):
            count(node)
        upper = max(memo.values(), default=1)
    must(upper <= catalog["policy"]["max_proc_events_per_root"],
         f"proc root bound {upper} exceeds declared budget")
    return upper


def validate_catalog(catalog: dict, canonical_path: Path = CANONICAL) -> dict:
    must(catalog.get("schema_version") == 1, "fixture schema version must equal 1")
    must(catalog.get("kind") == "build_skill_architecture_fixture", "not a build proposal fixture")
    must(catalog.get("status") == "proposal-only-not-canonical", "sample must never become canonical")
    policy = catalog["policy"]
    for key in ("active_capacity", "passive_capacity", "gift_capacity", "offer_count", "max_proc_events_per_root"):
        posint(policy[key], key)
    tables = tables_for(catalog)
    all_ids = [x for group in tables.values() for x in group]
    must(len(all_ids) == len(set(all_ids)), "ID collision across fixture categories")

    canonical_skills = {s["id"] for s in load_json(canonical_path / "skills.json")["skills"]}
    canonical_statuses = {s["id"] for s in load_json(canonical_path / "statuses.json")["statuses"]}
    canonical_classes = {s["id"] for s in load_json(canonical_path / "classes.json")["classes"]}
    must({"skill.spirit_sword", "skill.thunder_chain"} <= canonical_skills,
         "expected canonical base skills missing")
    must({"class.sword", "class.thunder"} <= canonical_classes, "expected canonical classes missing")

    allowed_schools = {"sword", "thunder", "talisman", "body", "neutral"}
    allowed_geometry = {"projectile", "chain", "zone", "aura", "arc", "orbit", "beam", "nova", "summon", "buff"}
    for ident, skill in tables["skills"].items():
        posint(skill["max_rank"], f"{ident}.max_rank")
        must(skill["acquisition"] in {"starter", "general", "transformation"}, "unknown acquisition")
        must(skill["geometry_kind"] in allowed_geometry, f"unknown geometry: {ident}")
        must(bool(skill["school_tags"]) and set(skill["school_tags"]) <= allowed_schools,
             f"unknown school tag: {ident}")
        must(skill["status_ids"] is not None and set(skill["status_ids"]) <= canonical_statuses,
             f"unknown status ref: {ident}")
        if skill["canonical_ref"] is not None:
            must(skill["canonical_ref"] in canonical_skills, f"missing canonical skill: {ident}")
        if skill["acquisition"] == "transformation":
            must(skill["canonical_ref"] is None, "sample transformation must not override canonical skill")
    for ident, p in tables["passives"].items():
        posint(p["max_rank"], f"{ident}.max_rank")
    for ident, p in tables["powers"].items():
        posint(p["max_stacks"], f"{ident}.max_stacks")
    for ident, p in tables["gifts"].items():
        posint(p["max_copies"], f"{ident}.max_copies")

    kinds = {"rank_up_active": "skills", "acquire_active": "skills",
             "acquire_passive": "passives", "add_power": "powers"}
    for ident, offer in tables["offers"].items():
        posint(offer["weight"], f"{ident}.weight")
        must(offer["kind"] in kinds, f"invalid offer kind: {ident}")
        must(offer["target_id"] in tables[kinds[offer["kind"]]], f"offer unknown target: {ident}")
        if offer["kind"] == "acquire_active":
            must(tables["skills"][offer["target_id"]]["acquisition"] == "general",
                 "transformation/starter not in general acquisition pool")

    grant_kind = {"active": "skills", "gift": "gifts"}
    for ident, recipe in tables["transformations"].items():
        kind = recipe["kind"]
        consumed = recipe["consumes_skill_ids"]
        must(kind in {"EVOLUTION", "UNION", "GIFT"}, f"invalid transformation kind: {ident}")
        expected_min = {"EVOLUTION": 1, "UNION": 2, "GIFT": 0}[kind]
        must(len(consumed) >= expected_min, f"insufficient recipe inputs: {ident}")
        if kind == "GIFT":
            must(len(consumed) == 0, "gift cannot consume skills by default")
        if kind == "EVOLUTION":
            must(len(consumed) == 1, "evolution must consume exactly one active skill")
        must(len(consumed) == len(set(consumed)), f"duplicate consumed skill: {ident}")
        must(set(consumed) <= tables["skills"].keys(), f"unknown consumed skill: {ident}")
        prereq = {x["id"]: x["min_rank"] for x in recipe["required_skills"]}
        must(set(consumed) <= prereq.keys(), f"recipe consumes without prerequisite: {ident}")
        for source, rank in prereq.items():
            must(source in tables["skills"], f"recipe missing input skill: {ident}")
            posint(rank, "required min_rank")
            must(rank <= tables["skills"][source]["max_rank"], f"unreachable rank: {ident}")
        for source in recipe["required_passives"]:
            must(source["id"] in tables["passives"], f"recipe missing catalyst: {ident}")
            posint(source["min_rank"], "catalyst min_rank")
            must(source["min_rank"] <= tables["passives"][source["id"]]["max_rank"],
                 f"unreachable passive rank: {ident}")
        must(set(recipe["preserves_passive_ids"]) <= {
            x["id"] for x in recipe["required_passives"]}, f"preserve unknown catalyst: {ident}")
        grant = recipe["grants"]
        must(grant["kind"] in grant_kind, f"unknown grant kind: {ident}")
        must(grant["id"] in tables[grant_kind[grant["kind"]]], f"unknown grant: {ident}")
        must(recipe["slot_cost"] == 1, f"fixture grant slot cost must equal one: {ident}")
        if kind in {"UNION", "EVOLUTION"}:
            must(grant["kind"] == "active", "active transformation requires active result")
            must(recipe["exclusive_group"], "transformation must declare exclusive group")
            must(tables["skills"][grant["id"]]["acquisition"] == "transformation",
                 "transformation result should not be draft-acquirable")
        else:
            must(grant["kind"] == "gift", "gift recipe must grant gift")

    bound = max_proc_events(catalog)
    for ident, witness in tables["witnesses"].items():
        build = witness["build"]
        validate_build(build, tables, policy)
        actual = applicable_recipes(catalog, build, witness["event_gate"])
        must(actual == sorted(witness["expected_recipes"]),
             f"{ident}: expected recipes {witness['expected_recipes']} got {actual}")
        for recipe_id in actual:
            projected = apply_recipe(catalog, build, recipe_id, build["revision"], witness["event_gate"])
            must(projected["revision"] == build["revision"] + 1, "transaction revision not advanced")
        if ident.endswith(".conflict"):
            must(conflicting_choices(catalog, actual), "missing explicit exclusive recipe conflict")
    return {"skills": len(tables["skills"]), "passives": len(tables["passives"]),
            "powers": len(tables["powers"]), "offers": len(tables["offers"]),
            "recipes": len(tables["transformations"]), "witnesses": len(tables["witnesses"]),
            "proc_bound": bound}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, default=SAMPLE)
    args = parser.parse_args()
    try:
        summary = validate_catalog(load_json(args.fixture))
    except (ContractError, ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f"FAIL build-skill architecture: {error}\n")
    print("PASS architecture-only BUILD-SKILL-001", json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
