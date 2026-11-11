# BUILD-SKILL-001 — развитие билдов, трансформации и культивация (architecture proposal)

- **id:** BUILD-SKILL-001
- **status:** design-proposal / NOT ACCEPTED / NOT IMPLEMENTED
- **date:** 2026-11-11
- **supersedes:** nothing; complements historical v5/v6 material without rewriting archived source
- **dependencies:** [ADR-002](../../decisions/ADR-002-combat.md), [ADR-006](../../decisions/ADR-006-content-catalog.md), [ContentRegistry](content-registry-contract.md), [v5 combat semantics](../v5/v5_semantics.md), [v5 event budget](../v5/v5_budget.md), [v5 build design](../v5/v5_design.md), [v6 classes](../v6/v6_classes.md)
- **acceptance:** design-only checks from §13, no runtime or balance claim
- **evidence:** only existing v7 content catalogs and source references listed below; implementation tests NOT RUN

> **Scope boundary (2026-11-11): architecture, contracts, validation plans and authoring efficiency ONLY.** No `game/`, Godot scenes, runtime, image assets, balance claims or gameplay code in this slice. **New direction:** preserve freedom to build extremely powerful combinations; 6 active + 6 passive slots, 5 ranks, one-copy skills and nonrecursive proc chains are **possible presets, not engine ceilings**. Consult [FLEXIBILITY-FIRST-001](flexibility-first-build-policies.md) for configurable policies and finite bounded reaction cycles. Numbers, slot defaults and balance choices remain proposals until reviewed.

## 1. Product invariant: automation vs strategic choice

- **Automatic:** normal combat skill application, default aim, repeated casts, derived reactions, class intrinsic triggers. Rendering never changes combat events.
- **Explicit choice while combat paused:** level-up offer, mutually exclusive evolution, meridian route, other strategic build choices.
- **Candidate future option:** auto-pick strategy for accessibility/bots; it invokes the same draft/commit API as the player.
- The historical `s18` proposal to *choose the moment of a breakthrough* conflicts with the pure-auto narrative if implemented as a combat-button. Resolve by separating `Qi accrual`, optional `BreakthroughReady` and paused `BreakthroughChoice`. Manual timing is **OPEN**, not an accepted mechanic.
- Pause must freeze simulation tick and RNG streams; UI time may continue (existing `s04` contract).

## 2. Four distinct clocks / progression scopes

| Scope | Identity / owner | When modified | Persistence |
|---|---|---|---|
| Class intrinsic | class_id | starts with hero; changes through authorized mutations | run snapshot |
| Run build | skill ranks, passive ranks, power stacks, transformations | level up, reward, breakthrough | current run only |
| Cultivation | Qi, realm, route, temporary class ascension | own deterministic events | run snapshot |
| Meta | mastery, sect talents, unlocks, currencies | settlement / out-of-run UI | profile |

Never call `talents.json` the catalog of run-passives. It currently represents purchases and mastery. Do not mix Qi with XP or late currency Dao Seals.

## 3. Strong type taxonomy (non-overlapping axes)

Every skill needs separate fields for:
1. `school_tags` (sword, thunder, talisman, body, neutral; multi-tag permitted);
2. `element_tags` (metal, lightning, fire, physical, etc.);
3. `geometry_kind` (projectile, chain, zone, aura, arc, orbit, beam, nova, summon, buff);
4. `delivery_tags` (melee, ranged, periodic, contact, etc.);
5. `status_ids` it applies; conditions for on-hit/on-apply;
6. `target_policy_id` and `aim_policy` (autonomous / optional manual);
7. `origin_kind` (direct, echo, chained, periodic, secondary reaction);
8. `availability` (defined/design-only/runtime-implemented) and `acquisition` policy.

Do not reuse a single ambiguous `type` tag for school, geometry, and element. For conditional powers distinguish **number of unique compatible skills** vs number of sources applying a status (one skill with three effects is not automatically three unique sources).

## 4. Build occupancy and acquisition

Design hypothesis: 6 active slots **including** starting skill; 6 limited passive-art slots; one intrinsic outside normal slots; unlimited *inventory slots* for PowerStacks but finite caps/allowed operations. More complex variants require separate run-mode policy.

`ActiveSkillInstance`: stable skill ID, rank, slot, build_revision, skill_runtime_revision, evolution ancestry. `PassiveArtInstance`: ID, rank, slot. `PowerStack`: ID, rank/stack, scope, origin. `ClassIntrinsicState`: class-specific accumulator; not an arbitrary script in JSON.

Acquisition types MUST be disjoint:
- new active;
- active rank-up;
- new passive;
- passive rank-up;
- repeatable / capped Power;
- transformation reward (evolution/union/gift);
- breakthrough/meridian selection;
- meta unlock (not a normal level-up reward).

**Full slots:** new active is ineligible unless replacement offer is explicitly enabled. Replacement policy, refund and rank-transfer are OPEN; default proposal is removal with no implicit refund and new rank 1. No hidden replacement via evolution.

