"""hip-fx-v1 reference (ADR-008): committed artifacts current, ops checked against
independent definitions (Python big ints, math.isqrt, math.sin)."""
import importlib.util
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fx", ROOT / "tools/content/fx.py")
fx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fx)

INT64_MIN, INT64_MAX = -(1 << 63), (1 << 63) - 1


class FxReferenceTests(unittest.TestCase):
    def test_committed_artifacts_are_current(self):
        self.assertEqual(fx.VECTORS_PATH.read_bytes(), fx.vectors_bytes())
        self.assertEqual(fx.TABLES_PATH.read_bytes(), fx.tables_bytes())

    def test_isqrt_matches_math_isqrt(self):
        rng = random.Random(8)
        for n in [0, 1, 2, 3, fx.PRODUCT_LIMIT] + [rng.randrange(fx.PRODUCT_LIMIT) for _ in range(2000)]:
            self.assertEqual(fx.isqrt(n), math.isqrt(n), n)

    def test_sin_table_matches_math_sin(self):
        for i, value in enumerate(fx.SIN_TABLE):
            self.assertEqual(value, round(16384 * math.sin(2 * math.pi * i / 4096)), i)
        self.assertEqual((fx.SIN_TABLE[0], fx.SIN_TABLE[-1]), (0, 16384))

    def test_sin_cos_symmetry(self):
        for bam in range(0, 65536, 16):
            self.assertEqual(fx.sin_q14(bam), -fx.sin_q14(-bam))
        for bam in range(0, 65536, 97):
            self.assertEqual(fx.cos_q14(bam), fx.sin_q14(bam + 16384))
            self.assertLessEqual(abs(fx.sin_q14(bam)), 16384)

    def test_results_stay_in_int64(self):
        edges = [INT64_MIN, -fx.PRODUCT_LIMIT, -1, 0, 1, fx.PRODUCT_LIMIT, INT64_MAX]
        for a in edges:
            for b in edges:
                for op in (fx.mul, fx.mul_sym, fx.div, fx.mul_hp):
                    self.assertTrue(INT64_MIN <= op(a, b) <= INT64_MAX, (op.__name__, a, b))
                x, y = fx.normalize_q14(a, b)
                self.assertTrue(abs(x) <= 16384 and abs(y) <= 16384)

    def test_mul_sym_is_odd_and_mul_floors(self):
        rng = random.Random(3)
        for _ in range(2000):
            a, b = rng.randrange(-10**9, 10**9), rng.randrange(0, 5000)
            self.assertEqual(fx.mul_sym(-a, b), -fx.mul_sym(a, b))
            self.assertEqual(fx.mul(a, b), (a * b) // 1000)

    def test_normalized_vectors_have_unit_length(self):
        rng = random.Random(5)
        for _ in range(2000):
            x, y = rng.randrange(-10**8, 10**8), rng.randrange(-10**8, 10**8)
            if x == 0 and y == 0:
                continue
            nx, ny = fx.normalize_q14(x, y)
            self.assertLessEqual(abs(math.hypot(nx, ny) - 16384), 2.0, (x, y))
            self.assertEqual(fx.normalize_q14(-x, -y), (-nx, -ny))

    def test_catalog_conversion_is_exact_and_fail_closed(self):
        self.assertEqual(fx.from_catalog(1.85), 1850)
        self.assertEqual(fx.from_catalog(0.38), 380)
        self.assertEqual(fx.from_catalog(5), 5000)
        for bad in (1.2345, 1e7, float("inf"), True, "1"):
            with self.assertRaises(fx.FxError):
                fx.from_catalog(bad)

    def test_period_accumulator_has_no_haste_staircase(self):
        period = fx.period_mt(167)  # 167 ms ~ 10 ticks
        fires_normal = fires_haste = 0
        acc_n = acc_h = 0
        for _ in range(6000):
            acc_n, f = fx.period_step(acc_n, 1000, period)
            fires_normal += f
            acc_h, f = fx.period_step(acc_h, 1050, period)
            fires_haste += f
        self.assertAlmostEqual(fires_haste / fires_normal, 1.05, delta=0.002)


if __name__ == "__main__":
    unittest.main()
