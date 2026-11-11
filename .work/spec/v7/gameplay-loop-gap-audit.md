# GAMEPLAY-GAP-001 — что недоопределено в игровом цикле и архитектуре

- **id:** GAMEPLAY-GAP-001
- **status:** DESIGN AUDIT / PROPOSAL — NOT ACCEPTED, NOT IMPLEMENTED
- **verified date:** 2026-11-11
- **scope:** only gameplay architecture, contracts, developer acceleration; NO Godot runtime/scenes/assets
- **references in repo:** [BUILD-SKILL](build-skill-architecture-proposal.md), [FLEXIBILITY-FIRST](flexibility-first-build-policies.md), [Combat ADR](../../decisions/ADR-002-combat.md), [v7 enemy threat](enemy-threat-contract.md), [v7 late-game](late-game-progression.md), [v5 enemies](../v5/v5_enemies.md), [v5 UX](../v5/v5_ux.md), [v6 UX](../v6/v6_ux.md), [v7 stages](../../config/v7/stages.json), [v7 rosters](../../config/v7/enemy_rosters.json)
- **evidence boundaries:** Comparison uses public patches/wiki/community sources below. NO local copies/binary inspection of Vampire Survivors or Soulstone Survivors; no claim of reverse engineering their implementation.
- **acceptance:** audited gap coverage + prioritized schema candidates + future static tests. No gameplay performance or fun was measured.
- **do not override:** accepted v7 economy, enemy tiers, unlock gates or user decision to defer game development.

## 0. Status vocabulary / objective

Three states MUST NOT be conflated:
1. **Existing normative design** — v7/ADRs already define a rule; gap is implementation/evidence or end-to-end composition.
2. **Historical/reference only** — sXX/v5/v6 mentions the concept but it is not a current integrated v7 contract.
3. **Unspecified** — no sufficiently precise schema, invariant, target, or test in current design.

The largest architecture mistake is optimizing the skill graph in isolation. Survivor-like gameplay is the coupling of `movement→danger→kills→pickups→XP→choices→build strength→new danger` plus spatial/temporal goals and persistent discovery. Changes to one arrow alter the others.

**Product principles:** automatic combat; meaningful continuous positioning and dodge; strategic choices at explicit pauses; easy-to-enter difficult-to-master; very powerful builds allowed; no compulsory out-of-run crafting or external service; current scope design-only.

## 1. Ranked gameplay gap inventory

