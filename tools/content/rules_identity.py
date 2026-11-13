"""hip-rules-hash-v1: reference encoding of RulesHash (ADR-007, section d).

rules_hash = sha256(preimage) as lowercase hex, where the preimage is NOT JSON:

    ASCII "HEAVENISPREY/RULES-HASH/v1" + 0x00
    F(sim_schema_version as canonical decimal)
    F(content_digest)          64 lowercase hex chars = sha256 of registry.json bytes
    F(rng_policy_id)
    F(stage_id)
    F(difficulty_id)
    U32BE(number of modes), then F(mode_id) for every mode sorted by bytes
    F(class_id)
    F(run seed as canonical decimal uint64)

    F(s) = U32BE(byte length of s) + ASCII bytes of s

Every field is ASCII in v1, so a GDScript port reproduces the bytes with
PackedByteArray and hashes them with HashingContext.

This module is the oracle for game/tests/fixtures/rules_hash_vectors.json:
    python tools/content/rules_identity.py            # rewrite the golden vectors
    python tools/content/rules_identity.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ENCODING_ID = "hip-rules-hash-v1"
DOMAIN_PREFIX = b"HEAVENISPREY/RULES-HASH/v1"
VECTORS_SCHEMA_VERSION = 1
SIM_SCHEMA_VERSION = 4          # simulation schema since enemy separation (ADR-009 section 2)
RNG_POLICY_ID = "hip-rng-v1"

U32_MAX = (1 << 32) - 1
U64_MAX = (1 << 64) - 1

_U64_RE = re.compile(r"0|[1-9][0-9]{0,19}")
_ID_RE = re.compile(r"[a-z0-9_]+(\.[a-z0-9_]+)+")
_POLICY_RE = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
_DIGEST_RE = re.compile(r"[0-9a-f]{64}")

FIELD_ORDER = ("sim_schema_version", "content_digest", "rng_policy_id", "stage_id",
               "difficulty_id", "mode_ids", "class_id", "seed")

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "rules_hash_vectors.json"


class RulesIdentityError(ValueError):
    """Any rejected input: the reference fails closed and never normalizes silently."""


def _u32be(value: int) -> bytes:
    return value.to_bytes(4, "big")


def _field(text: str) -> bytes:
    data = text.encode("ascii")
    return _u32be(len(data)) + data


def _match(pattern: re.Pattern, value: object, what: str) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise RulesIdentityError("invalid " + what + ": %r" % (value,))
    return value


def rules_preimage(*, sim_schema_version: int, content_digest: str, rng_policy_id: str,
                   stage_id: str, difficulty_id: str, mode_ids: list[str], class_id: str,
                   seed: str) -> bytes:
    """Exact bytes hashed by rules_hash(). The seed is a canonical uint64 decimal string."""
    if (isinstance(sim_schema_version, bool) or not isinstance(sim_schema_version, int)
            or not 0 <= sim_schema_version <= U32_MAX):
        raise RulesIdentityError("sim_schema_version must be a uint32")
    _match(_DIGEST_RE, content_digest, "content_digest")
    _match(_POLICY_RE, rng_policy_id, "rng_policy_id")
    _match(_ID_RE, stage_id, "stage_id")
    _match(_ID_RE, difficulty_id, "difficulty_id")
    _match(_ID_RE, class_id, "class_id")
    if not isinstance(mode_ids, (list, tuple)):
        raise RulesIdentityError("mode_ids must be a list")
    for mode_id in mode_ids:
        _match(_ID_RE, mode_id, "mode_id")
    if len(set(mode_ids)) != len(mode_ids):
        raise RulesIdentityError("duplicate mode_id")
    _match(_U64_RE, seed, "seed")
    if int(seed) > U64_MAX:
        raise RulesIdentityError("seed exceeds uint64")

    ordered_modes = sorted(mode_ids, key=lambda item: item.encode("ascii"))
    parts = [
        DOMAIN_PREFIX + b"\x00",
        _field(str(sim_schema_version)),
        _field(content_digest),
        _field(rng_policy_id),
        _field(stage_id),
        _field(difficulty_id),
        _u32be(len(ordered_modes)),
    ]
    parts += [_field(mode_id) for mode_id in ordered_modes]
    parts += [_field(class_id), _field(seed)]
    return b"".join(parts)


def rules_hash(**fields) -> str:
    return hashlib.sha256(rules_preimage(**fields)).hexdigest()


# ---------------------------------------------------------------- golden vectors

def _digest_of(label: str) -> str:
    """Synthetic content digests: the vectors must not depend on the live registry."""
    return hashlib.sha256(label.encode("ascii")).hexdigest()


def _case(name: str, **fields) -> dict:
    return {"name": name, "input": fields}


VECTOR_CASES = (
    _case("no_modes_seed_zero",
          sim_schema_version=1, content_digest=_digest_of("hip-test-content-a\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.jade_grove",
          difficulty_id="difficulty.apprentice", mode_ids=[], class_id="class.sword", seed="0"),
    _case("single_mode",
          sim_schema_version=1, content_digest=_digest_of("hip-test-content-a\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.jade_grove",
          difficulty_id="difficulty.standard", mode_ids=["mode.normal"], class_id="class.sword",
          seed="280617"),
    _case("modes_given_unsorted",
          sim_schema_version=1, content_digest=_digest_of("hip-test-content-a\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.mist_cliffs",
          difficulty_id="difficulty.tribulation",
          mode_ids=["mode.hyper", "mode.ascetic", "mode.hurry"], class_id="class.thunder",
          seed="9223372036854775808"),
    _case("modes_given_sorted_same_hash_as_unsorted",
          sim_schema_version=1, content_digest=_digest_of("hip-test-content-a\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.mist_cliffs",
          difficulty_id="difficulty.tribulation",
          mode_ids=["mode.ascetic", "mode.hurry", "mode.hyper"], class_id="class.thunder",
          seed="9223372036854775808"),
    _case("max_seed_other_content_and_schema",
          sim_schema_version=4294967295, content_digest=_digest_of("hip-test-content-b\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.mist_cliffs",
          difficulty_id="difficulty.abyss", mode_ids=["mode.endless_limited"],
          class_id="class.thunder", seed="18446744073709551615"),
    # mode_10 sorts before mode_9 by bytes; a numeric-aware sort would break parity.
    _case("bytewise_sort_not_natural_sort",
          sim_schema_version=1, content_digest=_digest_of("hip-test-content-b\n"),
          rng_policy_id=RNG_POLICY_ID, stage_id="stage.jade_grove",
          difficulty_id="difficulty.hard",
          mode_ids=["mode.test_9", "mode.test_10", "mode.test.a", "mode.test_a"],
          class_id="class.body", seed="1"),
)

_VALID = dict(sim_schema_version=1, content_digest=_digest_of("hip-test-content-a\n"),
              rng_policy_id=RNG_POLICY_ID, stage_id="stage.jade_grove",
              difficulty_id="difficulty.standard", mode_ids=["mode.normal"],
              class_id="class.sword", seed="1")

# Inputs that every implementation must reject instead of hashing.
INVALID_CASES = (
    ("seed_leading_zero", {"seed": "01"}),
    ("seed_overflow", {"seed": "18446744073709551616"}),
    ("seed_negative", {"seed": "-1"}),
    ("seed_empty", {"seed": ""}),
    ("duplicate_mode", {"mode_ids": ["mode.normal", "mode.normal"]}),
    ("non_ascii_stage_id", {"stage_id": "stage.нефрит"}),
    ("uppercase_class_id", {"class_id": "class.Sword"}),
    ("id_without_namespace", {"difficulty_id": "standard"}),
    ("digest_uppercase", {"content_digest": _digest_of("hip-test-content-a\n").upper()}),
    ("digest_short", {"content_digest": "abc123"}),
    ("empty_rng_policy", {"rng_policy_id": ""}),
    ("negative_schema_version", {"sim_schema_version": -1}),
    # Regex engines whose `$` matches before a final newline must still reject these.
    ("class_id_trailing_newline", {"class_id": "class.sword\n"}),
    ("mode_id_trailing_newline", {"mode_ids": ["mode.normal\n"]}),
    ("digest_trailing_newline", {"content_digest": _digest_of("hip-test-content-a\n") + "\n"}),
    ("rng_policy_trailing_newline", {"rng_policy_id": "hip-rng-v1\n"}),
)


def build_vectors() -> dict:
    cases = []
    for case in VECTOR_CASES:
        preimage = rules_preimage(**case["input"])
        cases.append({
            "name": case["name"],
            "input": case["input"],
            "preimage_hex": preimage.hex(),
            "rules_hash": hashlib.sha256(preimage).hexdigest(),
        })
    invalid = []
    for name, override in INVALID_CASES:
        fields = dict(_VALID)
        fields.update(override)
        try:
            rules_preimage(**fields)
        except RulesIdentityError:
            invalid.append({"name": name, "input": fields})
        else:
            raise RulesIdentityError("invalid case was accepted: " + name)
    return {
        "schema_version": VECTORS_SCHEMA_VERSION,
        "kind": "hip-rules-hash-vectors",
        "encoding_id": ENCODING_ID,
        "generator": "tools/content/rules_identity.py",
        "domain_prefix": DOMAIN_PREFIX.decode("ascii"),
        "field_order": list(FIELD_ORDER),
        "cases": cases,
        "invalid": invalid,
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
        print("OK: rules hash vectors match the reference")
        return 0
    VECTORS_PATH.parent.mkdir(parents=True, exist_ok=True)
    VECTORS_PATH.write_bytes(expected)
    print("written " + VECTORS_PATH.relative_to(ROOT).as_posix() + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
