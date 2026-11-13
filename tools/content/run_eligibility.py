"""hip-run-eligibility-v1: may a profile START a new run with these rules? (IC-02)

Reference for game/core/rules/run_eligibility.gd. Rules validity (known IDs, stage
compatibility, mode exclusions, seed) is RunRulesSnapshot's job; eligibility only
answers whether the profile has the unlocks the chosen class/difficulty/modes need.

Link in the v7 catalog: classes, difficulty_profiles and modes carry `unlock_id`
(null = available from the start, otherwise an `unlock_rules` id). Stages have no
`unlock_id` in v7 and are always eligible. The profile is reduced to the set of
granted unlock IDs; how unlock rules are earned is meta-progression, not this check.

Checks, first failure wins (reason codes are stable API, shared with GDScript):
  registry_invalid           (GDScript only: ContentRegistry failed to load)
  unknown_unlock_in_profile  a granted ID is not an unlock_rules id (corrupt/foreign profile)
  unknown_definition         class/difficulty/mode ID is not in its catalog
  content_unlock_unknown     a definition's unlock_id is neither null nor a known unlock id
  class_locked | difficulty_locked | mode_locked   (modes checked in byte order)
  ok

Golden vectors: game/tests/fixtures/run_eligibility_vectors.json, computed from the
generated registry.json; profile cases derive their granted unlock IDs from
.work/config/v7/profile_fixtures.json (unlock_id of every unlocked class/difficulty).
    python tools/content/run_eligibility.py            # rewrite the golden vectors
    python tools/content/run_eligibility.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

POLICY_ID = "hip-run-eligibility-v1"
VECTORS_SCHEMA_VERSION = 1

OK = "ok"
UNKNOWN_UNLOCK_IN_PROFILE = "unknown_unlock_in_profile"
UNKNOWN_DEFINITION = "unknown_definition"
CONTENT_UNLOCK_UNKNOWN = "content_unlock_unknown"
CLASS_LOCKED = "class_locked"
DIFFICULTY_LOCKED = "difficulty_locked"
MODE_LOCKED = "mode_locked"

ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "game" / "content" / "generated" / "registry.json"
PROFILES_PATH = ROOT / ".work" / "config" / "v7" / "profile_fixtures.json"
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "run_eligibility_vectors.json"


class Catalog:
    """Definitions by catalog stem from the generated registry (the runtime's view)."""

    def __init__(self, registry: dict):
        self._by_stem = {}
        for stem, key in registry["index"].items():
            self._by_stem[stem] = {d["id"]: d for d in registry["catalogs"][stem][key]}

    def ids(self, stem: str) -> dict:
        return self._by_stem.get(stem, {})


def load_catalog(path: Path = REGISTRY_PATH) -> Catalog:
    return Catalog(json.loads(path.read_bytes()))


def check(catalog: Catalog, granted_unlock_ids, class_id: str, difficulty_id: str,
          mode_ids) -> str:
    unlocks = catalog.ids("unlock_rules")
    granted = set(granted_unlock_ids)
    if any(type(g) is not str or g not in unlocks for g in granted):
        return UNKNOWN_UNLOCK_IN_PROFILE
    targets = [("classes", class_id, CLASS_LOCKED),
               ("difficulty_profiles", difficulty_id, DIFFICULTY_LOCKED)]
    targets += [("modes", m, MODE_LOCKED) for m in sorted(mode_ids)]
    for stem, def_id, _ in targets:
        if def_id not in catalog.ids(stem):
            return UNKNOWN_DEFINITION
    for stem, def_id, locked in targets:
        unlock_id = catalog.ids(stem)[def_id].get("unlock_id")
        if unlock_id is None:
            continue
        if type(unlock_id) is not str or unlock_id not in unlocks:
            return CONTENT_UNLOCK_UNKNOWN
        if unlock_id not in granted:
            return locked
    return OK


def profile_unlocks(catalog: Catalog, profile: dict) -> list[str]:
    """Granted unlock IDs implied by a profile fixture's unlocked classes/difficulties."""
    granted = set()
    for stem, field in (("classes", "unlocked_class_ids"),
                        ("difficulty_profiles", "unlocked_difficulty_ids")):
        for def_id in profile[field]:
            unlock_id = catalog.ids(stem)[def_id].get("unlock_id")
            if unlock_id is not None:
                granted.add(unlock_id)
    return sorted(granted)


# (name, profile fixture id or explicit granted list, class, difficulty, modes)
PROFILE_CASES = [
    ("clean_sword_standard_normal", "profile.clean", "class.sword", "difficulty.standard",
     ["mode.normal"]),
    ("clean_apprentice_no_modes", "profile.clean", "class.sword", "difficulty.apprentice", []),
    ("clean_training_needs_no_unlock", "profile.clean", "class.sword", "difficulty.standard",
     ["mode.training"]),
    ("clean_hard_locked", "profile.clean", "class.sword", "difficulty.hard", ["mode.normal"]),
    ("clean_thunder_locked", "profile.clean", "class.thunder", "difficulty.standard",
     ["mode.normal"]),
    ("clean_endless_locked", "profile.clean", "class.sword", "difficulty.apprentice",
     ["mode.endless_limited"]),
    ("hard_thunder_hard_normal", "profile.hard_unlocked", "class.thunder", "difficulty.hard",
     ["mode.normal"]),
    ("hard_profile_hyper_locked", "profile.hard_unlocked", "class.thunder", "difficulty.hard",
     ["mode.hyper"]),
    ("hard_profile_tribulation_locked", "profile.hard_unlocked", "class.sword",
     "difficulty.tribulation", []),
    ("tribulation_sword_tribulation", "profile.tribulation_unlocked", "class.sword",
     "difficulty.tribulation", ["mode.normal"]),
    ("tribulation_profile_abyss_locked", "profile.tribulation_unlocked", "class.sword",
     "difficulty.abyss", ["mode.normal"]),
    ("abyss_thunder_abyss", "profile.abyss_unlocked", "class.thunder", "difficulty.abyss", []),
    ("abyss_profile_talisman_locked", "profile.abyss_unlocked", "class.talisman",
     "difficulty.standard", []),
    ("class_checked_before_difficulty", "profile.clean", "class.body", "difficulty.abyss",
     ["mode.hyper"]),
]
EXPLICIT_CASES = [
    ("granted_hyper_with_normal", ["unlock.hyper"], "class.sword", "difficulty.standard",
     ["mode.normal", "mode.hyper"]),
    ("second_mode_locked", ["unlock.hurry"], "class.sword", "difficulty.standard",
     ["mode.hyper", "mode.hurry"]),
    ("everything_granted", ["unlock.abyss", "unlock.body", "unlock.challenge_trials",
                            "unlock.hurry", "unlock.hyper"],
     "class.body", "difficulty.abyss", ["mode.challenge_trials", "mode.hurry", "mode.hyper"]),
    ("duplicate_grant_is_a_set", ["unlock.hard", "unlock.hard"], "class.sword",
     "difficulty.hard", []),
    ("unknown_unlock_in_profile", ["unlock.unknown"], "class.sword", "difficulty.standard", []),
    ("definition_id_is_not_an_unlock", ["class.thunder"], "class.thunder",
     "difficulty.standard", []),
    ("unknown_class", [], "class.unknown", "difficulty.standard", []),
    ("difficulty_id_used_as_mode", [], "class.sword", "difficulty.standard",
     ["difficulty.hard"]),
    ("class_id_used_as_difficulty", [], "class.sword", "class.sword", []),
]


def build_vectors(catalog: Catalog | None = None) -> dict:
    catalog = catalog or load_catalog()
    profiles = {p["id"]: p for p in json.loads(PROFILES_PATH.read_bytes())["profiles"]}
    rows = [(name, profile_unlocks(catalog, profiles[pid]), pid, c, d, m)
            for name, pid, c, d, m in PROFILE_CASES]
    rows += [(name, granted, None, c, d, m) for name, granted, c, d, m in EXPLICIT_CASES]
    cases = []
    for name, granted, pid, class_id, difficulty_id, mode_ids in rows:
        case = {"name": name, "granted_unlock_ids": granted, "class_id": class_id,
                "difficulty_id": difficulty_id, "mode_ids": mode_ids,
                "expected": check(catalog, granted, class_id, difficulty_id, mode_ids)}
        if pid is not None:
            case["profile_fixture_id"] = pid
        cases.append(case)
    return {
        "schema_version": VECTORS_SCHEMA_VERSION,
        "kind": "hip-run-eligibility-vectors",
        "policy_id": POLICY_ID,
        "generator": "tools/content/run_eligibility.py",
        "cases": cases,
    }


def vectors_bytes() -> bytes:
    text = json.dumps(build_vectors(), ensure_ascii=False, sort_keys=True, indent=2,
                      allow_nan=False)
    return (text + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    expected = vectors_bytes()
    rel = VECTORS_PATH.relative_to(ROOT).as_posix()
    if "--check" in argv:
        if not VECTORS_PATH.is_file() or VECTORS_PATH.read_bytes() != expected:
            print("FAIL: " + rel + " differs from the reference")
            return 1
        print("OK: run eligibility vectors match the reference")
        return 0
    VECTORS_PATH.write_bytes(expected)
    print("written " + rel + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