| ID | Area / repo coverage | Gap / required owner | Future acceptance |
|---|---|---|---|
| GP-01 P0 | **End-to-end run loop**; v5 design/UX historical | No one contract binding XP, spawn, rewards, level-up and victory; `RunTimelineDef` | deterministic 5-minute sequence of event intents; no hidden cross-system assumptions |
| GP-02 P0 | **Pickup / XP economy**; little normative data | `PickupDef`, magnet, gem merging, XP preservation, multiple level-ups at same tick | zero lost XP; deterministic pickups; capped entity count via value-preserving condensation |
| GP-03 P0 | **Choice event queue**; DraftService proposed | Levels/chests/breakthrough/portal choices can collide in same tick | unique ordered choice IDs; pause freezes sim/RNG; exactly-once apply |
| GP-04 P0 | **Pre-run strategy**; class/talents/modes exist separately | `RunLoadoutDef`: chosen starting variant, runes/Dao vows, restrictions; same rules hash | class identity preserved; illegal loadouts rejected; source of each modifier explicit |
| GP-05 P0 | **World as meaningful arena**; v5 enemies/s14 historical | `StagePOI/StageInteractableDef`, stage rewards, landmark navigation and risks | useful paths; reachable POIs; no untelegraphed hazard/exp exploit |
| GP-06 P0 | **Wave & encounter dramaturgy**; v7 4 windows and normal tiers | Encounter events, kill quotas vs elapsed clock, intensity curve, elites/boss thresholds | staged varied threats, guaranteed legal spawn, clear escalation |
| GP-07 P0 | **Boss gameplay**; v5 description, v7 boss IDs | `BossPatternDef`, phase grammar, arena hazard, vulnerabilities/rewards, multi-boss fairness | telegraph/recovery, multiple build families viable, no unavoidable path blockers |
| GP-08 P0 | **Reward ecology**; v7 meta economy but no in-run rewards | distinction between XP draft, chest evolution, boss power, world pickup, breakthrough, merchant/event | reward source/eligibility/one-shot ledger, no double grant |
| GP-09 P1 | **Class ascension as spatial objective**; class intrinsic proposed | pickup rituals/shrines/position challenges as optional source of charge or form | no manual skill casting; task spatially fair and recoverable |
| GP-10 P1 | **Qualitative difficulty & curses**; v7 late tier qualitative intent | reusable `ThreatModifierDef` (enemy composition, hazard, tempo, boss conjunction), not only HP | legal composed modes; counterplay and rewards preserved |
| GP-11 P1 | **Run mode grammar**; names/rewards already v7 | survivor timer / kill-phase / challenge / boss-rush / continued cycle | distinctive objective and exit/continue choice, no separate combat engines |
| GP-12 P1 | **Damage provenance & summons**; combat semantic baseline | damage/stat inheritance across DOT/summon/chain/kill, life/death ownership, tooltip math | trace source chain and correct modifier stages across origins |
| GP-13 P1 | **Meaningful advancement pace**; only hypotheses v5 | time-to-first-choice, evolution gate window, choice interruptions/min, downtime | scripted progression witnesses for short/long runs |
| GP-14 P1 | **Learning, grimoire, unlock surfacing**; meta unlock in v7 | recipe/POI/loot/titan power compendium + clear next-goal surfaces | player can learn without external wiki |
| GP-15 P1 | **Death/end/retry loop**; rewards defined | defeat attribution, summary, fail-forward, replay, fast retry and portal/exit policy | exactly-once settlement and no illegitimate progression |
| GP-16 P1 | **Strong build counterplay**; threat caps exist | counterplay to AoE/chain/DoT/one-skill without stealth DPS nerfs | no absolute immunity invalidating whole classes; multi-axis test |
| GP-17 P1 | **Spatial feel / movement**; v5 enemies and S11 | dodge versus kiting, knockback, collision crowd, stuck recovery, obstacle fairness | skillful viable routes and controllable dense encounters |
| GP-18 P1 | **Decision UX / clarity**; v5 UX historical | queued menus, 3/4/5 options, rarity, provenance, warning layering, accessibility | warning remains visible under high VFX; context explanation in UI |
| GP-19 P1 | **Audio & feedback architecture**; v5 UX historical | event-priority mixer, semantic hit/kill/level/evo cues, reduced-noise modes | key feedback not obscured by high proc rates |
| GP-20 P1 | **Analytics & authoring test harness**; v7 bots designed | game-loop domain fixtures and agent impact links, not just skill references | checks stage objectives, reward economy, class paths and danger |
| GP-21 P2 | **Secrets and map discovery**; v6 unlocks, but level geography thin | opt-in discoveries, lore and long-term collection | not gated exclusively by wiki/hidden luck |
| GP-22 P2 | **Multiplayer scope decision** | deliberately not supported unless separately chosen | single-player ownership semantics clean; no speculative netcode |
| GP-23 P2 | **Content production pipeline for encounters** | current pipeline skill-centric | templates for waves, hazards, bosses, POIs, loot, tutorials | positive/negative fixtures each; generated index/coverage |
| GP-24 P1 | **Formal experiment selection** | v5 bots and metrics proposed | hypothesis, baseline, deterministic seed cohorts, human playtests, stop conditions | no balance/FPS/fun claims from JSON CI |

## 2. Core loop: separate four event clocks

| Clock | Examples | Owner / decision |
|---|---|---|
| Simulation ticks | collision, casts, enemy tells, movement, pickup radius | Combat/World fixed tick, no presentation influence |
| Encounter timeline | timed wave, elite arrival, guaranteed chest carrier, boss entry | `EncounterDirector` data-driven intents; not a separate damage engine |
| Reward / strategic choice | level-up, ritual, evolution, Dao choice, optional exit | `ChoiceCoordinator` ordered queue, pauses simulation; draft distinct from reward delivery |
| Meta lifecycle | unlocks, mastered classes, settlement, next goal | existing profile & economy contracts; no run-currency duplication |

