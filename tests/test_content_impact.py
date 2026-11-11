"""Static dependency impact reports for canonical design-only v7 catalogs."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("design_impact", ROOT / "scripts/content_impact.py")
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class ContentImpactDesignTests(unittest.TestCase):
    def test_known_status_lists_skill_and_mastery_dependents(self):
        definitions, graph = tool.build_graph()
        impacted = {x["id"] for x in tool.impact("status.mark", definitions, graph)}
        self.assertIn("skill.spirit_sword", impacted)
        self.assertIn("talent.sword.focus", impacted)

    def test_skill_references_class(self):
        definitions, graph = tool.build_graph()
        impacted = {x["id"] for x in tool.impact("skill.spirit_sword", definitions, graph)}
        self.assertIn("class.sword", impacted)

    def test_deterministic_impact_order(self):
        definitions, graph = tool.build_graph()
        self.assertEqual(tool.impact("status.mark", definitions, graph),
                         tool.impact("status.mark", definitions, graph))
        self.assertEqual(tool.impact("status.mark", definitions, graph)[0]["role"], "changed")

    def test_unknown_id_is_error(self):
        definitions, graph = tool.build_graph()
        with self.assertRaisesRegex(ValueError, "unknown content ID"):
            tool.impact("status.nonexistent", definitions, graph)


if __name__ == "__main__":
    unittest.main()