**Banish/Lock/Reroll:** lock is a proposal, not sourced as a confirmed rule of the reference games. Locked cards must revalidate availability before commit; stale locks cannot bypass exclusivity.

## 5. Deterministic draft algorithm (DESIGN)

`DraftRequest` = (run_rules_hash, content_hash, build_revision, upgrade_level, profile_unlocks, draft_rng_state, draft_history, policy_id, slot_limits). Build a typed `EligiblePool`:

1. Filter by unlock, rank cap, current occupancy, required skills/tags/status sources, bans, exclusivity, current mode.
2. Include upgrades to already-owned skills separately from new acquisitions.
3. Derive weights from declared `DraftWeightPolicy` (rarity, class relevance, opportunity cost, repeated-offer policy). Never invent weights dynamically from unspecified heuristics.
4. Stable sort by canonical ID **before** RNG sampling; no dependence on JSON insertion or hash map iteration.
5. Sample without replacement (except explicitly repeatable distinct variants), record RNG state before/after.
6. Apply declared `anti_brick_policy`: at least one currently usable offer **if a usable offer exists**, without promising an optimal build. Define usable based on available valid effects rather than AI judgment.
7. If fewer than required candidates: declare a visible and testable `FallbackRewardPolicy` (e.g. health/currency) rather than offering invalid cards.
8. Every reroll increments its own choice event and consumes the **draft** RNG only, not combat RNG.

No free hidden pity/tactical override: if introducing a pity meter for rare/synergy offers, it must be visible in `DraftPolicyDef`, count eligible offers, and be deterministic. A policy version goes into RunRulesHash.

## 6. Transformation algebra

Represent all transforms through common `TransformationDef` with distinct `kind`:
- `EVOLUTION`: one skill replaced by evolved skill; passive catalysts preserved unless explicitly consumed.
- `UNION`: 2+ active skills consumed and replaced; occupancy delta computed from explicit slot costs.
- `GIFT`: base remains; grants additional skill/passive/intrinsic effect with explicit special-slot policy.
- `MORPH`: class/character change, not an alias for ordinary evolution; defer until product need.
- `MUTATION`: changes class/meridian rules, does not necessarily consume skills.
- `SYNERGY`: does not consume skills; a conditional modifier or reaction and not a transformation.

`TransformationDef` minimum: id, kind, requires (AND/OR with named predicates), event_gate, consumes, preserves, grants, slot_cost_delta, exclusive_group, priority_if_unambiguous, on_inflight_policy, on_cooldown_policy, migration_policy, presentation_key, provenance.

An event satisfying 2 mutually exclusive recipes MUST produce a paused choice; neither can win because of list order. Atomically validate at build revision R; reserve components; apply consumption/grant; recompute; commit revision R+1; rollback all on error. Concurrent level-up and reward queue must have an explicit deterministic ordering.

**In-flight effect:** attacks already committed remain with cast snapshot and attribution until expiry unless their own `on_owner_transform` policy says otherwise. Do not magically despawn in-flight projectiles or reset cooldowns for free.

## 7. Modifier semantics, effect provenance and safety

- Fixed ordering: base rank -> additive groups -> multiplicative groups -> snapshot -> target defenses/status and quantization at hit; use existing `s07` / Combat Semantics as normative fallback.
- `SkillChain` (cast triggers another skill) is **not** Multicast (repetition of one cast); not equivalent to status reaction (hit/status event).
- Default proc source policy: direct cast may echo and may chain; echo cannot echo or chain; chained cast cannot echo or chain; status ticks cannot chain; reaction cannot recursively trigger same rule. Any exception needs a proof of finite bound and a separate explicit op trait.
- Root, parent, generation, owner-handle + generation, skill ID and independent attribution must be preserved for replay and logging.
- Never silently drop valid combat events for FPS. Limit authorable combinations **before** publication through bounded proc graph and declared max event counts.
- An already-active hazard is not removed merely because its source died or a cosmetic rendering budget was exceeded.
- Multiple status source identities need an explicit stacking/ownership rule; `refresh_and_add` alone is insufficient to state duration/expiry policy.

## 8. Four class identity contracts (no balance claim)

| Class | Start skill (already v7) | Intrinsic state candidate | Build divergence / counter-risk |
|---|---|---|---|
| Sword | `skill.spirit_sword` | sword resonance / marks | single-target focus vs mass blades; wasted overkill |
| Thunder | `skill.thunder_chain` | accumulated lightning charge | large crowd vs lone boss; controlled chain length |
| Talisman | `skill.talisman_seal` | formation slots / seal placement | zone prediction vs fast enemies; overdraw |
| Body | `skill.body_pulse` | fortitude from **safe** proximity/blocked hits | crowd risk without forced self-damage |

Every class should have at least one own-route and one cross-school viable candidate path, not forced character-specific hard-coded trees. Distinguish globally acquirable school skill from intrinsic-exclusive class skill.

## 9. Cultivation / ascension unresolved choices

