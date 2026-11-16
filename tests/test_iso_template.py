"""ADR-015 section 9: the geometry template of prop sheets is the 2:1 floor projection (stdlib only;
the pixel check runs where Pillow is installed)."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("iso_template", ROOT / "tools" / "art" / "iso_template.py")
iso = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iso)


def slope(a, b):
    return (b[1] - a[1]) / (b[0] - a[0])


class IsoTemplateTests(unittest.TestCase):
    def test_every_base_lies_on_the_two_to_one_floor(self):
        for name, layout in iso.LAYOUTS.items():
            for prop in layout:
                for block in iso.blocks(prop):
                    left, right, top = block["left"], block["right"], block["top"]
                    # Lower edges: up 1 px per 2 px sideways on both sides of the front corner.
                    self.assertAlmostEqual(slope(left[0], left[1]), 0.5, msg=name)
                    self.assertAlmostEqual(slope(right[0], right[1]), -0.5, msg=name)
                    # Equal faces and a front corner in the middle; vertical edges stay vertical.
                    self.assertAlmostEqual(left[1][0] - left[0][0], right[1][0] - right[0][0], msg=name)
                    self.assertEqual(left[1][0], left[2][0])
                    # The top is a diamond twice as wide as it is tall.
                    width = top[3][0] - top[1][0]
                    self.assertAlmostEqual(width, 2 * (top[0][1] - top[2][1]), msg=name)

    def test_stacked_blocks_are_coaxial(self):
        for name, layout in iso.LAYOUTS.items():
            for prop in layout:
                stack = iso.blocks(prop)
                self.assertEqual(stack[0]["left"][1], (prop["x"], prop["y"]), "front corner of the base")
                for below, above in zip(stack, stack[1:]):
                    top, base = below["top"], above["left"]
                    # The bottom diamond of the upper block is centred on the top face below:
                    # same x, and its side corners at the height of that centre.
                    self.assertEqual(base[1][0], prop["x"], name)
                    self.assertAlmostEqual(base[0][1], (top[0][1] + top[2][1]) / 2, msg=name)

    def test_props_stay_inside_their_grid_cells(self):
        cell_w, cell_h = iso.SIZE[0] / 2, iso.SIZE[1] / 2
        for name, layout in iso.LAYOUTS.items():
            for prop in layout:
                points = [p for block in iso.blocks(prop) for face in block.values() for p in face]
                col, row = int(prop["x"] // cell_w), int(prop["y"] // cell_h)
                for x, y in points:
                    self.assertTrue(col * cell_w < x < (col + 1) * cell_w, (name, x))
                    self.assertTrue(row * cell_h < y <= (row + 1) * cell_h - 4, (name, y))

    @unittest.skipUnless(importlib.util.find_spec("PIL"), "Pillow is not installed")
    def test_render_draws_the_lowest_corner_of_every_base(self):
        image = iso.render("courtyard_guardians")
        for prop in iso.LAYOUTS["courtyard_guardians"]:
            self.assertNotEqual(image.getpixel((prop["x"], prop["y"] - 1)), iso.KEY)
            self.assertEqual(image.getpixel((prop["x"], prop["y"] + 2)), iso.KEY)


if __name__ == "__main__":
    unittest.main()
