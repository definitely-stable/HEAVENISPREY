"""ADR-015: arena 07 after REF-033 - the drawn grid, its GAME-ARCH-02 rules and the rules of the board."""
from __future__ import annotations

import copy
import importlib.util
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


arena = _module("hip_arena_layout", "scripts/validate_arena_layout.py")
drawing = _module("hip_arena_drawing", "tools/content/arena_layout.py")


def set_cell(data: dict, x: int, y: int, ch: str) -> None:
    row = data["rows"][y]
    data["rows"][y] = row[:x] + ch + row[x + 1:]


def cells_of(data: dict, ch: str) -> list[tuple[int, int]]:
    return [(x, y) for y, row in enumerate(data["rows"]) for x, c in enumerate(row) if c == ch]


class ArenaLayoutTests(unittest.TestCase):
    def setUp(self):
        self.data = arena.load()

    def rejects(self, code: str, data: dict) -> None:
        with self.assertRaisesRegex(arena.ContractError, code):
            arena.verify(data)

    def test_the_drawn_arena_passes(self):
        result = arena.verify(self.data)
        self.assertGreaterEqual(result["field_factor"], 3.0, "bigger than the P0 field, not smaller")
        self.assertEqual(result["loop_spawns"], 6)
        self.assertEqual(result["entries"], 2)
        self.assertLessEqual(result["max_corridor"], 4)

    def test_file_is_what_the_script_draws(self):
        self.assertEqual(drawing.render(drawing.draw()), arena.TOPOLOGY.read_text(encoding="utf-8"))
        self.assertEqual(drawing.draw(), drawing.draw(), "deterministic")

    def test_the_board_layout(self):
        rows = self.data["rows"]
        cx, cy = self.data["centre"]
        self.assertEqual(rows[cy][cx], ".", "the seal is open floor")
        for name, ch in (("gate stairs", "^"), ("bridge", "B"), ("raised wings", "H"), ("solids", "#")):
            self.assertTrue(cells_of(self.data, ch), name)
        gate = [(x, y) for x, y in cells_of(self.data, "#") if x + y < cx + cy - 30]
        self.assertTrue(gate, "the gate hall stands at the back, the top of the screen")
        west, east = sorted(cells_of(self.data, "E"), key=lambda e: e[0] - e[1])
        self.assertLess(west[0] - west[1], -40, "the first entry is far left on screen, over the bridge")
        self.assertGreater(east[0] - east[1], 30, "the second entry is on the right")

    def test_a_blocked_stair_isolates_its_wing(self):
        data = copy.deepcopy(self.data)
        for x, y in cells_of(data, "B"):
            set_cell(data, x, y, "w")
        self.rejects("E_ISOLATED_POCKET", data)

    def test_raised_floor_needs_stairs(self):
        data = copy.deepcopy(self.data)
        x, y = next(c for c in cells_of(data, "^") if any(
            data["rows"][c[1] + b][c[0] + a] == "." for a, b in arena.STEPS))
        set_cell(data, x, y, "H")
        self.rejects("E_HEIGHT", data)

    def test_solid_in_the_boss_circle_is_rejected(self):
        data = copy.deepcopy(self.data)
        cx, cy = data["centre"]
        set_cell(data, cx + 2, cy, "#")
        self.rejects("E_ARENA_BLOCKER", data)

    def test_spawn_points_and_entries(self):
        data = copy.deepcopy(self.data)
        loop = [s for s in cells_of(data, "S") if any(
            data["rows"][s[1] + b][s[0] + a] == "." for a, b in arena.STEPS)]
        set_cell(data, *loop[0], ".")
        self.rejects("E_SPAWN_POINTS", data)
        data = copy.deepcopy(self.data)
        set_cell(data, *cells_of(data, "E")[0], "H")
        self.rejects("E_ENTRIES", data)

    def test_a_small_field_is_rejected(self):
        data = copy.deepcopy(self.data)
        cx, cy = data["centre"]
        for y, row in enumerate(data["rows"]):
            for x, ch in enumerate(row):
                if ch == "." and math.hypot(x - cx, y - cy) > 20:
                    set_cell(data, x, y, "w")
        with self.assertRaises(arena.ContractError):
            arena.verify(data)

    def test_the_seal_ring_has_ruins_and_gaps(self):
        data = copy.deepcopy(self.data)
        cx, cy = data["centre"]
        for y, row in enumerate(data["rows"]):
            for x, ch in enumerate(row):
                if arena.SEAL_RING[0] <= math.hypot(x - cx, y - cy) <= arena.SEAL_RING[1] and ch in "w#":
                    set_cell(data, x, y, ".")
        self.rejects("E_SEAL_RING", data)

    def test_unknown_symbol_is_rejected(self):
        data = copy.deepcopy(self.data)
        set_cell(data, 0, 0, "?")
        self.rejects("E_TERRAIN", data)


if __name__ == "__main__":
    unittest.main()
