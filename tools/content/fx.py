"""hip-fx-v1: integer fixed-point arithmetic of the simulation (ADR-008).

Reference for game/core/fx/fx.gd. Every value is a Python int that stays inside
signed 64 bits; the GDScript port must return the same int for every vector.

    FX_ONE = 1000      multipliers (fx), distances (1 px = 1000 su), HP (mhp)
    Q14    = 16384     unit vectors and sin/cos
    BAM    = 65536     angle units per turn

Rounding rules (exactly three):
  1. mul / div / floor_div: toward -infinity, for non-negative scalars;
  2. mul_sym: symmetric around zero, for signed quantities;
  3. catalog conversions round to nearest, half up; the sin table is half-even.
Products saturate at +/-2^62 before division, in every build (no asserts).

Artifacts (python tools/content/fx.py [--check]):
  game/tests/fixtures/fx_vectors.json   golden vectors for GUT parity
  game/core/fx/fx_tables.gd             generated const sin table (quarter wave)
"""
from __future__ import annotations

import hashlib
import json
import sys
from decimal import Decimal, ROUND_HALF_EVEN, getcontext
from pathlib import Path

POLICY_ID = "hip-fx-v1"
VECTORS_SCHEMA_VERSION = 1

FX_ONE = 1000
Q14 = 16384
BAM_TURN = 65536
SIN_STEPS = 4096                 # table resolution per turn; index = bam >> 4
SIN_QUARTER = SIN_STEPS // 4     # 1024; the table holds 1025 entries (0..1024)
PRODUCT_LIMIT = 1 << 62
HP_MAX = 1 << 40
MULT_MAX = 1 << 20
COORD_MAX = 1 << 29
NORM_MAX = 1 << 30               # larger vectors are halved symmetrically first
NORM_UPSCALE_BELOW = 1 << 15
CATALOG_ABS_MAX = 10 ** 6
TICKS_PER_SECOND = 60

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "fx_vectors.json"
TABLES_PATH = ROOT / "game" / "core" / "fx" / "fx_tables.gd"
REGISTRY_PATH = ROOT / "game" / "content" / "generated" / "registry.json"

_PI = Decimal("3.14159265358979323846264338327950288419716939937510582097494459")


class FxError(ValueError):
    pass


def sign(a: int) -> int:
    return (a > 0) - (a < 0)


def floor_div(a: int, b: int) -> int:
    """Floor division; b <= 0 is outside the policy and yields 0."""
    return a // b if b > 0 else 0


def floor_mod(a: int, b: int) -> int:
    return a % b if b > 0 else 0


def clamp62(a: int) -> int:
    """Inputs are clamped to +/-2^62 first, so |a| never overflows (|INT64_MIN|)."""
    return min(max(a, -PRODUCT_LIMIT), PRODUCT_LIMIT)


def sat_product(a: int, b: int) -> int:
    """a * b saturated to +/-2^62 (never wraps)."""
    a, b = clamp62(a), clamp62(b)
    if a == 0 or b == 0:
        return 0
    if abs(a) > PRODUCT_LIMIT // abs(b):
        return sign(a) * sign(b) * PRODUCT_LIMIT
    return a * b


def mul(a: int, b: int) -> int:
    """Rule 1: floor(a * b / 1000) for non-negative scalars."""
    return floor_div(sat_product(a, b), FX_ONE)


def mul_sym(a: int, b: int) -> int:
    """Rule 2: symmetric around zero, for signed quantities."""
    a, b = clamp62(a), clamp62(b)
    return sign(a) * sign(b) * floor_div(sat_product(abs(a), abs(b)), FX_ONE)


def mul_q14(a: int, q: int) -> int:
    """Signed value times a Q14 factor (unit-vector component), symmetric around zero."""
    a, q = clamp62(a), clamp62(q)
    return sign(a) * sign(q) * floor_div(sat_product(abs(a), abs(q)), Q14)


