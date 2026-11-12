"""DEV-ENV-002: repo-local agent skills, Claude adapter and vendored-skill lock."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hip_validate_agent_skills", ROOT / "scripts/validate_agent_skills.py")
skills = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skills)

EMPTY_LOCK = {"schema_version": 1, "kind": "skills-lock", "vendored": []}


class AgentSkillTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        shutil.copytree(ROOT / ".agents", self.tmp / ".agents")
        shutil.copytree(ROOT / ".work", self.tmp / ".work")
        shutil.copytree(ROOT / "scripts", self.tmp / "scripts")
        shutil.copytree(ROOT / ".github", self.tmp / ".github")
        shutil.copy(ROOT / "AGENTS.md", self.tmp / "AGENTS.md")
        self.dir = self.tmp / ".agents" / "skills"
        self.lock = json.loads(json.dumps(skills.load_lock()))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_check(self, lock=None):
        return skills.validate(self.dir, self.tmp, self.lock if lock is None else lock)

    def edit(self, name, old, new):
        path = self.dir / name / "SKILL.md"
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def test_repository_skills_are_valid(self):
        summary = skills.validate()
        self.assertGreaterEqual(summary["project"], 8)

    def test_core_skill_set_is_present(self):
        names = {p.name for p in (ROOT / ".agents/skills").iterdir()}
        for name in ("hip-orientation", "hip-task-slice", "hip-combat-contract", "hip-build-authoring",
                     "hip-content-registry", "hip-deterministic-qa", "hip-code-review", "hip-ci-closeout"):
            self.assertIn(name, names)

    def test_name_must_match_directory(self):
        self.edit("hip-orientation", "name: hip-orientation", "name: orientation")
        with self.assertRaisesRegex(skills.ContractError, "name must equal"):
            self.run_check()

    def test_description_without_trigger_fails(self):
        self.edit("hip-code-review", "Use when", "Useful if")
        with self.assertRaisesRegex(skills.ContractError, "Use when"):
            self.run_check()

    def test_broken_canonical_link_fails(self):
        self.edit("hip-ci-closeout", "CURRENT_STATE.md)", "CURRENT_STATE_OLD.md)")
        with self.assertRaisesRegex(skills.ContractError, "broken link"):
            self.run_check()

    def test_archive_v6_as_active_canon_fails(self):
        self.edit("hip-orientation", "## Procedure", "[v6](../../../.work/archive/architecture-v6-original.md)\n\n## Procedure")
        with self.assertRaisesRegex(skills.ContractError, "archived v6"):
            self.run_check()

    def test_model_exclusive_role_fails(self):
        self.edit("hip-code-review", "## Procedure", "Only Opus may review combat.\n\n## Procedure")
        with self.assertRaisesRegex(skills.ContractError, "AI models"):
            self.run_check()

    def test_undefined_tool_reference_fails(self):
        self.edit("hip-deterministic-qa", "## Procedure", "Run `python scripts/does_not_exist.py`.\n\n## Procedure")
        with self.assertRaisesRegex(skills.ContractError, "missing tool"):
            self.run_check()

    def test_missing_section_fails(self):
        self.edit("hip-task-slice", "## Not for", "## Out of scope")
        with self.assertRaisesRegex(skills.ContractError, "Not for"):
            self.run_check()

    def test_secret_in_skill_fails(self):
        self.edit("hip-ci-closeout", "## Procedure", "token ghp_" + "a" * 36 + "\n\n## Procedure")
        with self.assertRaisesRegex(skills.ContractError, "secret"):
            self.run_check()

    def test_claude_skills_copy_is_rejected_as_duplicate_id(self):
        target = self.tmp / ".claude" / "skills" / "hip-orientation"
        shutil.copytree(self.dir / "hip-orientation", target)
        with self.assertRaisesRegex(skills.ContractError, "duplicates"):
            self.run_check()

    def test_missing_claude_adapter_fails(self):
        (self.tmp / ".agents" / ".claude-plugin" / "plugin.json").unlink()
        with self.assertRaisesRegex(skills.ContractError, "adapter"):
            self.run_check()

    def test_unpinned_or_drifted_vendored_skill_fails(self):
        folder = self.dir / "third-party-x"
        folder.mkdir()
        (folder / "SKILL.md").write_text("---\nname: third-party-x\ndescription: x\n---\nbody\n", encoding="utf-8")
        (folder / "LICENSE").write_text("MIT", encoding="utf-8")
        entry = {"name": "third-party-x", "commit": "a" * 40, "license": "MIT", "license_file": "LICENSE",
                 "tree_sha256": skills.tree_digest(folder)}
        lock = dict(self.lock, vendored=self.lock["vendored"] + [entry])
        self.assertEqual(self.run_check(lock)["vendored"], len(self.lock["vendored"]) + 1)
        (folder / "SKILL.md").write_text("---\nname: third-party-x\ndescription: changed\n---\n", encoding="utf-8")
        with self.assertRaisesRegex(skills.ContractError, "drifted"):
            self.run_check(lock)
        entry["commit"] = "main"
        with self.assertRaisesRegex(skills.ContractError, "pinned commit"):
            self.run_check(lock)

    def test_trigger_cases_route_to_expected_skill(self):
        self.assertGreaterEqual(self.run_check()["trigger_cases"], 16)

    def test_indistinguishable_descriptions_fail_trigger_check(self):
        review = (self.dir / "hip-code-review" / "SKILL.md").read_text(encoding="utf-8")
        closeout = self.dir / "hip-ci-closeout" / "SKILL.md"
        meta, _ = skills.parse_frontmatter(review)
        text = closeout.read_text(encoding="utf-8")
        old, _ = skills.parse_frontmatter(text)
        closeout.write_text(text.replace(old["description"], meta["description"]), encoding="utf-8")
        with self.assertRaisesRegex(skills.ContractError, "ambiguous trigger"):
            self.run_check()

    def test_vendored_skills_are_pinned_and_licensed(self):
        for entry in self.lock["vendored"]:
            self.assertRegex(entry["commit"], r"^[0-9a-f]{40}$")
            self.assertTrue((self.dir / entry["name"] / entry["license_file"]).is_file())
        self.assertGreaterEqual(self.run_check()["vendored"], 13)

    def test_tree_digest_order_is_case_sensitive_and_platform_independent(self):
        folder = self.tmp / "case"
        folder.mkdir()
        (folder / "b.md").write_text("b", encoding="utf-8")
        (folder / "B2.md").write_text("B", encoding="utf-8")
        expected = hashlib.sha256()
        for rel, data in (("B2.md", b"B"), ("b.md", b"b")):
            expected.update(rel.encode() + b"\0" + data + b"\0")
        self.assertEqual(skills.tree_digest(folder), expected.hexdigest())

    def test_route_returns_none_on_tie_or_no_overlap(self):
        self.assertEqual(skills.route("zzz qqq", {"a": "alpha", "b": "beta"})[0], None)
        self.assertEqual(skills.route("shared words", {"a": "shared words", "b": "shared words"})[0], None)

    def test_unlisted_third_party_skill_is_checked_as_project_skill(self):
        folder = self.dir / "random-skill"
        folder.mkdir()
        (folder / "SKILL.md").write_text("---\nname: random-skill\ndescription: x\n---\n", encoding="utf-8")
        with self.assertRaisesRegex(skills.ContractError, "hip- prefix"):
            self.run_check(EMPTY_LOCK)


if __name__ == "__main__":
    unittest.main()
