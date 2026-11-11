# GAME-UX-001 — UX-first integration audit, October 2026 baseline

- **ID:** GAME-UX-001
- **Status:** DESIGN PROPOSAL, architecture + static UX-contract checks only, **NOT** accepted gameplay tuning/implemented game
- **Evidence cutoff:** 2026-10-31 inclusive (sources after this date are not used for the comparator)
- **Authored/verified:** 2026-11-11
- **Scope:** improve the *existing* GAME-ARCH-00/01, BUILD-SKILL, v7 class/reward/stage contracts and future player experience **without Godot, gameplay code or art**.
- **Source of truth:** accepted v7/ADRs for existing gameplay/economy; this is the proposal for unapproved UX policies. Historical [v5 UX](../v5/v5_ux.md) and [v6 UX](../v6/v6_ux.md) remain references, not independently normative.
- **Static evidence:** [reference oracle](../../../scripts/validate_run_loop_proposal.py), [negative tests](../../../tests/test_run_loop_proposal.py), [fixture](../../proposals/game-arch-00-01/reference_run.json).
- **No claims:** no user testing, measured retention, human perception, actual ability RNG, game FPS, full save/load or production UX assets.

## 1. Findings: UX must shape the game-event architecture, not just decorate it

The prior design mostly optimizes **semantic correctness** (unique receipt, level accounting, stable choice queue, revision). These are necessary and insufficient for a good survivor-like. In particular:
- It always paused for level-ups; the player could not bank unspent choices.
- Each level-up was one blocking logical choice, but no *presentation* flow was specified to avoid repeatedly reopening the same panel.
- No "why this is offered" / synergy / catalyst / loss-of-slot explanation exists in a future choice card contract.
- Consolidator treated XP, HEAL and CATALYST as arithmetically additive if their positions matched. That is unsafe: two distinct heals or consumable relics can have nonadditive game rules.
- XP dedupe prevented repeat receipts and sources but did **not** prove that the credited amount was authorized by its original drop. The test oracle now has an *optional trusted source manifest* proof in the reference pipeline.
- An event batch could span different ticks despite claiming to represent one committed tick. The static oracle now rejects cross-tick batches.
- Class/Qi reward, ordinary upgrades, boss evolution, and run-mode modifiers have separate writeups, but no unified **player comprehension surface**.

**Do not solve UX fatigue by reducing the number of earned upgrades, silently nerfing fast builds, globally vacuuming XP or lowering visualized warning priority.** Provide user-controlled presentation and faithful, well-signposted state.

## 2. Evidence: genre product changes and player signal by 2026-10-31

