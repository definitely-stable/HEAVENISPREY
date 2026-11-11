# BUILD-SKILL-001 — unresolved architectural decisions

- **Status:** review-required / proposal-only
- **Date:** 2026-11-11
- **Authority:** subordinate to accepted ADR-002 and ADR-006. Does NOT alter canonical v7 gameplay definitions.
- **Goal:** prevent agents from silently converting design hypotheses into accepted rules.

| ID | Priority | Question | Recommended default (NOT ACCEPTED) | Design counter-risk | Acceptance evidence |
|---|---|---|---|---|---|
| BLD-01 | P0 | Active/passive capacity | **Configurable mode policy**, e.g. 6+6 standard and optional bonuses/extra slots; no engine ceiling | Too many slots may dilute meaningful choices | Expanded-capacity static tests + future balance |
| BLD-02 | P0 | Power inventory | No inventory slot; capped stacks and static effect fanout | Unbounded event graph | Max-stacks and budget negative fixture |
| BLD-03 | P0 | Acquisition source | Distinct active/passive/Power/transform/realm/meta categories | Meta talents mistaken for in-run passives | Type taxonomy tests |
| BLD-04 | P0 | Active ranks | Per-skill authored ranks, optional post-max growth policy; **not fixed 5** | Excess low-value rank cards may clog draft | Per-skill rank-12 test + later Limit Break schema |
| BLD-05 | P0 | Full active slots | Normal draft respects current capacity; special drops/union/meridian can **increase capacity** | Capacity grants can trivialize slot choice | Policy-dependent acquisition test |
| BLD-06 | P0 | Replacing skill | No implicit refund; rank of replacement begins at 1 | Sunk cost makes experimentation unattractive | Design review and explicit choice UI |
| BLD-07 | P0 | Evolution gate | Specific ritual/chest reward; not any random level-up | Evolution may never become reachable | Minimum-picks witness and time gate |
| BLD-08 | P0 | Alternative recipes | Paused choice when both consume same input | Silent arbitrary recipe selection | Conflict witness / revision guard |
| BLD-09 | P0 | Gift capacity | Mode/class/event-defined special capacity; one is **sample only** | Unbounded automatic casts if all gifts active | Variable-capacity static test |
| BLD-10 | P0 | Event order | Stable monotonic event index, declared priority for concurrent level-up/rewards | Nondeterministic consumed components | Multiple-event golden examples (future) |
| BLD-11 | P0 | SkillChain/Multicast | Safe direct-only preset; **bounded recursive chains allowed by explicit generation/resource budget** | Silent event loss or nontermination | Both bounded and unbounded cycle tests |
| BLD-12 | P0 | Draft fallback | Explicit typed fallback, never silent invalid card | Stalled level-up or unplanned farm | Empty/few-eligible fixture |
| BLD-13 | P0 | Draft randomness | Stable canonical ID order and separate RNG stream | JSON reorder changes outcome | Eligibility order test; seeded sampler later |
| BLD-14 | P1 | Pity / guaranteed synergy | No hidden pity. Any protection must be declared and deterministic | Optimal combinations become guaranteed | User-facing rule and distribution tests |
| BLD-15 | P1 | Reroll / Banish / Lock | Reroll + Banish eventually; Lock remains optional proposal | Save/draft edge cases | Paused event reproducibility |
| BLD-16 | P0 | Qi vs XP | Separate run tracks; class mastery separate profile track | Feedback loop doubles progression | RunBuild/Meta boundaries |
| BLD-17 | P0 | Breakthrough timing | Automatic Qi accumulation; choose rule/meridian on pause; manual timing OPEN | Loss of agency vs violated auto-combat | Explicit rule and human UX test later |
| BLD-18 | P1 | Status source counting | Distinct skill count != distinct status source count | Conditional Powers wrongly eligible | Source-key negative fixture |
| BLD-19 | P0 | Visual-referenced assets | Reference board != production sprite | Animation mismatch / copyright provenance | Reference manifest and visual gate |
| BLD-20 | P0 | Content migration/hash | Include schema + rules + canonicalized definitions in hash | Incompatible saves/replay drift | Canonical byte policy and migration fixtures |
| BLD-21 | P1 | Actual balance thresholds | Leave numerical DPS/rewards unset pending gameplay tests | False precision / scope creep | Real runtime/playtest later |

**User direction:** prioritise freedom of combinations; values such as 6 slots, 5 ranks and recursion disabled are **presets**, not automatic product decisions. The technical invariant is a proved finite process, never a silent DPS/VFX nerf.

| BLD-22 | P0 | Duplicate owned skill copies | Optional independent instances keyed by instance_uid; no global duplicate ban in future type system | Consumed instance and cooldown attribution ambiguous | UID/cooldown ownership design fixture (NOT YET IMPLEMENTED) |
| BLD-23 | P0 | N-to-M unions and multi-tier recipes | Transformations may consume evolved forms and produce several typed grants | Slot accounting / recipe loops | Graph witness and future typed schema (NOT YET IMPLEMENTED) |
| BLD-24 | P1 | Growth beyond normal max | Post-max Limit Break with declared property scaling | Endless ranking noise / overflow | Explicit growth policy and formal scale bound |
| BLD-25 | P1 | Proc bounded recursion | Acyclic profile or explicit finite generation/resource policy | New constraint may silently remove promised reaction | Bounded-cycle and rejection tests; design policy must be visible |

## Resolution procedure

1. Proposal author provides evidence and at least one counterexample for the selected ID.
2. Review distinguishes (a) objectively checkable invariant, (b) aesthetic/design preference, and (c) numerical balance hypothesis.
3. Only accepted decisions may modify a canonical ADR or v7 catalog.
4. New change must update authoring template, test fixture, validator and dependent index **in one PR**.
5. If unresolved, preserve the existing assumption as **OPEN**, do not invent a default in implementation.
6. Current user scope forbids Godot runtime and game creation; BLD-21 stays open until that scope changes.

[Build system proposal](../../spec/v7/build-skill-architecture-proposal.md) · [FLEXIBILITY-FIRST-001](../../spec/v7/flexibility-first-build-policies.md) · [Static witnesses](README.md) · [Authoring guide](../../guides/CONTENT_AUTHORING_ACCELERATOR.md)
