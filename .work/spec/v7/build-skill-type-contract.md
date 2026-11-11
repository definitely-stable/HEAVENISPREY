# ARCH-01 — Typing and lifecycle contract for skills, passives, powers, builds

- **Status:** DESIGN PROPOSAL; not approved, not game content, not runtime-implemented
- **Date:** 2026-11-11
- **Owner domain:** Build & Skill System
- **Dependencies:** [BUILD-SKILL-001](build-skill-architecture-proposal.md), [ADR-002](../../decisions/ADR-002-combat.md), [ADR-006](../../decisions/ADR-006-content-catalog.md), [reference fixtures](../../proposals/build-skill-001/README.md)
- **Non-goals:** Godot code, scene authoring, tuning numeric DPS, final art, auto-gameplay
- **Evidence:** 19 isolated build-design tests + four dependency impact tests; GitHub CI evidence belongs to PR, not assumed here

## 1. Strict boundaries

The canonical v7 `skills.json` and `talents.json` remain unchanged. Proposed types below define how future schemas should evolve **after review**. The `sample.*` fixture IDs deliberately cannot be mistaken for canonical IDs.

**Definitions** are immutable and content-hashed. **Instances** have owner, current rank/stacks and a build revision. **Presentation** and authored artwork are separately referenced. A skill description is not an executable function.

| Concept | Definition | Runtime instance (future) | Lifetime |
|---|---|---|---|
| Active technique | `SkillDef` | `ActiveSkillInstance` + `SkillCastRuntime` | Current run |
| Passive art | `PassiveArtDef` | `PassiveArtInstance` | Current run |
| Power | `PowerDef` | `PowerStack` | Current run |
| Intrinsic class skill | `ClassIntrinsicDef` | `ClassIntrinsicState` | Current run |
| Evolution/Union/Gift | `TransformationDef` | Transaction record / provenance | Acquisition event |
| Cultivation route | `MeridianDef` | Realm/route state | Current run |
| Global/mastery talent | existing `TalentDef` | Meta profile entry | Across runs |

No `talents.json` mapping directly onto run-passive slots. Scope differences are semantic, not cosmetic.

## 2. Structural contract for skills

`SkillDef` **required domain groups** (later map to concrete schema fields):

| Group | Required / optional | Purpose |
|---|---|---|
| Identity | required ID, localization keys, schema/status | Stable identity and honest availability |
| Accessibility | required acquisition type, class allowlist, unlock requirements | Who can obtain it and how |
| Tags | separate school, element, geometry, delivery, source-of-status | Conditional Powers and counterplay |
| Ranks | required rank 1..max, per-rank deltas or authored operations | No hidden changes |
| Scheduling | required timing and no-target policy; optional windup/recovery | Auto attacks, not animation callbacks |
| Targeting | required target policy + deterministic tie-break | Different meanings for cone, chain, zone |
| Combat semantics | effect ops, hit policy, snapshot ownership | Exact damage/status provenance |
| Proc safety | allowed proc origins, max targets/echoes/depth, declared upper bound | Finite event fanout |
| Presentation | art-ref ID, semantic VFX tags, warning priority | Visuals never drive damage |
| Transformability | permissible recipe IDs / exclusivity | Evolutions, union, gift |

**Hard rule:** `school_tags`, `element_tags` and `geometry_kind` never occupy the same untyped array. A source with multiple independent burn operations does not automatically count as multiple **unique skills**.

**Unknown fields:** fail structural validation after the full schema is approved; for now fixture checker validates the most consequential semantic fields, and is not claimed to be JSON Schema-complete.

## 3. Passive vs Power vs intrinsic (future schema rules)

**PassiveArtDef:** `id`, `max_rank`, `slot_cost`, effect ops with scope, catalyzes recipes, acquisition restrictions, localization. A passive can remain useful after evolution. Catalyst preservation/consumption belongs to the recipe, not an implicit global rule.

**PowerDef:** `id`, explicit `stack_policy`, `max_stacks` (or finite author-approved bound), `applicability_predicate`, modifier stage, rarity/pool policy, conditional source count semantics. No inventory slot does **not** imply infinite computational cost. Define when eligibility is checked (before draw; at card confirmation; after transformation).

**ClassIntrinsicDef:** `class_id`, `resource_key`, trigger set, accumulation/decay bounds, automatic activation, safe cooldown policy, release/event flags. Each class can use a unique mechanic without special-casing the generic damage pipeline.

## 4. Build state and optimistic revision

