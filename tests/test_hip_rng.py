"""hip-rng-v1 and hip-rules-hash-v1 reference oracles (ADR-007); not a Godot run."""
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "content"))

import hip_rng  # noqa: E402
import rules_identity  # noqa: E402

FIXTURES = ROOT / "game" / "tests" / "fixtures"
U64_MAX = (1 << 64) - 1


class ThreefryBlockTests(unittest.TestCase):
    def test_published_known_answers(self):
        # Random123 kat_vectors, threefry2x32 with 20 rounds.
        self.assertEqual(hip_rng.threefry2x32_20(0, 0, 0, 0), (0x6B200159, 0x99BA4EFE))
        self.assertEqual(
            hip_rng.threefry2x32_20(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF),
            (0x1CB996FC, 0xBB002BE7))
        self.assertEqual(
            hip_rng.threefry2x32_20(0x13198A2E, 0x03707344, 0x243F6A88, 0x85A308D3),
            (0xC4923A9C, 0x483DF7A0))

    def test_words_must_be_uint32(self):
        for bad in (-1, 1 << 32, True, 1.0, "1"):
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.threefry2x32_20(bad, 0, 0, 0)

    def test_block_is_a_bijection_of_the_counter_sample(self):
        outputs = {hip_rng.threefry2x32_20(7, 9, c, 0) for c in range(4096)}
        self.assertEqual(len(outputs), 4096)


class StreamTests(unittest.TestCase):
    def test_same_inputs_same_sequence(self):
        a = hip_rng.HipRng(280617, "enemy")
        b = hip_rng.HipRng(280617, "enemy")
        self.assertEqual([a.next_u32() for _ in range(256)], [b.next_u32() for _ in range(256)])

    def test_streams_and_seeds_are_separated(self):
        heads = {}
        for seed in (0, 1, 2, 1 << 32, 1 << 63, U64_MAX):
            for name in hip_rng.STREAMS:
                rng = hip_rng.HipRng(seed, name)
                heads[(seed, name)] = tuple(rng.next_u32() for _ in range(8))
        self.assertEqual(len(set(heads.values())), len(heads))
        keys = {hip_rng.stream_key(5, name) for name in hip_rng.STREAMS}
        self.assertEqual(len(keys), len(hip_rng.STREAMS))

    def test_zero_seed_is_not_degenerate(self):
        # A counter-based generator has no absorbing all-zero state: the key
        # schedule always contains the parity constant, also for seed 0.
        self.assertNotEqual(hip_rng.KS_PARITY ^ 0 ^ 0, 0)
        for name in hip_rng.STREAMS:
            rng = hip_rng.HipRng(0, name)
            words = [rng.next_u32() for _ in range(64)]
            self.assertEqual(len(set(words)), 64)
            self.assertNotIn(0, words)

    def test_name_packing_is_little_endian_and_zero_padded(self):
        self.assertEqual(hip_rng.stream_name_words("a"), (0x61, 0))
        self.assertEqual(hip_rng.stream_name_words("drops"), (0x706F7264, 0x73))
        self.assertEqual(hip_rng.stream_name_words("abcdefgh"), (0x64636261, 0x68676665))

    def test_bad_stream_names_rejected(self):
        for bad in ("", "Drops", "9lives", "toolongname", "dr ops", "дроп", "a\x00", None, 5):
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.HipRng(1, bad)

    def test_bad_seed_and_cursor_rejected(self):
        for bad in (-1, U64_MAX + 1, True, 1.5, "1"):
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.HipRng(bad, "drops")
        for bad in (-1, hip_rng.CURSOR_MAX + 1, True, 0.0, "0"):
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.HipRng(1, "drops", bad)

    def test_cursor_counts_words_and_random_access_matches(self):
        rng = hip_rng.HipRng(42, "stage")
        sequential = []
        for expected_cursor in range(101):
            self.assertEqual(rng.cursor, expected_cursor)
            sequential.append(rng.next_u32())
        self.assertEqual(sequential, [hip_rng.word_at(42, "stage", i) for i in range(101)])
        for value in sequential:
            self.assertTrue(0 <= value <= hip_rng.MASK32)

    def test_stream_exhaustion_fails_closed(self):
        rng = hip_rng.HipRng(1, "drops", hip_rng.CURSOR_MAX - 1)
        rng.next_u32()
        self.assertEqual(rng.cursor, hip_rng.CURSOR_MAX)
        with self.assertRaises(hip_rng.HipRngError):
            rng.next_u32()