Proposed high-level architecture:

```text
RunSetup (class + start variant + runes + stage + difficulty)
  -> immutable RunRulesSnapshot
World / EncounterDirector -> Spawn/Objective/Hazard intents
Combat -> Death/Hit/Status events -> PickupDrops + RewardEvents
PickupService -> XP queue -> LevelUp events
ChoiceCoordinator <- level-up, chest, ritual, breakthrough, portal
ChoiceCoordinator -> typed BuildTransaction + RunBuild revision
Outcome/Settlement -> idempotent meta journal -> Hub/Retry
Presentation <- read-only events and snapshots
```

Do not make `DraftService` the owner of a chest, portal, boss drop or Qi breakthrough. It supplies **eligible offers**; `ChoiceCoordinator` decides when and in what order a user-facing decision opens.

### Explicit choice event queue

A tick may kill a boss, collect a chest, acquire enough XP for 3 levels, and reach Qi threshold. Queue events by a declared `event_sequence` and `reward_source`, not by render-frame timing or filesystem/JSON ordering. Once a choice is displayed and committed, later choices must re-evaluate eligibility at the new build revision. A canceled/invalid UI choice does not duplicate a reward. Accessibility auto-pick uses the same transaction route.

## 3. XP and pickup system is a strategic mechanic, not a detail

Vampire Survivors experience is spatial: kills create gems; collecting them requires moving; Magnet changes effective access to XP; many uncollected gems can be merged without deleting earned value. Borrow the **value-preserving condensation concept**, not any unverified internal formula.

Required design components:
- `DropIntent` with source ID, position, amount/value, kind, pickup policy;
- `PickupEntity` vs a **logical pooled value** represented by fewer visible drops;
- pickup collection, per-kind magnet radius, stage-only special pickups;
- `XPService`: threshold function, stored overflow, multiple pending level-ups, deterministic tie-break;
- `PickupConsolidator`: invariant `sum(logical value before)=sum(value after)`, preserve player ownership and pickup reachability;
- `Attract/DropRate/Growth` modifiers separate; avoid confusing pickup range with increased XP multiplier;
- overflow near obstacles and stage boundaries; never place consolidated XP into unreachable map area.

**Risk:** if XP is vacuumed globally, positioning loses a major purpose. If collection is too difficult, skill upgrades become independent of combat strength. Route the balance via magnet stats, drops, partial auto-collection events and readable gem trails — not through hidden loss of XP.

**Design-only tests:** zero total XP loss through condensation; same seed and movement yields same XP; overflow level-up choices are queued; collecting while UI paused does not alter sim; death during pickup cannot pay twice.

## 4. World design: stage topology + points of interest

Current canonical `stages.json` defines two 5-minute stages, allowed classes/modes, and boss IDs; `enemy_rosters.json` defines four enemy windows. These do not yet determine arena topology, objective paths, discoverable pickups, hazard schedules, destructibles or ritual stations.

Need typed `StageTopologyDef`, `PointOfInterestDef`, `StagePickupRule`, `InteractionRule`:
- world boundary/obstacle and safe-movement graph; fake isometric visuals must not change logic hit plane;
- static/dynamic landmarks, guidance for off-screen POIs, reachable-path constraints;
- sacrifice/ritual zone, rare catalyst relic, chest carrier, destructible shrine (optional examples);
- `POI risk`: reward, travel cost, danger and reveal time; avoid reducing everything to one optimum route;
- distinguish virtual pickups (e.g. skill gain) from physically collected objects;
- no procedural generation obligation in the first phase: handcrafted stage graph with parameterized events is more auditable.

The guiding tension is **choose where to fight, where to collect XP, whether to detour for a powerful reward, and whether to risk a breakthrough**.

## 5. Threat/encounter pacing and bosses

Current v7 defines **13 normal enemies / 14 attack definitions** and threat budgets. Keep all normal tiers stable. **Missing is orchestration**: when and why threats arrive, how hazard types combine, boss tells and alternate spawn scenarios influence choices.

