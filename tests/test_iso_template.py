"""ADR-015 section 9: the geometry template of prop sheets is the 2:1 floor projection."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("iso_template", ROOT / "tools" / "art" / "iso_template.py")
iso = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iso)


class IsoTemplateTests(unittest.TestCase):
    def test_every_base_lies_on_the_two_to_one_floor(self):
        for name, layout in iso.LAYOUTS.items():
            pixels = np.asarray(iso.render(name)).astype(int)
            solid = ~((pixels[..., 0] == 0) & (pixels[..., 1] == 255) & (pixels[..., 2] == 0))
            for prop in layout:
                half = max(width for width, _ in prop["blocks"]) // 2
                xs = range(prop["x"] - half + 4, prop["x"] + half - 4)
                top = prop["y"] // (iso.SIZE[1] // 2) * (iso.SIZE[1] // 2)  # the grid cell of the prop
                bottom = {x: top + int(np.nonzero(solid[top:prop["y"] + 1, x])[0].max()) for x in xs}
                self.assertEqual(max(bottom.values()), prop["y"], name)
                for x in xs:
                    expected = prop["y"] - abs(x - prop["x"]) / 2
                    self.assertLessEqual(abs(bottom[x] - expected), 1.0, (name, prop["x"], x))

    def test_stacked_blocks_are_coaxial(self):
        pixels = np.asarray(iso.render("courtyard_guardians")).astype(int)
        for prop in iso.LAYOUTS["courtyard_guardians"]:
            row = pixels[prop["y"] - 2]
            left = prop["x"] - iso.SIZE[0] // 4  # the grid cell of the prop
            cell = row[left:left + iso.SIZE[0] // 2]
            solid = left + np.nonzero(~((cell[:, 0] == 0) & (cell[:, 1] == 255) & (cell[:, 2] == 0)))[0]
            self.assertLessEqual(abs((solid.min() + solid.max()) / 2 - prop["x"]), 1.0)


if __name__ == "__main__":
    unittest.main()
