#!/usr/bin/env python3
"""GAME-UX-001 cross-domain design witness, not game implementation.

Connects existing isolated GAME-ARCH-00/01 receipts to the isolated
BUILD-SKILL-001 eligibility and transaction projection. The two sample
catalogs are synthetic and intentionally not canonical game data.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runloop = _load_module("ux_runloop", ROOT / "scripts/validate_run_loop_proposal.py")
buildsystem = _load_module("ux_buildsystem", ROOT / "scripts/validate_build_proposal.py")


def sample_run_and_build():
    rc = runloop.load_json(runloop.SAMPLE)
    bc = buildsystem.load_json(buildsystem.SAMPLE)
    b = next(copy.deepcopy(x["build"]) for x in bc["witnesses"]
             if x["id"] == "sample.witness.not_ready")
    r = rc["rules"]
    collected, _ = runloop.collect_pickups(
        runloop.consolidate_pickups(rc["pickups"]),
        owner_uid=r["player_uid"], region_id=r["region_id"],
        x=r["player_position"]["x"], y=r["player_position"]["y"],
        radius=r["pickup_radius"])
    events = runloop.xp_events_from_pickups(
        collected, run_uid=rc["run_uid"], tick=r["event_tick"],
        first_sequence=r["first_sequence"]) + copy.deepcopy(rc["other_events"])
    s = runloop.apply_events(runloop.initial_run(rc), events, r["xp_cost_by_level"])
    # The two source fixtures use different synthetic initial revision numbers.
    # This alignment is purely test setup; a real RunBuild must be the owner.
    s["build_revision"] = b["revision"]
    return bc, s, b


def preview_upgrade(catalog: dict, current_build: dict, offer_id: str) -> dict:
    """Pure, grounded card facts derived from a current build projection."""
    valid = buildsystem.eligible_offers(catalog, current_build)
    buildsystem.must(offer_id in valid, "cannot preview ineligible offer")
    offer = buildsystem.tables_for(catalog)["offers"][offer_id]
    before = buildsystem.skill_rank(current_build, offer["target_id"])
    proposed = buildsystem.apply_upgrade_offer(catalog, current_build, offer_id,
                                               current_build["revision"])
    after = buildsystem.skill_rank(proposed, offer["target_id"])
    prev_recipes = set(buildsystem.applicable_recipes(catalog, current_build,
                                                      "ritual_reward"))
    next_recipes = set(buildsystem.applicable_recipes(catalog, proposed,
                                                      "ritual_reward"))
    return {
        "offer_id": offer_id,
        "kind": offer["kind"],
        "target_id": offer["target_id"],
        "active_rank_before": before if offer["kind"] in
                              {"rank_up_active", "acquire_active"} else None,
        "active_rank_after": after if offer["kind"] in
                             {"rank_up_active", "acquire_active"} else None,
        "active_slots_delta": len(proposed["active"]) - len(current_build["active"]),
        "unlocked_ritual_recipes": sorted(next_recipes - prev_recipes),
        "revision_before": current_build["revision"],
        "revision_after": proposed["revision"],
    }


def replay_choice_chain() -> dict:
    """Three actual *design-model* XP upgrades followed by ritual evolution."""
    catalog, session, current_build = sample_run_and_build()
    original_session = copy.deepcopy(session)
    original_build = copy.deepcopy(current_build)
    offer_sequence = ["sample.offer.sword_rank", "sample.offer.echo",
                      "sample.offer.echo"]
    discovered = []
    for offer in offer_sequence:
        runloop.require(session["pending_choices"][0]["kind"] == "LEVEL_UP",
                        "expected ordinary level reward")
        preview = preview_upgrade(catalog, current_build, offer)
        offered_now = buildsystem.eligible_offers(catalog, current_build)
        projected_build = buildsystem.apply_upgrade_offer(
            catalog, current_build, offer, current_build["revision"])
        session = runloop.commit_choice(
            session, choice_uid=session["pending_choices"][0]["uid"],
            expected_build_revision=current_build["revision"],
            selection_token=offer, trusted_eligible_tokens=offered_now)
        runloop.require(session["build_revision"] == projected_build["revision"],
                        "cross-domain revision divergence")
        discovered.extend(preview["unlocked_ritual_recipes"])
        current_build = projected_build
    runloop.require(session["pending_choices"][0]["kind"] == "RITUAL_REWARD",
                    "expected ritual after earned level choices")
    recipes = buildsystem.applicable_recipes(catalog, current_build, "ritual_reward")
    runloop.require("sample.evolution.thousand_swords" in recipes,
                    "chosen rank-up did not unlock ritual evolution")
    projected_build = buildsystem.apply_recipe(
        catalog, current_build, "sample.evolution.thousand_swords",
        current_build["revision"], "ritual_reward")
    session = runloop.commit_choice(
        session, choice_uid=session["pending_choices"][0]["uid"],
        expected_build_revision=current_build["revision"],
        selection_token="sample.evolution.thousand_swords",
        trusted_eligible_tokens=recipes)
    runloop.require(session["build_revision"] == projected_build["revision"],
                    "ritual transaction diverged from choice revision")
    runloop.require(session["pending_choices"][0]["kind"] == "BREAKTHROUGH",
                    "cultivation choice should remain pending")
    runloop.require(not any(x["id"] == "sample.skill.spirit_sword" for x in
                            projected_build["active"]), "evolution did not consume base")
    runloop.require(original_session["build_revision"] == 6 and
                    original_build["revision"] == 6,
                    "cross-layer test mutated source fixture")
    return {
        "level_choices_committed": 3,
        "ritual_choices_committed": 1,
        "remaining_choices": [x["kind"] for x in session["pending_choices"]],
        "ready_after_first_upgrade": "sample.evolution.thousand_swords" in discovered,
        "final_build_revision": projected_build["revision"],
        "final_choice_revision": session["build_revision"],
        "final_active": [x["id"] for x in projected_build["active"]],
        "final_power_stacks": copy.deepcopy(projected_build["powers"]),
    }


def main():
    argparse.ArgumentParser(description="Design-only cross-layer choice witness").parse_args()
    try:
        result = replay_choice_chain()
    except (buildsystem.ContractError, runloop.ContractError,
            KeyError, ValueError, TypeError) as e:
        raise SystemExit("FAIL GAME-UX cross-layer witness: " + str(e))
    print("PASS GAME-UX architecture-only choice bridge",
          json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