`EncounterDef` proposal: `id`, `stage_id`, start_condition (time/kill/objective), enemy composition, spawn lanes, pressure budgets, optional elites, stage-hazard intents, exit_condition, reward route, telegraph policy, target intensity band.

Avoid designing a fully adaptive "AI director" before there are authored scenarios. Prefer a reproducible timeline plus explicit modulation rule. Track:
- enemy pressure density and escape corridors;
- **offense**: kill/XP gain and status proliferation;
- **defense**: incoming dangerous tells/sec, contact pressure, healer/summon count;
- **disruptions**: elite window, boss phase, rare chest, ritual objective;
- **recovery windows** after extreme threat.

`BossPatternDef`: phases and transitions; telegraph/lock/commit/active/recovery; attack geometry; allowed hazard overlap; fair target selection; resistances and fallbacks against DOT/control and close-range builds; drop event IDs; interrupt/kill provenance. A boss is not normal enemy ×100 HP.

**Important new comparator:** Soulstone Survivors Titan Hunt uses map tasks/fragments then a Titan, whose reward grants special powers. The distinction between fights for survival and fights for a specific objective is architecturally significant, but it does not require copying its exact resource quotas.

## 6. Pre-run strategic layer

Repo currently has `classes.json`, meta talents, modes, stage selection but **no unified loadout contract** like Soulstone's chosen starting weapon/runes.

`RunLoadoutDef` candidate:
- class ID;
- one `starting_technique_variant_id` (default class starter, exceptions policy-authored);
- equipped `pre_run_rule_modifiers` / `DaoVow` with costs and compatible categories;
- profile unlock evidence and mode-specific exclusions;
- `RunRulesHash` including effects/order/versions.

Examples are **design possibilities**, not accepted content: "Sword Dao: extra sword mark source, fewer passive slots"; "Forbidden Scripture: can pick duplicate skills but starts with lower HP"; "Ascetic Oath: no starter active, receive one early draft choice." This matches the idea of Soulstone's character weapons and rune tradeoffs while staying xianxia-specific.

**Guardrails**: cost/slot constraints belong to loadout policy, not engine; metaprogression unlocks options, not secretly changes active run after a balance patch.

## 7. Unique class ascension should move the player

A class special bar that fills merely by killing may be a disguised automatic buff. In Soulstone Survivors, some Ascensions require **going somewhere**: reaching a shrine, collecting rifts/parts, following footprints, or performing a short area task. The architecture needs a reusable `ClassTaskDef` and `MapTriggerDef` as well as `ClassIntrinsicState`.

Candidate xianxia tasks:
- Sword: collect spirit sword fragments from marked elite kills; avoid turning it into mandatory farming.
- Thunder: touch 2 safe lightning conduits during wave to awaken a temporary thunder domain.
- Talisman: defend ritual circle for a short duration; fallback if heavy zone overlaps.
- Body: maintain close-range combat pressure to trigger dragon-body ascent; never require intentionally taking damage.

Avoid forcing every class into a "stand still in a circle" mechanic. Tasks should leverage the same spatial grammar but have distinct player actions, an always-available recovery/fallback path, and useful rewards. **Automatic combat remains unchanged**; movement and positioning are player choices.

## 8. Qualitative difficulty and alternate run loops

v7 `difficulty_profiles.json`, `modes.json` and rewards already have normative late-game constraints and anti-farm. Extend with data-only threat mutations:
- introduce special enemy compositions and multi-boss overlap;
- change hazard rules/spawn windows, not only enemy HP;
- distinct optional objectives with transparent risk/reward;
- support end-of-run **exit vs continue** portal (if accepted) with immutable continuation rules, no duplicate meta payout;
- modes may use survival time, kill phases, target quests or boss-centric cycles, but share core Combat/RunBuild.

The Soulstone Survivors wiki documents Overlord, Titan Hunt and qualitatively different curses; use their **loop variety** as inspiration, never copy exact curse tiers or loot formulas into v7. Check any late-game additions against existing Dao Seals allowlist and exactly-once reward contract.

## 9. Damage consistency across origins and pause states

2026 Soulstone updates explicitly fixed damage scaling applied inconsistently to DoTs and summons, player damage persisting after leaving an area, and special stacks changing while the game is paused. These are concrete implementation hazards and suggest architectural negative tests.

