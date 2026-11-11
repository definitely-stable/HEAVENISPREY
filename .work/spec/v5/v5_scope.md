---
id: v5_scope
title: "Дополнение N. Новый конкретный roadmap, зависимости между этапами и критерии «действительно сделали»"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_scope"></a>
## Дополнение N. Новый конкретный roadmap, зависимости между этапами и критерии «действительно сделали»

Не строить 20 систем в одном PR. Рекомендую восемь узких вертикально связанных changesets; сроки ориентировочные и зависят от фактической доступности агентов и сложности imagegen.

| Slice/PR | Задача | Зависит от | Acceptance |
|---|---|---|---|
| `P0-00 TOOLCHAIN` | Godot 4.7.2, typed GDScript rules, clean import, GUT, GitHub Actions | нет | clean checkout, negative test fails CI, Windows/Linux exports |
| `P0-01 CORE` | Tick loop, entity handles, spatial grid, movement, replay digest | P0-00 | golden movement, reused slot, 500–1000 fixture recorded |
| `P0-02 ATTACK` | 3 auto-cast skills, projectile/aura hit ledger | P0-01 | no manual attacks, repeated hit semantics, no duplicate kills |
| `P0-03 STATUS` | 3 statuses, tick scheduler, one reaction + proc budget | P0-02 | seeded golden + cycle validation + VFX independence |
| `P0-04 GAMELOOP` | XP, upgrades draft, 2 enemy families, elite/boss telegraph | P0-03 | 5-min playable loop + controller test + death explainability |
| `P0-05 RENDER` | Hero/elite sprites, bulk enemy render batches, VFX tiers | P0-04 | readable telegraphs, visual 2D sorting, exported performance A/B |
| `P0-06 ART` | Codex hero keyframes, 2 enemy families, 3 skill FX, atlas QA | P0-05 | accepted scene gallery and asset manifests |
| `P0-07 REVIEW` | replay/benchmark/art/playtest gate, report to M1 | all | 3 short independent playtests, tracked issues, no P0 blockers |

В параллельном **RE lane**: `RE-VS-001` (code/data source audit) и `RE-SS-001` (patch-dependent multicast/status audit) могут идти после P0-00; RE не редактирует combat runtime непосредственно. По результатам выдаётся `RE_DECISIONS.md` с proposed changes для отдельного PR. В параллельном **ART lane** концепт героя можно начать после `ART_STYLE_BIBLE.md`, но runtime atlas и pivot должны соответствовать P0-05.

### 32N.1. M0 acceptance как функциональная игра

1. Игрок движется, уклоняется, а все выбранные способности **применяются автоматически**.
2. По двум разновидностям врагов видна разная пространственная задача, элита делает читаемую атаку.
3. Есть 3 навыка, 3 statuses, одна реакция и минимум 3 содержательных upgrades; новый build заметно меняет удары.
4. HP/death, XP collection и 5-минутное завершение/победа присутствуют; нет бесконечного unhandled event loop.
5. Профайлер публикует реальные отдельные `sim_tick`, `frame`, `events/sec`, `GPU presentation` при доступности; не обещает 5000@60FPS до замера.
6. UI позволяет выбрать улучшение клавиатурой/геймпадом, остановить игру, видеть опасность при FX_LOW.
7. Чистая GitHub Actions CI компилирует/импортирует Godot сцену, выполняет unit/golden и экспортирует Windows/Linux, attach exact run IDs.
8. Render quality toggles не меняют state digest на выбранных seeds.
9. Сохраняются settings, прогресс и данные диагностики; возможность run suspend зависит от этапа и не рекламируется ранее M1.
10. Игрок-испытатель понимает, чем отличается наша «стадия культивации» от обычного level-up; до получения этого результата не создавать 40 школ и 200 артефактов.

### 32N.2. Чего **не делать**, несмотря на моду 2026

- Подключать сторонний ECS framework «на всякий случай», прежде чем SoA/GDScript не измерены.
- Запускать сразу два MCP, изменяющих один Godot editor, или делать MCP обязательным для CI.
- Гоняться за 100k врагов, прежде чем работает атака, элита и игровой feedback.
- Создавать AI-арт всех персонажей до утверждения pivot/animation/atlas standard.
- Называть «доказанный replay» поток, который меняется от нового Godot patch.
- Вводить сервер, multiplayer, cloud telemetry, платные image APIs, маркетплейс ассетов или сложный creator economy.
- Создавать собственный language parser для skill programming; runtime оперирует ограниченными типизированными opcode действиями, эволюция языка — только по доказанной необходимости.
