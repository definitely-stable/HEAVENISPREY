"""P0-00 ContentRegistry generator (GAP-REGISTRY-GEN, ADR-007): canonical bytes, fail-closed."""
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gen = load("generate_registry", "tools/content/generate_registry.py")
tool = load("godot_tool_for_tests", "scripts/dev/godot_tool.py")


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src = self.tmp / "v7"
        shutil.copytree(gen.SOURCE_DIR, self.src)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_committed_artifacts_are_current(self):
        self.assertEqual(gen.check(), [])

    def test_build_is_deterministic_and_canonical(self):
        reg1, man1 = gen.build()
        reg2, man2 = gen.build()
        self.assertEqual((reg1, man1), (reg2, man2))
        self.assertTrue(reg1.endswith(b"\n") and not reg1.endswith(b"\n\n"))
        self.assertNotIn(b"\r", reg1)
        obj = json.loads(reg1)
        self.assertEqual(gen.canonical_bytes(obj), reg1)
        manifest = json.loads(man1)
        self.assertEqual(manifest["registry_sha256"], hashlib.sha256(reg1).hexdigest())
        self.assertEqual(manifest["registry_bytes"], len(reg1))
        self.assertEqual(manifest["digest_policy"], "hip-canonical-json-v1")

    def test_only_runtime_catalogs_included(self):
        obj = json.loads(gen.build()[0])
        expected = {Path(name).stem for name in gen.CONTENT_SOURCES}
        self.assertEqual(set(obj["catalogs"]), expected)
        for excluded in ("localization_context", "translations", "bot_scenarios",
                         "profile_fixtures", "id_compatibility"):
            self.assertNotIn(excluded, obj["catalogs"])
        self.assertEqual(obj["index"]["classes"], "classes")

    def test_every_source_is_classified_exactly_once(self):
        names = {p.name for p in gen.SOURCE_DIR.glob("*.json")}
        self.assertEqual(gen.CONTENT_SOURCES & set(gen.EXCLUDED_SOURCES), frozenset())
        self.assertEqual(names, set(gen.CONTENT_SOURCES) | set(gen.EXCLUDED_SOURCES))

    def test_unclassified_source_aborts_generation(self):
        (self.src / "new_catalog.json").write_text('{"schema_version":2}', encoding="utf-8")
        with self.assertRaises(gen.RegistryError) as ctx:
            gen.build(self.src)
        self.assertIn("unclassified source(s) new_catalog.json", str(ctx.exception))

    def test_test_and_tooling_catalog_edits_do_not_change_digest(self):
        before = gen.content_digest(self.src)
        for name, key in (("bot_scenarios.json", "scenarios"), ("profile_fixtures.json", "profiles"),
                          ("id_compatibility.json", "mappings")):
            path = self.src / name
            data = json.loads(path.read_text(encoding="utf-8"))
            data[key] = data[key][:1]
            path.write_text(json.dumps(data), encoding="utf-8")
        self.assertEqual(gen.content_digest(self.src), before)

    def test_localization_edit_does_not_change_digest(self):
        before = gen.content_digest(self.src)
        csv = self.src / "translations.csv"
        csv.write_text(csv.read_text(encoding="utf-8") + "EXTRA_KEY,x,y\n", encoding="utf-8")
        ctx = self.src / "localization_context.json"
        data = json.loads(ctx.read_text(encoding="utf-8"))
        data["extra_note"] = "presentation only"
        ctx.write_text(json.dumps(data), encoding="utf-8")
        self.assertEqual(gen.content_digest(self.src), before)

    def test_gameplay_edit_changes_digest(self):
        before = gen.content_digest(self.src)
        path = self.src / "stages.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["stages"][0]["duration_minutes"] += 1
        path.write_text(json.dumps(data), encoding="utf-8")
        self.assertNotEqual(gen.content_digest(self.src), before)

    def test_key_order_and_whitespace_do_not_change_digest(self):
        before = gen.content_digest(self.src)
        path = self.src / "classes.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        path.write_text(json.dumps(dict(reversed(list(data.items()))), indent=4), encoding="utf-8")
        self.assertEqual(gen.content_digest(self.src), before)

    def _expect_error(self, text, fragment):
        (self.src / "classes.json").write_text(text, encoding="utf-8")
        with self.assertRaises(gen.RegistryError) as ctx:
            gen.build(self.src)
        self.assertIn(fragment, str(ctx.exception))

    def test_rejects_duplicate_keys(self):
        self._expect_error('{"schema_version":2,"schema_version":2}', "duplicate JSON key")

    def test_rejects_nonfinite_numbers(self):
        self._expect_error('{"schema_version":2,"x":NaN}', "non-finite")

    def test_rejects_overflowing_float_literal(self):
        self._expect_error('{"schema_version":2,"x":[1e400]}', "non-finite")

    def test_rejects_integers_godot_cannot_represent(self):
        self._expect_error('{"schema_version":2,"x":{"y":9007199254740992}}', "2^53")
        self._expect_error('{"schema_version":2,"x":-9007199254740992}', "2^53")
        (self.src / "classes.json").write_text(
            '{"schema_version":2,"classes":[{"id":"class.z","n":9007199254740991}]}', encoding="utf-8")
        gen.build(self.src)

    def test_check_detects_stray_generated_file(self):
        out = self.tmp / "out"
        out.mkdir()
        reg, man = gen.build()
        (out / gen.REGISTRY_FILE).write_bytes(reg)
        (out / gen.MANIFEST_FILE).write_bytes(man)
        self.assertEqual(gen.check(out), [])
        (out / "extra.json").write_text("{}", encoding="utf-8")
        self.assertTrue(any("unexpected file" in p for p in gen.check(out)))

    def test_rejects_wrong_schema_version(self):
        self._expect_error('{"schema_version":1}', "schema_version")

    def test_rejects_duplicate_ids_across_catalogs(self):
        self._expect_error('{"schema_version":2,"classes":[{"id":"skill.spirit_sword"}]}',
                           "duplicate definition id")

    def test_check_detects_hand_edit(self):
        out = self.tmp / "out"
        reg, man = gen.build()
        out.mkdir()
        (out / gen.REGISTRY_FILE).write_bytes(reg.replace(b'"duration_minutes":5', b'"duration_minutes":6'))
        (out / gen.MANIFEST_FILE).write_bytes(man)
        self.assertTrue(any("hand-edited" in p for p in gen.check(out)))
        (out / gen.MANIFEST_FILE).unlink()
        self.assertTrue(any("missing" in p for p in gen.check(out)))


