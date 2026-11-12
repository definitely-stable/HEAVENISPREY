#!/usr/bin/env python3
"""CHOICE-SAVE-002 — design-only integrated SaveEnvelope v2 for run, build and draft.

Not a Godot save system and not approved balance. It joins two merged design
oracles without changing them:
- SAVE-CONTRACT-001 (strict envelope v1, receipts, legacy choice actions, rules hash);
- DRAFT-CONTRACT-002 (run-scoped draft, offers RNG counter, bans, charges, pity).

Contract points checked here:
1. one authoritative offers cursor: `rng_policy.streams.offers.cursor` equals the
   number of raw draws made by an independent replay; the draft state has no copy;
2. run, build and draft are persisted as one sealed record and must equal replay;
3. lossless migration v1 -> v2, and v1 + DRAFT-002 overlay -> v2 (same result as a
   native v2 replay); unknown versions and guessed RNG state are rejected;
4. stale/duplicate/conflicting commands after reload, idempotent retries;
5. focus survives only as a presentation hint; confirm is never armed after load;
6. two-slot primary/backup store: a torn primary falls back to the last valid save.
Python stdlib only; Ubuntu and Windows CI.
"""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / ".work/proposals/choice-save-002/reference_plan.json"
SCHEMA = 2
KIND = "choice_save_002_snapshot"
STATUS = "design-proposal-not-canonical"
RNG_POLICY_ID = "choice-save-002.streams-v1"
ENVELOPE = {"schema_version", "kind", "status", "header", "rng_policy", "source_manifest",
            "receipts", "legacy_choice_actions", "draft_commands", "state", "presentation",
            "checksum"}
HEADER = {"run_uid", "content_digest", "rules_hash", "draft_policy_hash", "sim_schema_version",
          "rng_policy_id", "digest_policy", "tick", "event_cursor", "phase"}
PERSISTED_DRAFT = {"version", "status", "run_uid", "catalog_digest", "policy_hash", "banned_ids",
                   "rerolls_left", "banishes_left", "pity_misses", "opened_choices", "active",
                   "receipts"}
COMMAND = {"uid", "kind", "offer_id", "expected_hand_revision"}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


draft = load_module("choice_save_draft", ROOT / "scripts/validate_draft_contract_proposal.py")
save = draft.save
builds = draft.builds
loop = draft.loop


class ContractError(ValueError):
    pass


ERRORS = (ContractError, draft.ContractError, save.ContractError, builds.ContractError, loop.ContractError)


def require(ok, message):
    if not ok:
        raise ContractError(message)


# ---------------------------------------------------------------- identity

def rules_identity(rc, bc, policy):
    content_digest, _ = save.rules_identity(rc, bc, {"rng_policy": {"id": RNG_POLICY_ID}})
    policy_hash = save.hash_json(policy)
    rules_hash = save.hash_json({
        "content_digest": content_digest, "sim_schema_version": 1,
        "choice_mode": rc["rules"].get("choice_mode", "IMMEDIATE"),
        "sequence_policy": "per-tick-committed-monotonic-v1",
        "rng_policy_id": RNG_POLICY_ID, "offers_algorithm": draft.ALGO,
        "draft_policy_hash": policy_hash, "build_policy": bc["policy"],
    })
    return content_digest, rules_hash, policy_hash


def rng_policy(save_plan, offers_cursor):
    streams = copy.deepcopy(save_plan["rng_policy"]["streams"])
    streams["offers"]["cursor"] = str(offers_cursor)
    return {"id": RNG_POLICY_ID, "streams": streams}


# ---------------------------------------------------------------- replay

def persisted(bundle_draft):
    return {k: copy.deepcopy(v) for k, v in bundle_draft.items() if k in PERSISTED_DRAFT}


