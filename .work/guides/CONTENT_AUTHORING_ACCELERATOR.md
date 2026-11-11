# Content Authoring Accelerator — архитектура и ускорение будущей разработки

- **id:** AUTHORING-PIPELINE-001
- **status:** design-proposal / not implemented
- **date:** 2026-11-11
- **scope:** архитектурная документация, дизайн-данные, проверки и агентская навигация; NO GAME DEVELOPMENT
- **dependencies:** [Build skill proposal](../spec/v7/build-skill-architecture-proposal.md), [ADR-006](../decisions/ADR-006-content-catalog.md), [WORKFLOW](WORKFLOW.md), [DOC_STANDARDS](DOC_STANDARDS.md)
- **acceptance:** review of the workflow plus future static fixtures; no generated code or pipeline claimed running
- **evidence:** current v7 JSON catalogs, Python validators and tests

## 1. Problem inventory, with anti-duplication policy

Existing: 63 section navigation, v7 canonical catalogs, `validate_work.py`, `validate_content.py`, `validate_migration.py`, negative data tests, Linux/Windows CI, agent routing, task/evidence templates.

Missing for **build/skill** authoring: cross-catalog skill rank schemas, independent passive vs meta vs Power definitions, transformation recipes, a policy table for unresolved choice semantics, static reachability witnesses, proc graph checks, machine-readable content dependency graph, automatic change-impact reports, dedicated visual reference registry.

Do not replace existing files with another architectural handbook. New specs add **only missing contracts**, cite current ADRs, and remain PROPOSED until accepted. Do not inflate skill catalogs before validation rules.

## 2. One authoring action = one traceable change set

Every new skill or evolution should come with:
1. **Definition** in the single canonical design source (v7 directory, when its schema is accepted).
2. **Legal constraints:** typed taxonomy, max rank, acquisition, slots, target/cast policy and proc bounds.
3. **References:** IDs for prerequisite skills, statuses, passives and class availability.
4. **Fixture:** minimal positive witness (can acquire/transform) and negative witness (cannot acquire/transform).
5. **Presentation contract:** RU/EN names/description, warning/visual priority, reference asset IDs (not raw image assumed to be a game sprite).
6. **Traceability:** source spec -> fixture -> validator -> reviewer -> future runtime test.
7. **Impact:** list of upstream/downstream definitions affected by the change.

Use the [skill template](../templates/SKILL_SPEC.md) to eliminate missing fields and repeated discussions.

## 3. Schema-first: proposed static validation layers

| Layer | Proposed check | Currently available? |
|---|---|---|
| L0 | UTF-8, parse and duplicate-key rejection | existing |
| L1 | field types/enums/ranges, unknown-field rejection | partial; extend |
| L2 | referenced IDs + localization keys | existing for current catalogs |
| L3 | skill acquisition/ranks/slots and transformation cardinality | missing |
| L4 | recipe graph witness + exclusivity conflicts | missing |
| L5 | finite proc graph and event upper bounds | described historically, validator missing |
| L6 | draft offer eligibility, finite fallback and seeded reproducibility | missing |
| L7 | cross-version migration policy, content hash, save compatibility | contract only |
| L8 | gameplay bot, rendering, visual clarity, FPS | future only; do not run in this phase |

**Option:** adopt pinned JSON Schema 2020-12 to validate L1. This does not replace semantic graph checks L3-L7. A pure stdlib validator is acceptable when simpler; avoid adding a second runtime source of truth or unnecessary Python deps.

## 4. Automatable artifact generation proposals

All generated files are **derived views**, not independently editable sources:
- `generated/build-graph.md`: Mermaid graph skill -> prerequisites -> evolution/union/gift.
- `generated/skill-matrix.csv`: class, school, geometry, tags, status source, acquisition and rank caps.
- `generated/impact-report.md`: affected recipes, classes, localization and tests for changed IDs.
- `generated/content-index.md`: ID -> source path -> authoritative spec -> status.
- `generated/l10n-coverage.md`: missing and mismatched RU/EN keys.
- `generated/decision-register.md`: unresolved policy entries with owner/status and ADR link.
- `generated/art-reference-index.md`: asset ID, original file hash, view, scale, license/provenance, approved status.

**Available now (design-only; CI verified on Ubuntu + Windows):**
- `python scripts/validate_build_proposal.py` — validates the isolated `.work/proposals/build-skill-001/reference_catalog.json` catalog, its five witnesses, transformation slot math, exact gates, and an acyclic conservative proc-event bound. This is **not** a runtime engine or canonical content validation.
- `python scripts/content_impact.py --id status.mark --json` — read-only reverse dependency impact against the **existing** canonical v7 definitions; exact-ID references only.
- `python -m unittest discover -s tests -v` — includes BUILD-SKILL negative cases and dependency-graph tests.