`XP` grants ordinary drafts; `Qi` fuels breakthrough; `Mastery` is out-of-run. Separate `TemporaryAscension` (automatic state boost) from `RealmBreakthrough` (run-scale strategic rule mutation). Those are NOT aliases for skill evolution. Do not equate `Tribulation` event inside a run with `difficulty.tribulation` from late-game unlocks.

Open design questions to settle explicitly before content expansion:
- Is breakthrough time selected from pause or triggered automatically at threshold?
- Does failed breakthrough consume Qi, change enemy director, or only deny reward?
- Are meridian changes exclusive for whole run or only current realm?
- How are Qi and XP earned without class-dependent runaway feedback?
- Which cultivation decisions alter reward eligibility and RunRulesHash?

## 10. Time-to-evolution and draft feasibility

Under proposed 6 active skills × 5 ranks + 6 passive arts × 3 ranks, full rank coverage can require up to 48 acquisitions depending on starting rank and how a new item consumes a choice (subtract initial freebies). Additional Powers and transformations create competition. **Five-minute pilot cannot assume full build**.

For any target recipe calculate:
- minimum number of mandatory draft picks;
- minimum compatible offers given filtered pool and expected level-ups;
- event/chest gate availability by run minute;
- worst-case inability from mutually-exclusive options;
- empirical seed reachability after implementation (NOT RUN now).

Use explicit `build_path_fixture`: starting class, a sequence of legal rewards, expected occupied slots/ranks, eligible recipes, final result. Static witness paths should be tested before declaring a recipe reachable; random bot success alone is not enough.

## 11. Required boundary contracts

- `ContentRegistry`: validates and produces typed immutable definitions (existing ADR-006).
- `RunBuild`: single mutable owner of run skill/passive/power/class states.
- `DraftService`: pure offer engine, returns offer IDs and RNG state; never applies damage.
- `BuildTransaction`: atomic choice, rank-up, evolution, union and gift. Consumes exact expected build revision.
- `BuildResolver`: derives effective skill stats and allowed synergies; produces cache keyed by build revision.
- `AutoCastScheduler`: consumes skill instances + effective definition; outputs cast events.
- `CombatEffectEngine`: existing hit/status/reaction pipeline; no knowledge of UI card.
- `PresentationBridge`: reads snapshots and render events, no mutation of simulation.

All boundaries must be testable independently without Godot scene nodes once runtime work is later authorized.

## 12. Design-only deliverables — NO game code

1. Reviewed decisions for unresolved questions in this proposal (ADR amendment only when accepted).
2. Schema contracts for skill ranks, passives, powers, draft, transformation and class intrinsic.
3. At least **one positive and one negative fixture** per operation: acquire, rank-up, full slots, reroll, banish, evolution, union, gift, conflicting recipe, stale build revision, in-flight effects, dead source, proc cycle.
4. JSON reference integrity, unique IDs, domain-specific tags, failure messages and translation coverage.
5. Draft eligibility fixtures with expected exact offer candidates; no claim of RNG statistical fairness without later sample runs.
6. A human-readable transformation graph and source-to-test traceability.
7. A class-independent authoring template and update checklist.

**Non-goals:** implement `game/`, animate sprites, generate finished character packs, assign numerical balance, start Godot import, run bot matches.

## 13. Acceptance for architecture review

- [ ] Named decision recorded for each OPEN policy (no conflicting implicit defaults).
- [ ] Invariants and schemas unambiguous; no second source of numerical values.
- [ ] Unique separation of `talent`, `passive`, `power`, `intrinsic`, `skill`, `evolution`, `meridian`.
- [ ] At least one reproducible recipe witness for each transformation family.
- [ ] Cross-reference/negative fixtures planned and linked to eventual validators.
- [ ] Versioning, RNG stream, attribution and rollback defined.
- [ ] Acceptance clearly remains DESIGN-ONLY until actual tests exist.
- [ ] No runtime in PR and no unapproved merge.

## 14. External evidence (not a claim of code inspection)

- [Vampire Survivors Evolution / Union / Gift / Morph](https://vampire.survivors.wiki/w/Evolution), consulted 2026-11-11.
- [Vampire Survivors level-up and reroll/banish/skip](https://vampire.survivors.wiki/w/Level_up), consulted 2026-11-11.
- [Soulstone Survivors Power conditions and synergy tags](https://soulstone-survivors.fandom.com/wiki/Powers), consulted 2026-11-11. Community wiki; patch-specific values need independent version checks.
- [Soulstone Survivors 2026-06-12 Gift of the Veil patch](https://steamdb.info/patchnotes/23706374/), especially chained skills cannot multicast.
- [JSON Schema 2020-12](https://json-schema.org/specification), reference only; adoption is an option, not a preinstalled dependency.

**Important:** Sources justify the distinction between categories and highlight risks; all named xianxia techniques, proposed limits, and policy decisions in this document are HEAVENISPREY design proposals, not facts about the reference games.