def resolve(bundle, bc, row):
    """Non-draft reward (ritual) through its own trusted resolver, exactly once."""
    require(row["expected_hand_revision"] is None, "RESOLVE has no draft hand revision")
    d, run, build = bundle["draft"], bundle["run"], bundle["build"]
    fingerprint = save.hash_json({k: row[k] for k in sorted(COMMAND)})
    if row["uid"] in d["receipts"]:
        require(d["receipts"][row["uid"]] == fingerprint, "interaction UID conflict")
        return copy.deepcopy(bundle)
    require(d["active"] is None, "close the draft hand before resolving another reward")
    require(bool(run["pending_choices"]) and run["pending_choices"][0]["kind"] == "RITUAL_REWARD",
            "RESOLVE needs a pending ritual reward at the queue front")
    allowed = builds.applicable_recipes(bc, build, "ritual_reward")
    require(row["offer_id"] in allowed, "ritual recipe not applicable")
    result = copy.deepcopy(bundle)
    new_build = builds.apply_recipe(bc, build, row["offer_id"], build["revision"], "ritual_reward")
    new_run = loop.commit_choice(run, choice_uid=run["pending_choices"][0]["uid"],
                                 expected_build_revision=build["revision"],
                                 selection_token=row["offer_id"], trusted_eligible_tokens=allowed)
    require(new_run["build_revision"] == new_build["revision"], "run/build diverged after ritual")
    result["run"], result["build"] = new_run, new_build
    result["draft"]["receipts"][row["uid"]] = fingerprint
    return result


def apply_command(bundle, bc, policy, row):
    require(type(row) is dict and set(row) == COMMAND, "draft command schema invalid")
    if row["kind"] == "RESOLVE":
        return resolve(bundle, bc, row)
    return draft.command(bundle, bc, policy, **row)


def replay(rc, bc, save_plan, policy, receipts, legacy_actions, commands):
    """Independent recomputation: v1 legacy prefix, then the run-scoped draft journal."""
    session, build = save.replay_journal(rc, bc, receipts, legacy_actions)
    anchor = save.hash_json({"run": session, "build": build})
    base = {"header": {"run_uid": session["run_uid"]}, "state": {"run": session, "build": build},
            "checksum": anchor}
    bundle = draft.start(base, bc, policy, save_plan["rng_policy"]["streams"]["offers"]["seed"])
    require(type(commands) is list, "draft journal must be a list")
    seen = set()
    for row in commands:
        require(type(row) is dict and row.get("uid") not in seen, "duplicate interaction UID in journal")
        seen.add(row["uid"])
        bundle = apply_command(bundle, bc, policy, row)
    return bundle


# ---------------------------------------------------------------- envelope

def build_snapshot(rc, bc, save_plan, policy, receipts, legacy_actions, commands, focus_offer=None):
    bundle = replay(rc, bc, save_plan, policy, receipts, legacy_actions, commands)
    content_digest, rules_hash, policy_hash = rules_identity(rc, bc, policy)
    run = bundle["run"]
    doc = {
        "schema_version": SCHEMA, "kind": KIND, "status": STATUS,
        "header": {
            "run_uid": run["run_uid"], "content_digest": content_digest, "rules_hash": rules_hash,
            "draft_policy_hash": policy_hash, "sim_schema_version": 1, "rng_policy_id": RNG_POLICY_ID,
            "digest_policy": save.DIGEST_POLICY, "tick": run["last_tick"],
            "event_cursor": run["last_sequence"],
            "phase": "CHOICE_PAUSED" if run["paused"] else "RUNNING",
        },
        "rng_policy": rng_policy(save_plan, bundle["draft"]["rng"]["counter"]),
        "source_manifest": save.source_manifest(rc),
        "receipts": copy.deepcopy(receipts),
        "legacy_choice_actions": copy.deepcopy(legacy_actions),
        "draft_commands": copy.deepcopy(commands),
        "state": {"run": run, "build": bundle["build"], "draft": persisted(bundle["draft"])},
        "presentation": {"focus_offer": focus_offer},
    }
    check_focus(doc)
    return save.seal(doc)