class GodotToolTests(unittest.TestCase):
    def test_tree_digest_policy(self):
        files = {"b.gd": b"2", "a/x.gd": b"1"}
        lines = "".join(p + "\0" + hashlib.sha256(files[p]).hexdigest() + "\n" for p in sorted(files))
        self.assertEqual(tool.tree_digest(files), hashlib.sha256(lines.encode()).hexdigest())

    def test_gut_lock_is_pinned_to_commit(self):
        gut = tool.load_spec(tool_id="tool.gut")
        self.assertRegex(gut["source_commit"], r"^[0-9a-f]{40}$")
        self.assertTrue(gut["archive_url"].startswith(tool.GUT_PREFIX))
        self.assertTrue(gut["archive_url"].endswith(gut["source_commit"]))
        self.assertRegex(gut["tree_sha256"], r"^[0-9a-f]{64}$")
        self.assertGreater(gut["file_count"], 0)

    def test_gut_summary_parsing(self):
        log = "Totals\n------\nErrors                1\n\nScripts 1\nTests                 8\nPassing Tests         8\n"
        counts = tool.parse_gut_counts(log)
        self.assertEqual(counts["Tests"], 8)
        self.assertEqual(counts["Errors"], 1)
        self.assertEqual(tool.parse_gut_counts("no summary"), {})
        self.assertEqual(tool.parse_gut_counts("Asserts           1328/1701\n")["Asserts"], 1328)

    def test_suite_problems_require_clean_nonempty_pass(self):
        clean = {"Tests": 3, "Passing Tests": 3, "Asserts": 9}
        self.assertEqual(tool.suite_problems(0, clean, []), [])
        bad = [
            (1, clean, []),
            (0, {}, []),
            (0, {"Tests": 2, "Asserts": 0, "Risky/Pending": 2}, []),  # no-assert/pending suite
            (0, {"Tests": 3, "Passing Tests": 2, "Failing Tests": 1, "Asserts": 9}, []),
            (0, dict(clean, Errors=1), []),
            (0, clean, ["SCRIPT ERROR: Parse Error"]),
        ]
        for rc, counts, errors in bad:
            with self.subTest(counts=counts, rc=rc, errors=errors):
                self.assertTrue(tool.suite_problems(rc, counts, errors))

    def test_error_lines_detect_script_errors(self):
        log = "ok\nSCRIPT ERROR: Parse Error: x\n[GUT ERROR]: path missing\n  ERROR: res load\nfine\n"
        self.assertEqual(len(tool.error_lines(log)), 3)


if __name__ == "__main__":
    unittest.main()
