#!/usr/bin/env python3
"""DRAFT-CONTRACT-002 — design-only, run-scoped, reproducible draft oracle.

No Godot, no production DraftService, no approved balance. It uses current
BUILD-SKILL-001 eligibility and SAVE-CONTRACT-001 synthetic checkpoint.
SHA256 counter bytes and integer rejection sampling are explicit protocol
candidates; future GDScript parity and integrated SAVE migration remain open.
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
PLAN = ROOT / ".work/proposals/draft-contract-002/reference_plan.json"
SCOPE = "design-proposal-not-canonical"
ALGO = "sha256-counter-rejection-v1"
PREFIX = b"HEAVENISPREY/DRAFT-CONTRACT-002/v1\x00"
UINT64_MAX = (1 << 64) - 1
DRAW_RANGE = 1 << 256
OPS = {"OPEN", "REROLL", "BANISH", "LOCK", "UNLOCK", "SELECT", "SKIP"}
FIELDS = {"version", "status", "run_uid", "base_checksum", "catalog_digest",
          "policy_hash", "rng", "banned_ids", "rerolls_left", "banishes_left",
          "pity_misses", "opened_choices", "active", "receipts"}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


save = load_module("draft_save_contract", ROOT / "scripts/validate_save_contract_proposal.py")
builds = save.builds
loop = save.loop


class ContractError(ValueError):
    pass


def require(test, reason):
    if not test:
        raise ContractError(reason)


def integer(value, name, *, low=0, high=UINT64_MAX):
    require(type(value) is int and low <= value <= high, f"{name}: invalid bounded integer")


def string(value, name):
    require(type(value) is str and bool(value), f"{name}: invalid string")


def decimal_seed(value):
    string(value, "seed")
    require(re.fullmatch(r"(0|[1-9][0-9]*)", value) is not None and
            int(value) <= UINT64_MAX, "seed must be canonical uint64 decimal")


def hash_value(value):
    return save.hash_json(value)


def policy_validate(policy, catalog):
    require(type(policy) is dict and set(policy) == {
        "version", "algorithm", "hand_size", "rerolls", "banishes",
        "pity_after", "protected_ids", "empty_policy",
    }, "draft policy schema invalid")
    require(type(policy["version"]) is int and policy["version"] == 1,
            "draft policy version unsupported")
    require(policy["algorithm"] == ALGO, "draft RNG algorithm unsupported")
    for field in ("hand_size", "pity_after"):
        integer(policy[field], field, low=1)
    for field in ("rerolls", "banishes"):
        integer(policy[field], field)
    require(policy["empty_policy"] == "EXPLICIT_SKIP",
            "draft empty-pool fallback not implemented")
    ids = [x["id"] for x in catalog["offers"]]
    require(len(ids) == len(set(ids)), "duplicate offer definition ID")
    for x in catalog["offers"]:
        integer(x["weight"], "weight", low=1, high=2**32 - 1)
    require(type(policy["protected_ids"]) is list and
            policy["protected_ids"] == sorted(set(policy["protected_ids"])) and
            set(policy["protected_ids"]) <= set(ids),
            "protected IDs must be known canonical-sorted offers")
    require(sum(x["weight"] for x in catalog["offers"]) <= UINT64_MAX,
            "catalog total weight overflows 64-bit contract")


def encode_piece(value):
    part = value.encode("utf-8")
    require(len(part) < 2**32, "RNG input too long")
    return len(part).to_bytes(4, "big") + part


def raw256(state, choice_uid):
    rng = state["rng"]
    decimal_seed(rng["seed"])
    integer(rng["counter"], "RNG counter")
    require(rng["counter"] < UINT64_MAX, "RNG counter exhausted")
    # Exact domain separation and bytes; no JSON key-order or platform hash.
    msg = (PREFIX + encode_piece(state["run_uid"]) +
           encode_piece(rng["seed"]) + encode_piece("offers") +
           encode_piece(choice_uid) +
           rng["counter"].to_bytes(8, "big"))
    value = int.from_bytes(hashlib.sha256(msg).digest(), "big")
    rng["counter"] += 1
    return value


def unbiased_mod(raw, upper):
    """Returns None for the rejection tail; never map arbitrary modulo bytes.

    Random uniform 256-bit values yield exactly uniform [0, upper) after
    rejection if the hash stream is modeled as uniform. This does not prove
    empirical game balance or that cryptography is necessary at runtime.
    """
    integer(upper, "total integer weight", low=1)
    require(type(raw) is int and 0 <= raw < DRAW_RANGE,
            "raw draw outside 256-bit range")
    bound = DRAW_RANGE - DRAW_RANGE % upper
    return raw % upper if raw < bound else None


def below(state, choice_uid, upper):
    while True:
        sample = unbiased_mod(raw256(state, choice_uid), upper)
        if sample is not None:
            return sample


def weighted_one(state, choice_uid, candidates, weights):
    require(type(candidates) is list and candidates == sorted(set(candidates)) and
            bool(candidates), "draw candidates must be stable sorted unique IDs")
    total = 0
    for uid in candidates:
        integer(weights[uid], "selected offer weight", low=1, high=2**32-1)
        total += weights[uid]
    integer(total, "total candidate weight", low=1)
    roll = below(state, choice_uid, total)
    for uid in candidates:
        roll -= weights[uid]
        if roll < 0:
            return uid
    raise ContractError("weight traversal inconsistency")


def weights_for(catalog):
    return {offer["id"]: offer["weight"] for offer in catalog["offers"]}


def valid_ids(catalog, build, bans):
    """One source of truth: reuse BUILD-SKILL eligible_offers."""
    return sorted(set(builds.eligible_offers(catalog, build)) - set(bans))


def empty_reason(catalog, build, bans):
    legal = builds.eligible_offers(catalog, build)
    if not legal:
        return "NO_BUILD_ELIGIBLE_OFFERS"
    if not valid_ids(catalog, build, bans):
        return "ALL_ELIGIBLE_BANNED"
    return None


def fill(state, catalog, build, choice_uid, existing, *, fresh_from=()):
    weights = weights_for(catalog)
    pool = valid_ids(catalog, build, state["banned_ids"])
    hand = list(existing)
    need = min(state["policy_hand_size"], len(pool))
    require(set(hand) <= set(pool) and len(hand) <= need,
            "hand contains ineligible offers or exceeds policy")
    # On paid reroll first draw one genuinely previously unseen legal offer,
    # then refill remaining slots from all eligible choices.
    fresh = sorted(set(pool) - set(fresh_from) - set(hand))
    if fresh and len(hand) < need:
        hand.append(weighted_one(state, choice_uid, fresh, weights))
    while len(hand) < need:
        candidates = sorted(set(pool) - set(hand))
        hand.append(weighted_one(state, choice_uid, candidates, weights))
    return hand


def start(base, catalog, policy, seed):
    policy_validate(policy, catalog)
    decimal_seed(seed)
    run, build = base["state"]["run"], base["state"]["build"]
    require(run["run_uid"] == base["header"]["run_uid"] and
            run["build_revision"] == build["revision"], "base run/build mismatch")
    return {
        "run": copy.deepcopy(run), "build": copy.deepcopy(build),
        "draft": {
            "version": 1, "status": SCOPE, "run_uid": run["run_uid"],
            "base_checksum": base["checksum"],
            "catalog_digest": hash_value(catalog),
            "policy_hash": hash_value(policy),
            "rng": {"algorithm": ALGO, "seed": seed, "counter": 0},
            "banned_ids": [], "rerolls_left": policy["rerolls"],
            "banishes_left": policy["banishes"],
            "pity_misses": 0, "opened_choices": 0,
            "active": None, "receipts": {},
        }
    }


def validate_bundle(bundle, catalog, policy, base_checksum):
    require(type(bundle) is dict and set(bundle) == {"run", "build", "draft"},
            "draft bundle schema invalid")
    d, run, build = bundle["draft"], bundle["run"], bundle["build"]
    require(type(d) is dict and set(d) == FIELDS, "draft run-state fields invalid")
    require(d["version"] == 1 and d["status"] == SCOPE,
            "draft state version/status mismatch")
    require(d["run_uid"] == run["run_uid"] and
            d["base_checksum"] == base_checksum, "draft owner/checkpoint mismatch")
    require(d["catalog_digest"] == hash_value(catalog) and
            d["policy_hash"] == hash_value(policy),
            "draft policy/catalog version mismatch")
    require(d["rng"]["algorithm"] == ALGO, "draft RNG algorithm mismatch")
    decimal_seed(d["rng"]["seed"])
    integer(d["rng"]["counter"], "RNG counter")
    for key in ("rerolls_left", "banishes_left", "pity_misses", "opened_choices"):
        integer(d[key], key)
    require(d["rerolls_left"] <= policy["rerolls"] and
            d["banishes_left"] <= policy["banishes"],
            "draft charges exceed run policy")
    all_ids = {x["id"] for x in catalog["offers"]}
    bans = d["banned_ids"]
    require(type(bans) is list and bans == sorted(set(bans)) and
            set(bans) <= all_ids, "persistent bans invalid")
    require(type(d["receipts"]) is dict, "draft receipt ledger invalid")
    require(run["build_revision"] == build["revision"],
            "draft and build revision diverged")
    if d["active"] is not None:
        hand = d["active"]
        require(type(hand) is dict and set(hand) == {
            "choice_uid", "source_event_uid", "build_revision", "hand_revision",
            "cards", "lock", "forced_pity", "fallback_reason",
        }, "active hand schema invalid")
        require(run["paused"] and bool(run["pending_choices"]) and
                run["pending_choices"][0]["kind"] == "LEVEL_UP",
                "active draft has no paused earned level choice")
        front = run["pending_choices"][0]
        require((hand["choice_uid"], hand["source_event_uid"]) ==
                (front["uid"], front["source_event_uid"]),
                "active hand bound to different reward source")
        require(hand["build_revision"] == build["revision"],
                "active hand bound to stale build")
        integer(hand["hand_revision"], "hand revision", low=1)
        cards = hand["cards"]
        require(type(cards) is list and len(cards) == len(set(cards)),
                "duplicate hand card")
        require(set(cards) <= set(valid_ids(catalog, build, bans)) and
                len(cards) <= policy["hand_size"], "hand has invalid offer or size")
        require(hand["lock"] is None or hand["lock"] in cards,
                "locked card no longer visible")


def _open(bundle, catalog, policy):
    d, run, build = bundle["draft"], bundle["run"], bundle["build"]
    require(d["active"] is None, "choice hand already open")
    require(bool(run["pending_choices"]) and run["paused"] and
            run["pending_choices"][0]["kind"] == "LEVEL_UP",
            "only paused ordinary level reward opens draft hand")
    front = run["pending_choices"][0]
    eligible = valid_ids(catalog, build, d["banned_ids"])
    protected = sorted(set(eligible) & set(policy["protected_ids"]))
    forced = bool(protected and d["pity_misses"] >= policy["pity_after"] - 1)
    # No worldwide pity guarantee: only when currently legal.
    d["policy_hand_size"] = policy["hand_size"]
    cards = []
    if forced:
        cards.append(weighted_one(d, front["uid"], protected, weights_for(catalog)))
    cards = fill(d, catalog, build, front["uid"], cards)
    d.pop("policy_hand_size")
    if protected:
        d["pity_misses"] = 0 if set(cards) & set(protected) else d["pity_misses"] + 1
    d["opened_choices"] += 1
    d["active"] = {
        "choice_uid": front["uid"], "source_event_uid": front["source_event_uid"],
        "build_revision": build["revision"], "hand_revision": 1,
        "cards": cards, "lock": None, "forced_pity": forced,
        "fallback_reason": empty_reason(catalog, build, d["banned_ids"]),
    }


def _act(bundle, catalog, policy, kind, offer):
    d, run, build = bundle["draft"], bundle["run"], bundle["build"]
    h = d["active"]
    require(h is not None, "no active hand to update")
    if kind == "REROLL":
        require(offer is None, "REROLL cannot specify target")
        require(d["rerolls_left"] > 0, "no rerolls available")
        pool = set(valid_ids(catalog, build, d["banned_ids"]))
        old = set(h["cards"])
        require(len(h["cards"]) > int(h["lock"] is not None),
                "locked hand has no free slot")
        require(bool(pool - old), "reroll cannot show a new legal offer")
        d["rerolls_left"] -= 1
        d["policy_hand_size"] = policy["hand_size"]
        locked = [h["lock"]] if h["lock"] else []
        h["cards"] = fill(d, catalog, build, h["choice_uid"], locked,
                          fresh_from=old)
        d.pop("policy_hand_size")
    elif kind == "BANISH":
        require(offer in h["cards"], "banish requires visible offer")
        require(offer != h["lock"], "unlock before banishing")
        require(d["banishes_left"] > 0, "no banish charges")
        d["banishes_left"] -= 1
        d["banned_ids"] = sorted(set(d["banned_ids"]) | {offer})
        h["cards"] = [x for x in h["cards"] if x != offer]
        d["policy_hand_size"] = policy["hand_size"]
        retained = h["cards"][:]
        h["cards"] = fill(d, catalog, build, h["choice_uid"], retained)
        d.pop("policy_hand_size")
        h["fallback_reason"] = empty_reason(catalog, build, d["banned_ids"])
    elif kind == "LOCK":
        require(offer in h["cards"], "lock requires visible card")
        require(h["lock"] in (None, offer), "another card already locked")
        h["lock"] = offer
    elif kind == "UNLOCK":
        require(h["lock"] is not None, "nothing locked")
        require(offer is None or offer == h["lock"], "unlock target mismatch")
        h["lock"] = None
    else:
        raise ContractError("unknown draft modification")
    h["hand_revision"] += 1


def _commit(bundle, catalog, kind, offer):
    d, run, build = bundle["draft"], bundle["run"], bundle["build"]
    h = d["active"]
    require(h is not None, "cannot commit without open hand")
    if kind == "SELECT":
        require(offer in h["cards"], "selected offer is not displayed")
        require(offer in valid_ids(catalog, build, d["banned_ids"]),
                "selected offer no longer eligible")
        b2 = builds.apply_upgrade_offer(catalog, build, offer, build["revision"])
        selected = offer
    else:
        require(offer is None, "SKIP must not select a card")
        selected = "sample.choice.explicit_skip"
        b2 = copy.deepcopy(build)
        b2["revision"] += 1
        builds.validate_build(b2, builds.tables_for(catalog), catalog["policy"])
    r2 = loop.commit_choice(
        run, choice_uid=h["choice_uid"], expected_build_revision=build["revision"],
        selection_token=selected, trusted_eligible_tokens=[selected])
    require(r2["build_revision"] == b2["revision"],
            "run and build committed different revisions")
    bundle["run"], bundle["build"] = r2, b2
    d["active"] = None
    # Banish persists across hands; lock and any held VFX focus never do.


def command(bundle, catalog, policy, *, uid, kind, offer_id=None,
            expected_hand_revision=None):
    """Retry-safe one-command state transition; no in-place mutation."""
    string(uid, "interaction UID")
    require(kind in OPS, "unknown draft operation")
    validate_bundle(bundle, catalog, policy, bundle["draft"]["base_checksum"])
    d = bundle["draft"]
    fingerprint = hash_value({
        "uid": uid, "kind": kind, "offer_id": offer_id,
        "expected_hand_revision": expected_hand_revision,
    })
    if uid in d["receipts"]:
        require(d["receipts"][uid] == fingerprint,
                "interaction UID conflict")
        return copy.deepcopy(bundle)
    result = copy.deepcopy(bundle)
    draft = result["draft"]
    if kind == "OPEN":
        require(offer_id is None and expected_hand_revision is None,
                "OPEN must not refer to a prior card revision")
        _open(result, catalog, policy)
    else:
        hand = draft["active"]
        require(hand is not None, "no active draft hand")
        integer(expected_hand_revision, "expected hand revision", low=1)
        require(expected_hand_revision == hand["hand_revision"],
                "stale draft hand revision")
        if kind in {"SELECT", "SKIP"}:
            _commit(result, catalog, kind, offer_id)
        else:
            _act(result, catalog, policy, kind, offer_id)
    result["draft"]["receipts"][uid] = fingerprint
    validate_bundle(result, catalog, policy, result["draft"]["base_checksum"])
    return result


def view(bundle, catalog, policy):
    validate_bundle(bundle, catalog, policy, bundle["draft"]["base_checksum"])
    d = bundle["draft"]
    h = d["active"]
    require(h is not None, "no open hand")
    pool = valid_ids(catalog, bundle["build"], d["banned_ids"])
    can_reroll = bool(d["rerolls_left"] and
                      len(h["cards"]) > int(h["lock"] is not None) and
                      set(pool) - set(h["cards"]))
    return {
        "choice_uid": h["choice_uid"], "source_event_uid": h["source_event_uid"],
        "build_revision": h["build_revision"],
        "hand_revision": h["hand_revision"], "cards": copy.deepcopy(h["cards"]),
        "banned_ids": copy.deepcopy(d["banned_ids"]),
        "rerolls_left": d["rerolls_left"], "banishes_left": d["banishes_left"],
        "can_reroll": can_reroll,
        "fallback_reason": h["fallback_reason"],
        "fallback_requires_explicit_action": h["fallback_reason"] is not None,
        "pity_guarantee_applied": h["forced_pity"],
        "pity_misses": d["pity_misses"],
    }


def seal_overlay(base, catalog, policy, seed, commands, bundle):
    doc = {
        "schema_version": 1, "kind": "draft_contract_002_overlay",
        "status": SCOPE,
        "base_save_checksum": base["checksum"],
        "catalog_digest": hash_value(catalog),
        "policy_digest": hash_value(policy),
        "rng_algorithm": ALGO,
        "seed": seed,
        "commands": copy.deepcopy(commands),
        "bundle": copy.deepcopy(bundle),
    }
    doc["checksum"] = hash_value(doc)
    return doc


def verify_overlay(doc, base, run_catalog, catalog, save_plan, policy):
    save.validate_snapshot(base, run_catalog, catalog, save_plan)
    require(type(doc) is dict and set(doc) == {
        "schema_version", "kind", "status", "base_save_checksum", "catalog_digest",
        "policy_digest", "rng_algorithm", "seed", "commands", "bundle", "checksum",
    }, "draft overlay schema invalid")
    require(type(doc["schema_version"]) is int and doc["schema_version"] == 1 and
            doc["kind"] == "draft_contract_002_overlay" and
            doc["status"] == SCOPE, "draft overlay version or status mismatch")
    require(doc["checksum"] == hash_value({
        k: v for k, v in doc.items() if k != "checksum"
    }), "draft overlay checksum mismatch")
    require(doc["base_save_checksum"] == base["checksum"],
            "draft overlay attached to different base save")
    require(doc["catalog_digest"] == hash_value(catalog) and
            doc["policy_digest"] == hash_value(policy) and
            doc["rng_algorithm"] == ALGO,
            "draft catalog/policy/RNG version mismatch")
    decimal_seed(doc["seed"])
    require(type(doc["commands"]) is list, "draft commands not a list")
    current = start(base, catalog, policy, doc["seed"])
    seen = set()
    for row in doc["commands"]:
        require(type(row) is dict and set(row) == {
            "uid", "kind", "offer_id", "expected_hand_revision",
        }, "draft command journal schema invalid")
        require(row["uid"] not in seen, "duplicate interaction UID in journal")
        seen.add(row["uid"])
        current = command(current, catalog, policy, **row)
    require(current == doc["bundle"],
            "draft run/hand/RNG/ban state diverged from deterministic replay")
    return copy.deepcopy(current)


def fixture():
    plan = save.load_json(PLAN)
    require(plan["status"] == SCOPE and plan["schema_version"] == 1,
            "draft test plan version mismatch")
    base, run_catalog, catalog, save_plan = save.sample_checkpoint()
    save.validate_snapshot(base, run_catalog, catalog, save_plan)
    policy = plan["policy"]
    policy_validate(policy, catalog)
    return base, run_catalog, catalog, save_plan, plan


def make_demo():
    base, rc, catalog, save_plan, plan = fixture()
    policy, seed = plan["policy"], plan["seed"]
    bundle = start(base, catalog, policy, seed)
    history = []

    def apply(uid, kind, offer_id=None):
        nonlocal bundle
        current_hand = bundle["draft"]["active"]
        revision = current_hand["hand_revision"] if current_hand else None
        cmd = {"uid": uid, "kind": kind, "offer_id": offer_id,
               "expected_hand_revision": revision}
        bundle = command(bundle, catalog, policy, **cmd)
        history.append(cmd)

    apply("sample.draft.open.1", "OPEN")
    first = view(bundle, catalog, policy)
    require(first["cards"], "demo first hand unexpectedly empty")
    locked = first["cards"][0]
    apply("sample.draft.lock.1", "LOCK", locked)
    if view(bundle, catalog, policy)["can_reroll"]:
        apply("sample.draft.reroll.1", "REROLL")
    cards = view(bundle, catalog, policy)["cards"]
    ban_candidate = next((x for x in cards if x != locked), None)
    if ban_candidate is not None:
        apply("sample.draft.banish.1", "BANISH", ban_candidate)
    banned = copy.deepcopy(bundle["draft"]["banned_ids"])
    apply("sample.draft.select.1", "SELECT", locked)

    apply("sample.draft.open.2", "OPEN")
    second_hand = view(bundle, catalog, policy)
    require(not set(second_hand["cards"]) & set(banned),
            "banned offer reappeared in next earned choice")
    if second_hand["cards"]:
        apply("sample.draft.select.2", "SELECT", second_hand["cards"][0])
    else:
        apply("sample.draft.skip.2", "SKIP")
    # Next is mandatory ritual, handled by its own distinct resolver.
    require(bundle["run"]["pending_choices"][0]["kind"] == "RITUAL_REWARD",
            "demo failed to preserve mandatory ritual boundary")
    overlay = seal_overlay(base, catalog, policy, seed, history, bundle)
    restored = json.loads(json.dumps(overlay, ensure_ascii=False,
                                    sort_keys=True, allow_nan=False))
    require(verify_overlay(restored, base, rc, catalog, save_plan, policy) == bundle,
            "demo failed deterministic overlay roundtrip")
    return {
        "draft_openings": bundle["draft"]["opened_choices"],
        "banned_ids": banned, "offers_cursor": bundle["draft"]["rng"]["counter"],
        "rerolls_remaining": bundle["draft"]["rerolls_left"],
        "banishes_remaining": bundle["draft"]["banishes_left"],
        "build_revision": bundle["build"]["revision"],
        "next_reward_kind": bundle["run"]["pending_choices"][0]["kind"],
        "actions": len(history), "replayed": True,
    }


def main():
    argparse.ArgumentParser(description="Design-only reproducible draft policy").parse_args()
    try:
        result = make_demo()
    except (ContractError, save.ContractError, builds.ContractError,
            loop.ContractError, ValueError, KeyError, TypeError) as error:
        raise SystemExit("FAIL DRAFT-CONTRACT-002: " + str(error))
    print("PASS DRAFT-CONTRACT-002 design-only", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