class BelowTests(unittest.TestCase):
    def test_range_for_every_vector_bound(self):
        for bound in hip_rng.VECTOR_BOUNDS + (7, 255, 256, 65537, 1 << 31):
            rng = hip_rng.HipRng(99, "offers")
            for _ in range(300):
                value = rng.below(bound)
                self.assertTrue(0 <= value < bound, (bound, value))

    def test_matches_independent_threshold_rejection(self):
        # Reject exactly the words below 2**32 mod n, then reduce modulo n.
        for bound in (1, 3, 6, 1000, 2147483649, 3000000000, 4294967295, 4294967296):
            rng = hip_rng.HipRng(280617, "drops")
            got = [rng.below(bound) for _ in range(200)]
            threshold = (1 << 32) % bound
            expected, index = [], 0
            while len(expected) < 200:
                word = hip_rng.word_at(280617, "drops", index)
                index += 1
                if word >= threshold:
                    expected.append(word % bound)
            self.assertEqual(got, expected)
            self.assertEqual(rng.cursor, index)

    def test_accepted_range_is_a_multiple_of_the_bound(self):
        # Exactness: every residue has the same number of accepted words.
        for bound in list(range(1, 2000)) + [2147483649, 3000000000, 4294967295, 4294967296]:
            threshold = (1 << 32) % bound
            self.assertEqual(((1 << 32) - threshold) % bound, 0)
            self.assertLess(threshold, bound)

    def test_rejection_really_happens_and_is_counted(self):
        rng = hip_rng.HipRng(0, "offers")
        for _ in range(200):
            rng.below(2147483649)
        self.assertGreater(rng.cursor, 300)   # about 50% of words are rejected

    def test_one_always_consumes_one_word(self):
        rng = hip_rng.HipRng(3, "stage")
        for expected_cursor in range(1, 20):
            self.assertEqual(rng.below(1), 0)
            self.assertEqual(rng.cursor, expected_cursor)

    def test_full_range_bound_returns_the_raw_word(self):
        a = hip_rng.HipRng(11, "enemy")
        b = hip_rng.HipRng(11, "enemy")
        self.assertEqual([a.below(1 << 32) for _ in range(64)], [b.next_u32() for _ in range(64)])

    def test_small_bound_frequencies_are_plausible(self):
        rng = hip_rng.HipRng(2026, "drops")
        counts = [0] * 6
        for _ in range(60000):
            counts[rng.below(6)] += 1
        for count in counts:
            self.assertTrue(9500 <= count <= 10500, counts)   # loose sanity, not a quality proof

    def test_bad_bounds_rejected(self):
        rng = hip_rng.HipRng(1, "drops")
        for bad in (0, -1, (1 << 32) + 1, True, 2.0, "6", None):
            with self.assertRaises(hip_rng.HipRngError):
                rng.below(bad)
        self.assertEqual(rng.cursor, 0)


