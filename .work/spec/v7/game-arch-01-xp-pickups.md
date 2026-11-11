# GAME-ARCH-01 — XP, Drops, Pickups и сохранение стоимости добычи

- **id:** GAME-ARCH-01
- **status:** DESIGN PROPOSAL / STATIC REFERENCE ONLY; GAMEPLAY NOT IMPLEMENTED
- **date:** 2026-11-11
- **scope:** модели, инварианты, тестовые данные без Godot и без обещаний FPS/баланса
- **dependencies:** [GAME-ARCH-00](game-arch-00-run-orchestration.md), [GAMEPLAY-GAP-001](gameplay-loop-gap-audit.md), [v5 gameplay](../v5/v5_design.md), [Combat Semantics](../v5/v5_semantics.md), [v7 economy](economy-and-talent-sinks.md), [v7 class/stage catalogs](../../config/v7/README.md)
- **evidence:** [synthetic fixture](../../proposals/game-arch-00-01/reference_run.json), [static oracle](../../../scripts/validate_run_loop_proposal.py), [negative tests](../../../tests/test_run_loop_proposal.py)
- **constraint:** XP, Qi, class mastery and Spirit Stones/Dao Seals are **different accounting domains**. This does not create a new currency or change v7 meta settlement.

## 1. Core loop: why pickups are gameplay

`death → authored DropIntent → logical Pickup → spatial collection → XP credit → level-up choices → BuildTransaction`.

The pickup changes **where the player moves** and **when progression happens**. This is not just visual loot. Automatically granting all XP on kill can erase spatial positioning; placing huge numbers of uncollected drops without consolidation can overload the presentation and world queries. Both properties should be policy-defined, not embedded in the Combat damage pipeline.

| Boundary | Authority / output |
|---|---|
| `DropService` | accepts authorized death/reward intent; uses declared loot policy; mints unique source UID |
| `PickupStore` | logical pickup value, fixed location/region/ownership, optional attraction state |
| `PickupConsolidator` | combines **equivalent** objects without changing collectible value or reachability |
| `PickupService` | checks one deterministic player-position snapshot, commits a collection receipt |
| `XPService` | credits integer XP and calculates each crossed threshold, keeps overflow |
| `ChoiceCoordinator` | one durable decision per earned level (see [GAME-ARCH-00](game-arch-00-run-orchestration.md)) |
| `PresentationBridge` | displays a subset of pickup visuals and magnet effects; never invents XP |

Don't grant a rune, skill, meta currency or XP directly from the physical sprite object.

## 2. PickupDefinition vs PickupInstance

Proposed `PickupDef` holds type, icon/presentation, pickup method, amount formula reference, applicable mode and eligibility.

Logical `PickupInstance` must separate:
- `pickup_uid` and sorted immutable `source_uids` with run namespace;
- `kind`: XP, health, catalyst, etc.; no implicit conversion to a meta currency;
- credited integer `value` and named modifier stage; never a partially formatted float;
- `owner_uid` or explicit shared-owner policy for future cases;
- logical `position`, `region_id`, visibility/activation and reachability status;
- `collection_policy`, radius/magnet group, expiry and spawn tick;
- `drop_event_uid`, `source_enemy_handle` where applicable, rules/content version.

Reference fixture only includes ID, kind, owner, region, policy, integer grid position/value and source UIDs. More fields are **required before claiming collision/radius timing equivalence in a runtime**.

## 3. Lossless condensation semantics

A consolidator may merge drops only if their collection behavior stays **observationally equivalent**.

Required invariant:

`Σ value(before) = Σ value(after)`

Plus:
- all source UIDs preserved **exactly once**;
- no cross-owner, cross-kind, cross-region, cross-policy aggregation;
- at least for the reference model, **exact same integer coordinates**; this guarantees same collection-time test for any player path with a given radius and no differing activation states;
- never silently merge a late-spawned pickup with an expired/hidden/unreachable one, or a pickup with differing collision/attraction/TTL policy;
- never merge different loot kinds merely because they have equal numeric value;
- **reference oracle combines XP only**; HEALTH/CATALYST are kept separate, even when co-located, until their kind-specific combination semantics are proven;
- choose a stable merged ID from the **sorted source set**, not list order or VFX object identity;
- merging only changes logical representation; it does not retroactively move XP, skip collision, change reward event order or award twice.

**Important restraint:** The real game may eventually need more aggressive spatial consolidation. Allowing merges across a cell/region is only correct if we can prove pickup timing/reachability equivalence or explicitly accept a visible gameplay-rule change. Don't pretend that preserving the sum alone preserves the spatial challenge.

The fixture merges three XP drops of values `14+9+17=40` at one grid point and leaves two other drops: one at an adjacent point (7), another in an inaccessible region (5). Total XP value stays `52` and is not auto-credited by condensation. With pickup radius 0, 40 XP is collected.

## 4. Exactly-once XP source accounting

Receipt dedupe on `event_uid` alone is **not** sufficient. A pickup originally represented as three source objects may later become one consolidated object with a different event UID.

Therefore:
- `processed_event_uid → event_digest` prevents repeating/altering the same event.
- `claimed_xp_source_uids` prevents awarding **the same logical source** through distinct receipt representations.
- Source overlap rejects the complete new reward atomically.
- A `source_uid` may represent only one authoritative value allocation in that run; changing a source amount in flight is an explicit correction event, **not** re-issuing its UID with another amount.
- If multiple legal partial claims against one source are introduced later, they need explicit `(source_uid, claim_segment_uid)` identity and per-source upper bound; do not weaken the rule by accepting duplicate sources silently.

