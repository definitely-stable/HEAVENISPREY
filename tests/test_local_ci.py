"""DEV-ENV-001: the local CI runner reads its steps from the workflows and leaves out only the
listed installs, so a step added to CI runs locally too."""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("local_ci", ROOT / "scripts" / "dev" / "local_ci.py")
local_ci = importlib.util.module_from_spec(spec)
sys.modules["local_ci"] = local_ci  # the dataclass looks its module up
spec.loader.exec_module(local_ci)

SAMPLE = """\
jobs:
  validate:
    steps:
      - uses: actions/checkout@v7
      - name: One line
        run: python scripts/validate_work.py
      - name: A block
        run: |
          python tools/a.py --check

          python tools/b.py --check
      - name: After the block
        run: python -m unittest discover -s tests -v
"""


class LocalCiTests(unittest.TestCase):
    def test_parser_reads_single_lines_and_blocks_in_order(self):
        steps = local_ci.parse_workflow(SAMPLE, "x.yml")
        self.assertEqual([s.command for s in steps], [
            "python scripts/validate_work.py",
            "python tools/a.py --check",
            "python tools/b.py --check",
            "python -m unittest discover -s tests -v",
        ])
        self.assertEqual([s.name for s in steps], ["One line", "A block", "A block", "After the block"])

    def test_every_workflow_command_runs_or_has_a_reason(self):
        steps = local_ci.workflow_steps()
        run, skipped = local_ci.plan(steps)
        planned = {s.command for s in run} | {s.command for s, _ in skipped}
        self.assertEqual(planned, {s.command for s in steps})
        for step, reason in skipped:
            self.assertTrue(reason, step.command)

    def test_skip_list_has_no_stale_entries(self):
        commands = [s.command for s in local_ci.workflow_steps()]
        for prefix in local_ci.SKIP:
            self.assertTrue(any(c.startswith(prefix) for c in commands), prefix)

    def test_the_checks_themselves_are_never_skipped(self):
        run, _ = local_ci.plan(local_ci.workflow_steps())
        commands = [s.command for s in run]
        for needed in ("python -m unittest discover -s tests -v", "python scripts/dev/godot_tool.py test",
                       "python scripts/validate_agent_skills.py"):
            self.assertIn(needed, commands)
        self.assertTrue(any(c.startswith("gdlint game/") for c in commands))
        # A command shared by two workflows runs once.
        self.assertEqual(commands.count("python scripts/validate_assets.py"), 1)

    def test_gut_runs_alone(self):
        self.assertTrue("python scripts/dev/godot_tool.py test".startswith(local_ci.SERIAL))
        commands = {s.command for s in local_ci.workflow_steps()}
        for prefix in local_ci.SERIAL:
            self.assertTrue(any(c.startswith(prefix) for c in commands), prefix)

    def test_a_missing_gdlint_is_reported_not_skipped(self):
        status, _, message = local_ci.run_step(local_ci.Step("w", "lint", "gdlint game/core"), None)
        self.assertEqual(status, "MISSING")
        self.assertIn("gdlint", message)


if __name__ == "__main__":
    unittest.main()