Future `EffectProvenance` must include:
`root_event_id`, `parent_event_id`, `owner_uid + generation`, `skill_instance_uid`, `origin_kind`, `snapshot_revision`, `cast_tick`, `target_uid`, `damage_kind`, and modifier stages. Dot/summon/zone/chain ownership should be explicit, and area membership evaluated at hit tick by named snapshot policy.

Test proposals:
- DOT derives valid owner modifiers, including buff changes under chosen snapshot/continuous policy.
- Summon inherits only documented modifiers and cannot create an extra ownership loop.
- Leaving hazardous area before tick means no lingering hit unless an intentional aftereffect is active.
- UI pause does not consume buffs, proc counters or RNG.
- Transformed skill keeps correct ancestry of in-flight projectiles.
- Statistics attribution distinguishes source skill, reaction and item without double counting.

## 10. Batching choices without removing meaningful decisions

As builds grow stronger, 2–4 levels can arrive immediately from a consolidated XP pickup. Opening 3–4 separate blocking menus may destroy the combat rhythm.

Need a `ChoiceQueuePolicy`:
- multiple queued levels are represented by exact pending choices, never merged into an unearned bonus;
- menu may present **batched sequential selections** but must update `RunBuild` and eligibility after each;
- advanced accessibility auto-pick/quick-pick uses same deterministic service;
- explicit `Reroll`, `Banish`, `Lock` scopes per choice and event gate;
- one available evolution may replace a ritual chest reward but may not consume the same source twice;
- reward and pause-time UX must fit keyboard/mouse/controller and readable RU/EN text.

One source of truth for legality; presentation should not privately roll additional options.

## 11. Discovery, player knowledge and meta pacing

Vampire Survivors uses relics, stage items, grimoire, arcanas, collections and character unlocks. Soulstone combines skill trees, runes, class weapons and titan powers. A June 2026 community complaint specifically wants an **in-game Titan upgrade encyclopedia** to avoid keeping a wiki open.

Future `Codex/HeavenlyManual` should expose:
- known vs unknown transformations, with optional spoiler settings;
- prerequisites, source of reward, whether catalyst consumed, available stage/mode;
- new unlock hints and next goals after each run;
- all discovered special powers and class routes;
- contribution report that explains the provenance of huge combos.

No wiki dependency or need to memorize 100 recipes. The system must index **canonical content and unlock metadata**, not become another handwritten catalog.

Economy remains 2 spendable currencies plus nonspendable mastery XP by current v7 ADR; introducing a third meta currency needs an explicit decision. In-run XP/Qi are separate and do not count as extra spendable meta currencies.

## 12. Feedback, readability and true gameplay quality

Historical v5 UX already discusses VFX priorities and warning layers. The missing work is measurable acceptance and a gameplay-wide resource budget.

`VisibilityContract` should define:
- enemy tell contrast and shape independent of color;
- important boss telegraphs cannot be hidden by player VFX slider or custom palette;
- projected hit area, actual logical hit area and lifetime must match (or be documented with grace);
- SFX mixer prioritizes danger signals, not each hit;
- gamepad focus and menu input latency while blocked by repeated choices;
- damage log explains last damaging attack and effect origin;
- debug overlay separates simulation cost, rendered events and visible danger signals.

Do not promise a fixed FPS until a real game exists. Preserving **logical** hit events does not mean rendering thousands of hit numbers or sounds. Rendering aggregations are legitimate if damage/status results do not change.

## 13. What to avoid copying

- Do not import exact Soulstone runic/multicast coefficients into an unrelated combat model. Patches in 2026 changed them substantially.
- Do not import the whole Vampire Survivors loot pool and evolution catalog; start with meaningful authored cross-school choices.
- Do not require a standing altar/circle for all classes: repetitive map mini-objectives undermine unique class identity.
- Do not turn every difficulty tier into a raw HP multiplier; qualitatively new compositions must remain fair.
- Do not enable unrestricted late-game meta payouts from Endless/Custom; the v7 economy explicitly prevents this.
- Do not mandate online co-op or netcode now; Soulstone developers have openly discussed performance/architecture costs of co-op. Solo is the current product scope.
- Do not infer source-code behavior, exact internal probability, or performance from wiki entries or screenshots.

