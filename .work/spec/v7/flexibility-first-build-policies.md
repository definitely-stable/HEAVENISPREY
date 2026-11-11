# FLEXIBILITY-FIRST-001 — свобода билдов как архитектурный принцип

- **id:** FLEXIBILITY-FIRST-001
- **status:** design proposal; user direction: **do not overconstrain builds**
- **date:** 2026-11-11
- **supersedes:** no accepted ADR; revises overly restrictive *defaults* in BUILD-SKILL-001/ARCH-01 (not the existing canonical v7 data)
- **dependencies:** [BUILD-SKILL-001](build-skill-architecture-proposal.md), [ARCH-01](build-skill-type-contract.md), [ADR-002](../../decisions/ADR-002-combat.md), [ADR-006](../../decisions/ADR-006-content-catalog.md)
- **non-goals:** gameplay/Godot code, hard numeric balance, production content, assets, perf claims, unreviewed merge

## 1. Rule: capability != policy != guardrail

1. **Capability**: the system *can express* multiple copies, evolved skills in a union, slot grants, multi-input recipes, rank overflow, diverse tags, long proc chains, endless modes.
2. **Mode / acquisition policy**: an individual run *chooses* allowed acquisition sources, initial slots, extra slots, replacement, rarity, transformation availability and whether rank extensions are offered.
3. **Technical invariant**: reproducibility, finite state/event transitions, stable ownership, deterministic ordering, no silent loss of promised gameplay outcomes.

Never confuse game-design defaults with engine limits. `6 active + 6 passive + 5 ranks` is a possible standard-mode preset, not a structural ceiling. `max_proc_events_per_root=128` in sample catalog is a **synthetic test budget**, not a proposed global technical limit.

Do **not** claim 'unlimited supported' without memory/counter bounds and profiling; a configurable high cap is different from a proven infinite system. Endless progression should be scalable by construction and validated via separate stress profiles.

## 2. Policy layers (composable, explicit, hashable)

`RunAcquisitionPolicy` declares initial active/passive capacity, allowed extra slots from drops/union/meridian/mode, per-source overrides and replacement rules. It supports *increased* capacity and intentional one-skill challenge runs. No forced 6-slot cap embedded in `SkillDef`.

`SkillGrowthPolicy` declares the authored rank track, optional named post-max growth (Limit Break), and per-property scaling. Authored functional ranks and repeatable stat growth are different systems; rank extensions need not create endless manually authored level rows.

`DuplicatePolicy` can forbid duplicates, permit separate skill instances, or grant additional linked casts. When duplicate instances are allowed, each owns an `instance_uid`, cooldown, rank, source, slot cost and attribution; `skill_id` alone is not a unique inventory key.

`TransformationPolicy`: EVOLUTION, UNION, GIFT and MUTATION remain distinct; inputs/outputs may include evolved forms. Allow **N-to-M** transformations for future content (not only N-to-1), with slot-cost calculations across all outputs. Grant-only and retain-all transforms are valid when explicitly authored. Special slots and gift capacity are policy choices.

`ProcPolicy` declares allowed origin transitions, per-op fanout, generation/charge/unique-target limits and the *bound used for validation*. Recursion is not categorically forbidden: **bounded** cycles may be allowed by a decreasing resource, cooldown/event gate or explicit generation limit, provided their total event work is demonstrably finite. The baseline direct-cast/no-retrigger model remains a conservative **preset**, not a global law.

`DraftPolicy` declares offer count, categories, weighting, pity/anti-brick, replacement and fallback. Contextual restrictions should be predicates, not hardcoded to 'exactly three cards'. A 4-card or special 5-card reward is representable without schema changes.

## 3. Progression should support three equally valid build fantasies

- **Focused ascendant:** 1–2 heavily invested skills, strong Limit Break/mutation, fewer sockets.
- **Arsenal ascendant:** many distinct skills, extra sockets, overlapping schools, multi-stage unions.
- **Reaction architect:** smaller set of well-chosen abilities with deep status synergies, status consumption, chains and ritual interactions.

No fantasy automatically dominates others. The purpose is *viable diversity* rather than equal DPS; extremely OP combinations are welcome as rewards for investment if they do not render every alternative trivially obsolete.

Builds must be allowed to branch and converge: `A→E1`, `A+B→U1`, `E1+C→U2`, `U1+D→Gift`. This requires ancestor/provenance tracking and explicit recipe eligibility; no hardcoded prohibition on evolved source inputs.

## 4. Improve 'limits' into deliberate levers

| Previously implicit restriction | Preferred architecture |
|---|---|
| Exactly 6 active / 6 passive | `capacity_policy` with defaults plus typed extra-slot sources |
| One copy per skill forever | `DuplicatePolicy` with optional independent instance IDs |
| Max rank 5 for all | Per-skill authored ranks and independent post-cap progression |
| One output from Union | Array of typed grants and consumes, future N-to-M |
| One Gift capacity | Mode/class/item-specific capacity |
| One evolution tier | Optional transformation tiers with cycle/reachability checks |
| No proc recursion ever | Policy-permitted **finite** cycles with verified bound |
| Fixed 3-card choice | Offer count and category distribution by source/mode |
| Fixed 100% chance ceiling | Explicit interpretation of overcap (extra rolls, conversion, diminishing gains), never accidental truncation |
| Rigid school purity | Cross-school tags, multi-tag techniques, trait-based Powers |
| Always ban excessive events | Optimize equivalent work or propose alternative authored gameplay semantics; never silently drop gameplay hits |
| All combination complexity in JSON | Typed effect primitives + optional explicitly approved special handlers; no arbitrary code injection |