class SaveRestoreTests(unittest.TestCase):
    def test_restore_continues_bit_for_bit(self):
        for seed in (0, 1, 1 << 63, U64_MAX):
            original = hip_rng.HipRng(seed, "offers")
            for step in range(37):
                original.below(2147483649) if step % 3 else original.next_u32()
            saved = original.save()
            self.assertEqual(set(saved), {"seed", "cursor"})
            self.assertEqual(saved["seed"], str(seed))
            resumed = hip_rng.HipRng.restore("offers", json.loads(json.dumps(saved)))
            self.assertEqual([resumed.next_u32() for _ in range(64)],
                             [original.next_u32() for _ in range(64)])

    def test_restore_is_constant_time_for_far_cursors(self):
        rng = hip_rng.HipRng.restore("enemy", {"seed": "7", "cursor": "9223372036854775000"})
        self.assertEqual(rng.next_u32(), hip_rng.word_at(7, "enemy", 9223372036854775000))

    def test_malformed_saved_streams_rejected(self):
        bad_values = (
            {"seed": "1"}, {"seed": "1", "cursor": "0", "state": "0"}, {"seed": 1, "cursor": "0"},
            {"seed": "01", "cursor": "0"}, {"seed": "1", "cursor": "-1"}, {"seed": "1", "cursor": "1.0"},
            {"seed": "18446744073709551616", "cursor": "0"}, {"seed": "1", "cursor": "9223372036854775808"},
            {"seed": " 1", "cursor": "0"}, {"seed": "1", "cursor": ""}, None, [],
        )
        for bad in bad_values:
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.HipRng.restore("drops", bad)

    def test_run_streams_bind_to_the_run_seed(self):
        streams = hip_rng.new_run_streams(280617)
        self.assertEqual(tuple(sorted(streams)), hip_rng.STREAMS)
        streams["offers"].below(3)
        saved = {name: stream.save() for name, stream in streams.items()}
        restored = hip_rng.restore_run_streams(280617, saved)
        self.assertEqual(restored["offers"].cursor, 1)
        with self.assertRaises(hip_rng.HipRngError):
            hip_rng.restore_run_streams(280618, saved)
        missing = dict(saved)
        del missing["stage"]
        with self.assertRaises(hip_rng.HipRngError):
            hip_rng.restore_run_streams(280617, missing)
        extra = dict(saved, cosmetic={"seed": "280617", "cursor": "0"})
        with self.assertRaises(hip_rng.HipRngError):
            hip_rng.restore_run_streams(280617, extra)

    def test_u64_text_is_canonical(self):
        self.assertEqual(hip_rng.parse_u64("0"), 0)
        self.assertEqual(hip_rng.parse_u64("18446744073709551615"), U64_MAX)
        self.assertEqual(hip_rng.format_u64(U64_MAX), "18446744073709551615")
        for bad in ("", "00", "+1", "1 ", "1e3", "0x10", "١", "18446744073709551616", "1" * 21, 1, None):
            with self.assertRaises(hip_rng.HipRngError):
                hip_rng.parse_u64(bad)