## 14. Design-only architecture priority plan

| Slice | Depends on | Deliverable | Static acceptance |
|---|---|---|---|
| GAME-ARCH-00 P0 | Current v7, ARCH-01 | Core loop + four clocks + ChoiceCoordinator | explicit event sequencing and legal transition witnesses |
| GAME-ARCH-01 P0 | GAME-ARCH-00 | XP pickups + pooling/condensation + run level growth | total-value invariant, multi-level queue example |
| GAME-ARCH-02 P0 | GAME-ARCH-00 | Encounter timeline + class/boss stage grammar | boss/fairness and collision/POI design fixtures |
| GAME-ARCH-03 P0 | ARCH-01 + GAME-ARCH-00 | Pre-run loadout and Dao vows | class/weapon/rune compatibility, RunRulesHash |
| GAME-ARCH-04 P1 | GAME-ARCH-01/02 | Reward and stage POI contracts | reachable locations, one-shot grant and event gate |
| GAME-ARCH-05 P1 | GAME-ARCH-02/03 | Qualitative curses and run mode loops | valid composition and no reward exploit |
| GAME-ARCH-06 P1 | ARCH-01/04 | Attribution and compatibility matrix for dots/summons/areas | negative case scenarios from 2026 patch evidence |
| GAME-ARCH-07 P1 | GAME-ARCH-00/04 | Codex / Heavenly Manual and post-run explanation | generated from canonical IDs with RU/EN |
| GAME-ARCH-08 P1 | All above | design experiment and UX test protocol | fixed hypothesis, input set, success/failure gates |

**No game runtime, assets, bots or balance scores are created in this phase.** The next *recommended* action is GAME-ARCH-00 and GAME-ARCH-01 **before more content recipes**, because the reward and XP timeline constrain whether those recipes can ever be obtained.

## 15. Evidence register (public, version-aware; accessed 2026-11-11)

| Reference | Verification role |
|---|---|
| [Vampire Survivors Evolution](https://vampire.survivors.wiki/w/Evolution) | chest gates, union/gift/morph distinction |
| [Vampire Survivors Weapons](https://vampire.survivors.wiki/w/Weapon) | slots, weapons, stage pickups |
| [Vampire Survivors Arcanas](https://vampire.survivors.wiki/w/Arcanas) | alternate run modifiers and timing |
| [Vampire Survivors Enemies](https://vampire.survivors.wiki/w/Enemy) | timed waves |
| [Vampire Survivors 2026-08-28 patch](https://steamdb.info/patchnotes/24926490/) | stage item exceptions, quickstart and performance changes |
| [Vampire Survivors 2026-10-16 patch](https://steamdb.info/patchnotes/25984009/) | current stable fixes to damage and reward systems |
| [Soulstone Survivors official 2026-06-12 patch](https://www.soulstonesurvivors.com/news/) | runes/Power synergy updates, multicast and hitbox bug fixes |
| [Soulstone Survivors Runes](https://soulstone-survivors.fandom.com/wiki/Runes) | pre-run choices, sacrifice/duplicate skills; wiki version caveat |
| [Soulstone Survivors Ascension](https://soulstone-survivors.fandom.com/wiki/Ascension) | character-dependent spatial tasks; page incomplete and sometimes outdated |
| [Soulstone Survivors Titan Hunt](https://soulstone-survivors.fandom.com/wiki/Titan_Hunt) | map tasks, titan powers, alternate goal structure |
| [Soulstone Survivors Void Fields](https://soulstone-survivors.fandom.com/wiki/Void_Fields) | curse-based qualitative danger, phases and portals |
| [2026 Reddit request for Titan encyclopedia](https://www.reddit.com/r/SoulstoneSurvivors/comments/1uan6wv/i_appreciate_how_much_support_and_free_updates_we/) | user experience signal, not population prevalence |

**Verification caveat:** All game-specific numeric examples in public wikis can be stale, differ by mode/DLC/version or require direct controlled experiments. No binary reverse engineering or current-game playtest was performed.
