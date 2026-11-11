#!/usr/bin/env python3
"""GAME-ARCH-00/01 design-only reference oracle.

No Godot, combat, presentation, weighted draft, or game runtime.
Checks proposed contracts: pickup value preservation, deterministic event
ordering, repeatable receipts, level overflow, paused choice queue, and
optimistic build revision. Stdlib only (Ubuntu + Windows CI).
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / ".work/proposals/game-arch-00-01/reference_run.json"
CANONICAL = ROOT / ".work/config/v7"
EVENT_KINDS = {"XP_GAIN", "RITUAL_REWARD", "BREAKTHROUGH_READY"}
CHOICE_KINDS = {"LEVEL_UP", "RITUAL_REWARD", "BREAKTHROUGH"}
PICKUP_KINDS = {"XP", "HEALTH", "CATALYST"}


class ContractError(ValueError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ContractError(message)


def nat(value, field: str) -> None:
    require(type(value) is int and value >= 0, f"{field}: expected nonnegative integer")


def positive(value, field: str) -> None:
    require(type(value) is int and value > 0, f"{field}: expected positive integer")


def load_json(path: Path) -> dict:
    def reject_duplicate(pairs):
        result = {}
        for k, value in pairs:
            require(k not in result, f"duplicate JSON key: {k}")
            result[k] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate)


def digest(obj: dict) -> str:
    """Canonical digest for receipt equality; not a full RunRulesHash format."""
    return hashlib.sha256(json.dumps(obj, ensure_ascii=False,
                                     sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def validate_pickups(pickups: list[dict]) -> None:
    require(isinstance(pickups, list), "pickups: expected list")
    ids, source_ids = set(), set()
    for item in pickups:
        require(isinstance(item, dict), "pickup must be object")
        for field in ("id", "kind", "owner_uid", "region_id", "collection_policy"):
            require(isinstance(item.get(field), str) and bool(item[field]),
                    f"pickup: invalid {field}")
        require(item["id"] not in ids, f"duplicate pickup ID {item['id']}")
        ids.add(item["id"])
        require(item["kind"] in PICKUP_KINDS, "unknown pickup kind")
        positive(item["value"], "pickup.value")
        for coord in ("x", "y"):
            require(type(item.get(coord)) is int, f"pickup.{coord}: expected grid integer")
        require(item["collection_policy"] in {"RADIUS", "EXPLICIT_INTERACT"},
                "unknown collection policy")
        raw = item.get("source_uids")
        require(isinstance(raw, list) and len(raw) > 0,
                "pickup.source_uids must be nonempty list")
        require(len(raw) == len(set(raw)), "duplicate source within pickup")
        for source in raw:
            require(isinstance(source, str) and bool(source), "invalid pickup source UID")
            require(source not in source_ids, f"source UID counted twice: {source}")
            source_ids.add(source)


def consolidate_pickups(pickups: list[dict]) -> list[dict]:
    """Only exact same location/region/owner/kind/policy can be consolidated.

    Crucially this is NOT a merge-across-distance algorithm. Collection timing
    is unchanged for any path because each source retains its logical position.
    """
    validate_pickups(pickups)
    groups = defaultdict(list)
    for item in pickups:
        key = (item["kind"], item["owner_uid"], item["region_id"],
               item["collection_policy"], item["x"], item["y"])
        groups[key].append(item)
    result = []
    for key in sorted(groups):
        group = sorted(groups[key], key=lambda p: p["id"])
        if len(group) == 1:
            result.append(copy.deepcopy(group[0]))
        else:
            sources = sorted(source for p in group for source in p["source_uids"])
            merged = copy.deepcopy(group[0])
            merged["id"] = "sample.merged." + digest({"sources": sources})[:20]
            merged["value"] = sum(p["value"] for p in group)
            merged["source_uids"] = sources
            result.append(merged)
    validate_pickups(result)
    require(sum(x["value"] for x in result) == sum(x["value"] for x in pickups),
            "pickup value lost during consolidation")
    return sorted(result, key=lambda p: p["id"])


def collect_pickups(pickups: list[dict], *, owner_uid: str,
                    region_id: str, x: int, y: int, radius: int) -> tuple[list, list]:
    validate_pickups(pickups)
    nat(radius, "pickup_radius")
    require(type(x) is int and type(y) is int, "pickup position must use integer grid")
    picked, remaining = [], []
    for p in sorted(pickups, key=lambda item: item["id"]):
        within = ((p["x"] - x) ** 2 + (p["y"] - y) ** 2 <= radius ** 2)
        (picked if (p["owner_uid"] == owner_uid and p["region_id"] == region_id
                    and p["collection_policy"] == "RADIUS" and within)
         else remaining).append(copy.deepcopy(p))
    require(len(picked) + len(remaining) == len(pickups), "collection cardinality changed")
    return picked, remaining


def xp_events_from_pickups(collected: list[dict], *, run_uid: str, tick: int,
                           first_sequence: int) -> list[dict]:
    """Produce receipts for eligible collected XP only; no implicit XP multiplier."""
    validate_pickups(collected)
    require(isinstance(run_uid, str) and bool(run_uid), "run_uid missing")
    nat(tick, "tick")
    positive(first_sequence, "sequence")
    events = []
    for item in sorted(collected, key=lambda p: p["id"]):
        if item["kind"] == "XP":
            events.append({
                "uid": "sample.event.pickup." + digest({"sources": sorted(item["source_uids"])})[:24],
                "run_uid": run_uid,
                "tick": tick,
                "sequence": first_sequence + len(events),
                "kind": "XP_GAIN",
                "payload": {"amount": item["value"],
                            "source_uids": sorted(item["source_uids"])},
            })
    return events


def initial_run(catalog: dict) -> dict:
    rules = catalog["rules"]
    return {
        "run_uid": catalog["run_uid"],
        "level": 1,
        "xp_bank": 0,
        "build_revision": 1,
        "last_tick": 0,
        "last_sequence": 0,
        "processed_events": {},
        "claimed_xp_sources": [],
        "pending_choices": [],
        "committed_choices": [],
        "paused": False,
    }


def event_order_key(event: dict) -> tuple[int, int, str]:
    return (event["tick"], event["sequence"], event["uid"])


def validate_event(event: dict) -> None:
    require(isinstance(event, dict), "event must be object")
    require(set(event) == {"uid", "run_uid", "tick", "sequence", "kind", "payload"},
            "event envelope keys invalid")
    require(isinstance(event["uid"], str) and bool(event["uid"]), "event UID missing")
    require(isinstance(event["run_uid"], str) and bool(event["run_uid"]), "event run UID missing")
    nat(event["tick"], "event.tick")
    positive(event["sequence"], "event.sequence")
    require(event["kind"] in EVENT_KINDS, "unknown run event kind")
    require(isinstance(event["payload"], dict), "event payload invalid")
    if event["kind"] == "XP_GAIN":
        require(set(event["payload"]) == {"amount", "source_uids"},
                "XP payload must contain amount and source_uids")
        positive(event["payload"]["amount"], "XP amount")
        sources = event["payload"]["source_uids"]
        require(isinstance(sources, list) and bool(sources) and
                all(isinstance(x, str) and x for x in sources) and
                sources == sorted(set(sources)), "XP sources must be sorted unique IDs")
    else:
        require(event["payload"] == {}, f"unrecognized payload for {event['kind']}")


def apply_events(run: dict, events: list[dict], xp_cost_by_level: list[int]) -> dict:
    """At one committed tick boundary: apply sorted events atomically.

    External producers assign unique monotonic event sequences. Multiple events
    from one tick are processed as a batch, *then* strategic pause becomes active.
    Repeated identical receipts are idempotent even during a paused state.
    """
    for n, cost in enumerate(xp_cost_by_level, start=1):
        positive(cost, f"xp threshold at level {n}")
    for ev in events:
        validate_event(ev)
    ordered = sorted(events, key=event_order_key)
    seen_batch = {}
    for ev in ordered:
        if ev["uid"] in seen_batch:
            require(seen_batch[ev["uid"]] == digest(ev),
                    f"event UID collision: {ev['uid']}")
        seen_batch[ev["uid"]] = digest(ev)
    # Enforce unique sequence across *distinct* events, independent of input order.
    distinct_seq = {}
    for ev in ordered:
        key = (ev["tick"], ev["sequence"])
        require(key not in distinct_seq or distinct_seq[key] == ev["uid"],
                f"event sequence collision: {key}")
        distinct_seq[key] = ev["uid"]
    result = copy.deepcopy(run)
    for ev in ordered:
        require(ev["run_uid"] == result["run_uid"], "cross-run event receipt rejected")
        uid, signature = ev["uid"], digest(ev)
        old = result["processed_events"].get(uid)
        if old is not None:
            require(old == signature, f"event UID reused with different payload: {uid}")
            continue
        require(not result["paused"], "new world event while choice queue paused")
        require(ev["tick"] >= result["last_tick"], "event tick moved backwards")
        require(ev["sequence"] > result["last_sequence"], "event sequence moved backwards")
        result["last_tick"] = ev["tick"]
        result["last_sequence"] = ev["sequence"]
        result["processed_events"][uid] = signature
        if ev["kind"] == "XP_GAIN":
            sources = ev["payload"]["source_uids"]
            repeated = set(sources) & set(result["claimed_xp_sources"])
            require(not repeated, f"XP source already claimed: {sorted(repeated)}")
            result["claimed_xp_sources"] = sorted(result["claimed_xp_sources"] + sources)
            result["xp_bank"] += ev["payload"]["amount"]
            while result["level"] - 1 < len(xp_cost_by_level):
                cost = xp_cost_by_level[result["level"] - 1]
                if result["xp_bank"] < cost:
                    break
                result["xp_bank"] -= cost
                result["level"] += 1
                result["pending_choices"].append({
                    "uid": f"{uid}:level:{result['level']}",
                    "kind": "LEVEL_UP",
                    "source_event_uid": uid,
                    "earned_level": result["level"],
                })
        else:
            name = "RITUAL_REWARD" if ev["kind"] == "RITUAL_REWARD" else "BREAKTHROUGH"
            result["pending_choices"].append({
                "uid": f"{uid}:{name.lower()}",
                "kind": name,
                "source_event_uid": uid,
            })
    result["paused"] = bool(result["pending_choices"])
    return result


def commit_choice(run: dict, *, choice_uid: str,
                  expected_build_revision: int, selection_token: str,
                  trusted_eligible_tokens: list[str]) -> dict:
    """Static choice coordinator only. Does NOT mutate the real RunBuild.

    In a future runtime the list of trusted eligible IDs must come from
    DraftService/RewardResolver at the CURRENT build revision, not from UI.
    """
    positive(expected_build_revision, "expected_build_revision")
    require(isinstance(selection_token, str) and bool(selection_token),
            "missing selection")
    require(isinstance(trusted_eligible_tokens, list) and
            len(trusted_eligible_tokens) == len(set(trusted_eligible_tokens)) and
            all(isinstance(x, str) and x for x in trusted_eligible_tokens),
            "trusted options invalid")
    require(bool(run["pending_choices"]) and run["paused"],
            "no pending strategic choice")
    front = run["pending_choices"][0]
    require(front["uid"] == choice_uid, "choice commit out of order or already consumed")
    require(run["build_revision"] == expected_build_revision,
            "stale build revision")
    require(selection_token in trusted_eligible_tokens,
            "selection not eligible at current build revision")
    result = copy.deepcopy(run)
    result["pending_choices"].pop(0)
    result["committed_choices"].append({
        "choice_uid": choice_uid,
        "selection_token": selection_token,
        "revision_before": expected_build_revision,
        "revision_after": expected_build_revision + 1,
    })
    result["build_revision"] += 1
    result["paused"] = bool(result["pending_choices"])
    return result


def validate_reference(catalog: dict, canonical: Path = CANONICAL) -> dict:
    require(catalog.get("schema_version") == 1, "sample schema must be 1")
    require(catalog.get("status") == "design-proposal-not-canonical",
            "sample must remain noncanonical")
    require(catalog.get("run_uid", "").startswith("sample."), "sample run UID expected")
    rules = catalog["rules"]
    require(rules["class_id"] in {
        x["id"] for x in load_json(canonical / "classes.json")["classes"]},
        "unknown canonical class ID")
    require(rules["stage_id"] in {
        x["id"] for x in load_json(canonical / "stages.json")["stages"]},
        "unknown canonical stage ID")
    costs = rules["xp_cost_by_level"]
    require(isinstance(costs, list) and costs, "XP cost ladder missing")
    for i, cost in enumerate(costs):
        positive(cost, f"xp_cost[{i}]")
    original = catalog["pickups"]
    reduced = consolidate_pickups(original)
    picked, remaining = collect_pickups(
        reduced, owner_uid=rules["player_uid"], region_id=rules["region_id"],
        x=rules["player_position"]["x"], y=rules["player_position"]["y"],
        radius=rules["pickup_radius"])
    require(sum(x["value"] for x in original) ==
            sum(x["value"] for x in picked + remaining), "pickup value lost")
    events = xp_events_from_pickups(picked, run_uid=catalog["run_uid"], tick=rules["event_tick"],
                                    first_sequence=rules["first_sequence"])
    events += copy.deepcopy(catalog["other_events"])
    state = apply_events(initial_run(catalog), list(reversed(events)), costs)
    expected = catalog["expected"]
    require(state["level"] == expected["level"], "fixture: wrong level")
    require(state["xp_bank"] == expected["xp_bank"], "fixture: XP overflow lost")
    require([x["kind"] for x in state["pending_choices"]] == expected["choice_kinds"],
            "fixture: incorrect strategic choice ordering")
    require(len(reduced) == expected["consolidated_count"],
            "fixture: incorrect consolidation count")
    require(sum(x["value"] for x in picked) == expected["collected_value"],
            "fixture: incorrect collected value")
    require(state["paused"] is True, "fixture: expected paused state")
    for choice in copy.deepcopy(state["pending_choices"]):
        state = commit_choice(state, choice_uid=choice["uid"],
                              expected_build_revision=state["build_revision"],
                              selection_token="sample.option." + choice["kind"].lower(),
                              trusted_eligible_tokens=[
                                  "sample.option." + choice["kind"].lower()])
    require(not state["paused"], "fixture: choices still paused")
    require(not state["pending_choices"], "fixture: pending choices left")
    require(len(state["committed_choices"]) == len(expected["choice_kinds"]),
            "fixture: lost choice")
    return {"original_pickups": len(original), "consolidated_pickups": len(reduced),
            "collected_value": expected["collected_value"],
            "earned_levels": expected["level"] - 1, "choice_count": len(expected["choice_kinds"]),
            "xp_remaining": expected["xp_bank"], "commit_revision": state["build_revision"]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, default=SAMPLE)
    args = parser.parse_args()
    try:
        summary = validate_reference(load_json(args.fixture))
    except (ContractError, KeyError, TypeError, ValueError, OSError) as e:
        parser.exit(1, f"FAIL GAME-ARCH-00/01 proposal: {e}\n")
    print("PASS architecture-only GAME-ARCH-00/01", json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
