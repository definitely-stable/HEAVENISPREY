class_name Fx
extends RefCounted
## `hip-fx-v1` (ADR-008): integer fixed-point arithmetic of the simulation.
##
## Exact port of tools/content/fx.py; vectors in res://tests/fixtures/fx_vectors.json.
## Scales: FX_ONE = 1000 (fx multipliers, su distances, mhp), Q14 = 16384 (unit vectors,
## sin/cos), BAM_TURN = 65536 (angles). Rounding rules: floor for non-negative scalars
## (mul/div/floor_div), symmetric for signed values (mul_sym, mul_q14), nearest-half-up for catalog
## conversions. Products saturate at +/-2^62 in every build; nothing relies on assert.
## This is the only file of the simulation allowed to use `/`, `%` and a float (isqrt seed).

const POLICY_ID: String = "hip-fx-v1"
const FX_ONE: int = 1000
const Q14: int = 16384
const BAM_TURN: int = 65536
const SIN_QUARTER: int = 1024
const PRODUCT_LIMIT: int = 1 << 62
const HP_MAX: int = 1 << 40
const MULT_MAX: int = 1 << 20
const COORD_MAX: int = 1 << 29
const NORM_MAX: int = 1 << 30
const NORM_UPSCALE_BELOW: int = 1 << 15
const CATALOG_ABS_MAX: int = 1000000
const TICKS_PER_SECOND: int = 60


static func clamp62(a: int) -> int:
	return clampi(a, -PRODUCT_LIMIT, PRODUCT_LIMIT)


## Floor division (toward -infinity, like Python //); b <= 0 is outside the policy -> 0.
@warning_ignore("integer_division")
static func floor_div(a: int, b: int) -> int:
	if b <= 0:
		return 0
	var q: int = a / b
	if a % b != 0 and a < 0:
		q -= 1
	return q


static func floor_mod(a: int, b: int) -> int:
	if b <= 0:
		return 0
	var r: int = a % b
	if r < 0:
		r += b
	return r


## a * b saturated to +/-2^62 (never wraps).
@warning_ignore("integer_division")
static func sat_product(a: int, b: int) -> int:
	a = clamp62(a)
	b = clamp62(b)
	if a == 0 or b == 0:
		return 0
	if absi(a) > PRODUCT_LIMIT / absi(b):
		return signi(a) * signi(b) * PRODUCT_LIMIT
	return a * b


## Rule 1: floor(a * b / 1000) for non-negative scalars.
static func mul(a: int, b: int) -> int:
	return floor_div(sat_product(a, b), FX_ONE)


## Rule 2: symmetric around zero, for signed quantities.
static func mul_sym(a: int, b: int) -> int:
	a = clamp62(a)
	b = clamp62(b)
	return signi(a) * signi(b) * floor_div(sat_product(absi(a), absi(b)), FX_ONE)


## Signed value times a Q14 factor (unit-vector component), symmetric around zero.
static func mul_q14(a: int, q: int) -> int:
	a = clamp62(a)
	q = clamp62(q)
	return signi(a) * signi(q) * floor_div(sat_product(absi(a), absi(q)), Q14)


## floor(a * 1000 / b); b <= 0 -> 0.
static func div(a: int, b: int) -> int:
	return floor_div(sat_product(a, FX_ONE), b)


## HP/damage/heal times a multiplier group, saturated to [0, HP_MAX].
static func mul_hp(value: int, mult: int) -> int:
	return mini(mul(clampi(value, 0, HP_MAX), clampi(mult, 0, MULT_MAX)), HP_MAX)


static func clamp_coord(x: int) -> int:
	return clampi(x, -COORD_MAX, COORD_MAX)


## floor(sqrt(n)), n clamped to [0, 2^62]. The float is only a seed: the integer
## correction defines the result.
static func isqrt(n: int) -> int:
	n = clampi(n, 0, PRODUCT_LIMIT)
	var r: int = int(sqrt(float(n)))
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r


static func _halve_sym(a: int) -> int:
	return signi(a) * (absi(a) >> 1)


## Unit vector in Q14 as [x, y]; (0, 0) stays (0, 0). Symmetric in sign.
static func normalize_q14(x: int, y: int) -> PackedInt64Array:
	x = clamp62(x)
	y = clamp62(y)
	if x == 0 and y == 0:
		return PackedInt64Array([0, 0])
	while maxi(absi(x), absi(y)) > NORM_MAX:
		x = _halve_sym(x)
		y = _halve_sym(y)
	if maxi(absi(x), absi(y)) < NORM_UPSCALE_BELOW:
		x *= NORM_UPSCALE_BELOW
		y *= NORM_UPSCALE_BELOW
	var length: int = isqrt(x * x + y * y)
	return PackedInt64Array([
		signi(x) * floor_div(absi(x) * Q14, length),
		signi(y) * floor_div(absi(y) * Q14, length),
	])


static func sin_q14(bam: int) -> int:
	var idx: int = (bam & (BAM_TURN - 1)) >> 4
	var quadrant: int = idx >> 10
	var i: int = idx & (SIN_QUARTER - 1)
	match quadrant:
		0:
			return FxTables.SIN_Q14_QUARTER[i]
		1:
			return FxTables.SIN_Q14_QUARTER[SIN_QUARTER - i]
		2:
			return -FxTables.SIN_Q14_QUARTER[i]
	return -FxTables.SIN_Q14_QUARTER[SIN_QUARTER - i]


static func cos_q14(bam: int) -> int:
	return sin_q14(bam + (BAM_TURN >> 2))


## Catalog number (JSON int or float) -> fx (x1000), or null when it is not exactly
## representable with <= 3 decimals and |v| <= 10^6 (fail-closed load error).
static func from_catalog(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		var whole: int = v
		return whole * FX_ONE if absi(whole) <= CATALOG_ABS_MAX else null
	if typeof(v) != TYPE_FLOAT:
		return null
	var number: float = v
	if not is_finite(number) or absf(number) > float(CATALOG_ABS_MAX):
		return null
	var scaled: float = number * FX_ONE
	var rounded: int = roundi(scaled)
	if absf(scaled - float(rounded)) >= 1e-6:
		return null
	return rounded


## One-shot duration in milliseconds -> ticks (nearest, half up); > 0 lasts >= 1 tick.
static func seconds_to_ticks(ms: int) -> int:
	if ms <= 0:
		return 0
	return maxi(1, floor_div(ms * TICKS_PER_SECOND + 500, 1000))


## su/s -> su/tick (nearest, half up).
static func speed_to_su_per_tick(su_per_second: int) -> int:
	return floor_div(su_per_second + (TICKS_PER_SECOND >> 1), TICKS_PER_SECOND)


## Period in milli-ticks (exact).
static func period_mt(ms: int) -> int:
	return maxi(ms, 0) * TICKS_PER_SECOND


## Advance a periodic accumulator one tick: returns [new_acc, fires].
static func period_step(acc: int, rate_fx: int, period: int) -> PackedInt64Array:
	if period <= 0:
		return PackedInt64Array([0, 0])
	acc += maxi(rate_fx, 0)
	var fires: int = 0
	while acc >= period:
		acc -= period
		fires += 1
	return PackedInt64Array([acc, fires])