Future `RunBuild` minimal snapshot:

- `run_rules_hash`, `content_digest`, `class_id`, `build_revision`;
- active [{skill_id, rank, slot, definition_revision}], passive [{art_id, rank, slot}], powers [{power_id, stacks, provenance}], class intrinsic state, cultivation state;
- banned/locked offer metadata, draft history and **separately versioned** RNG stream snapshots;
- transformation history (id, consumed component IDs, granted ID, revision, event seq).

All mutations require `expected_build_revision == current`, acquire a single logical transaction, validate capacity and exclusivity, apply all changes, then increment revision and recompute derived modifiers. Rejection causes no partial consumption or RNG ambiguity.

**Event ordering:** acquisition event IDs are monotonic. When level-up and ritual reward occur at the same tick, event order must be defined and persisted; neither should win based on arbitrary array iteration. Unresolved as BLD-10.

## 5. Draft offers and their eligibility

`OfferDef` has an independent ID, action kind, target, requirements, weighting policy and display key. Rank-up an owned skill and acquisition of that skill are *different offers*, even if the target is identical.

Eligibility should check: source unlock, applicable class/mode, target not already owned (for acquisition), available slot, positive remaining ranks/stacks, mutual exclusions, current source tags and source counts, ban state, policy allowlists.

RNG sampling happens only **after deterministic candidate enumeration**. The isolated fixture checks candidate-set stability under offer order reversal, but **does not implement weighted RNG or fairness**. Needed next: explicit integer/rational weights, unbiased sampling without replacement, stream state persistence, fallback when fewer than three offers are legal.

No AI classification of a 'good build' at runtime. Any anti-brick condition must be a formal predicate with visible scope.

## 6. Transformation requirements

All transformations have explicit typed preconditions and grants.

- EVOLUTION consumes one owned active skill; may preserve passive catalysts; grant remains an active skill.
- UNION consumes two or more owned active skills; new occupancy is `old_count - consumed_count + grant_slot_cost`.
- GIFT keeps source skills unless a separately accepted gift subtype says otherwise; special capacity is explicit.
- SYNERGY is **not** a consuming transformation; it is a triggered conditional effect or modifier.
- BREAKTHROUGH changes realm/meridian state; it is not a normal level-up or recipe.
- MORPH changes class/character identity; deliberately deferred.

Two recipes consuming the same active skill form an exclusive choice. If their requirements are simultaneously met, do not auto-resolve by JSON order. A grant must not be duplicated by stale, simultaneous requests. Committed in-flight attacks keep their own snapshot unless an explicitly named policy revokes them.

## 7. Modifiers and provenance

Modifiers require a stable `stage`/operation, normalized source and combining rule. Never assume that '20% more' and '+20%' are equivalent. A single status application is distinct from `HitResolved`; DoT ticks are not primary hits; echo/chained origins cannot recursively fire the same chains by default.

A formula with floats needs a documented quantization boundary and cross-platform golden tests later; a design-only JSON fixture cannot establish numerical replay identity.

## 8. Validated now vs not yet validated

| Check | Existing isolated design test | Still missing |
|---|---|---|
| Known v7 skill/status references | Yes | Global authoring schema |
| Rank and slot constraints | Yes, fixture examples | All production catalog combinations |
| Evolution, Union and Gift witnesses | Yes | Arbitrary graph solver |
| Conflicting recipes and stale revision | Yes, static projection | Concurrent runtime transactions |
| Draft eligibility | Yes, unweighted | Seeded weighted draws / odds distribution |
| Acyclic proc graph and conservative root bound | Yes | Nested bounded cycles / real perf |
| Reverse-ID impact | Yes, canonical v7 | Semantic/tag-based impact |
| Import/render/replay/visual playtest | No | Deferred until user authorizes game |

## 9. Architecture acceptance gate

To promote this proposal into an ADR:
1. Resolve [open design decisions](../../proposals/build-skill-001/OPEN_DECISIONS.md) and choose schema version/migration.
2. Specify formal `EffectOp` discriminated unions, rank overrides and typed predicates (including negative examples).
3. Add declarative valid/invalid fixtures for every kind, with expected error IDs.
4. Design a valid build witness path for each recipe and document where proof ends.
5. Keep cross-reference integrity, deterministic ordering, atomicity and static proc bounds in required CI.
6. Confirm no gameplay code or production assets are inadvertently introduced.

This contract intentionally prevents premature declaration that the game or its skills are implemented.
