"""hip-rng-v1: reference implementation of the simulation RNG (ADR-007, section c).

Counter-based generator: Threefry-2x32 with 20 rounds (Salmon et al., "Parallel
Random Numbers: As Easy as 1, 2, 3", SC'11). A named stream is fully described by
(seed: uint64, name, cursor); there is no hidden state, so the save shape
{seed, cursor} restores a stream in O(1) without fast-forwarding.

The algorithm uses only 32-bit additions, rotations and XOR. Every intermediate
value stays below 2**62 (the widest is a 32-bit word shifted left by 29 before
masking), so a typed GDScript port needs nothing but int64
arithmetic with explicit masking and never relies on signed overflow.

This module is the oracle for game/tests/fixtures/rng_vectors.json:
    python tools/content/hip_rng.py            # rewrite the golden vectors
    python tools/content/hip_rng.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

POLICY_ID = "hip-rng-v1"
VECTORS_SCHEMA_VERSION = 1

MASK32 = 0xFFFFFFFF
U64_MAX = (1 << 64) - 1
CURSOR_MAX = (1 << 63) - 1          # int64 range of the GDScript port; the policy rejects more
BELOW_MAX = 1 << 32                 # largest supported bound of below(n)

ROUNDS = 20
KS_PARITY = 0x1BD11BDA              # SKEIN_KS_PARITY32 of Threefry-2x32
ROTATIONS = (13, 15, 26, 6, 17, 29, 16, 24)

STREAMS = ("drops", "enemy", "offers", "stage")   # registered streams of the policy
STREAM_NAME_MAX_BYTES = 8

_U64_RE = re.compile(r"0|[1-9][0-9]{0,19}")
_STREAM_RE = re.compile(r"[a-z][a-z0-9_]{0,7}")

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "rng_vectors.json"


class HipRngError(ValueError):
    """Any rejected input: the reference fails closed and never guesses."""


# ---------------------------------------------------------------- uint64 text

def parse_u64(text: str) -> int:
    """Canonical decimal uint64: no sign, no spaces, no leading zeros."""
    if not isinstance(text, str) or not _U64_RE.fullmatch(text):
        raise HipRngError("not a canonical uint64 decimal string: %r" % (text,))
    value = int(text)
    if value > U64_MAX:
        raise HipRngError("uint64 overflow: " + text)
    return value


def format_u64(value: int) -> str:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= U64_MAX:
        raise HipRngError("not a uint64: %r" % (value,))
    return str(value)


def parse_cursor(text: str) -> int:
    value = parse_u64(text)
    if value > CURSOR_MAX:
        raise HipRngError("cursor above 2**63-1 is not supported by hip-rng-v1: " + text)
    return value


# ---------------------------------------------------------------- core block

def _rotl32(value: int, shift: int) -> int:
    return ((value << shift) & MASK32) | (value >> (32 - shift))


def threefry2x32_20(k0: int, k1: int, c0: int, c1: int) -> tuple[int, int]:
    """One Threefry-2x32-20 block: key (k0, k1), counter (c0, c1) -> (x0, x1)."""
    for word in (k0, k1, c0, c1):
        if isinstance(word, bool) or not isinstance(word, int) or not 0 <= word <= MASK32:
            raise HipRngError("threefry words must be uint32")
    ks = (k0, k1, KS_PARITY ^ k0 ^ k1)
    x0 = (c0 + ks[0]) & MASK32
    x1 = (c1 + ks[1]) & MASK32
    for r in range(ROUNDS):
        x0 = (x0 + x1) & MASK32
        x1 = _rotl32(x1, ROTATIONS[r % 8])
        x1 ^= x0
        if r % 4 == 3:
            s = r // 4 + 1
            x0 = (x0 + ks[s % 3]) & MASK32
            x1 = (x1 + ks[(s + 1) % 3] + s) & MASK32
    return x0, x1


# ---------------------------------------------------------------- streams

def stream_name_words(name: str) -> tuple[int, int]:
    """Pack the ASCII stream name little-endian into two uint32, zero padded."""
    if not isinstance(name, str) or not _STREAM_RE.fullmatch(name):
        raise HipRngError("stream name must match [a-z][a-z0-9_]{0,7}: %r" % (name,))
    data = name.encode("ascii").ljust(STREAM_NAME_MAX_BYTES, b"\x00")
    return int.from_bytes(data[0:4], "little"), int.from_bytes(data[4:8], "little")


def stream_key(seed: int, name: str) -> tuple[int, int]:
    """Stream key = Threefry(key = seed words, counter = name words).

    For a fixed seed Threefry is a bijection of the counter, so two different
    names can never share a key.
    """
    format_u64(seed)
    n0, n1 = stream_name_words(name)
    return threefry2x32_20(seed & MASK32, seed >> 32, n0, n1)


def _word(key: tuple[int, int], index: int) -> int:
    block = index >> 1
    x0, x1 = threefry2x32_20(key[0], key[1], block & MASK32, block >> 32)
    return x1 if index & 1 else x0


def word_at(seed: int, name: str, index: int) -> int:
    """Pure random access: the uint32 returned by next_u32() at cursor == index."""
    if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < CURSOR_MAX:
        raise HipRngError("index out of range")
    return _word(stream_key(seed, name), index)


class HipRng:
    """One named stream. State is exactly (seed, name, cursor)."""

    __slots__ = ("_seed", "_name", "_key", "_cursor")

    def __init__(self, seed: int, name: str, cursor: int = 0):
        format_u64(seed)
        if isinstance(cursor, bool) or not isinstance(cursor, int) or not 0 <= cursor <= CURSOR_MAX:
            raise HipRngError("cursor out of range: %r" % (cursor,))
        self._seed = seed
        self._name = name
        self._key = stream_key(seed, name)
        self._cursor = cursor

    @property
    def seed(self) -> int:
        return self._seed

    @property
    def name(self) -> str:
        return self._name

    @property
    def key(self) -> tuple[int, int]:
        return self._key

    @property
    def cursor(self) -> int:
        """Number of next_u32() results consumed so far (rejected draws included)."""
        return self._cursor

    def next_u32(self) -> int:
        if self._cursor >= CURSOR_MAX:
            raise HipRngError("stream exhausted: cursor reached 2**63-1")
        value = _word(self._key, self._cursor)
        self._cursor += 1
        return value

    def below(self, n: int) -> int:
        """Uniform integer in [0, n) for 1 <= n <= 2**32, exact (threshold rejection).

        Always consumes at least one word, also for n == 1.
        """
        if isinstance(n, bool) or not isinstance(n, int) or not 1 <= n <= BELOW_MAX:
            raise HipRngError("below(n) requires 1 <= n <= 2**32, got %r" % (n,))
        threshold = BELOW_MAX % n
        while True:
            value = self.next_u32()
            if value >= threshold:
                return value % n

    def save(self) -> dict[str, str]:
        """The {seed, cursor} shape of SaveEnvelope rng_policy.streams.<name>."""
        return {"seed": format_u64(self._seed), "cursor": format_u64(self._cursor)}

    @classmethod
    def restore(cls, name: str, saved: dict) -> "HipRng":
        if not isinstance(saved, dict) or set(saved) != {"seed", "cursor"}:
            raise HipRngError("saved stream must have exactly the keys seed and cursor")
        return cls(parse_u64(saved["seed"]), name, parse_cursor(saved["cursor"]))


def new_run_streams(run_seed: int) -> dict[str, HipRng]:
    """All registered streams of a new run: same seed, separated by name, cursor 0."""
    return {name: HipRng(run_seed, name) for name in STREAMS}


def restore_run_streams(run_seed: int, saved_streams: dict) -> dict[str, HipRng]:
    """Restore rng_policy.streams; any unknown, missing or foreign-seed stream is rejected."""
    if not isinstance(saved_streams, dict) or set(saved_streams) != set(STREAMS):
        raise HipRngError("streams must be exactly: " + ", ".join(STREAMS))
    result = {}
    for name in STREAMS:
        stream = HipRng.restore(name, saved_streams[name])
        if stream.seed != run_seed:
            raise HipRngError("stream seed differs from the run seed: " + name)
        result[name] = stream
    return result


# ---------------------------------------------------------------- golden vectors

# Published known-answer tests of Threefry-2x32-20 (Random123 kat_vectors).
THREEFRY_KAT = (
    ((0x00000000, 0x00000000), (0x00000000, 0x00000000), (0x6B200159, 0x99BA4EFE)),
    ((0xFFFFFFFF, 0xFFFFFFFF), (0xFFFFFFFF, 0xFFFFFFFF), (0x1CB996FC, 0xBB002BE7)),
    ((0x13198A2E, 0x03707344), (0x243F6A88, 0x85A308D3), (0xC4923A9C, 0x483DF7A0)),
)

VECTOR_SEEDS = (0, 1, 280617, 1 << 63, U64_MAX)
# 2147483649 and 3000000000 reject about 50% / 30% of words, so the rejection
# branch and the cursor accounting are really exercised.
VECTOR_BOUNDS = (1, 2, 3, 6, 10, 1000, 2147483649, 3000000000, 4294967295, 4294967296)
VECTOR_BELOW_DRAWS = 12
VECTOR_FAR_CURSORS = (4294967295, 4294967296, 8589934597, CURSOR_MAX - 7)


def build_vectors() -> dict:
    kat = [{"key": list(key), "counter": list(counter), "output": list(output)}
           for key, counter, output in THREEFRY_KAT]

    streams = []
    for seed in VECTOR_SEEDS:
        for name in STREAMS:
            rng = HipRng(seed, name)
            streams.append({
                "seed": format_u64(seed),
                "stream": name,
                "name_words": list(stream_name_words(name)),
                "key": list(rng.key),
                "next_u32": [rng.next_u32() for _ in range(16)],
                "cursor_after": format_u64(rng.cursor),
            })

    below = []
    for seed_index, seed in enumerate(VECTOR_SEEDS):
        for bound_index, bound in enumerate(VECTOR_BOUNDS):
            name = STREAMS[(seed_index + bound_index) % len(STREAMS)]
            rng = HipRng(seed, name)
            values = [rng.below(bound) for _ in range(VECTOR_BELOW_DRAWS)]
            below.append({
                "seed": format_u64(seed),
                "stream": name,
                "n": bound,
                "values": values,
                "cursor_after": format_u64(rng.cursor),
            })

    random_access = []
    for seed in (0, 280617, U64_MAX):
        for cursor in VECTOR_FAR_CURSORS:
            rng = HipRng(seed, "enemy", cursor)
            random_access.append({
                "seed": format_u64(seed),
                "stream": "enemy",
                "cursor": format_u64(cursor),
                "next_u32": [rng.next_u32() for _ in range(4)],
                "cursor_after": format_u64(rng.cursor),
            })

    restore = []
    for seed, name in ((0, "drops"), (1, "offers"), (1 << 63, "stage"), (U64_MAX, "enemy")):
        original = HipRng(seed, name)
        for _ in range(37):
            original.next_u32()
        saved = original.save()
        resumed = HipRng.restore(name, saved)
        after = [resumed.next_u32() for _ in range(8)]
        if after != [original.next_u32() for _ in range(8)]:
            raise HipRngError("restore diverged from the uninterrupted stream")
        restore.append({
            "seed": format_u64(seed),
            "stream": name,
            "advance_next_u32": 37,
            "saved": saved,
            "next_u32_after_restore": after,
        })

    # Mixed use with real rejections: save in the middle, continue after restore.
    mixed_ops = [["below", 2147483649], ["next_u32"], ["below", 6], ["below", 3000000000],
                 ["below", 1], ["next_u32"], ["below", 4294967296], ["below", 1000]]
    mixed = []
    for seed in (280617, U64_MAX):
        rng = HipRng(seed, "offers")
        steps = []
        for round_index in range(3):
            for op in mixed_ops:
                step = {"op": op[0]}
                if op[0] == "below":
                    step["n"] = op[1]
                    step["value"] = rng.below(op[1])
                else:
                    step["value"] = rng.next_u32()
                step["cursor_after"] = format_u64(rng.cursor)
                steps.append(step)
            if round_index == 0:
                rng = HipRng.restore("offers", rng.save())
        mixed.append({"seed": format_u64(seed), "stream": "offers",
                      "restore_after_step": len(mixed_ops), "steps": steps})

    return {
        "schema_version": VECTORS_SCHEMA_VERSION,
        "kind": "hip-rng-vectors",
        "rng_policy_id": POLICY_ID,
        "generator": "tools/content/hip_rng.py",
        "algorithm": {
            "block": "threefry2x32",
            "rounds": ROUNDS,
            "ks_parity": KS_PARITY,
            "rotations": list(ROTATIONS),
            "cursor_max": format_u64(CURSOR_MAX),
            "below_max": BELOW_MAX,
            "streams": list(STREAMS),
        },
        "threefry_kat": kat,
        "streams": streams,
        "below": below,
        "random_access": random_access,
        "restore": restore,
        "mixed": mixed,
    }


def vectors_bytes() -> bytes:
    text = json.dumps(build_vectors(), ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
    return (text + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    expected = vectors_bytes()
    if "--check" in argv:
        if not VECTORS_PATH.is_file() or VECTORS_PATH.read_bytes() != expected:
            print("FAIL: " + VECTORS_PATH.relative_to(ROOT).as_posix() + " differs from the reference")
            return 1
        print("OK: rng vectors match the reference")
        return 0
    VECTORS_PATH.parent.mkdir(parents=True, exist_ok=True)
    VECTORS_PATH.write_bytes(expected)
    print("written " + VECTORS_PATH.relative_to(ROOT).as_posix() + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