class RngVectorFileTests(unittest.TestCase):
    def test_committed_vectors_match_regeneration(self):
        self.assertEqual((FIXTURES / "rng_vectors.json").read_bytes(), hip_rng.vectors_bytes())

    def test_vector_file_covers_the_required_cases(self):
        data = json.loads((FIXTURES / "rng_vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["rng_policy_id"], "hip-rng-v1")
        seeds = {entry["seed"] for entry in data["streams"]}
        self.assertTrue({"0", "1", "18446744073709551615"} <= seeds)
        self.assertEqual({entry["stream"] for entry in data["streams"]}, set(hip_rng.STREAMS))
        for entry in data["streams"]:
            self.assertEqual(len(entry["next_u32"]), 16)
        bounds = {entry["n"] for entry in data["below"]}
        self.assertTrue({1, 2, 3, 6, 10, 1000, 4294967295, 4294967296} <= bounds)
        for entry in data["below"]:
            self.assertGreaterEqual(len(entry["values"]), 8)
            self.assertGreaterEqual(int(entry["cursor_after"]), len(entry["values"]))
        self.assertTrue(any(int(e["cursor_after"]) > len(e["values"]) for e in data["below"]))
        for entry in data["restore"]:
            self.assertEqual(entry["saved"]["cursor"], "37")
            self.assertEqual(len(entry["next_u32_after_restore"]), 8)

    def test_vector_numbers_survive_a_float64_json_parser(self):
        # Godot parses every JSON number as float: all numeric leaves must be exact in float64.
        def walk(node):
            if isinstance(node, dict):
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)
            elif isinstance(node, int) and not isinstance(node, bool):
                self.assertLessEqual(abs(node), 1 << 53)
            else:
                self.assertNotIsInstance(node, float)
        walk(json.loads((FIXTURES / "rng_vectors.json").read_text(encoding="utf-8")))
        walk(json.loads((FIXTURES / "rules_hash_vectors.json").read_text(encoding="utf-8")))

    def test_fixture_files_use_lf_only(self):
        for name in ("rng_vectors.json", "rules_hash_vectors.json"):
            data = (FIXTURES / name).read_bytes()
            self.assertNotIn(b"\r", data)
            self.assertTrue(data.endswith(b"\n") and not data.endswith(b"\n\n"))


class RulesHashTests(unittest.TestCase):
    BASE = dict(sim_schema_version=1, content_digest="ab" * 32, rng_policy_id="hip-rng-v1",
                stage_id="stage.jade_grove", difficulty_id="difficulty.standard",
                mode_ids=["mode.normal"], class_id="class.sword", seed="1")

    def variant(self, **override):
        fields = dict(self.BASE)
        fields.update(override)
        return fields

    def test_committed_vectors_match_regeneration(self):
        self.assertEqual((FIXTURES / "rules_hash_vectors.json").read_bytes(),
                         rules_identity.vectors_bytes())

    def test_vectors_recompute_from_inputs(self):
        data = json.loads((FIXTURES / "rules_hash_vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(data["schema_version"], 1)
        self.assertGreaterEqual(len(data["cases"]), 3)
        self.assertTrue(any(case["input"]["mode_ids"] == [] for case in data["cases"]))
        for case in data["cases"]:
            preimage = rules_identity.rules_preimage(**case["input"])
            self.assertEqual(preimage.hex(), case["preimage_hex"])
            self.assertEqual(hashlib.sha256(preimage).hexdigest(), case["rules_hash"])
            self.assertEqual(rules_identity.rules_hash(**case["input"]), case["rules_hash"])
            preimage.decode("ascii")   # v1 preimage is pure ASCII plus length bytes < 0x80
        for case in data["invalid"]:
            with self.assertRaises(rules_identity.RulesIdentityError, msg=case["name"]):
                rules_identity.rules_hash(**case["input"])

    def test_exact_layout_of_the_preimage(self):
        preimage = rules_identity.rules_preimage(**self.variant(mode_ids=[]))
        expected = (b"HEAVENISPREY/RULES-HASH/v1\x00"
                    + b"\x00\x00\x00\x01" + b"1"
                    + b"\x00\x00\x00\x40" + b"ab" * 32
                    + b"\x00\x00\x00\x0a" + b"hip-rng-v1"
                    + b"\x00\x00\x00\x10" + b"stage.jade_grove"
                    + b"\x00\x00\x00\x13" + b"difficulty.standard"
                    + b"\x00\x00\x00\x00"
                    + b"\x00\x00\x00\x0b" + b"class.sword"
                    + b"\x00\x00\x00\x01" + b"1")
        self.assertEqual(preimage, expected)

    def test_mode_order_is_irrelevant_but_every_field_matters(self):
        base = rules_identity.rules_hash(**self.variant(mode_ids=["mode.hyper", "mode.ascetic"]))
        self.assertEqual(
            base, rules_identity.rules_hash(**self.variant(mode_ids=["mode.ascetic", "mode.hyper"])))
        changed = [
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], sim_schema_version=2),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], content_digest="cd" * 32),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], rng_policy_id="hip-rng-v2"),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], stage_id="stage.mist_cliffs"),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], difficulty_id="difficulty.hard"),
            self.variant(mode_ids=["mode.hyper"]),
            self.variant(mode_ids=[]),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], class_id="class.thunder"),
            self.variant(mode_ids=["mode.hyper", "mode.ascetic"], seed="2"),
        ]
        hashes = {rules_identity.rules_hash(**fields) for fields in changed}
        self.assertEqual(len(hashes), len(changed))
        self.assertNotIn(base, hashes)

    def test_length_prefix_prevents_field_boundary_collisions(self):
        a = rules_identity.rules_hash(**self.variant(mode_ids=["mode.a", "mode.b"]))
        b = rules_identity.rules_hash(**self.variant(mode_ids=["mode.a.mode", "mode.b"]))
        c = rules_identity.rules_hash(**self.variant(mode_ids=[], class_id="class.sword"))
        d = rules_identity.rules_hash(**self.variant(mode_ids=["class.sword"], class_id="class.sword"))
        self.assertEqual(len({a, b, c, d}), 4)

    def test_invalid_inputs_rejected(self):
        bad_overrides = (
            {"seed": 1}, {"seed": "01"}, {"seed": "18446744073709551616"}, {"seed": "-1"},
            {"mode_ids": "mode.normal"}, {"mode_ids": ["mode.normal", "mode.normal"]},
            {"mode_ids": ["Mode.normal"]}, {"stage_id": "stage"}, {"stage_id": "stage.нефрит"},
            {"class_id": ""}, {"content_digest": "AB" * 32}, {"content_digest": "ab" * 31},
            {"rng_policy_id": "hip rng"}, {"sim_schema_version": True},
            {"sim_schema_version": 1 << 32}, {"sim_schema_version": "1"},
        )
        for override in bad_overrides:
            with self.assertRaises(rules_identity.RulesIdentityError, msg=str(override)):
                rules_identity.rules_hash(**self.variant(**override))

    def test_constants_agree_between_modules(self):
        self.assertEqual(rules_identity.RNG_POLICY_ID, hip_rng.POLICY_ID)


if __name__ == "__main__":
    unittest.main()