def div(a: int, b: int) -> int:
    """floor(a * 1000 / b); b <= 0 yields 0."""
    return floor_div(sat_product(a, FX_ONE), b)


def mul_hp(value: int, mult: int) -> int:
    """HP/damage/heal times a multiplier group, saturated to [0, HP_MAX]."""
    value = min(max(value, 0), HP_MAX)
    mult = min(max(mult, 0), MULT_MAX)
    return min(mul(value, mult), HP_MAX)


def clamp_coord(x: int) -> int:
    return min(max(x, -COORD_MAX), COORD_MAX)


def isqrt(n: int) -> int:
    """floor(sqrt(n)); n is clamped to [0, 2^62]."""
    n = min(max(n, 0), PRODUCT_LIMIT)
    r = int(n ** 0.5)  # seed only; the integer correction below defines the result
    while r * r > n:
        r -= 1
    while (r + 1) * (r + 1) <= n:
        r += 1
    return r


def _halve_sym(a: int) -> int:
    return sign(a) * (abs(a) >> 1)


def normalize_q14(x: int, y: int) -> tuple[int, int]:
    """Unit vector in Q14; (0, 0) stays (0, 0). Symmetric in sign."""
    x, y = clamp62(x), clamp62(y)
    if x == 0 and y == 0:
        return (0, 0)
    while max(abs(x), abs(y)) > NORM_MAX:
        x, y = _halve_sym(x), _halve_sym(y)
    if max(abs(x), abs(y)) < NORM_UPSCALE_BELOW:
        x, y = x * NORM_UPSCALE_BELOW, y * NORM_UPSCALE_BELOW
    length = isqrt(x * x + y * y)
    return (sign(x) * floor_div(abs(x) * Q14, length),
            sign(y) * floor_div(abs(y) * Q14, length))


def _decimal_sin(x: Decimal) -> Decimal:
    getcontext().prec = 60
    term, total, k = x, x, 1
    while True:
        term = -term * x * x / ((2 * k) * (2 * k + 1))
        if abs(term) < Decimal("1e-55"):
            return total
        total += term
        k += 1


def sin_table() -> list[int]:
    """Quarter-wave table: round_half_even(16384 * sin(2*pi*i/4096)), i = 0..1024."""
    getcontext().prec = 60
    table = []
    for i in range(SIN_QUARTER + 1):
        value = Q14 * _decimal_sin(2 * _PI * i / SIN_STEPS)
        table.append(int(value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN)))
    return table


SIN_TABLE = sin_table()


def sin_q14(bam: int) -> int:
    idx = (bam & (BAM_TURN - 1)) >> 4
    quadrant, i = idx >> 10, idx & (SIN_QUARTER - 1)
    if quadrant == 0:
        return SIN_TABLE[i]
    if quadrant == 1:
        return SIN_TABLE[SIN_QUARTER - i]
    if quadrant == 2:
        return -SIN_TABLE[i]
    return -SIN_TABLE[SIN_QUARTER - i]


