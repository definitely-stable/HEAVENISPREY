# GAME-ARCH-00 — RunOrchestrator, EventLedger и ChoiceCoordinator

- **id:** GAME-ARCH-00
- **status:** DESIGN PROPOSAL / STATIC REFERENCE VERIFIED WHEN CI PASSES / NOT GAME IMPLEMENTED
- **date:** 2026-11-11
- **scope:** только архитектура и статический контракт; **NO** `game/`, Godot, сцены, ассеты, боты и баланс
- **dependencies:** [GAMEPLAY-GAP-001](gameplay-loop-gap-audit.md), [combat time (s04)](../core/s04.md), [replay (s13)](../core/s13.md), [BUILD-SKILL-001](build-skill-architecture-proposal.md), [v7 economy](economy-and-talent-sinks.md), [XP design](game-arch-01-xp-pickups.md)
- **static evidence:** [isolated reference data](../../proposals/game-arch-00-01/reference_run.json) and [read-only Python oracle](../../../scripts/validate_run_loop_proposal.py), [negative tests](../../../tests/test_run_loop_proposal.py)
- **important:** merging these docs doesn't establish agreed gameplay priority among competing rewards. Decisions marked OPEN remain proposals.

## 1. Why this is a P0 contract

A single combat tick can kill an elite, produce a chest, collect enough XP for several levels, and reach a cultivation threshold. Existing skills/damage architecture says how effects apply, but not what **orders and owns** all strategic decisions.

`RunOrchestrator` coordinates lifecycle and owner services; it does **not** resolve damage, apply a skill rank or choose loot. `ChoiceCoordinator` queues the human decisions; it does **not** own the eligible pool.

### Logical ownership and APIs

| Owner | Consumes | Emits / owns | Does NOT do |
|---|---|---|---|
| `RunSession / RunOrchestrator` | command log, run rules, tick | phase/lifecycle, commit barrier | calculate hit damage or invent upgrade card |
| `CombatSimulation` | input, existing state | hit/death and stable event intents | present a choice menu |
| `EncounterDirector` | run timeline, danger policy | deterministic spawn/goal intents | rewrite drop reward in UI |
| `Drop/PickupService` | death/reward source, world position | logical pickup and collection receipts | grant meta settlement directly |
| `XPService` | credited XP | progression level events, overflow | decide which skill is offered |
| `ChoiceCoordinator` | level-up, ritual, breakthrough intents | queued exactly-once choice UID | compute DraftService or gameplay power |
| `DraftService / RewardResolver` | immutable run snapshot, build rev | currently eligible offer IDs | bypass `BuildTransaction` |
| `BuildTransaction` | selected *validated* offer + expected revision | new RunBuild revision or rejection | create extra reward from repeated input |
| `Outcome/Settlement` | terminal run result, RulesHash | exactly-once profile rewards | reopen a processed run payout |
| `PresentationBridge` | read-only snapshot and presentation events | UI/VFX/audio | mutate simulation state or RNG |

A runtime implementation may combine some types in a few modules. These are **logical responsibility boundaries**, not a requirement for 10 services.

## 2. Four clocks: existing baseline vs missing new contracts

- **Simulation:** deterministic fixed-tick movement/combat; existing [s04](../core/s04.md) contract.
- **Encounter timeline:** time/kill/objective gates of stage enemies and POIs; proposed [GAMEPLAY-GAP](gameplay-loop-gap-audit.md).
- **Choice queue:** user-visible strategic decisions. Once paused, the **simulation tick does not advance**. UI animations may continue; UI must not consume gameplay RNG.
- **Meta lifecycle:** results, run rewards and unlocks; existing exactly-once constraints [v7 economy](economy-and-talent-sinks.md).

Avoid a shadow timer in a chest UI, a projectile scene or a pickup object. Choice resolution does not trigger physics steps.

## 3. Event envelope and deterministic ordering

Future `RunEvent` fields:

