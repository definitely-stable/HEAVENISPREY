#!/usr/bin/env python3
"""CHOICE-VIEWMODEL-001: synthetic choice hand, actions, view facts and focus.

Architecture-only: no Godot, no UI assets, no real DraftService distribution,
no production save format. Uses BUILD-SKILL and SAVE-CONTRACT sample oracles.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / ".work/proposals/choice-viewmodel-001/reference_plan.json"
SCOPE = "design-proposal-not-canonical"
CHOICE_ACTIONS = {"REROLL", "BANISH", "LOCK", "UNLOCK"}
REWARD_ACTIONS = {"SELECT", "SKIP"}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


save = load_module("choice_save", ROOT / "scripts/validate_save_contract_proposal.py")
loop = save.loop
builds = save.builds


class ContractError(ValueError):
    pass


def require(cond, message):
    if not cond:
        raise ContractError(message)


def text(value, where):
    require(isinstance(value, str) and bool(value), f"invalid {where}")


def nat(value, where):
    require(type(value) is int and value >= 0, f"invalid {where}")


def pos(value, where):
    require(type(value) is int and value > 0, f"invalid {where}")


def json_hash(value):
    return save.hash_json(value)


def read_plan():
    plan = save.load_json(PLAN)
    require(plan["status"] == SCOPE and plan["schema_version"] == 1,
            "invalid choice reference plan")
    return plan


def check_pair(run, build):
    require(run["paused"] and bool(run["pending_choices"]),
            "draft requires paused, earned reward")
    require(run["pending_choices"][0]["kind"] == "LEVEL_UP",
            "reference draft supports level-up only")
    require(run["build_revision"] == build["revision"],
            "run/build revision mismatch")


def eligible_ids(catalog, build, banned):
    return sorted(set(builds.eligible_offers(catalog, build)) - set(banned))


def draw_hand(catalog, build, state, *, excluded=frozenset()):
    """Deterministic SAMPLE-only weighted without replacement.

    sha256(seed|choice_uid|counter) modulo weight is an algorithm assumption,
    not an implementation of Godot RNG; modulo bias is negligible but this
    algorithm must not be used as accepted gameplay odds without review.
    """
    eligible = eligible_ids(catalog, build, state["banned_ids"])
    locked = state["locked_offer"]
    require(locked is None or locked in eligible, "locked card lost eligibility")
    hand = [locked] if locked else []
    need = min(state["hand_size"], len(eligible))
    remaining = [id_ for id_ in eligible if id_ not in hand]
    weights = {x["id"]: x["weight"] for x in catalog["offers"]}
    for ident in remaining:
        pos(weights[ident], f"weight:{ident}")
    # On a paid reroll, make at least one new card appear when one exists.
    fresh = [id_ for id_ in remaining if id_ not in excluded]
    ordered_pools = [fresh, remaining] if fresh else [remaining]
    for pool in ordered_pools:
        while len(hand) < need:
            candidates = [x for x in pool if x not in hand]
            if not candidates:
                break
            total = sum(weights[ident] for ident in candidates)
            digest = hashlib.sha256(
                f'{state["seed"]}|{state["choice_uid"]}|{state["cursor"]}'.encode("utf-8")
            ).digest()
            r = int.from_bytes(digest, "big") % total
            state["cursor"] += 1
            for ident in candidates:
                r -= weights[ident]
                if r < 0:
                    hand.append(ident)
                    break
    return hand


def start_draft(run, build, catalog, *, seed: str,
                hand_size: int, rerolls: int, banishes: int,
                banned_ids=()):
    check_pair(run, build)
    text(seed, "seed")
    pos(hand_size, "hand_size")
    nat(rerolls, "rerolls")
    nat(banishes, "banishes")
    bans = sorted(banned_ids)
    require(len(bans) == len(set(bans)) and all(isinstance(x, str) and x for x in bans),
            "duplicate/invalid ban entries")
    all_ids = {x["id"] for x in catalog["offers"]}
    require(set(bans) <= all_ids, "ban refers to non-existent offer")
    front = run["pending_choices"][0]
    state = {
        "schema_version": 1,
        "status": SCOPE,
        "run_uid": run["run_uid"],
        "choice_uid": front["uid"],
        "source_event_uid": front["source_event_uid"],
        "build_revision": build["revision"],
        "seed": seed,
        "cursor": 0,
        "hand_size": hand_size,
        "rerolls_left": rerolls,
        "banishes_left": banishes,
        "banned_ids": bans,
        "locked_offer": None,
        "hand": [],
        "state_revision": 1,
        "receipts": {},
        "actions": [],
    }
    state["hand"] = draw_hand(catalog, build, state)
    return state


def check_state(state, run, build, catalog):
    check_pair(run, build)
    require(state["schema_version"] == 1 and state["status"] == SCOPE,
            "unsupported draft state schema")
    front = run["pending_choices"][0]
    require(state["run_uid"] == run["run_uid"] and
            state["choice_uid"] == front["uid"] and
            state["source_event_uid"] == front["source_event_uid"],
            "draft bound to stale/different reward")
    require(state["build_revision"] == build["revision"],
            "draft bound to stale build revision")
    for field in ("cursor", "rerolls_left", "banishes_left"):
        nat(state[field], field)
    pos(state["state_revision"], "draft state_revision")
    require(len(state["hand"]) == len(set(state["hand"])), "duplicate offer in hand")
    require(state["banned_ids"] == sorted(set(state["banned_ids"])),
            "ban list not canonical")
    allowed = eligible_ids(catalog, build, state["banned_ids"])
    require(set(state["hand"]) <= set(allowed), "stale/ineligible card in hand")
    require(len(state["hand"]) <= state["hand_size"], "hand capacity exceeded")
    require(state["locked_offer"] is None or state["locked_offer"] in state["hand"],
            "locked card not in hand")
    require(type(state["receipts"]) is dict and type(state["actions"]) is list,
            "draft action ledger invalid")


def _digest_action(uid, kind, offer_id, expected_revision):
    return json_hash({
        "uid": uid, "kind": kind, "offer_id": offer_id,
        "expected_revision": expected_revision,
    })


def act(state, run, build, catalog, *, uid, kind, offer_id=None,
        expected_revision):
    """Design-only hand operation; NO earned reward is consumed."""
    text(uid, "action UID")
    require(kind in CHOICE_ACTIONS, "invalid hand action")
    nat(expected_revision, "expected state revision")
    check_state(state, run, build, catalog)
    signature = _digest_action(uid, kind, offer_id, expected_revision)
    prior = state["receipts"].get(uid)
    if prior is not None:
        require(prior == signature, "action UID conflict")
        return copy.deepcopy(state)  # Exact retry cannot use another charge.
    require(expected_revision == state["state_revision"],
            "stale draft state revision")
    result = copy.deepcopy(state)
    if kind == "REROLL":
        require(offer_id is None, "reroll must not target card")
        require(result["rerolls_left"] > 0, "no rerolls left")
        require(bool(set(eligible_ids(catalog, build, result["banned_ids"])) -
                     set(result["hand"])),
                "reroll cannot reveal any new legal card")
        result["rerolls_left"] -= 1
        result["hand"] = draw_hand(catalog, build, result,
                                   excluded=set(result["hand"]) -
                                   ({result["locked_offer"]} if result["locked_offer"] else set()))
    elif kind == "BANISH":
        require(offer_id in result["hand"], "banish target missing")
        require(offer_id != result["locked_offer"], "unlock card before banish")
        require(result["banishes_left"] > 0, "no banishes left")
        result["banishes_left"] -= 1
        result["banned_ids"] = sorted(set(result["banned_ids"] + [offer_id]))
        result["hand"] = [x for x in result["hand"] if x != offer_id]
        # Fill from genuinely new pool if available; preserve survivors.
        survivors = result["hand"][:]
        extra = draw_hand(catalog, build, result, excluded=set(survivors))
        result["hand"] = survivors + [x for x in extra if x not in survivors]
        result["hand"] = result["hand"][:result["hand_size"]]
    elif kind == "LOCK":
        require(offer_id in result["hand"], "lock target missing")
        require(result["locked_offer"] in (None, offer_id),
                "another card already locked")
        result["locked_offer"] = offer_id
    else:
        require(offer_id is None or offer_id == result["locked_offer"],
                "unlock target mismatch")
        require(result["locked_offer"] is not None, "no locked card")
        result["locked_offer"] = None
    result["state_revision"] += 1
    result["receipts"][uid] = signature
    result["actions"].append({
        "uid": uid, "kind": kind, "offer_id": offer_id,
        "expected_revision": expected_revision,
    })
    check_state(result, run, build, catalog)
    return result


def view(state, run, build, catalog):
    """Only objective facts inferred from catalog and projected RunBuild.

    No invented DPS, localization, rarity, prices, or card optimization score.
    """
    check_state(state, run, build, catalog)
    tables = builds.tables_for(catalog)
    cards = []
    for offer_id in state["hand"]:
        offer = tables["offers"][offer_id]
        target = offer["target_id"]
        kind = offer["kind"]
        projection = builds.apply_upgrade_offer(catalog, build, offer_id,
                                                build["revision"])
        before_rank = builds.skill_rank(build, target) if kind in (
            "acquire_active", "rank_up_active") else None
        after_rank = builds.skill_rank(projection, target) if before_rank is not None else None
        before_power = next((x["stacks"] for x in build["powers"]
                             if x["id"] == target), 0)
        after_power = next((x["stacks"] for x in projection["powers"]
                            if x["id"] == target), 0)
        if kind in ("acquire_active", "rank_up_active"):
            tags = tables["skills"][target]["school_tags"]
        elif kind == "acquire_passive":
            tags = tables["passives"][target]["school_tags"]
        else:
            tags = []
        old_recipes = set(builds.applicable_recipes(catalog, build, "ritual_reward"))
        new_recipes = set(builds.applicable_recipes(catalog, projection,
                                                   "ritual_reward"))
        cards.append({
            "offer_id": offer_id, "kind": kind, "target_id": target,
            "school_tags": list(tags), "current_active_rank": before_rank,
            "next_active_rank": after_rank,
            "power_stack_delta": after_power - before_power,
            "active_slots_delta": len(projection["active"]) - len(build["active"]),
            "passive_slots_delta": len(projection["passive"]) - len(build["passive"]),
            "newly_eligible_rituals": sorted(new_recipes - old_recipes),
            "locked": offer_id == state["locked_offer"],
            "source_choice_uid": state["choice_uid"],
            "source_event_uid": state["source_event_uid"],
            "build_revision": build["revision"],
            # Localization and actual effect delta require canonical display defs.
            "localized_title": None, "numerical_damage_delta": None,
        })
    return {
        "choice_uid": state["choice_uid"],
        "build_revision": state["build_revision"],
        "hand_revision": state["state_revision"],
        "queue_remaining": len(run["pending_choices"]),
        "rerolls_left": state["rerolls_left"],
        "can_reroll": (state["rerolls_left"] > 0 and bool(
            set(eligible_ids(catalog, build, state["banned_ids"])) -
            set(state["hand"]))),
        "banishes_left": state["banishes_left"],
        "cards": cards,
        "empty_fallback_needed": len(cards) == 0,
    }


def consume(run, build, state, catalog, *, uid, kind, offer_id,
            expected_state_revision):
    """Atomic *sample* choice transaction after UI intent is independently vetted.

    SELECT must be displayed and still legal. SKIP is explicitly chosen and
    uses a no-power-change revision to keep existing run/build models aligned.
    """
    text(uid, "consume action UID")
    require(kind in REWARD_ACTIONS, "invalid reward action")
    check_state(state, run, build, catalog)
    require(expected_state_revision == state["state_revision"],
            "stale visible card hand")
    require(uid not in state["receipts"], "interaction UID already used")
    if kind == "SELECT":
        require(offer_id in state["hand"], "selection not in visible hand")
        legal = eligible_ids(catalog, build, state["banned_ids"])
        require(offer_id in legal, "selection no longer eligible")
        new_build = builds.apply_upgrade_offer(catalog, build, offer_id,
                                               build["revision"])
        selected = offer_id
    else:
        require(offer_id is None, "SKIP has no offer ID")
        selected = "sample.choice.explicit_skip"
        new_build = copy.deepcopy(build)
        new_build["revision"] += 1
        builds.validate_build(new_build, builds.tables_for(catalog),
                              catalog["policy"])
    new_run = loop.commit_choice(
        run, choice_uid=state["choice_uid"],
        expected_build_revision=build["revision"],
        selection_token=selected, trusted_eligible_tokens=[selected])
    require(new_run["build_revision"] == new_build["revision"],
            "run/build choice commit divergence")
    return {"run": new_run, "build": new_build,
            "consumed_choice_uid": state["choice_uid"],
            "selected_token": selected, "interaction_uid": uid}


def open_focus(state, *, held_buttons=()):
    require(type(held_buttons) in (tuple, list, set) and
            all(isinstance(x, str) and x for x in held_buttons),
            "invalid held button set")
    return {
        "choice_uid": state["choice_uid"],
        "hand_revision": state["state_revision"],
        "held_buttons": sorted(set(held_buttons)),
        "confirm_armed": not bool(held_buttons),
        "focused_offer": None,
    }


def focus_input(focus, state, *, button: str, transition: str,
                focused_offer=None):
    """Input-protocol oracle: require release of held keys after UI open.

    Returns a *candidate intent* only, not a committed game mutation.
    """
    text(button, "button")
    require(transition in {"PRESS", "RELEASE"}, "input transition invalid")
    require(focus["choice_uid"] == state["choice_uid"] and
            focus["hand_revision"] == state["state_revision"],
            "stale focus session after hand redraw")
    result = copy.deepcopy(focus)
    held = set(result["held_buttons"])
    intent = None
    if transition == "RELEASE":
        held.discard(button)
        if not held:
            result["confirm_armed"] = True
    else:
        if button in held:
            raise ContractError("held/repeated key cannot confirm")
        if button == "CONFIRM":
            require(result["confirm_armed"], "confirmation not armed")
            require(focused_offer in state["hand"],
                    "no legal focused card for confirmation")
            intent = {"choice_uid": state["choice_uid"],
                      "offer_id": focused_offer,
                      "hand_revision": state["state_revision"]}
        held.add(button)
    result["held_buttons"] = sorted(held)
    if focused_offer in state["hand"]:
        result["focused_offer"] = focused_offer
    return result, intent


def overlay(base_snapshot, state, catalog, plan):
    """A separate overlay; SAVE-CONTRACT-001 has a strict envelope.

    This cannot be merged into the existing canonical snapshot without a
    documented schema migration (future SAVE-CONTRACT-002).
    """
    base_run = base_snapshot["state"]["run"]
    base_build = base_snapshot["state"]["build"]
    check_state(state, base_run, base_build, catalog)
    result = {
        "schema_version": 1,
        "kind": "choice_draft_checkpoint_overlay",
        "status": SCOPE,
        "base_save_checksum": base_snapshot["checksum"],
        "seed": state["seed"],
        "hand_size": state["hand_size"],
        "rerolls_initial": plan["rerolls"],
        "banishes_initial": plan["banishes"],
        "initial_bans": list(plan.get("initial_bans", [])),
        "actions": copy.deepcopy(state["actions"]),
        "draft": copy.deepcopy(state),
    }
    result["checksum"] = json_hash(result)
    return result


def validate_overlay(doc, base_snapshot, catalog, plan):
    require(type(doc) is dict and set(doc) == {
        "schema_version", "kind", "status", "base_save_checksum",
        "seed", "hand_size", "rerolls_initial", "banishes_initial",
        "initial_bans", "actions", "draft", "checksum",
    }, "invalid draft overlay envelope")
    require(doc["schema_version"] == 1 and
            doc["kind"] == "choice_draft_checkpoint_overlay" and
            doc["status"] == SCOPE, "draft overlay version mismatch")
    require(doc["checksum"] == json_hash({
        k: v for k, v in doc.items() if k != "checksum"
    }), "draft overlay checksum mismatch")
    require(doc["base_save_checksum"] == base_snapshot["checksum"],
            "draft overlay bound to different base save")
    require(doc["seed"] == plan["seed"] and
            doc["hand_size"] == plan["hand_size"] and
            doc["rerolls_initial"] == plan["rerolls"] and
            doc["banishes_initial"] == plan["banishes"] and
            doc["initial_bans"] == plan.get("initial_bans", []),
            "draft policy differs from trusted plan")
    run, build = base_snapshot["state"]["run"], base_snapshot["state"]["build"]
    expected = start_draft(
        run, build, catalog, seed=doc["seed"], hand_size=doc["hand_size"],
        rerolls=doc["rerolls_initial"], banishes=doc["banishes_initial"],
        banned_ids=doc["initial_bans"])
    require(type(doc["actions"]) is list, "invalid draft action history")
    seen = set()
    for action in doc["actions"]:
        require(type(action) is dict and set(action) == {
            "uid", "kind", "offer_id", "expected_revision",
        }, "draft action history shape mismatch")
        require(action["uid"] not in seen, "duplicate draft action UID")
        seen.add(action["uid"])
        expected = act(expected, run, build, catalog, **action)
    require(expected == doc["draft"], "draft state diverges from action replay")
    return copy.deepcopy(expected)


def verify_fixture():
    plan = read_plan()
    base, rc, catalog, save_plan = save.sample_checkpoint()
    save.validate_snapshot(base, rc, catalog, save_plan)
    run, build = base["state"]["run"], base["state"]["build"]
    state = start_draft(run, build, catalog, seed=plan["seed"],
                        hand_size=plan["hand_size"], rerolls=plan["rerolls"],
                        banishes=plan["banishes"])
    initial_hand = list(state["hand"])
    for action in plan["actions"]:
        state = act(state, run, build, catalog, **action,
                    expected_revision=state["state_revision"])
    viewmodel = view(state, run, build, catalog)
    checkpoint = overlay(base, state, catalog, plan)
    restored = json.loads(json.dumps(checkpoint, sort_keys=True, ensure_ascii=False))
    require(validate_overlay(restored, base, catalog, plan) == state,
            "roundtrip and replay diverged")
    require(len(viewmodel["cards"]) == plan["expected"]["cards"],
            "unexpected final hand card count")
    require(state["rerolls_left"] == plan["expected"]["rerolls_left"],
            "unexpected rerolls remaining")
    require(state["banishes_left"] == plan["expected"]["banishes_left"],
            "unexpected banishes remaining")
    require(state["locked_offer"] == plan["expected"]["locked_offer"],
            "lock not retained across hand redraw")
    require(state["hand"] != initial_hand, "fixture did not change sample hand")
    return {"cards": len(viewmodel["cards"]), "actions": len(state["actions"]),
            "cursor": state["cursor"], "hand": state["hand"],
            "rerolls_left": state["rerolls_left"],
            "banishes_left": state["banishes_left"],
            "choice_still_earned": len(run["pending_choices"]),
            "verified_overlay": True}


def main():
    argparse.ArgumentParser(description="Design-only choice hand acceptance").parse_args()
    try:
        result = verify_fixture()
    except (ContractError, save.ContractError, loop.ContractError,
            builds.ContractError, KeyError, ValueError, TypeError) as error:
        raise SystemExit("FAIL CHOICE-VIEWMODEL-001: " + str(error))
    print("PASS CHOICE-VIEWMODEL-001 design-only", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
