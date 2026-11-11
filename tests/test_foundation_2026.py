"""Foundation gate safety and deterministic metamorphic tests.

These tests are deliberately *not* production physics, game AI or RL.
They verify existing static oracle contracts with seeded input variations.
"""
from __future__ import annotations

import copy
import importlib.util
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


gates = module("foundation_gates", ROOT / "scripts/validate_foundation_gates.py")
loop = module("foundation_runloop", ROOT / "scripts/validate_run_loop_proposal.py")


class FoundationGateTests(unittest.TestCase):
    def test_valid_foundations_are_proposals_not_fake_runtime_acceptance(self):
        summary = gates.validate(gates.load())
        self.assertGreaterEqual(summary["gate_count"], 12)
        self.assertGreaterEqual(summary["evidence_count"], 10)
        self.assertGreaterEqual(summary["deferred"], 2)
        self.assertGreaterEqual(summary["P0"], 6)

    def test_undocumented_source_fails_negative_control(self):
        catalog = gates.load()
        catalog["gates"][0]["evidence_ids"] = ["SRC-MADE-UP"]
        with self.assertRaisesRegex(gates.ContractError, "unknown evidence"):
            gates.validate(catalog)

    def test_untracked_document_path_fails(self):
        catalog = gates.load()
        catalog["gates"][0]["existing_docs"][0] = ".work/spec/v7/nonexistent.md"
        with self.assertRaisesRegex(gates.ContractError, "missing dependency doc"):
            gates.validate(catalog)

    def test_dependency_cycle_fails(self):
        catalog = gates.load()
        catalog["gates"][0]["depends_on"] = ["FND-03"]
        with self.assertRaisesRegex(gates.ContractError, "dependency cycle"):
            gates.validate(catalog)

    def test_unsupported_runtime_claim_fails(self):
        catalog = gates.load()
        catalog["scope"] = "gameplay_implemented"
        with self.assertRaisesRegex(gates.ContractError, "not in scope"):
            gates.validate(catalog)

    def test_deferred_research_cannot_be_rebranded_as_accepted(self):
        catalog = gates.load()
        future = next(x for x in catalog["gates"] if x["id"] == "FND-12")
        future["horizon"] = "fixture_now"
        with self.assertRaisesRegex(gates.ContractError, "deferred gate"):
            gates.validate(catalog)

    def test_duplicate_gate_fails(self):
        catalog = gates.load()
        catalog["gates"].append(copy.deepcopy(catalog["gates"][-1]))
        with self.assertRaisesRegex(gates.ContractError, "duplicate gate"):
            gates.validate(catalog)

    def test_schema_version_can_not_be_silently_moved(self):
        catalog = gates.load()
        catalog["schema_version"] = 2
        with self.assertRaisesRegex(gates.ContractError, "unsupported schema_version"):
            gates.validate(catalog)

    def test_source_link_must_be_https(self):
        catalog = gates.load()
        catalog["sources"][0]["url"] = "http://example.org/redirect"
        with self.assertRaisesRegex(gates.ContractError, "non-HTTPS"):
            gates.validate(catalog)


class MetamorphicPickupTests(unittest.TestCase):
    def test_random_collection_equivalence_before_after_safe_xp_merge(self):
        """128 deterministic small scenes, several player position/radius choices.

        A correct same-position XP merge must not change collectible source UIDs
        or value, even when health and catalyst objects are mixed in the scene.
        """
        for seed in range(128):
            rng = random.Random(seed)
            original = []
            for i in range(rng.randint(5, 35)):
                kind = rng.choice(["XP", "XP", "XP", "HEALTH", "CATALYST"])
                obj = {
                    "id": f"sample.pickup.{seed}.{i}",
                    "kind": kind,
                    "value": rng.randint(1, 250),
                    "owner_uid": rng.choice(["sample.owner.one", "sample.owner.two"]),
                    "region_id": rng.choice(["sample.region.a", "sample.region.b"]),
                    "collection_policy": rng.choice(["RADIUS", "EXPLICIT_INTERACT"]),
                    "x": rng.randint(-3, 3),
                    "y": rng.randint(-3, 3),
                    "source_uids": [f"sample.source.{seed}.{i}"],
                }
                original.append(obj)
            compact = loop.consolidate_pickups(original)
            self.assertEqual(sum(p["value"] for p in original),
                             sum(p["value"] for p in compact))
            for _ in range(3):
                owner = rng.choice(["sample.owner.one", "sample.owner.two"])
                region = rng.choice(["sample.region.a", "sample.region.b"])
                px, py, radius = rng.randint(-3, 3), rng.randint(-3, 3), rng.randint(0, 4)
                before, _ = loop.collect_pickups(original, owner_uid=owner,
                                                 region_id=region, x=px, y=py, radius=radius)
                after, _ = loop.collect_pickups(compact, owner_uid=owner,
                                                region_id=region, x=px, y=py, radius=radius)
                self.assertEqual(sum(p["value"] for p in before),
                                 sum(p["value"] for p in after),
                                 msg=f"seed={seed}")
                self.assertEqual(
                    set(s for p in before for s in p["source_uids"]),
                    set(s for p in after for s in p["source_uids"]),
                    msg=f"seed={seed}",
                )

    def test_randomly_permuted_event_batch_preserves_replay_result(self):
        catalog = loop.load_json(loop.SAMPLE)
        rules = catalog["rules"]
        compact = loop.consolidate_pickups(catalog["pickups"])
        picked, _ = loop.collect_pickups(
            compact, owner_uid=rules["player_uid"], region_id=rules["region_id"],
            x=rules["player_position"]["x"], y=rules["player_position"]["y"],
            radius=rules["pickup_radius"])
        batch = loop.xp_events_from_pickups(
            picked, run_uid=catalog["run_uid"], tick=rules["event_tick"],
            first_sequence=rules["first_sequence"]) + copy.deepcopy(catalog["other_events"])
        expected = loop.apply_events(loop.initial_run(catalog), batch,
                                     rules["xp_cost_by_level"])
        for seed in range(128):
            permuted = copy.deepcopy(batch)
            random.Random(seed).shuffle(permuted)
            got = loop.apply_events(loop.initial_run(catalog), permuted,
                                    rules["xp_cost_by_level"])
            self.assertEqual(expected, got)

    def test_xp_sources_refuse_unauthorized_value_across_seeded_trials(self):
        catalog = loop.load_json(loop.SAMPLE)
        source_values = {
            p["source_uids"][0]: p["value"]
            for p in catalog["pickups"]
            if p["kind"] == "XP"
        }
        for seed in range(64):
            rng = random.Random(seed)
            sources = rng.sample(sorted(source_values), k=rng.randint(1, 5))
            event = {
                "uid": f"sample.fuzz.receipt.{seed}",
                "run_uid": catalog["run_uid"],
                "tick": 100,
                "sequence": 12,
                "kind": "XP_GAIN",
                "payload": {
                    "amount": sum(source_values[s] for s in sources),
                    "source_uids": sorted(sources),
                }
            }
            loop.verify_xp_source_values([event], source_values)
            forged = copy.deepcopy(event)
            forged["payload"]["amount"] += 1
            with self.assertRaisesRegex(loop.ContractError, "authoritative"):
                loop.verify_xp_source_values([forged], source_values)


if __name__ == "__main__":
    unittest.main()