def check_focus(doc):
    hint = doc["presentation"].get("focus_offer")
    active = doc["state"]["draft"]["active"]
    require(set(doc["presentation"]) == {"focus_offer"}, "unknown presentation fields")
    require(hint is None or (active is not None and hint in active["cards"]),
            "focus hint must name a visible card of the open hand")


def validate(doc, rc, bc, save_plan, policy):
    """Exact schema, identity, single cursor, then full replay; returns the live bundle."""
    require(type(doc) is dict and set(doc) == ENVELOPE, "unsupported v2 envelope")
    require(type(doc["schema_version"]) is int and doc["schema_version"] == SCHEMA,
            "unsupported save schema version")
    require(doc["kind"] == KIND and doc["status"] == STATUS, "not a CHOICE-SAVE-002 design snapshot")
    save.verify_checksum(doc)
    header = doc["header"]
    require(type(header) is dict and set(header) == HEADER, "unknown or missing header field")
    content_digest, rules_hash, policy_hash = rules_identity(rc, bc, policy)
    require(header["content_digest"] == content_digest, "content digest mismatch: refuse silent migration")
    require(header["rules_hash"] == rules_hash, "rules hash mismatch: refuse silent policy migration")
    require(header["draft_policy_hash"] == policy_hash, "draft policy changed: refuse resume")
    require(header["run_uid"] == rc["run_uid"], "save belongs to a different run")
    require(header["rng_policy_id"] == RNG_POLICY_ID and header["digest_policy"] == save.DIGEST_POLICY
            and header["sim_schema_version"] == 1, "policy identity mismatch")
    rng = doc["rng_policy"]
    require(type(rng) is dict and set(rng) == {"id", "streams"} and rng["id"] == RNG_POLICY_ID,
            "unknown RNG policy")
    for name in save.STREAMS:
        stream, planned = rng["streams"][name], save_plan["rng_policy"]["streams"][name]
        require(set(stream) == {"seed", "cursor"} and stream["seed"] == planned["seed"],
                "RNG %s seed differs from run policy" % name)
        draft.decimal_seed(stream["cursor"])
        if name != "offers":
            require(stream["cursor"] == planned["cursor"], "RNG %s cursor not justified by journal" % name)
    require(doc["source_manifest"] == save.source_manifest(rc), "source manifest mismatch")
    bundle = replay(rc, bc, save_plan, policy, doc["receipts"], doc["legacy_choice_actions"],
                    doc["draft_commands"])
    require(rng["streams"]["offers"]["cursor"] == str(bundle["draft"]["rng"]["counter"]),
            "offers cursor differs from replayed draw count")
    state = doc["state"]
    require(type(state) is dict and set(state) == {"run", "build", "draft"}, "unknown state shape")
    require(state["run"] == bundle["run"], "saved run diverges from replay")
    require(state["build"] == bundle["build"], "saved build diverges from replay")
    require(type(state["draft"]) is dict and set(state["draft"]) == PERSISTED_DRAFT,
            "draft state fields invalid (cursor must live only in rng_policy)")
    require(state["draft"] == persisted(bundle["draft"]), "saved draft diverges from replay")
    run = bundle["run"]
    require((header["tick"], header["event_cursor"]) == (run["last_tick"], run["last_sequence"]),
            "header tick/event cursor mismatch")
    require(header["phase"] == ("CHOICE_PAUSED" if run["paused"] else "RUNNING"), "phase mismatch")
    check_focus(doc)
    return bundle


def append(doc, rc, bc, save_plan, policy, row, focus_offer=None):
    """Apply one command to a validated save and return the new sealed save."""
    bundle = validate(doc, rc, bc, save_plan, policy)
    if row["uid"] in {c["uid"] for c in doc["draft_commands"]}:
        apply_command(bundle, bc, policy, row)  # retry: identical -> no-op, conflict -> error
        return copy.deepcopy(doc)
    apply_command(bundle, bc, policy, row)  # reject before journaling
    commands = doc["draft_commands"] + [copy.deepcopy(row)]
    return build_snapshot(rc, bc, save_plan, policy, doc["receipts"], doc["legacy_choice_actions"],
                          commands, focus_offer)


