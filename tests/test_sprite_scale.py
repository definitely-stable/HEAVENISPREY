"""ADR-014 A5d: a leggy creature's rows are measured on their scaled frames (build_sprites
measure_scaled), so thin legs that lose their solid pixels when scaled down do not change its
height from one direction to the other."""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_sprites", ROOT / "tools/art/build_sprites.py")
build_sprites = importlib.util.module_from_spec(SPEC)
sys.modules["build_sprites"] = build_sprites
SPEC.loader.exec_module(build_sprites)


def creature(legs: int) -> Image.Image:
    """A 40 px wide body 60 px tall on `legs` px tall legs one px thin."""
    image = Image.new("RGBA", (60, 60 + legs), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(60):
        for x in range(10, 50):
            pixels[x, y] = (90, 40, 90, 255)
    for y in range(60, 60 + legs):
        for x in (12, 47):
            pixels[x, y] = (90, 40, 90, 255)
    return image


class ScaledMeasureTests(unittest.TestCase):
    def test_row_scale_hits_the_target_measured_after_scaling(self):
        clip = {"name": "walk", "frames": 1}
        for legs in (0, 30, 60):
            figure = creature(legs)
            cells = [(figure, (0, 0, figure.width, figure.height), 30, figure.height)]
            measured = build_sprites.body_height(np.asarray(figure.getchannel("A")))
            source_scale = 50.0 / measured
            scale = build_sprites.scaled_row_scale(clip, 50.0, source_scale, cells, 1.0)
            size = (round(figure.width * scale), round(figure.height * scale))
            scaled = build_sprites.resize_premultiplied(figure, size)
            height = build_sprites.body_height(np.asarray(scaled.getchannel("A")))
            self.assertLessEqual(abs(height - 50), 1, f"legs {legs}: {height} px")

    def test_fit_keeps_every_frame_inside_its_cell(self):
        cells = [(None, (10, 20, 90, 120), 50, 120)]
        fit = build_sprites.fit_rows([("walk", "se", 2.0, cells)], 128, 64, 122, 4)
        self.assertLessEqual((50 - 10) * 2.0 * fit, 64 - 4 + 1e-9)
        self.assertLessEqual((120 - 20) * 2.0 * fit, 122 - 4 + 1e-9)


if __name__ == "__main__":
    unittest.main()
