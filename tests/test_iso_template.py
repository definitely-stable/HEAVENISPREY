"""ADR-015 section 9: the geometry template of prop sheets is the 2:1 floor projection (stdlib only;
the pixel check runs where Pillow is installed)."""
from __future__ import annotations

import importlib.util
import json
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
                if not stack:
                    continue
                self.assertEqual(stack[0]["left"][1], (prop["x"], prop["y"]), "front corner of the base")
                for below, above in zip(stack, stack[1:]):
                    top, base = below["top"], above["left"]
                    # The bottom diamond of the upper block is centred on the top face below:
                    # same x, and its side corners at the height of that centre.
                    self.assertEqual(base[1][0], prop["x"], name)
                    self.assertAlmostEqual(base[0][1], (top[0][1] + top[2][1]) / 2, msg=name)

    def test_props_stay_inside_their_grid_cells(self):
        for name, layout in iso.LAYOUTS.items():
            cols, rows = iso.GRIDS.get(name, (2, 2))
            cell_w, cell_h = iso.SIZE[0] / cols, iso.SIZE[1] / rows
            for prop in layout:
                points = [p for block in iso.blocks(prop) for face in block.values() for p in face]
                rect = iso.flat_rect(prop)
                if rect:
                    points += [(rect[0], rect[1]), (rect[2], rect[3])]
                self.assertTrue(points, name)
                col, row = int(prop["x"] // cell_w), int(prop["y"] // cell_h)
                for x, y in points:
                    self.assertTrue(col * cell_w < x < (col + 1) * cell_w, (name, x))
                    self.assertTrue(row * cell_h < y <= (row + 1) * cell_h - 4, (name, y))

    def test_every_prop_is_blocks_or_a_flat_elevation(self):
        for name, layout in iso.LAYOUTS.items():
            for prop in layout:
                self.assertNotEqual("blocks" in prop, "flat" in prop, name)

    # ADR-015 section 11: the ruin ring around the seal, drawn from the arena file.

    def test_the_ring_is_six_fragments_of_low_wall_and_pillars(self):
        data = iso.load_arena()
        ruins = iso.ruins(data)
        self.assertEqual([r["index"] for r in ruins], list(range(6)))
        rows = data["rows"]
        every = set()
        for ruin in ruins:
            codes = {rows[y][x] for x, y in ruin["cells"]}
            self.assertEqual(codes, {"w", "#"}, ruin["index"])
            self.assertTrue(ruin["solid"], ruin["index"])
            self.assertFalse(every & set(ruin["cells"]), "fragments do not share cells")
            every |= set(ruin["cells"])
        cx, cy = data["centre"]
        ring = {(x, y) for y, row in enumerate(rows) for x, ch in enumerate(row)
                if ch in "w#" and 9.5 < ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 < 12.3}
        self.assertEqual(ring, every, "every wall cell of the ring belongs to a fragment")

    def test_pillar_groups_have_one_outline(self):
        self.assertEqual(iso.outline([(0, 0)]), [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])
        self.assertEqual(len(iso.outline([(0, 0), (1, 0), (1, 1)])), 6, "an L has six corners")
        with self.assertRaises(ValueError):
            iso.outline([(0, 0), (1, 1)])
        self.assertEqual(iso.cell_groups([(0, 0), (1, 0), (3, 3)]), [[(0, 0), (1, 0)], [(3, 3)]])

    def test_ruin_sheets_fit_and_anchor_at_the_prop(self):
        data = iso.load_arena()
        layout = iso.ruin_layout(data)
        self.assertEqual(len(layout["fragments"]), 6)
        self.assertEqual({f["sheet"] for f in layout["fragments"]}, set(range(1, iso.RUIN_SHEETS + 1)))
        half = iso.SIZE[0] / 2
        for frag, ruin in zip(layout["fragments"], layout["ruins"]):
            x0, y0, x1, y1 = iso._extent(ruin)
            ox, oy = frag["origin"]
            s = layout["scale"]
            self.assertGreater(ox + s * x0, half * frag["slot"] + 8, frag["index"])
            self.assertLess(ox + s * x1, half * (frag["slot"] + 1) - 8, frag["index"])
            self.assertGreater(oy + s * y0, 8)
            self.assertLess(oy + s * y1, iso.SIZE[1] - 8)
            u, v = iso.iso_screen(*ruin["at"])
            self.assertAlmostEqual(frag["anchor"][0], ox + s * u, places=1)
            self.assertAlmostEqual(frag["anchor"][1], oy + s * v, places=1)
        # Every floor edge of the template lies on the 2:1 floor.
        for points, _, line in iso.ruin_polygons(1, data):
            if line:
                (ax, ay), (bx, by) = points
                self.assertAlmostEqual(abs(slope((ax, ay), (bx, by))), 0.5)

    def test_ruin_source_matches_the_template(self):
        path = ROOT / "art_source" / "seal_ruins" / "source.json"
        source = json.loads(path.read_text(encoding="utf-8"))
        layout = iso.ruin_layout()
        self.assertEqual(source["sheet"]["grid"], [2, iso.RUIN_SHEETS])
        props = {p["name"]: p for p in source["props"]}
        for frag in layout["fragments"]:
            prop = props[f"ruin_{frag['index']}"]
            self.assertEqual(prop["cell"], frag["slot"] + 2 * (frag["sheet"] - 1))
            self.assertEqual(prop["sheet_scale"], layout["scale"])
            self.assertAlmostEqual(prop["anchor"][0], frag["anchor"][0], places=2)
            self.assertAlmostEqual(prop["anchor"][1], frag["anchor"][1] + iso.SIZE[1] * (frag["sheet"] - 1), places=2)

    @unittest.skipUnless(importlib.util.find_spec("PIL"), "Pillow is not installed")
    def test_render_draws_the_lowest_corner_of_every_base(self):
        image = iso.render("courtyard_guardians")
        for prop in iso.LAYOUTS["courtyard_guardians"]:
            self.assertNotEqual(image.getpixel((prop["x"], prop["y"] - 1)), iso.KEY)
            self.assertEqual(image.getpixel((prop["x"], prop["y"] + 2)), iso.KEY)


if __name__ == "__main__":
    unittest.main()