def cos_q14(bam: int) -> int:
    return sin_q14(bam + BAM_TURN // 4)


def from_catalog(v) -> int:
    """Catalog number -> fx (x1000), exact; FxError when it is not representable."""
    if type(v) is bool or type(v) not in (int, float):
        raise FxError("not a number: %r" % (v,))
    if type(v) is int:
        if abs(v) > CATALOG_ABS_MAX:
            raise FxError("catalog number beyond 10^6: %r" % v)
        return v * FX_ONE
    if v != v or abs(v) > CATALOG_ABS_MAX:
        raise FxError("catalog number not finite or beyond 10^6: %r" % v)
    scaled = Decimal(repr(v)) * FX_ONE
    if scaled != scaled.to_integral_value():
        raise FxError("catalog number has more than 3 decimals: %r" % v)
    return int(scaled)


def seconds_to_ticks(ms: int) -> int:
    """One-shot duration in milliseconds -> ticks, nearest (half up); > 0 lasts >= 1 tick."""
    if ms <= 0:
        return 0
    return max(1, floor_div(ms * TICKS_PER_SECOND + 500, 1000))


def speed_to_su_per_tick(su_per_second: int) -> int:
    """su/s -> su/tick, nearest (half up)."""
    return floor_div(su_per_second + TICKS_PER_SECOND // 2, TICKS_PER_SECOND)


def period_mt(ms: int) -> int:
    """Period in milli-ticks (exact): ms * 60."""
    return max(ms, 0) * TICKS_PER_SECOND


def period_step(acc: int, rate_fx: int, period: int) -> tuple[int, int]:
    """Advance a periodic accumulator one tick; returns (new_acc, fires)."""
    if period <= 0:
        return (0, 0)
    acc += max(rate_fx, 0)
    fires = 0
    while acc >= period:
        acc -= period
        fires += 1
    return (acc, fires)


# ---- golden vectors -------------------------------------------------------

_EDGE = [0, 1, -1, 999, -999, 1000, -1000, 1001, -1001, 1850, -1850, 123456789,
         -123456789, PRODUCT_LIMIT, -PRODUCT_LIMIT, (1 << 63) - 1, -(1 << 63)]


def _catalog_numbers() -> list:
    registry = json.loads(REGISTRY_PATH.read_bytes())
    found = set()

    def walk(value):
        if type(value) in (int, float) and type(value) is not bool:
            found.add(value)
        elif type(value) is dict:
            for item in value.values():
                walk(item)
        elif type(value) is list:
            for item in value:
                walk(item)
    walk(registry["catalogs"])
    return sorted(found, key=lambda v: (float(v), type(v) is float))


def build_vectors() -> dict:
    ops = []

    def add(op, args, expected):
        ops.append({"op": op, "args": [str(a) for a in args], "expected": [str(e) for e in expected]})

    for a in _EDGE:
        for b in (1, 7, 60, 1000, -7):
            add("floor_div", [a, b], [floor_div(a, b)])
            add("floor_mod", [a, b], [floor_mod(a, b)])
    for a in _EDGE:
        for b in (0, 1, 500, 1000, 1850, -1850, MULT_MAX, PRODUCT_LIMIT):
            add("mul", [a, b], [mul(a, b)])
            add("mul_sym", [a, b], [mul_sym(a, b)])
            add("div", [a, b], [div(a, b)])
    for a in _EDGE:
        for q in (0, 1, -1, 11585, -11585, 16384, -16384, 16385):
            add("mul_q14", [a, q], [mul_q14(a, q)])
    for value in (-5, 0, 1, 18500, HP_MAX - 1, HP_MAX, HP_MAX + 1, 1 << 62):
        for mult in (-1, 0, 1, 1000, 1850, MULT_MAX, MULT_MAX + 1):
            add("mul_hp", [value, mult], [mul_hp(value, mult)])
    for x in (-(1 << 40), -COORD_MAX - 1, -COORD_MAX, 0, COORD_MAX, COORD_MAX + 1):
        add("clamp_coord", [x], [clamp_coord(x)])
    squares = [-1, 0, 1, 2, 3, 4, 15, 16, 17, 99, 100, 101, (1 << 52) - 1, 1 << 52,
               (1 << 61) + 12345, PRODUCT_LIMIT - 1, PRODUCT_LIMIT, PRODUCT_LIMIT + 1,
               (1 << 63) - 1]
    for r in (3037000499, 2147483647, 46340, 94906265):
        squares += [r * r - 1, r * r, r * r + 1]
    for n in squares:
        add("isqrt", [n], [isqrt(n)])
    vectors = [(0, 0), (1, 0), (0, 1), (-1, 0), (1, 1), (-1, -1), (1, -1), (3, 4), (-3, 4),
               (3, -4), (12345, 6789), (-12345, 6789), (COORD_MAX, COORD_MAX),
               (-COORD_MAX * 2, COORD_MAX * 2), (1 << 40, 3), (-(1 << 40), -(1 << 39)),
               (32767, 1), (32768, 1), (16384, 16384), (-7, 1000000)]
    for x, y in vectors:
        add("normalize_q14", [x, y], list(normalize_q14(x, y)))
    for bam in list(range(-32, 65536 + 2048, 509)) + [0, 16, 4096, 8192, 16384, 32768, 49152,
                                                         65535, 65536, -1, -16384]:
        add("sin_q14", [bam], [sin_q14(bam)])
        add("cos_q14", [bam], [cos_q14(bam)])
    for ms in (-5, 0, 1, 8, 9, 16, 17, 25, 500, 1000, 1008, 2500, 300000):
        add("seconds_to_ticks", [ms], [seconds_to_ticks(ms)])
        add("period_mt", [ms], [period_mt(ms)])
    for su_s in (0, 29, 30, 89, 90, 10000, 60000, 150000, 175500, 400000):
        add("speed_to_su_per_tick", [su_s], [speed_to_su_per_tick(su_s)])
    for acc, rate, period in ((0, 1000, 600000), (599500, 1000, 600000), (0, 1050, 10000),
                              (9999, 1050, 10000), (0, 50000, 10000), (5, -10, 100),
                              (7, 1000, 0)):
        add("period_step", [acc, rate, period], list(period_step(acc, rate, period)))

    catalog = [{"value": v, "expected": str(from_catalog(v))} for v in _catalog_numbers()]
    rejected = [0.0001, 1.2345, 1000000.5, 1e7, 10 ** 6 + 1]
    for v in rejected:
        try:
            from_catalog(v)
        except FxError:
            continue
        raise FxError("rejection vector was accepted: %r" % v)
    return {
        "schema_version": VECTORS_SCHEMA_VERSION,
        "kind": "hip-fx-vectors",
        "policy_id": POLICY_ID,
        "generator": "tools/content/fx.py",
        "note": "ints are decimal strings: JSON numbers become float in Godot",
        "sin_table_sha256": hashlib.sha256(",".join(map(str, SIN_TABLE)).encode("ascii")).hexdigest(),
        "ops": ops,
        "from_catalog": catalog,
        "from_catalog_rejected": [repr(v) for v in rejected],
    }


def vectors_bytes() -> bytes:
    text = json.dumps(build_vectors(), sort_keys=True, indent=1, allow_nan=False)
    return (text + "\n").encode("utf-8")


def tables_bytes() -> bytes:
    rows = []
    for start in range(0, len(SIN_TABLE), 16):
        rows.append("\t" + ", ".join(str(v) for v in SIN_TABLE[start:start + 16]) + ",")
    text = (
        "class_name FxTables\n"
        "extends RefCounted\n"
        "## GENERATED by tools/content/fx.py (hip-fx-v1, ADR-008). Do not edit by hand.\n"
        "## Quarter-wave sine in Q14: round_half_even(16384 * sin(2*pi*i/4096)), i = 0..1024.\n"
        "\n"
        "const SIN_Q14_QUARTER: Array[int] = [\n" + "\n".join(rows) + "\n]\n"
    )
    return text.encode("utf-8")


def main(argv: list[str]) -> int:
    outputs = ((VECTORS_PATH, vectors_bytes()), (TABLES_PATH, tables_bytes()))
    if "--check" in argv:
        stale = [p for p, data in outputs if not p.is_file() or p.read_bytes() != data]
        for path in stale:
            print("FAIL: " + path.relative_to(ROOT).as_posix() + " differs from the reference")
        if stale:
            return 1
        print("OK: hip-fx-v1 vectors and tables match the reference")
        return 0
    for path, data in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print("written " + path.relative_to(ROOT).as_posix() + " (%d bytes)" % len(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
