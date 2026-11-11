# BUILD-SKILL-001 — reference design fixtures (NOT canonical)

**Status:** PROPOSAL / STATIC SPECIFICATION EXAMPLE, not in-game content, not a Godot implementation.

The single runtime-facing design source of truth remains [v7](../../config/v7/README.md). This directory intentionally contains **sample.** IDs, synthetic test ranks and minimal entities. None are importable content. No balance or gameplay effectiveness is claimed.

## What is covered

- Active, passive and Power inventories are disjoint.
- Class start skill IDs spirit_sword and thunder_chain, and status IDs mark and shock, must still exist in v7.
- Distinct school tags / elements / attack geometry.
- A skill evolution, a two-input Union and a nonconsuming Gift.
- A conflict witness: both evolution and Union require the same base, so explicit paused choice is required; no implicit JSON-order priority.
- Five positive/negative witness states; exact expected eligible recipes.
- Draft **eligibility** only (not weighted sampling, probabilities or in-game cards).
- Static proc graph rooted in DIRECT_CAST; detects any cycle and limits conservative worst-case tree expansion.

## Commands

    python scripts/validate_build_proposal.py
    python -m unittest discover -s tests -p test_build_proposal.py -v

The script uses only the Python standard library. GitHub CI runs the second via the usual unit-test discovery. **These verify only design data and reference transition semantics**, not actual in-game behavior.

## Deliberate limitations

1. Does not claim JSON Schema 2020-12 compliance; the current parser performs focused semantic and primitive checks. A formal Draft 2020-12 structural schema is a future authoring decision.
2. Does not implement weighted RNG, reroll, lock, pity policies, synergy graph, player movement, combat or rendering.
3. Does not enumerate every possible arbitrary build. Witnesses demonstrate specific legal paths; proof of global reachability is future work.
4. The proc bound counts a conservative **tree of events**. It is not CPU time, FPS or a complete bound for every future EffectOp. Rules with generational loops require a different explicit bounded analysis; this fixture rejects cycles.
5. Transaction example verifies build projections and revision guards; storage atomicity and concurrent event scheduling require future runtime tests.
6. Any number in this fixture is a **synthetic structural testing input**. Never copy it into authoritative gameplay economy or balance.

## Authoring sequence

1. Resolve open design decisions in [BUILD-SKILL-001](../../spec/v7/build-skill-architecture-proposal.md).
2. Extend contract/fixture and add a failing negative test.
3. Update the static checker until tests pass.
4. Inspect effect graph and dependency impact.
5. Promote an explicitly approved schema/design into v7 in a separate reviewed slice; retain provenance.

[Content authoring workflow](../../guides/CONTENT_AUTHORING_ACCELERATOR.md) · [Skill template](../../templates/SKILL_SPEC.md)