```text
run_uid
event_uid                 immutable unique receipt ID, namespaced by run
tick                      simulation tick at acceptance
simulation_phase          phase ordering from s04 (not UI frame)
global_event_sequence     strictly monotonic sequence assigned by sim
emitter_uid + generation  who created the event; no dangling instance-only name
origin_event_uid          optional parent/root provenance
kind                      XP_GAIN / RITUAL_REWARD / BREAKTHROUGH_READY / etc
payload                   typed by kind (not open arbitrary JSON)
rules_hash + schema_version
```

**Reference oracle uses the minimal subset:** `run_uid, uid, tick, sequence, kind, payload`. The extended fields above are future schema requirements; don't claim they are implemented in the test.

**Sequence allocation contract (future):** canonical `s04` simulation phases establish an ordered set of event producers. Within a phase, sort eligible handles by stable UID and generation; allocate monotonic sequence numbers *on accepted events*. A sequence is never assigned from JSON insertion order, callback arrival, VFX, filesystem traversal or wall-clock time. Simultaneous events follow the committed event log, not a random priority of their UI types.

The **current reference fixture** chooses an explicit source sequence and sorts an unordered batch by `(tick, sequence, uid)`. It rejects a second distinct event with the same `(tick, sequence)`, nonmonotonic sequence or past tick.

**OPEN RLOOP-01:** If a game designer wants explicit source priority (ritual before XP, e.g.), it must be an immutable `ChoicePriorityPolicy` version, not a hidden sort by kind.

## 4. Event processing and strategic pause

At the end of tick `T`:
1. Collect all accepted world/reward intents from the committed simulation tick.
2. Validate IDs, ordering and typed payloads; reject conflicting receipts.
3. Apply XP accounting and produce one level-up **choice per earned level**; enqueue ritual/breakthrough choices with their independent UIDs.
4. Complete the **entire deterministic event batch**. Enter `CHOICE_PAUSED` if the [GAME-UX-001](game-ux-001-oct-2026.md) policy is **Immediate** or a mandatory ritual/breakthrough is pending; in optional **Bank Levels** mode, ordinary levels remain earned and queued while simulation may continue until the player opens the panel.
5. Show first choice or a batched-sequential UI. Obtain **fresh eligible IDs** from `DraftService` / `RewardResolver` using the current `build_revision` and `RunRulesHash`.
6. On user action validate first-in-queue choice UID, current build revision, selected eligible ID and available source. An atomic `BuildTransaction` commits the mutation and increments revision.
7. Re-evaluate eligibility of the next queued choice; no stale menu options. Resume simulation **only once queue is empty**.
8. Exact replay of a processed reward receipt is an idempotent no-op. Reuse of a UID with different contents, different run or overlapping consumed pickup source IDs is rejected.

**Example (reference test):** one pickup grants 40 XP, thresholds `5,12,20,30` are incremental costs from levels 1→2→3→4→5. Player advances 1→4, keeps 3 XP, and queues 3 level choices. A ritual reward and Qi breakthrough at the same tick follow them according to event sequences. Total = 5 user decisions. After all five commits the run resumes **at the original tick**, not after five simulated frames.

`ChoiceCoordinator` may display several cards at once but must commit **sequentially**, because the first choice can alter the legality of the second. No silently bundled bonus that removes earned choices.

**UX distinction (as-of October 2026):** the presence of an earned `pending_choice` does **not** itself imply `paused=True`. A deliberately deferred level-up is still owed; a mandatory ritual opens the queue while preserving FIFO. The isolated Python model now validates same-tick input batches, two presentation modes and an explicit manual open/defer action. [GAME-UX-001](game-ux-001-oct-2026.md) documents future controller/focus, auto-pick and batching behavior; none is claimed to exist in the game.

## 5. Lifecycle proposal

`RUN_SETUP → RUNNING → CHOICE_PAUSED ↔ RUNNING → FINISHING → SETTLED`

