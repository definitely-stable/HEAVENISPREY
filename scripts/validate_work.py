#!/usr/bin/env python3
"""Read-only validation of the AI knowledge hub and v7 design fixtures."""
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".work"
CONFIG = WORK / "config" / "v7"
ERRORS = []

def fail(value):
    ERRORS.append(value)

def load_json(file):
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(file.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)

def records(items, name):
    result = {}
    for entry in items:
        key = entry["id"]
        if key in result:
            fail(name + ": duplicate " + key)
        result[key] = entry
    return result

def validate_documentation():
    manifest = load_json(WORK / "MANIFEST.json")
    original = WORK / "archive" / "architecture-v6-original.md"
    digest = hashlib.sha256(original.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    if digest != manifest["source"]["sha256"]:
        fail("Original v6 SHA-256 mismatch: " + digest)
    if len(original.read_text(encoding="utf-8").splitlines()) != manifest["source"]["lines"]:
        fail("v6 original lines mismatch")
    sections = manifest["sections"]
    if len(sections) != 63 or len(set(x["id"] for x in sections)) != 63:
        fail("Expected 63 unique sections")
    index = (WORK / "INDEX.md").read_text(encoding="utf-8")
    for entry in sections:
        f = ROOT / entry["path"]
        if not f.is_file():
            fail("Missing section: " + entry["path"])
        else:
            text = f.read_text(encoding="utf-8")
            if "id: " + entry["id"] not in text[:500]:
                fail("Missing section ID metadata: " + entry["path"])
        if entry["id"] + " · " not in index:
            fail("Missing index entry: " + entry["id"])
    pages = [ROOT / "README.md", ROOT / "AGENTS.md", WORK / "INDEX.md",
             WORK / "indexes" / "AGENT_ROUTING.md", WORK / "decisions" / "README.md"]
    pages += list((WORK / "spec" / "v7").glob("*.md"))
    pages += list((WORK / "decisions").glob("ADR-*.md"))
    pages += list((WORK / "config" / "v7").glob("README.md"))
    pages += list((WORK / "roadmap").glob("*.md"))
    for page in pages:
        for target in re.findall(r"\]\(([^)]+)\)", page.read_text(encoding="utf-8")):
            if "://" in target or target.startswith("#"):
                continue
            ref = target.split("#")[0]
            if ref and not (page.parent / ref).resolve().is_file():
                fail("Broken relative link: " + str(page.relative_to(ROOT)) + " -> " + target)

def validate_v7():
    difficulties = records(load_json(CONFIG / "difficulty_profiles.json")["profiles"], "difficulty")
    unlocks = records(load_json(CONFIG / "unlock_rules.json")["rules"], "unlock")
    currencies = records(load_json(CONFIG / "currencies.json")["currencies"], "currency")
    modes = records(load_json(CONFIG / "modes.json")["profiles"], "mode")
    talents = records(load_json(CONFIG / "late_talents.json")["talents"], "talent")
    rewards = load_json(CONFIG / "reward_contract.json")
    for file in CONFIG.glob("*.json"):
        if load_json(file).get("schema_version") != 2:
            fail("Wrong schema_version: " + file.name)
    if [d["tier"] for d in difficulties.values()] != list(range(5)):
        fail("Expected tier 0..4")
    expected_late = {"difficulty.tribulation", "difficulty.abyss"}
    if set(rewards["dao_seals_allowed_difficulties"]) != expected_late:
        fail("Reward allowlist must contain only late difficulties")
    for key, d in difficulties.items():
        if d["unlock_id"] and d["unlock_id"] not in unlocks:
            fail("Unknown difficulty unlock: " + key)
        for metric in ["enemy_hp_mult", "enemy_damage_mult", "spawn_budget_mult", "elite_frequency_mult", "spirit_stones_mult"]:
            v = d[metric]
            if type(v) not in (float, int) or not (0 < v < 100):
                fail("Invalid difficulty multiplier: " + key + "." + metric)
        if (d["dao_seals_on_clear"] > 0) != (key in expected_late):
            fail("Late currency generated on wrong tier: " + key)
        if d["tier"] < 3 and d["optional_dao_seals_max"] != 0:
            fail("Early tier optional late currency: " + key)
    if difficulties["difficulty.abyss"]["dao_seals_on_clear"] <= difficulties["difficulty.tribulation"]["dao_seals_on_clear"]:
        fail("Abyss should grant more Dao Seals than Tribulation")
    if difficulties["difficulty.abyss"]["spirit_stones_mult"] <= difficulties["difficulty.tribulation"]["spirit_stones_mult"]:
        fail("Abyss should grant more Spirit Stones than Tribulation")
    for key, unlock in unlocks.items():
        if not unlock["all"]:
            fail("Empty AND unlock: " + key)
        for condition in unlock["all"]:
            if condition["event"] not in ("win", "boss_defeated", "class_mastery", "stage_complete", "run_finished"):
                fail("Unknown unlock event: " + key)
            if "difficulty_id" in condition and condition["difficulty_id"] not in difficulties:
                fail("Unknown difficulty in unlock: " + key)
    for key, mode in modes.items():
        if mode["unlock_id"] and mode["unlock_id"] not in unlocks:
            fail("Unknown mode unlock: " + key)
        for other in mode["excludes"]:
            if other not in modes or key not in modes[other]["excludes"]:
                fail("Asymmetric mode exclusion: " + key + " / " + other)
    for key in rewards["prohibited_progress_modes"]:
        if key not in modes or modes[key]["reward_eligible"]:
            fail("Unranked mode eligible for rewards: " + key)
    for key, talent in talents.items():
        if talent["cost_currency_id"] not in currencies:
            fail("Missing currency for talent: " + key)
        for req in talent["requires"]:
            if req not in talents:
                fail("Missing talent prerequisite: " + req)
    checked = set()
    def visit(node, visiting):
        if node in visiting:
            fail("Talent prerequisite cycle: " + node)
            return
        if node in checked:
            return
        visiting.add(node)
        for parent in talents[node]["requires"]:
            visit(parent, visiting)
        visiting.remove(node)
        checked.add(node)
    for talent in talents:
        visit(talent, set())
    with (CONFIG / "localization_additions.csv").open(encoding="utf-8", newline="") as inp:
        rows = list(csv.DictReader(inp))
    translations = records([{"id": x["keys"], **x} for x in rows], "translation")
    for item in list(talents.values()) + list(currencies.values()):
        if item["name_key"] not in translations:
            fail("Missing i18n key: " + item["name_key"])
    if any(not row["en"].strip() or not row["ru"].strip() for row in rows):
        fail("Missing EN/RU translation")
    for name in ["unlock.hard", "unlock.tribulation", "unlock.abyss"]:
        if name not in unlocks:
            fail("Missing progression gate " + name)

if __name__ == "__main__":
    try:
        validate_documentation()
        validate_v7()
    except Exception as exc:
        fail("Validation crashed: " + repr(exc))
    if ERRORS:
        for issue in ERRORS:
            print("FAIL:", issue, file=sys.stderr)
        raise SystemExit(1)
    print("PASS: v6 archive/63 sections, navigation, v7 gated economy/modes/i18n contracts")
