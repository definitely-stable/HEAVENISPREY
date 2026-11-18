"""Q1: the PresentationSettings defaults equal .work/config/v7/settings.example.cfg."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / ".work/config/v7/settings.example.cfg"
STORE = ROOT / "game/presentation/settings/presentation_settings.gd"
DEFAULT_LINE = re.compile(r"^var (\w+): (\w+) = (.+)$")


def parse_example(text: str) -> dict[str, str]:
    """key -> value without quotes; the example sections hold flat, unique keys."""
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or (line.startswith("[") and line.endswith("]")):
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        values[key.strip()] = value
    return values


def parse_defaults(text: str) -> dict[str, tuple[str, str]]:
    """name -> (GDScript type, default text) for the class-level `var` lines only."""
    values: dict[str, tuple[str, str]] = {}
    for line in text.splitlines():
        match = DEFAULT_LINE.match(line)
        if match:
            values[match.group(1)] = (match.group(2), match.group(3).strip())
    return values


def same_value(example: str, kind: str, default: str) -> bool:
    if kind in ("float", "int"):
        try:
            return abs(float(example) - float(default)) < 1e-9
        except ValueError:
            return False
    if kind == "String":
        return example == default.strip('"')
    if kind == "bool":
        return example == default and default in ("true", "false")
    return False


def compare_defaults(example_text: str, store_text: str) -> list[str]:
    """Problems that break parity; an empty list means every default matches the example."""
    example = parse_example(example_text)
    store = parse_defaults(store_text)
    problems: list[str] = []
    for key in sorted(set(example) | set(store)):
        if key not in example:
            problems.append("%s has no value in the example" % key)
        elif key not in store:
            problems.append("%s has no GDScript default" % key)
        elif not same_value(example[key], store[key][0], store[key][1]):
            problems.append("%s: example %s != default %s" % (key, example[key], store[key][1]))
    return problems


class PresentationSettingsParityTests(unittest.TestCase):
    def setUp(self):
        self.example = EXAMPLE.read_text(encoding="utf-8")
        self.store = STORE.read_text(encoding="utf-8")

    def test_example_keys_are_the_eight_gdscript_variables(self):
        keys = set(parse_example(self.example))
        self.assertEqual(keys, set(parse_defaults(self.store)))
        self.assertEqual(len(keys), 8)

    def test_every_default_matches_its_example_value(self):
        self.assertEqual(compare_defaults(self.example, self.store), [])

    def test_a_changed_default_is_reported(self):
        changed = self.store.replace("var vfx_intensity: float = 0.65", "var vfx_intensity: float = 0.4")
        self.assertNotEqual(changed, self.store)
        problems = compare_defaults(self.example, changed)
        self.assertTrue(any("vfx_intensity" in problem for problem in problems), problems)


if __name__ == "__main__":
    unittest.main()