The reference oracle implements run-scoped receipt equality, source-overlap rejection and no partial mutation on failure. It is an illustrative ledger, **not** a database implementation. A future runtime must persist it in snapshots and define retention/migration.

## 5. XP thresholds and multiple pending levels

Proposed `XPThresholdPolicy` supports either:
- explicit integer **incremental** costs `cost(level→level+1)`, or
- an explicitly versioned monotone formula or piecewise tier table.

`XPService` keeps `current_level`, `xp_bank` and independent `pending_level_choices`.

For each XP receipt:
1. `xp_bank += credited_value`.
2. While `xp_bank >= cost_for_next_level`: subtract cost, increment level, enqueue one `LevelUpChoice`.
3. Never discard overflow. If a finite test cost ladder ends, retain XP; production policy must declare new tier, overflow conversion or terminal max-level behavior.
4. The number of **visible menus** may be reduced via sequential batched UX, but the number of earned **choices** is not reduced.
5. An **immediate** or mandatory choice opens a pause at the deterministic tick boundary. In optional [Bank Levels mode](game-ux-001-oct-2026.md), earned ordinary levels may remain queued while the world runs; each eventual selection re-evaluates current `RunBuild`.

Fixture: starting `level=1, xp=0`; next-level incremental costs `5,12,20,30`; a collected 40 XP produces levels 2, 3, 4 (three choices), **3 XP overflow**, and leaves cost 30 for level 5. Neither 6-slot nor 5-rank caps are implied.

**OPEN XP-01:** value multiplier timing. Apply XP growth at **drop creation** or **pickup credit**? Both can be valid, but each source must be modified exactly once with consistent snapshot ownership. Gold/Spirit Stones are unrelated.

**OPEN XP-02:** magnetization, global pickup on boss exit or end-of-stage, and loss behavior on death. If triggered, visible policy must state whether inaccessible XP is converted/collected; never claim the data structure itself creates XP.

**OPEN XP-03:** non-XP pickups with stackable heal, relic, catalyst, Qi or world objective payloads; each needs own claim type and one-shot effect. The reference checker only awards XP and does not create a universal loot interpreter.

## 6. Spatial pickup contract

`collect_at(owner, region, player_grid_position, radius)` is a design-only helper. A real 2D world should use the same authoritative coordinate system as player collision, along with a precise pickup radius/shape; it must **not** use a distorted 2.5D rendered offset as the gameplay distance.

Reachability must distinguish:
- nearby but blocked behind hard geometry;
- same position but inside inaccessible layer/region;
- explicit interaction object vs passively magnetized gem;
- transient attraction that moves an object;
- virtual reward delivered by a verified ritual event rather than a physical pickup.

The reference test takes a strict region and integer radius. Region equality is a synthetic approximation, **not pathfinding proof**.

For aggressive late-game pickup optimization, investigate a spatial index plus value buckets while preserving source provenance and authorized loot amounts. Rendering can draw fewer glowing gems without erasing their logical collection rules.

## 7. Strong builds and progression economy

Allow very powerful multi-school builds and extra slots (see [FLEXIBILITY-FIRST](flexibility-first-build-policies.md)). The XP system must scale without assuming that six active skills or a fixed five-level cap are hard engine ceilings.

Avoid:
- all XP instantly granted on kill: removes movement incentive;
- dropping a logical `PackedScene` for each of thousands of enemies: costly, hard to batch;
- silently deleting "overflow" XP or level-up menus;
- applying XP multipliers both on death and collection;
- letting `PickupConsolidator` change reward rarity, ownership or collectible timing;
- presenting 6 sequential menus without any consideration of player fatigue.

Architecture should support a fast 5-minute proof of game loop and a longer run with different leveling policy **without a new XP implementation**.

## 8. Acceptance and future measurements

**Static checks in this slice:**
- lossless total value and stable source provenance through merging;
- data-order independence of same-cell consolidation;
- prohibition of cross-kind, cross-owner, cross-region, cross-position or cross-collection-policy merging;
- no collection outside radius/region and no accidental interaction pickup;
- rejected duplicate pickup/source IDs;
- exact XP credit, multilevel choices, leftover XP after exhausting authored thresholds;
- source UID + receipt UID dedupe, non-duplicate XP after conversion of representation;
- frozen sim tick while queued choices are committed.

**Not proved:** collision timing against polygon geometry, bias in drop RNG, XP/min, player comfort, density of gems, real FPS/memory, satisfying magnet progression or power curve. Those require eventual runtime/playtests; no future simulation should be claimed completed merely because Python fixtures pass.

## 9. Recommended next analysis

With GAME-ARCH-00/01 specified, prioritize [GAME-ARCH-02](gameplay-loop-gap-audit.md): stage topology, encounter timing and boss phase contracts, because they control spatial pickup access and reward gates. Before approving content production, decide XP-01/02/03 and RLOOP-01/02/03 in an ADR. Do not change accepted [meta reward contract](../../config/v7/reward_contract.json) as part of an XP refactor.

[Reference data and tests](../../proposals/game-arch-00-01/README.md) · [Run coordination](game-arch-00-run-orchestration.md)