## 5. Distinguish true engineering guards from gameplay nerfs

**Must not change:**
- valid hits, rewards, source identity, i-frames, status ownership, event order cannot silently depend on FPS;
- no unbounded event loop or unbounded recursion that exhausts memory;
- no dropping valid scheduled effects because of a global count threshold;
- deterministic stream partitioning, save format IDs and formal failure messages;
- visual budgets cannot change hitboxes or damage.

**Can be policy-defined:**
- active/passive counts; acquisitions beyond cap via special rewards;
- number of ranks and post-max increments; number of independent copies;
- evolution inputs/outputs; number of gifts, chain generation depth;
- numerical proc counts and stacking; allowable cross-element reactions;
- choice pool size, acquisition and pity policies.

A worst-case workload check is a validation problem: compare a proven conservative event bound to a **declared target capacity profile**. It is **not** the same as a fixed global 128-event rule or an automatic game-time discard.

## 6. Bounded cycles: proof modes (design contract)

A cycle `A→B→A` can be safe if **each edge traversing the cycle consumes an integer generation budget** that strictly decreases, or another rigorously decreasing finite resource. Validation uses an extended graph state `(event_kind, remaining_generation, resource_state)` and must terminate. A simple current fixture can use `max_generation` for *all* descendants; later validators may support source-scoped budgets.

An acyclic path has finite bound via topological recurrence:
`W(v)=1+Σ(max_children(e)×W(to(e)))`.
For generation-limited branching:
`W(v,0)=1`, `W(v,g)=1+Σ(max_children(e)×W(to(e),g-1))`.

The latter is conservative if it limits all child edges, including acyclic effects. It should be selected only when the scope/semantics are documented. It proves an upper bound on **logical event nodes**, not CPU time, memory, or a smooth frame rate.

*Small example:* a self-triggering thunder chain with child fanout 1 and a 3-step generation budget yields at most 4 event nodes, not an infinite loop. With fanout 2 and 3 steps, the tree bound is 15. These are illustration-only values.

Do not make `can_proc_from_proc=false` an immutable global restriction. Allow safe opt-in when finite, unique-target/charge-bound, or explicitly staged across simulation ticks.

## 7. New testing requirements before making this canonical

- **Open slot test:** capacity 6 vs 10 vs 12 (same definitions; legal run changes).
- **Different rank test:** a skill with 5 authored ranks and a separate one with 12; future Limit Break meta tiers.
- **Alternative policy:** direct-only proc graph and bounded self/cross-cycle; reject unbounded cycle.
- **Multiple skill copies:** instance UID uniqueness, per-instance rank/slot ownership and deterministic target selection.
- **Multi-tier recipe witness:** base→evolved→combined→gift; prove at least one legal acquisition path.
- **Flexible event budget:** synthetic bound 128 vs larger declared profile, with no hidden runtime discard.
- **Special rewards:** gift/union or event can raise occupancy or grant independent abilities even when standard level-up pool is full.
- **Overcap conversion:** chances >100% handled by named stochastic policy and tests, never implicitly clamped.
- **Draft policy:** 3/4/5 offer cases and empty-pool fallback are expressible.
- **Static performance impact:** report upper logical event estimate and expensive geometry ops separately; defer real performance claims.

## 8. Reference comparison and justification

- [Vampire Survivors weapons](https://vampire.survivors.wiki/w/Weapon) — base six-slot pool plus ways to gain more weapons.
- [Vampire Survivors Limit Break](https://vampire.survivors.wiki/w/Limit_Break) — post-max weapon growth, per-property limits, evolution interactions.
- [Soulstone Survivors Gift of the Veil patch, 2026-06-12](https://steamdb.info/patchnotes/23706374/) — chain-triggered skills no longer multicast; shows a **version-specific balance policy**, not a mathematical ban on every safe chain.
- [2026 Vampire Survivors community discussion](https://www.reddit.com/r/VampireSurvivors/comments/1uuzty1/no_max_weapon_limit/) — many acquired weapons are desired; heavy combinations can hurt performance.

These sources support a flexible design intent; they are not claims that specific mechanics in HEAVENISPREY have been playtested.

## 9. Priority and acceptance

**Immediate architecture-only priority:** remove hard caps from normative *intent*, add explicit policy-presets, strengthen static checks to accept variable capacities/ranks and finite bounded cycles, and add counterexamples. Do not multiply speculative skills before the authoring contract is stable.

**Remain open:** what standard/default mode actually uses (6+6 vs 8+8, three-card vs four-card), how frequent additional slots drop, how far Limit Break scales, and which recursion options are fun. These are balancing/design decisions, not schema limitations.

**No Godot runtime or game implementation is authorized.**
