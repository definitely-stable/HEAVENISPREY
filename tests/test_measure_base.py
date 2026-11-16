"""ADR-015 section 9: the base check of prop sheets (stdlib; contours are built by hand)."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("measure_base", ROOT / "tools" / "art" / "measure_base.py")
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)


def diamond(half: int, rise: float, front: int = 300, pad: int = 10) -> list[int]:
    """Lower contour of a base with its front corner at x = pad + half: it rises `rise` px per px."""
    out = [-1] * pad
    out += [front - round(abs(x - half) * rise) for x in range(2 * half + 1)]
    return out + [-1] * pad


class MeasureBaseTests(unittest.TestCase):
    def test_two_to_one_base_is_on_the_floor(self):
        result = mb.measure(diamond(100, 0.5), top=0)
        self.assertAlmostEqual(result["left"], 0.5, delta=0.01)
        self.assertAlmostEqual(result["right"], -0.5, delta=0.01)
        self.assertTrue(mb.on_floor(result))
        self.assertEqual(result["height_px"], 301)

    def test_front_view_base_is_rejected(self):
        # The first guardian sheet: a flatter left side, as a near front view draws it.
        bottom = diamond(100, 0.5)
        for x in range(10, 110):
            bottom[x] = 300 - round((110 - x) * 0.26)
        result = mb.measure(bottom, top=0)
        self.assertFalse(mb.on_floor(result))
        self.assertAlmostEqual(result["left"], 0.26, delta=0.02)

    def test_a_leaf_below_the_edge_does_not_move_the_median(self):
        bottom = diamond(100, 0.5)
        for x in range(30, 36):
            bottom[x] += 12  # a maple leaf hanging under the left edge
        self.assertTrue(mb.on_floor(mb.measure(bottom, top=0)))

    def test_a_small_base_is_measured_finer_than_the_tolerance(self):
        # A balustrade post: 75 px per side. One pixel of rounding on a fixed 16 px step read
        # 0.438 and failed a base that lies on the floor.
        bottom = diamond(75, 0.5)
        bottom[40] -= 1
        bottom[56] += 1
        result = mb.measure(bottom, top=0)
        self.assertAlmostEqual(result["left"], 0.5, delta=0.02)
        self.assertTrue(mb.on_floor(result))
        self.assertFalse(mb.on_floor(mb.measure(diamond(75, 0.42), top=0)))

    def test_chips_at_the_corners_do_not_tilt_the_edge(self):
        # The broken balustrade post: stone chips lie below both outer corners of its plinth.
        bottom = diamond(75, 0.5)
        for x in list(range(12, 22)) + list(range(150, 160)):
            bottom[x] += 9
        result = mb.measure(bottom, top=0)
        self.assertAlmostEqual(result["left"], 0.5, delta=0.02)
        self.assertAlmostEqual(result["right"], -0.5, delta=0.02)

    def test_base_width_is_taken_over_the_lowest_rows(self):
        result = mb.measure(diamond(100, 0.5), top=0)
        # Lowest 15 % of 301 rows = 45 rows; a 2:1 edge spans 90 px of x per side within it.
        self.assertEqual(result["base_px"], 2 * 89 + 1)


if __name__ == "__main__":
    unittest.main()