- `RUN_SETUP`: build immutable rules snapshot (existing stage/difficulty/mode/profile/skill schema), create run UID and independent RNG streams.
- `RUNNING`: advance only a fully authorized tick; all phase intents collected at barrier.
- `CHOICE_PAUSED`: no simulation / enemy AI / XP pickup / status expiry; UI selections do not alter run tick or gameplay RNG.
- `FINISHING`: finalize terminal event exactly once and freeze new reward intents; resolve mutually exclusive outcomes.
- `SETTLED`: only permitted meta journal transaction `run_uid/reward_event_id`; idempotent reopen of result screen.

**OPEN RLOOP-02:** death and same-tick level-up, revival effect, or boss victory precedence. A game runtime must not invent its rule; define terminal event priority and whether pending choices are canceled or resolved. Current static oracle deliberately does not model death/settlement.

**OPEN RLOOP-03:** quit during paused menu; serialize queue, receipt ledger, build revision and source claims so resume neither rerolls nor duplicates a reward. Profile save is not the same as a mid-run save.

## 6. Receipt identity and anti-duplication

- Run event UID is unique **per run**; identical second receipt is a no-op.
- Reusing UID with changed payload fails even after a pause.
- Consolidated XP keeps a stable, sorted list of **source_uids**. A second XP receipt with a **different** event UID but any overlapping source UID fails, preventing re-credit after a presentation representation changes.
- Receipt and source claims are distinct: receipt dedupe alone does not prevent source-level double payment.
- `event_uid` is not `reward_event_id` of the **meta** settlement. Don't mix in-run drops with Spiritual Stones / Dao Seals payout.
- `RulesHash` must include run-specific gameplay policy versions and content digests; not invented by the design oracle.

## 7. Replay and failure modes

Proposed golden log: `run_uid, tick, event_sequence, event_uid, choice_uid, build_revision_before/after, source_uids, class/stage, rules_hash`. Do not store full redundant display objects with the event stream.

| Failure case | Mandatory outcome |
|---|---|
| Same event twice, same payload | one payment / same queued choices |
| Same UID, changed payload | explicit rejection, no partial mutation |
| Different UID but already claimed XP source | explicit rejection |
| Same tick and sequence, different UIDs | deterministic validation error |
| World event while choice pause active | reject until resume (except exact receipt replay) |
| Second choice committed before first | reject |
| Choice based on stale build revision | reject and re-resolve offers |
| Invalid/now-unavailable offer | reject; don't consume reward |
| Multiple levels from XP lump | no loss of XP or level choice |
| UI focus loss or animation lag | no simulation tick/RNG advancement |
| Sibling rewards competing for one skill | current build revision checked after each commit |

### Reference implementation limits

The Python oracle only models `receipt → XP → pending choices → revision acknowledgements`, **not** actual gameplay effects of the chosen option. It receives a *trusted* offered-token list supplied by tests; a future implementation must compute it from current immutable RunBuild definitions. Transaction projection from [ARCH-01](build-skill-type-contract.md) is separate.

The oracle does not prove death/terminal precedence, physical movement, loot RNG, performance, human enjoyment or complete save migration. These remain explicit architectural blockers rather than secretly assumed behavior.

## 8. Architecture acceptance / next decisions

- [x] Minimal event ordering, run scoping and duplicate receipt rejection have a **design-time test model** (once linked CI is successful).
- [x] Multiple levels plus ritual and breakthrough yield distinct ordered choices.
- [x] No choice from stale revision; no simulation tick advancement during a paused selection.
- [ ] RLOOP-01/02/03 policy decisions explicitly approved.
- [ ] Full typed envelope with `simulation_phase`/generation/RulesHash and migration version.
- [ ] Integration with a trusted `DraftService` and `BuildTransaction` (later runtime only).
- [ ] Real pause/resume replay, death and settlement property tests (later).
- [ ] Human UX review of batched-sequential reward menus (later).

## 9. Authoring rule for AI agents

If editing event ordering, update this contract, [GAME-ARCH-01](game-arch-01-xp-pickups.md), reference fixture, negative tests and the traceability row in one PR. **Do not** modify historical s04, nor the accepted v7 reward formula as a side effect.

[Reference fixture and caveats](../../proposals/game-arch-00-01/README.md) · [Gameplay gap audit](gameplay-loop-gap-audit.md)
