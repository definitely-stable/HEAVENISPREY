"""Routing regression: real task phrasings must reach the right spec and validator in two hops."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTING = ROOT / ".work/indexes/AGENT_ROUTING.md"
START = ROOT / ".work/guides/START_HERE.md"
LINK = re.compile(r"\]\(([^)#]+)(?:#[^)]*)?\)")
SCRIPT = re.compile(r"`python (scripts/[\w/.-]+\.py)")

# (task, words that must all appear in the row's first column, specs and validators the row must reach)
CASES = (
    ("new Union recipe for two techniques", ("RunBuild",),
     {"arch-02-recipe-graph.md"}, {"scripts/validate_recipe_graph_proposal.py"}),
    ("new enemy attack that roots and slows", ("монстры", "телеграфы"),
     {"enemy-threat-contract.md", "game-arch-02-encounters.md"}, {"scripts/validate_encounter_proposal.py"}),
    ("boss relic and level-up in the same tick", ("Цикл забега", "боссы"),
     {"game-arch-00-run-orchestration.md", "game-arch-02-encounters.md"}, set()),
    ("proc chain of a new skill", ("proc chains",),
     {"arch-04-effect-chains.md", "ADR-002-combat.md"}, {"scripts/validate_effect_chain_proposal.py"}),
    ("VFX intensity setting and a new RU/EN key", ("Переводы",),
     {"settings.example.cfg", "localization_context.json"}, {"scripts/validate_content.py"}),
    ("style of a new hero sprite", ("стиль", "ассетов"),
     {"art-bible-001.md", "ART_LOOKDEV.md"}, set()),
)


def rows(path):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("|") and len(cells) == 3 and not set(cells[0]) <= {"-"}:
            out.append(cells)
    return out


class AgentRoutingTests(unittest.TestCase):
    def setUp(self):
        self.rows = rows(ROUTING)

    def row(self, words):
        found = [r for r in self.rows if all(w.lower() in r[0].lower() for w in words)]
        self.assertEqual(len(found), 1, f"{words} must select exactly one routing row, got {len(found)}")
        return found[0]

    def test_real_tasks_route_to_spec_and_validator(self):
        for task, words, specs, validators in CASES:
            with self.subTest(task=task):
                row = self.row(words)
                text = " ".join(row)
                targets = {Path(t).name for t in LINK.findall(text)}
                self.assertLessEqual(specs, targets, task)
                self.assertLessEqual(validators, set(SCRIPT.findall(text)), task)

    def test_every_link_and_validator_in_routing_exists(self):
        for path in (ROUTING, START):
            text = path.read_text(encoding="utf-8")
            for target in LINK.findall(text):
                if target.startswith("http"):
                    continue
                with self.subTest(doc=path.name, target=target):
                    self.assertTrue((path.parent / target).resolve().exists())
            for script in SCRIPT.findall(text):
                with self.subTest(doc=path.name, script=script):
                    self.assertTrue((ROOT / script).exists())

    def test_routed_validators_run_in_ci(self):
        ci = "\n".join(p.read_text(encoding="utf-8")
                       for p in sorted((ROOT / ".github/workflows").glob("*.yml")))
        for script in set(SCRIPT.findall(ROUTING.read_text(encoding="utf-8"))):
            with self.subTest(script=script):
                self.assertIn(script, ci)

    def test_entry_points_state_p0_00_status_and_area_validators(self):
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        self.assertIn("Статус P0-00", agents)
        self.assertIn("AGENT_ROUTING.md", agents)
        self.assertIn("P0-00", START.read_text(encoding="utf-8").split("Текущий статус")[-1])
        self.assertIn("arch-02-recipe-graph.md", START.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