# ---------------------------------------------------------------- migration

def migrate_v1(v1, rc, bc, save_plan, policy, overlay=None):
    """v1 -> v2. Lossless only: no draws before v2 unless a verified DRAFT-002 overlay exists."""
    require(type(v1) is dict and v1.get("schema_version") == save.CURRENT_SCHEMA,
            "only SAVE-CONTRACT-001 v1 can migrate to v2")
    save.validate_snapshot(v1, rc, bc, save_plan)
    commands = []
    if overlay is None:
        require(v1["rng_policy"]["streams"]["offers"]["cursor"] == "0",
                "v1 offers cursor advanced without draft journal: refuse to guess RNG state")
    else:
        bundle = draft.verify_overlay(overlay, v1, rc, bc, save_plan, policy)
        require(overlay["seed"] == save_plan["rng_policy"]["streams"]["offers"]["seed"],
                "overlay seed differs from the authoritative offers stream")
        commands = copy.deepcopy(overlay["commands"])
    doc = build_snapshot(rc, bc, save_plan, policy, v1["receipts"], v1["choice_actions"], commands)
    if overlay is not None:
        state = doc["state"]
        require(state["run"] == bundle["run"] and state["build"] == bundle["build"] and
                state["draft"] == persisted(bundle["draft"]) and
                doc["rng_policy"]["streams"]["offers"]["cursor"] == str(bundle["draft"]["rng"]["counter"]),
                "migrated v2 differs from the verified overlay")
    return doc


def load_any(doc, rc, bc, save_plan, policy):
    version = doc.get("schema_version") if type(doc) is dict else None
    if version == SCHEMA:
        validate(doc, rc, bc, save_plan, policy)
        return doc
    if version == save.CURRENT_SCHEMA:
        return migrate_v1(doc, rc, bc, save_plan, policy)
    raise ContractError("unknown save schema version: %r" % (version,))


# ---------------------------------------------------------------- focus

def restore_focus(doc):
    """Focus survives reload only as a hint; confirm needs a fresh release."""
    active = doc["state"]["draft"]["active"]
    if active is None:
        return None
    return {"choice_uid": active["choice_uid"], "hand_revision": active["hand_revision"],
            "focused_offer": doc["presentation"]["focus_offer"], "confirm_armed": False}


def release_all(focus):
    result = copy.deepcopy(focus)
    result["confirm_armed"] = True
    return result


def confirm(doc, focus, uid):
    active = doc["state"]["draft"]["active"]
    require(focus is not None and active is not None, "no open hand to confirm")
    require(focus["confirm_armed"], "confirm not armed: held input after load must be released")
    require((focus["choice_uid"], focus["hand_revision"]) == (active["choice_uid"], active["hand_revision"]),
            "stale focus session")
    require(focus["focused_offer"] in active["cards"], "no focused visible card")
    return {"uid": uid, "kind": "SELECT", "offer_id": focus["focused_offer"],
            "expected_hand_revision": active["hand_revision"]}


# ---------------------------------------------------------------- two-slot store

def serialize(doc):
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, allow_nan=False)


def parse(text):
    def no_dupes(pairs):
        out = {}
        for key, value in pairs:
            require(key not in out, "duplicate JSON property: " + key)
            out[key] = value
        return out
    return json.loads(text, object_pairs_hook=no_dupes,
                      parse_constant=lambda x: (_ for _ in ()).throw(ContractError("nonfinite " + x)))


def write_slots(store, doc, rc, bc, save_plan, policy):
    """Validate first, keep the previous primary as backup, then replace primary."""
    text = serialize(doc)
    validate(parse(text), rc, bc, save_plan, policy)
    return {"primary": text, "backup": store.get("primary")}


