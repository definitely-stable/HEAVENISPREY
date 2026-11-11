# SKILL_SPEC — шаблон проектирования техники / пассива / Power / рецепта

> Это шаблон **архитектурной заявки**, не валидный исполняемый JSON и не инструкция реализовать игру.
>
> **Source of truth:** после утверждения схемы данные помещаются в `.work/config/v7/`; здесь фиксируют требования и evidence. Не храните вторую независимую копию чисел.

## Идентичность
- **Stable ID:** `skill.*` / `passive.*` / `power.*` / `evolution.*` / `union.*` / `gift.*`
- **Display name RU / EN:** 
- **Status:** PROPOSED / ACCEPTED DESIGN / STATIC VERIFIED / IMPLEMENTED (future)
- **Owner class / globally acquirable:** 
- **Tags (separate):** school / element / geometry / delivery / status / origin
- **Sources and visual references:** precise URLs/asset IDs + SHA where possible
- **Design goal and counterplay:** what choice, what role, what downside?

## Acquisition
- **Source:** intrinsic / level-up active / level-up passive / Power / ritual reward / meta unlock
- **Active/passive slot cost:** 
- **Max rank, repeatability, exclusivity:** 
- **Required unlocks, prerequisite IDs and tags:** 
- **Applicable classes/modes:** 
- **Draft eligibility and weighting:** explicit policy ID, no undocumented pity
- **Fallback when slots full or no candidates:** 

## Gameplay semantics (for future runtime)
- **TargetPolicy + tie-break:** 
- **Aim/cast policy:** auto trigger, no-target behavior, windup and cooldown
- **Geometry and collision:** center, units, shape, max targets, hit interval
- **Effects, statuses, owner snapshots:** 
- **Origin/proc flags:** direct / echo / chained / DoT / reaction
- **Bounded worst-case events per root:** 
- **In-flight on evolve / on death:** 
- **Presentation / accessibility:** telegraph priority, animation, VFX cap

## Development ranks and transformations
| Rank | Visible functional change | Numerical modifier | Prerequisites |
|---|---|---|---|
| I | | | |
| II | | | |
| III | | | |
| IV | | | |
| V | | | |

- **Evolution recipe IDs:** 
- **Union / Gift / alternate branch IDs:** 
- **Consumes / preserves / grants:** 
- **Atomicity / slot arithmetic / conflicting recipe policy:** 
- **Qi / realm / meridian effect (if any):** 

## Static witnesses and counterexamples (mandatory before acceptance)
- **Positive fixture:** minimal legal build sequence and exact expected result
- **Negative fixture A:** unmet rank or catalyst -> ineligible
- **Negative fixture B:** full slots / mutual exclusion / stale build revision -> rejected
- **Graph check:** recipe reachable, no impossible cycles or duplicate ownership
- **Localization check:** all UI keys RU+EN
- **Source-impact check:** dependent class/skills/statuses/recipes/bots/translation IDs
- **Status of tests:** NOT RUN / actual command + observed result

## Decisions and sign-off
- **OPEN questions:** list rather than filling them with guesses
- **Related ADR:** 
- **Decision owner/date:** 
- **Acceptance:** proposed rule plus independent review and evidence
- **Limitations:** no balance / enjoyment / FPS / Godot assertion from design-only review

[Architecture proposal](../spec/v7/build-skill-architecture-proposal.md) · [Authoring guide](../guides/CONTENT_AUTHORING_ACCELERATOR.md) · [TASK_SPEC](TASK_SPEC.md)