**Still proposed, NOT implemented:**
- Formal JSON Schema 2020-12 structural validation / richer semantic schema tests.
- `scripts/render_content_graph.py` (read-only derived Mermaid), asset manifest metadata validator, migration proof, seeded weighted draft sampler, all-build reachability analyzer.

**Restriction:** the sample catalog uses `sample.*` IDs and synthetic numbers. Do not import these into `game/` or overwrite `.work/config/v7/`. Existing v7 remains the only accepted source of gameplay design definitions.

## 5. The minimum useful agent context pack

For a narrow skill change, load in this order:
1. `AGENTS.md`, `START_HERE.md`, current HEAD/PR and `CURRENT_STATE.md` (treat stored state as a snapshot).
2. `ADR-002`, `ADR-006`, then just `build-skill-architecture-proposal.md` if relevant.
3. Direct definitions (class, skill, status, passive/Power/recipe) and a relevant fixture.
4. Only the touched validator functions/tests.
5. Historical v5/v6 sections **only** when a conflict or origin question arises.

Avoid copying the 2633-line archive or dumping the entire v7 catalog for a single skill. Use a stable bounded context and a written change impact map.

## 6. Review loop that catches semantic errors

Use two **independent** checklists, not two model-specific roles:
- **Definition review:** stable IDs; tags; valid prerequisite graph; acquisition and rank; honest class identity; localization; no numerical value duplicated elsewhere.
- **Mechanics review:** slot arithmetic; automatic/strategic boundary; deterministic offer generation; transformation atomicity; future in-flight policy; proc upper bound; replay attribution.

A review with no fixture or counterexample is incomplete. Proposed gate: every new semantic op requires one positive and two negative tests; for purely documentary changes, link checking and traceability may suffice.

## 7. Visual asset provenance before production

User-supplied character sheets and level boards are **references**, not animation source or game-ready textures. A future `visual_reference_manifest.json` should distinguish:
- `reference` (concept sheet), `master` (approved character/view), `normalized` (clean PNG), `atlas` (derived sprites);
- SHA-256 of source bytes and stored relative path; do not claim traceability from image filename alone;
- reference IDs, body scale, feet anchor, facing directions, light direction, pose, palette, art/QA approval;
- class/enemy/stage ID, review thumbnail, provenance/usage notes;
- derivative operation and license/permission metadata where applicable.

Do not produce a sprite sheet solely by cropping a turnaround infographic: frames may differ in anatomy, perspective, scale and clothing topology.

## 8. Architectural questions to settle BEFORE content expansion

- Which proposals become accepted? 6+6 cap, max 5 ranks, exact auto-target rules, Power scaling/rarity, acquisition fallback.
- How to distinguish category/tag/source counts in conditional offers?
- What events cause an evolution: chest, class breakthrough, boss drop or direct level-up?
- Can the player decline/postpone available evolution? What happens when two recipes compete?
- Can a union consume an evolved skill, a gift, or a passive catalyst?
- How are build history and released in-flight projectiles preserved after transformation?
- Are realm breakthroughs timed or automatic; how is Qi distinct from XP and Dao Seals?
- Which "impossible" combinations should be prevented by schema vs guarded by content-level approval?

Keep answers in a concise decision register. Do not implicitly decide them in individual JSON cards.

## 9. Incremental architecture-only roadmap

| Priority | Deliverable | Static acceptance | No-go |
|---|---|---|---|
| A0 | Decision table / proposal review | every unresolved policy has explicit status | no runtime |
| A1 | Skill and passive/Power schemas | type/rank/tag rules and negative fixtures | no mass content |
| A2 | Evolution/Union/Gift schemas + witness paths | graph satisfiable, exclusivity and slot arithmetic | no game systems |
| A3 | Draft rules, seeded choice fixtures | reproducible eligible pool and fallback spec | no game simulation claim |
| A4 | Proc budget static estimator spec | finite rule graph + bound for representative combos | no FPS claim |
| A5 | Content impact + generated graph design | no second source of truth, deterministic output | no extra framework by default |
| A6 | Art-reference + visualization standard | provenance, sizes, pivot, class identity and readability QA criteria | no generated sprites |

A later explicit change of scope can authorize `P0-00` Godot bootstrap. Until then it is **deferred**, not the next permitted action.

## 10. Anti-scope checklist

- [ ] No `game/` directory or `project.godot`.
- [ ] No scene files, runtime GDScript, or automatic combat bots.
- [ ] No fabricated pass results, performance data or playable balance.
- [ ] No raw AI assets as purported production-ready sprites.
- [ ] No changes to gameplay numeric config solely to satisfy a proposal.
- [ ] No merge of a proposal without explicit review.
- [ ] A changed definition has a provenance/impact record.

Useful sources: [JSON Schema spec](https://json-schema.org/specification) and [Mermaid syntax](https://mermaid.js.org/syntax/flowchart.html); consulted 2026-11-11. Both are optional tools, not new required dependencies.