def load_slots(store, rc, bc, save_plan, policy):
    errors = []
    for slot in ("primary", "backup"):
        text = store.get(slot)
        if text is None:
            continue
        try:
            doc = load_any(parse(text), rc, bc, save_plan, policy)
            return doc, slot
        except ERRORS + (ValueError, KeyError, TypeError) as exc:
            errors.append("%s: %s" % (slot, exc))
    raise ContractError("no valid save slot (fail closed): " + "; ".join(errors))


# ---------------------------------------------------------------- fixture

def fixture():
    plan = save.load_json(PLAN)
    require(plan["status"] == STATUS and plan["schema_version"] == 1 and
            plan["kind"] == "choice_save_002_architecture_fixture", "bad CHOICE-SAVE-002 fixture")
    v1, rc, bc, save_plan = save.sample_checkpoint()
    draft_plan = save.load_json(draft.PLAN)
    policy = draft_plan["policy"]
    draft.policy_validate(policy, bc)
    require(draft_plan["seed"] == save_plan["rng_policy"]["streams"]["offers"]["seed"],
            "draft seed and offers stream seed must be one value")
    return plan, v1, rc, bc, save_plan, policy


def run_golden():
    plan, v1, rc, bc, save_plan, policy = fixture()
    ctx = (rc, bc, save_plan, policy)
    doc = migrate_v1(v1, *ctx)
    for row in plan["before_checkpoint"]:
        doc = append(doc, *ctx, row)
    focus_card = doc["state"]["draft"]["active"]["cards"][0]
    doc = build_snapshot(rc, bc, save_plan, policy, doc["receipts"], doc["legacy_choice_actions"],
                         doc["draft_commands"], focus_card)
    checkpoint = doc
    store = write_slots({}, checkpoint, *ctx)
    reloaded, slot = load_slots(store, *ctx)
    require(slot == "primary" and reloaded == checkpoint, "reload changed the save")
    focus = restore_focus(reloaded)
    require(focus["confirm_armed"] is False, "confirm armed after load")
    row = confirm(reloaded, release_all(focus), plan["confirm_uid"])
    resumed = append(reloaded, *ctx, row)
    for row in plan["after_checkpoint"]:
        resumed = append(resumed, *ctx, row)
    direct = build_snapshot(rc, bc, save_plan, policy, v1["receipts"], v1["choice_actions"],
                            resumed["draft_commands"])
    require(direct == resumed, "resume after reload diverged from uninterrupted replay")
    return plan, checkpoint, resumed, store


def verify_fixture():
    plan, checkpoint, final, _ = run_golden()
    expected = plan["expected"]
    hand = checkpoint["state"]["draft"]["active"]
    got = {
        "checkpoint_cards": hand["cards"], "checkpoint_lock": hand["lock"],
        "checkpoint_hand_revision": hand["hand_revision"],
        "checkpoint_offers_cursor": checkpoint["rng_policy"]["streams"]["offers"]["cursor"],
        "final_offers_cursor": final["rng_policy"]["streams"]["offers"]["cursor"],
        "final_build_revision": final["state"]["build"]["revision"],
        "final_banned_ids": final["state"]["draft"]["banned_ids"],
        "final_pending_kinds": [c["kind"] for c in final["state"]["run"]["pending_choices"]],
        "final_state_digest": save.hash_json(final["state"]),
    }
    for key, value in expected.items():
        require(got[key] == value, "golden mismatch %s: expected %r, got %r" % (key, value, got[key]))
    return {k: got[k] for k in ("checkpoint_offers_cursor", "final_offers_cursor", "final_build_revision",
                                "final_pending_kinds")}


def main():
    try:
        result = verify_fixture()
    except ERRORS + (OSError, KeyError, TypeError, ValueError) as exc:
        raise SystemExit("FAIL CHOICE-SAVE-002: %s" % exc)
    print("PASS CHOICE-SAVE-002 design-only", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
