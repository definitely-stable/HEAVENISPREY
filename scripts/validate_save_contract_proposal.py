#!/usr/bin/env python3
"""SAVE-CONTRACT-001: architecture-only replay/checkpoint reference oracle.

This is NOT a Godot save system, a complete combat replay, a secure signature,
a runtime DraftService, or a cross-language canonical JSON implementation.

It binds existing synthetic GAME-ARCH-00/01 event/XP receipts to synthetic
ARCH-01 RunBuild projections, then tests checkpoint→restore→resume invariants.
Uses Python stdlib; intended for Ubuntu and Windows GitHub-hosted CI.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / ".work/proposals/save-contract-001/reference_plan.json"
CURRENT_SCHEMA = 1
KIND = "save_contract_design_snapshot"
STATUS = "design-proposal-not-canonical"
# This is intentionally a Python model digest, NOT RFC 8785/JCS.
DIGEST_POLICY = "reference-python-json-v1"
STREAMS = ("drops", "enemy", "offers", "stage")
MAX_U64 = 2**64 - 1


def load_module(name, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


loop = load_module("save_loop_oracle", ROOT / "scripts/validate_run_loop_proposal.py")
builds = load_module("save_build_oracle", ROOT / "scripts/validate_build_proposal.py")


class ContractError(ValueError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ContractError(message)


def positive(value, name: str) -> None:
    require(type(value) is int and value > 0, f"{name} must be positive integer")


def natural(value, name: str) -> None:
    require(type(value) is int and value >= 0, f"{name} must be nonnegative integer")


def strval(value, name: str) -> None:
    require(isinstance(value, str) and bool(value), f"{name} must be nonblank text")


def load_json(path: Path) -> dict:
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON property: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"),
                      object_pairs_hook=reject_duplicates,
                      parse_constant=lambda x: (_ for _ in ()).throw(
                          ContractError(f"nonfinite number: {x}")))


def copy_json(value):
    # JSON roundtrip rejects NaNs/Infinity and tests serialization boundaries.
    return json.loads(json.dumps(value, ensure_ascii=False, allow_nan=False))


def hash_json(value) -> str:
    data = json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def seal(snapshot: dict) -> dict:
    result = copy.deepcopy(snapshot)
    result.pop("checksum", None)
    result["checksum"] = hash_json(result)
    return result


def verify_checksum(doc: dict) -> None:
    require(type(doc) is dict and "checksum" in doc,
            "missing checkpoint checksum")
    check = doc["checksum"]
    require(type(check) is str and re.fullmatch(r"[0-9a-f]{64}", check) is not None,
            "invalid checkpoint checksum")
    expected = hash_json({k: v for k, v in doc.items() if k != "checksum"})
    require(check == expected, "checkpoint checksum mismatch")


def validate_rng(policy: dict, expected: dict) -> None:
    require(type(policy) is dict and set(policy) == {"id", "streams"},
            "unknown RNG policy fields")
    require(policy["id"] == expected["id"],
            "RNG algorithm/policy version mismatch")
    require(type(policy["streams"]) is dict and
            set(policy["streams"]) == set(STREAMS),
            "named RNG stream set mismatch")
    for name in STREAMS:
        stream = policy["streams"][name]
        original = expected["streams"][name]
        require(type(stream) is dict and set(stream) == {"seed", "cursor"},
                f"RNG stream fields invalid: {name}")
        for field in ("seed", "cursor"):
            value = stream[field]
            require(type(value) is str and re.fullmatch(r"(0|[1-9][0-9]*)", value) is not None,
                    f"RNG {name}.{field} must be unsigned decimal string")
            require(int(value) <= MAX_U64, f"RNG {name}.{field} overflow")
        require(stream["seed"] == original["seed"],
                f"RNG {name} seed differs from run policy")
        # The reference does not advance gameplay RNG; a nonzero cursor
        # cannot be justified by an event recorded by this minimal oracle.
        require(stream["cursor"] == original["cursor"],
                f"RNG {name} cursor not justified by reference event log")


def source_manifest(run_catalog: dict) -> dict:
    """Trusted synthetic authored drops; never read authoritative amounts from UI."""
    result = {}
    for item in run_catalog["pickups"]:
        if item["kind"] != "XP":
            continue
        require(len(item["source_uids"]) == 1,
                "reference requires one independent source per raw pickup")
        uid = item["source_uids"][0]
        require(uid not in result, f"duplicate source manifest entry: {uid}")
        positive(item["value"], "manifest XP")
        result[uid] = item["value"]
    return result


def trusted_receipts(run_catalog: dict) -> list[dict]:
    rules = run_catalog["rules"]
    compact = loop.consolidate_pickups(run_catalog["pickups"])
    collected, _ = loop.collect_pickups(
        compact, owner_uid=rules["player_uid"], region_id=rules["region_id"],
        x=rules["player_position"]["x"], y=rules["player_position"]["y"],
        radius=rules["pickup_radius"])
    events = loop.xp_events_from_pickups(
        collected, run_uid=run_catalog["run_uid"], tick=rules["event_tick"],
        first_sequence=rules["first_sequence"]) + copy.deepcopy(run_catalog["other_events"])
    return sorted(events, key=loop.event_order_key)


def rules_identity(run_catalog: dict, build_catalog: dict, plan: dict) -> tuple[str, str]:
    """Reference-only, reproducible *within Python* for this synthetic fixture.

    Production needs a formally selected cross-platform canonicalization and
    typed content schema. Presentation-only prefs must be identified as such.
    """
    rules = run_catalog["rules"]
    content_digest = hash_json({
        "run_schema_version": run_catalog["schema_version"],
        "build_catalog": build_catalog,
        "class_id": rules["class_id"],
        "stage_id": rules["stage_id"],
        "xp_cost_by_level": rules["xp_cost_by_level"],
    })
    rules_digest = hash_json({
        "content_digest": content_digest,
        "sim_schema_version": 1,
        "choice_mode": rules.get("choice_mode", "IMMEDIATE"),
        "sequence_policy": "per-tick-committed-monotonic-v1",
        "rng_policy_id": plan["rng_policy"]["id"],
        "build_policy": build_catalog["policy"],
    })
    return content_digest, rules_digest


def baseline(run_catalog: dict, build_catalog: dict) -> tuple[dict, dict]:
    original = next(copy.deepcopy(entry["build"]) for entry in build_catalog["witnesses"]
                    if entry["id"] == "sample.witness.not_ready")
    builds.validate_build(original, builds.tables_for(build_catalog),
                          build_catalog["policy"])
    run = loop.initial_run(run_catalog)
    # Deliberately align two independent synthetic fixture versions.
    # In a future engine, RunBuild has one authoritative revision.
    run["build_revision"] = original["revision"]
    return run, original


def replay_journal(run_catalog: dict, build_catalog: dict,
                   receipts: list[dict], actions: list[dict]) -> tuple[dict, dict]:
    """Recompute checkpoint from trusted fixture and recorded actions.

    This is stronger than merely comparing a self-reported state checksum.
    Claims of physical pickup/movement fairness or independent gameplay RNG
    are explicitly out of scope.
    """
    require(type(receipts) is list and type(actions) is list,
            "invalid replay journal")
    require(all(type(event) is dict and isinstance(event.get("uid"), str)
                for event in receipts), "invalid receipt envelope")
    require(len({event["uid"] for event in receipts}) == len(receipts),
            "duplicate receipt UID in journal")
    ordered = sorted(receipts, key=loop.event_order_key)
    require(ordered == receipts, "receipt journal not in committed event order")
    require(receipts == trusted_receipts(run_catalog),
            "receipt journal differs from trusted synthetic source fixture")
    loop.verify_xp_source_values(receipts, source_manifest(run_catalog))
    session, build = baseline(run_catalog, build_catalog)
    session = loop.apply_events(session, receipts,
                                run_catalog["rules"]["xp_cost_by_level"])
    seen_choice_uids = set()
    for action in actions:
        require(type(action) is dict and set(action) ==
                {"choice_uid", "expected_revision", "selection_token"},
                "choice action contract invalid")
        strval(action["choice_uid"], "choice UID")
        strval(action["selection_token"], "selection")
        positive(action["expected_revision"], "expected_revision")
        require(action["choice_uid"] not in seen_choice_uids,
                "duplicate choice action UID")
        seen_choice_uids.add(action["choice_uid"])
        require(bool(session["pending_choices"]), "choice without earned reward")
        front = session["pending_choices"][0]
        require(front["uid"] == action["choice_uid"],
                "stale or out-of-order choice action")
        require(build["revision"] == action["expected_revision"],
                "stale choice/build revision")
        token = action["selection_token"]
        if front["kind"] == "LEVEL_UP":
            allowed = builds.eligible_offers(build_catalog, build)
            require(token in allowed, "ineligible upgrade offer on replay")
            new_build = builds.apply_upgrade_offer(
                build_catalog, build, token, build["revision"])
        elif front["kind"] == "RITUAL_REWARD":
            allowed = builds.applicable_recipes(build_catalog, build, "ritual_reward")
            require(token in allowed, "ineligible ritual on replay")
            new_build = builds.apply_recipe(
                build_catalog, build, token, build["revision"], "ritual_reward")
        else:
            raise ContractError("BREAKTHROUGH replay lacks a trusted resolver")
        new_run = loop.commit_choice(
            session, choice_uid=action["choice_uid"],
            expected_build_revision=action["expected_revision"],
            selection_token=token, trusted_eligible_tokens=allowed)
        require(new_run["build_revision"] == new_build["revision"],
                "run/build revisions diverged after replayed choice")
        session, build = new_run, new_build
    return session, build


def snapshot_from_journal(run_catalog: dict, build_catalog: dict,
                          plan: dict, receipts: list[dict],
                          actions: list[dict]) -> dict:
    session, build = replay_journal(run_catalog, build_catalog, receipts, actions)
    content_digest, rules_hash = rules_identity(run_catalog, build_catalog, plan)
    policy = copy.deepcopy(plan["rng_policy"])
    validate_rng(policy, plan["rng_policy"])
    doc = {
        "schema_version": CURRENT_SCHEMA,
        "kind": KIND, "status": STATUS,
        "header": {
            "run_uid": session["run_uid"],
            "content_digest": content_digest,
            "rules_hash": rules_hash,
            "sim_schema_version": 1,
            "rng_policy_id": policy["id"],
            "digest_policy": DIGEST_POLICY,
            "tick": session["last_tick"],
            "event_cursor": session["last_sequence"],
            "phase": "CHOICE_PAUSED" if session["paused"] else "RUNNING",
        },
        "rng_policy": policy,
        "source_manifest": source_manifest(run_catalog),
        "receipts": copy.deepcopy(receipts),
        "choice_actions": copy.deepcopy(actions),
        "state": {"run": session, "build": build},
    }
    return seal(doc)


def validate_snapshot(snapshot: dict, run_catalog: dict,
                      build_catalog: dict, plan: dict) -> tuple[dict, dict]:
    """Exact schema and evidence, then independent model replay.

    A checksum detects accidental changes, not deliberate adversarial edits:
    JSON on the user's PC has no secret signing key.
    """
    require(type(snapshot) is dict and set(snapshot) == {
        "schema_version", "kind", "status", "header", "rng_policy",
        "source_manifest", "receipts", "choice_actions", "state", "checksum",
    }, "unsupported snapshot envelope")
    require(type(snapshot["schema_version"]) is int and
            snapshot["schema_version"] == CURRENT_SCHEMA,
            "unsupported snapshot schema")
    require(snapshot["kind"] == KIND and snapshot["status"] == STATUS,
            "snapshot is not an architecture-only fixture")
    verify_checksum(snapshot)
    header = snapshot["header"]
    require(type(header) is dict and set(header) == {
        "run_uid", "content_digest", "rules_hash", "sim_schema_version",
        "rng_policy_id", "digest_policy", "tick", "event_cursor", "phase",
    }, "unknown or missing snapshot header")
    expected_content, expected_rules = rules_identity(
        run_catalog, build_catalog, plan)
    require(header["content_digest"] == expected_content,
            "content digest mismatch: refuse silent rule migration")
    require(header["rules_hash"] == expected_rules,
            "rules hash mismatch: refuse silent policy migration")
    require(header["run_uid"] == run_catalog["run_uid"],
            "checkpoint belongs to different run")
    require(type(header["sim_schema_version"]) is int and
            header["sim_schema_version"] == 1, "simulation schema mismatch")
    require(header["digest_policy"] == DIGEST_POLICY,
            "digest policy mismatch")
    require(header["rng_policy_id"] == plan["rng_policy"]["id"],
            "RNG policy mismatch")
    natural(header["tick"], "snapshot tick")
    natural(header["event_cursor"], "event cursor")
    require(header["phase"] in {"RUNNING", "CHOICE_PAUSED"},
            "invalid phase")
    validate_rng(snapshot["rng_policy"], plan["rng_policy"])
    require(snapshot["source_manifest"] == source_manifest(run_catalog),
            "source manifest mismatch")
    reconstructed_run, reconstructed_build = replay_journal(
        run_catalog, build_catalog,
        snapshot["receipts"], snapshot["choice_actions"])
    require(type(snapshot["state"]) is dict and set(snapshot["state"]) == {"run", "build"},
            "unknown snapshot state shape")
    require(reconstructed_run == snapshot["state"]["run"],
            "saved run state diverges from replay")
    require(reconstructed_build == snapshot["state"]["build"],
            "saved build state diverges from replay")
    require(header["tick"] == reconstructed_run["last_tick"],
            "snapshot tick mismatch")
    require(header["event_cursor"] == reconstructed_run["last_sequence"],
            "snapshot event cursor mismatch")
    phase = "CHOICE_PAUSED" if reconstructed_run["paused"] else "RUNNING"
    require(header["phase"] == phase, "paused/running phase mismatch")
    return copy.deepcopy(reconstructed_run), copy.deepcopy(reconstructed_build)


def choose(snapshot: dict, token: str, run_catalog: dict,
           build_catalog: dict, plan: dict) -> dict:
    session, _ = validate_snapshot(snapshot, run_catalog, build_catalog, plan)
    require(bool(session["pending_choices"]),
            "cannot select without pending earned choice")
    choice = session["pending_choices"][0]
    actions = copy.deepcopy(snapshot["choice_actions"])
    actions.append({
        "choice_uid": choice["uid"],
        "expected_revision": session["build_revision"],
        "selection_token": token,
    })
    new_snapshot = snapshot_from_journal(
        run_catalog, build_catalog, plan, snapshot["receipts"], actions)
    validate_snapshot(new_snapshot, run_catalog, build_catalog, plan)
    return new_snapshot


def migrate_legacy_header_v0(legacy: dict, run_catalog: dict,
                             build_catalog: dict, plan: dict) -> dict:
    """Only a *known, lossless* v0 header rename; no guessing missing data."""
    require(type(legacy) is dict and legacy.get("schema_version") == 0,
            "unsupported legacy save schema")
    verify_checksum(legacy)
    migrated = copy.deepcopy(legacy)
    require(type(migrated.get("header")) is dict and
            "captured_tick" in migrated["header"] and
            "tick" not in migrated["header"],
            "legacy captured_tick missing or ambiguous")
    migrated["header"]["tick"] = migrated["header"].pop("captured_tick")
    migrated["schema_version"] = 1
    migrated = seal(migrated)
    validate_snapshot(migrated, run_catalog, build_catalog, plan)
    return migrated


def sample_checkpoint() -> tuple[dict, dict, dict, dict]:
    plan = load_json(PLAN)
    require(plan["schema_version"] == 1 and
            plan["status"] == "design-proposal-not-canonical" and
            plan["kind"] == "save_contract_architecture_fixture",
            "bad save architecture fixture")
    run_catalog = loop.load_json(loop.SAMPLE)
    build_catalog = builds.load_json(builds.SAMPLE)
    receipts = trusted_receipts(run_catalog)
    checkpoint = snapshot_from_journal(
        run_catalog, build_catalog, plan, receipts, [])
    for token in plan["checkpoint_choice_tokens"]:
        checkpoint = choose(checkpoint, token, run_catalog, build_catalog, plan)
    return checkpoint, run_catalog, build_catalog, plan


def verify_fixture() -> dict:
    checkpoint, rc, bc, plan = sample_checkpoint()
    original = copy.deepcopy(checkpoint)
    initial, _ = replay_journal(rc, bc, checkpoint["receipts"], [])
    require(len(initial["pending_choices"]) == plan["expected"]["initial_pending"],
            "fixture initial queue mismatch")
    run, build = validate_snapshot(checkpoint, rc, bc, plan)
    require(len(run["pending_choices"]) == plan["expected"]["checkpoint_pending"],
            "fixture checkpoint queue mismatch")
    require(run["build_revision"] == plan["expected"]["checkpoint_build_revision"],
            "fixture checkpoint build rev mismatch")
    serialized = json.dumps(checkpoint, ensure_ascii=False, sort_keys=True,
                            allow_nan=False)
    restored = json.loads(serialized)
    validate_snapshot(restored, rc, bc, plan)
    for token in plan["resume_choice_tokens"]:
        restored = choose(restored, token, rc, bc, plan)
    final_run, final_build = validate_snapshot(restored, rc, bc, plan)
    expected = plan["expected"]
    require(final_run["build_revision"] == expected["after_resume_build_revision"],
            "fixture final revision mismatch")
    require([c["kind"] for c in final_run["pending_choices"]] ==
            expected["remaining_choice_kinds"], "fixture remaining queue mismatch")
    require(any(x["id"] == expected["expected_evolved_skill"]
                for x in final_build["active"]),
            "fixture evolution not reached")
    require(final_run["xp_bank"] == expected["remaining_xp"],
            "fixture XP bank was lost")
    require(sum(checkpoint["source_manifest"][uid]
                for uid in final_run["claimed_xp_sources"]) ==
            expected["credited_xp"], "fixture source XP conservation mismatch")
    require(checkpoint == original, "fixture checkpoint mutated by replay")
    # Compare with uninterrupted *synthetic* replay from original receipts.
    direct_actions = restored["choice_actions"]
    direct_run, direct_build = replay_journal(
        rc, bc, checkpoint["receipts"], direct_actions)
    require((direct_run, direct_build) == (final_run, final_build),
            "checkpoint resume diverged from uninterrupted model replay")
    return {
        "checkpoint_pending": len(run["pending_choices"]),
        "checkpoint_revision": run["build_revision"],
        "final_revision": final_run["build_revision"],
        "remaining_choices": len(final_run["pending_choices"]),
        "credited_xp": expected["credited_xp"],
        "content_bound": True,
        "same_as_uninterrupted": True,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, default=PLAN)
    args = parser.parse_args()
    # CLI fixture can be used only as reference source; no arbitrary gameplay.
    require(args.fixture.resolve() == PLAN.resolve(),
            "custom save fixtures must be tested via import/test API")
    try:
        result = verify_fixture()
    except (ContractError, loop.ContractError, builds.ContractError,
            OSError, KeyError, TypeError, ValueError) as ex:
        parser.exit(1, f"FAIL SAVE-CONTRACT-001 reference: {ex}\n")
    print("PASS SAVE-CONTRACT-001 architecture-only", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