| Evidence, date | What it establishes | Implication / caveat |
|---|---|---|
| [Vampire Survivors 1.16.100 Aug 28 2026](https://nintendoeverything.com/vampire-survivors-1-16-100-update-out-now-patch-notes/) | Banish can keep level-up screen open, Quickstart favors missing unlock, special passives can be offered past usual slots, CPU/memory and damage-number improvements | Distinguish UI interactions from permanent choice consumption; "six slots" is not a hard engine ceiling |
| [Vampire Survivors level-up and Random LevelUp](https://vampire.survivors.wiki/w/Level_up) | Manual level selections, reroll/banish/skip, random option and alternative end-level rewards | Accessible automation can coexist with strategic manual choices; wiki may combine version notes |
| [Vampire Survivors Quick Treasures](https://vampire.survivors.wiki/w/Treasure_Chest) | Experienced users can reduce repetitive treasure presentation | Separate reward delivery from cinematic presentation |
| [Soulstone Survivors Gift of the Veil Jun 12 2026](https://steamcommunity.com/app/2066020/allnews/) | Fixes for hazards outside areas, UI localization, cooldown precision and damage logging, skill/rune status changes | Source provenance, exact tooltips and warning visibility need stable interfaces |
| [Soulstone feedback: auto-level setting Aug 3 2025](https://www.reddit.com/r/SoulstoneSurvivors/comments/1mgkdyf/) | Users explicitly differ between manual and automated upgrade experiences | Preference signal, NOT population prevalence or validation of a particular mode |
| [Soulstone feedback: pause behavior May 16 2025](https://www.reddit.com/r/SoulstoneSurvivors/comments/1knwu3f/) | Unpaused upgrade screen perceived as unfair/dangerous | Default selection must safely pause; deferred mode opens panel explicitly at a safe barrier |
| [Soulstone feedback: visibility Jul 30 2026](https://www.reddit.com/r/SoulstoneSurvivors/comments/1vb4765/) | One VFX slider can over-dim some spells and insufficiently reduce bright ones | Divide visual groups and protect enemy tells |
| [Vampire Survivors feedback Sep 13 2026](https://www.reddit.com/r/VampireSurvivors/comments/1wfe5k7/) | Late-run pickup/menu interrupts remain a point of friction | Avoid compulsory reward popups for repetitive nonchoices |
| [Soulstone feedback: banish and build-dependent utility Jun 21 2026](https://www.reddit.com/r/SoulstoneSurvivors/comments/1ubomnq/) | Players consider banish strategically and often misunderstand caps/scaling | Cards should show applicability, source, opportunity cost; do not claim every "best" upgrade is universal |

Evidence from player threads is qualitative/selection-biased, not a statistical study. Dates are the **event dates**, not indexing dates. Do not import November 2026 patches when making an October-baseline decision.

## 3. Three independent dimensions of "autoplay"

**A. Automatic combat** (accepted concept): techniques automatically trigger/aim. Player moves, dodges and decides build trajectory.

**B. Automatic presentation of an earned choice**: does the level-up panel open immediately or can the player bank levels and explicitly open the panel later?

**C. Automatic decision-making**: if the player opts in, which currently eligible card does a deterministic preference policy pick? This is **not the same** as B. Options must not silently lock builds into a heuristic.

Proposed user-facing modes:

| Mode | Level-up delivery | Special ritual/boss/meridian choices | Status |
|---|---|---|---|
| **Immediate / classic** | Pause and show pending levels at committed tick barrier | Pause and show | Static oracle implemented, current sample default |
| **Bank levels** | Accumulate owed level selections while gameplay continues; visible count; open manually | Must open at barrier (and reveal previously banked levels in FIFO) | Static oracle implemented; **not** future Godot UI |
| **Auto-pick by authored preference** | Explicit opt-in; deterministic policy chooses on current build revision; highlights when no valid candidate | **Manual by default**, optional specific advanced policy later | PROPOSED ONLY; not in oracle |
| **Batch sequential presentation** | One modal session, queue badge \`1 of N\`, no scene close/reopen after every commit | Same queue/atomicity | PROPOSED VIEW only; not a merged reward transaction |

Bank mode affects **presentation/when choices are committed**, not when experience or the level is earned. The player is responsible for the temporary opportunity cost of unused skill ranks. No hidden reward reduction, fabricated catch-up stats, altered drops or double leveling.

**Policy boundary:** pending ordinary level choices may be deferred, while ritual/boss/meridian choices remain mandatory in the reference design. Future alternate handling of special rewards needs explicit authored source policy and save semantics.

### Causal ordering when a mandatory reward arrives

Suppose the player has banked three normal level choices and then triggers an evolution ritual. The event ledger enqueues the ritual *after* the earlier levels. The panel opens because of the mandatory ritual, and the prior three choices are presented first. This preserves FIFO and permits earlier picks to change evolution eligibility. It can feel long; alternatives such as special priority routing must be defined as game mechanics, not hidden UI sorting.

**SAVE-CONTRACT-001 linkage:** [reference checkpoint](save-contract-001.md) проверяет, что очередь, пауза, ревизия билда и уже полученные награды переживают сериализацию/восстановление между двумя выборами; сохранение DraftService hand/Reroll/Lock и UI focus ещё открыто.

## 4. Design-time state machine and contracts

The prior \`pending_choices\` model convolved two distinct facts: (1) an unclaimed decision exists and (2) the simulation is paused. Separate them:

- \`pending_choices: ChoiceReceipt[]\` — durable ownership of **earned**, unconsumed choices.
- \`choice_mode: IMMEDIATE | BANK_LEVELS\` — declared, versioned run/presentation policy.
- \`paused: bool\` — only when an immediate/mandatory choice is open or the player explicitly opens banked options.
- \`build_revision\` — authoritative optimistic token for selecting an eligible offer.
- \`last_tick\` / \`last_sequence\` — simulation progression, never presentation time.

Reference helpers:
- \`open_pending_choices\`: open a pending bank with **zero** sim-tick advancement.
- \`defer_pending_choices\`: permitted only for banked **ordinary levels**; never delete/payout owed choices.
- \`choice_summary\`: read-only snapshot for UI indicator; shows banked levels and mandatory choices.
- \`apply_events\`: accepts one committed tick batch, not a mixed multi-tick stack. New world events may arrive while *banked but not paused*. Replaying an identical receipt remains idempotent while paused.
- \`commit_choice\`: head-of-queue, only with trusted currently eligible IDs and current build revision; no accidental second commit from held accept key.

**Persisted run state must include** choice mode, pending UID queue, receipt ledger, XP source claims, revision, independent RNG streams and rules snapshot. A user settings toggle must not change the meaning of already committed reward events. Changing presentation mode mid-run is **OPEN**; avoid silent reordering.

### UX controls for the real game (not yet implemented)

- A **visible pending-count indicator** is mandatory in bank mode (including when HUD is simplified). It conveys "unspent levels", not a free bonus.
- An explicit "Open upgrades" action must work with keyboard/mouse/controller, including non-combat safe contexts.
- The selected card must **not** be confirmed by a key press that was being held to dodge or move as the panel appeared. Consume and release trigger input; require a fresh accept transition. Controller focus always starts on a valid card or a safe no-selection state.
- The return from pause must not inadvertently send "Confirm" to the gameplay dodge input; preserve simulation cooldown/velocity and any authored active dodge state, no free i-frames introduced by UI.
- For **batch** choice UX, retain the same modal root and display a \`N remaining\` badge while re-evaluating legal cards after every commit; no multiple cinematic animations for an ordinary rank-up.
- Reroll, Lock and Banish are *operations on the current offer*, not automatically a spent \`LevelUpChoice\`. Their effect on pool/next hand/charges/RNG must be formalized in [BUILD-SKILL](build-skill-architecture-proposal.md) before runtime.
- If no legal candidate remains: source- and mode-specific fallback is explained, not a fake selectable card.
- Auto-pick preference is always **explicit**; respect user-defined priority/avoid list and record reason, rule revision and chosen token. Do not auto-pick a rare mutually exclusive evolution or meridian path by default.

**Integration update:** [CHOICE-VIEWMODEL-001](choice-viewmodel-001.md) содержит проверяемую модель source-grounded карточек, hand/locked/banned, явный Skip и защиту от удерживаемого Confirm. Это ещё не интерфейс Godot и не human-verified accessibility.

## 5. Choice-card information architecture

The choice card should answer in 2–3 seconds:
1. **What do I get?** \`Active | Passive | Power | Evolution | Ritual | Breakthrough\`; title, school/tag and icon.
2. **What changes now?** exact current→next rank or stack and a functional delta (new projectile, wider cone, new status), not just a vague \`+15% potency\` label.
3. **Why is it relevant?** matching owned tags, statuses, prerequisites and a clear \`Catalyst for X\` or \`Completes recipe\` when discovered.
4. **What do I sacrifice?** slot use, replaced/consumed skills, new cooldown, mutually exclusive route, owned-rank loss if any.
5. **Where did this offer come from?** XP, elite, chest, altar, class breakthrough; locked/unlocked reason; optional details from the Canon.
6. **Can I safely act?** explicit button label, disabled/fallback state, reroll/banish counters, focus outline and a visible queue \`3 of 5\`.

Avoid ungrounded auto-generated "best for your build" labels. A tag explanation can state objective compatibility, but synergy viability and DPS forecasts need a provenance-backed calculation. **Do not duplicate gameplay formulas inside localized display strings**: generate card facts from canonical definitions and immutable RunBuild snapshot; RU/EN strings only present the facts.

Proposed pure \`ChoiceViewModel\` fields:
\`\`\`
choice_uid, source_event_uid, source_kind, queue_index/total
choice_mode, build_revision, content_digest
offer_id, offer_kind, current_rank, proposed_rank
school_tags, relevant_owned_ids, eligibility_reasons
effect_delta_view[], cap_policy, slot_delta, consumes_ids[], grants_ids[]
recipe_progress, rarity, localization_keys, can_confirm
can_reroll, can_banish, can_lock, source_reward_label
\`\`\`

The static \`choice_summary\` in this slice is a *tiny subset* of this contract, **not** a production card renderer.

## 6. XP pickup UX and accessibility

XP delivery is a **spatial agency mechanism**, not a screenshot decoration. The player needs visible distinction between:
- **XP available on ground**, **XP physically/legally collected**, **XP credited**, **levels earned**, **pending unspent choices**.
- **Magnet radius** vs Growth/XP bonus. Showing "Collection range +20%" does not imply "XP +20%".
- Ordinary XP vs Qi and class-ascension objects. Same glow/color does not establish same resource.
- Pickups on the far side of obstacles; a region tag in the reference fixture **does not prove reachability**.
- Special chest/gift/ritual vs a repeated nonchoice XP collection. Animations should communicate reward significance, not interrupt continuously.

### Safety improvement to the reference oracle

Prior consolidation applied to \`XP, HEALTH, CATALYST\`, potentially summing **non-additive** rewards. Now the sample consolidator only combines XP objects at the exact same owner/region/position/policy and preserves all original source UIDs. HEALTH/CATALYST stay separate unless a future **kind-specific associative rule** has proof.

An XP receipt can no longer be considered fully authorized merely because its UID is new. The reference now checks its credited amount against a trusted **drop source-value manifest** (derived from the original synthetic pickups). In a future game this must come from an authoritative \`DropLedger\` and persist through serialization; it must never trust arbitrary client/UI-reported values.

This is a targeted proof, **not** a complete in-game loot ledger: actual drops, magnetization, colliders, TTL, item ownership and exp growth remain future contracts.

## 7. Perceptual performance must not nerf combat semantics

Existing [v5 UX](../v5/v5_ux.md) correctly separates audio priority, enemy tells, and damage labels. Extend it into measurable contracts:

| Category | Preserve regardless of chaos | Can be scaled down |
|---|---|---|
| Enemy hazard / boss telegraph | geometry, timing, outline, distinct shape and high visibility | optional bloom outside warning boundary |
| Player attack feedback | skill identity, important reaction, boss/elite kill | particles, redundant flashes, simultaneous damage number popups |
| Audio | critical danger cue, hurt cue, meaningful evolution | routine hit voice count, overlapping similar sounds |
| Text/UI | XP and unspent choices, level/HP and legal pause state | noncritical popups and ambient decorations |

One global \`VFX opacity\` setting risks hiding some attacks while leaving others overpowering. Consider distinct \`Player Projectiles\`, \`Spells/Area Effects\`, \`Enemy Warnings\` controls (warning minimum contrast remains stable). This is a design proposal, not a tested parameter set.

**Never** remove logical hits/status procs or alter source counting to satisfy a cosmetic budget. Aggregated damage numbers and pooled audio events are allowed because they do not change the game-state result.

## 8. Integration matrix — avoid incompatible local improvements

| Producer → consumer | UX-dependent requirement | Current status |
|---|---|---|
| \`Combat/DropService → Pickup/XPService\` | source/value proof, no XP loss, clear ground-to-credit state | static reference partial, no game |
| \`XPService → ChoiceCoordinator\` | choose immediate or bank, durable queue, mandatory special rewards | **static reference for two presentation modes** |
| \`ChoiceCoordinator → DraftService\` | exact fresh eligibility, no stale card, clear fallback | design only |
| \`DraftService → RunBuild/BuildTransaction\` | atomic selection, revision, correct slot/consume preview | build projection separate; no integration |
| \`Cultivation/StageEvent → ChoiceCoordinator\` | independent choices, event source, priority, protection from duplicate ritual | static ritual/breakthrough envelopes; source reward contracts OPEN |
| \`RunBuild/Transformation → ChoiceViewModel\` | display recipe readiness, consumption, next rank and cost | new contract proposal |
| \`SimulationSnapshot → Presentation\` | visual readability, focus and no ghost input on resume | historical v5 UX; no runtime |
| \`Outcome → MetaLedger\` | separate Spirit Stones/Dao Seals from in-run XP/Qi; exactly once | v7 accepted meta reward contract, unchanged |

The app-level \`ChoiceViewModel\` should read a **stable** snapshot and never mutate gameplay stats. The same validity engine must serve mouse, controller, accessibility auto-pick and later headless bots.

## 9. Player journeys as future human acceptance scenarios

### First run: discoverability and confidence
- Choose sword or thunder with clear starting technique/identity and run length.
- XP piles teach magnet vs Growth through visual distinction, not mandatory text walls.
- First level-up defaults to paused **Immediate**, one readable card selection.
- New technique provides an immediately recognizable geometry change and rank delta.
- First evolution card indicates the catalyst and which technique is consumed if unlocked.
- On death, results show the incoming source and *one suggested next goal*, not a pile of unexplained stats.

### Experienced 20-minute run: flow and mastery
- Player elects \`BANK_LEVELS\`; pending count persists and can be opened at a chosen moment.
- A ritual chest forces a strategic choice; banked levels remain guaranteed and occur first by defined FIFO rule.
- Five pending choices appear as **one sequential decision session**, not five flashing popup transitions.
- When source skills are full, special rewards can use authored extended capacity rules; UI shows exactly why.
- Reroll/Banish remain available via explicit budget; unavailable cards have a clear reason.
- A highly synergistic build retains telegraph visibility and damage attribution.

### High-power/Endless: scalability
- At extreme XP flow, level gains are not silently discarded, nor are pending choices.
- The player may explicitly opt into deterministic auto-pick and/or skip repeated purely numerical presentation **only when authorized by design policies**.
- Warning SFX and boss hit shapes are preserved while cosmetic VFX/counters are aggregated.
- Collection and level queues remain crash-resumable; meta reward settlement never repeats.

## 10. Proposed measurement plan (hypotheses, not measurements)

Future experiments should collect **per-mode and per-player cohort**:
- interruption rate: choice windows shown/minute, not levels earned/minute;
- median/p90 time spent in the choice screen per deliberate selection;
- input errors: accidental confirmations, cancel/reopen, focus loss, invalid card confirmations;
- post-resume death rate within a small declared tick window (must distinguish dangerous position from input carryover);
- percentage of earned XP and level choices ultimately credited/claimed;
- reroll/banish/lock frequency and discovered evolution readiness;
- tutorial comprehension: can players explain Magnet vs Growth, Catalyst vs consumed component, XP vs Qi?
- hazard recognition under low VFX, color-blind modes and extreme builds;
- first-run clarity of next goal and retry path.

Set numerical targets **after** reference playtests with keyboard+mouse and controller, not by inventing "industry-standard" conversion rates. Bot-only tests cannot validate perceived fairness or readability.

## 11. Open decision register (no hidden acceptance)

| ID | Priority | Proposed default | Why it stays open |
|---|---|---|---|
| UX-01 | P0 | Immediate panel default; Bank Levels available as selectable preference | Player study for interruptions vs challenge |
| UX-02 | P0 | Special ritual/breakthrough forces pause, FIFO follows banked levels | Could be annoying after extreme backlog; needs human test |
| UX-03 | P1 | Batch sequential panel with queue badge | Presentation vs chronological offer visibility |
| UX-04 | P1 | Deterministic preference auto-pick opt-in, not default | Need DraftService proof; important choice protection |
| UX-05 | P0 | Fresh-press controller/keyboard confirm after opening panel | Avoid accidental duplicate selection while dodging |
| UX-06 | P1 | Reroll/Banish/Lock are separate interactions, not reward consumption | Changes RNG/card state, needs revised API |
| UX-07 | P0 | Separate warning layer from scalable player VFX groups | Requires visual QA with real assets |
| UX-08 | P1 | Card shows rank delta, catalyst, consumed IDs, origin, slot cost | Need canonical ViewModel/localization adapters |
| UX-09 | P1 | Choice presentation preference may change mid-run only at safe boundary | Replay and rules-hash semantics undecided |
| UX-10 | P1 | Non-XP pickup merging disabled absent kind-specific proof | Re-evaluate only when real item behaviors defined |
| UX-11 | P0 | XP amount backed by trusted DropLedger source-values | Needs future authoritative loot producer |
| UX-12 | P1 | No mandatory autoplay for mutually exclusive meridians/evolutions | Control and decision ownership |

**Acceptance for this proposal:** link to concrete decision for each policy before adding canonical schema; keep per-user preference distinct from gameplay RulesHash unless preference affects future simulation decisions; make all simulated/strategic actions replayable and no silent progression loss.

## 12. Next design slice (not GAME-ARCH-02 yet)

Close **GAME-UX-001** before building more stages:
1. Clarify choice presentation state, queue vs paused, precise input focus.
2. Add cross-layer \`ChoiceViewModel\` schema and negative examples for stale/consumed/capped offers.
3. Specify ritual/chest UI journey with banked levels and multiple events.
4. Define separate drop-source ledger/claimed-value semantics and kind-specific pickup combine proof.
5. Define developer-friendly UX instrumentation and future controlled playtest protocol.

**No Godot runtime, sprites or user testing is claimed by these checks.**
