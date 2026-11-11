---
id: v5_audit
title: "Дополнение A. Аудит всех 32 разделов v4: что недоопределено, какое исправление принято"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_audit"></a>
## Дополнение A. Аудит **всех 32 разделов v4**: что недоопределено, какое исправление принято

Обозначения: **P0** — отсутствие решения блокирует корректную реализацию; **P1** — риск крупной переделки; **P2** — разрешено отложить. Статус относится к архитектурной определённости, не к выполненному коду.

| Блок v4 | Оценка | Недостаток | Правка v5 / критерий |
|---|---|---|---|
| 00. Executive | P0 | «Combat Simulation» слишком широк; нет границы Entity/View ownership | Добавить lifecycle, stable IDs и staging boundary |
| 01. Аудит v3 | P2 | Аудит прошлой версии не проверяет новые регрессии v4 | Настоящая таблица и change log v4→v5 |
| 02. Границы игры | P1 | Недостаточно defined input, dodge, death, enemy fairness | PlayerController, Damage Receiver, BossDirector, UX contract |
| 03. Renderer | P1 | Не оговорена детальная поддержка атласов и Y-sort при инстансинге | Render families, buckets, pivot, per-instance UV, benchmark |
| 04. Runtime | P0 | Fixed step есть, но не специфицирован catch-up / frame stall | Max accumulated ticks и политика slow-motion; нельзя пропускать sim ticks без контроля |
| 05. Content | P0 | Отсутствует завершённая машинная схема и кросс-валидация | JSON Schema + link validator + UUID-safe IDs + revision policy |
| 06. Scheduler | P0 | Слабая семантика target loss, snapshot, attack intervals | State machine + schedule ordering + unit examples |
| 07. Damage | P0 | Не определены shields, invuln, contact hit, overkill, kill-owner | Отдельные stages и golden tests |
| 08. Status | P0 | Модели представлены, но неполные правила aggregation/dispel | Expiry ordering, source attribution, tick batching proofs |
| 09. Proc | P0 | Static bound указан, но нет исполняемого budget analyzer | Formula root bound + cycle checker + reject incompatible combo |
| 10. Spatial | P0 | Нет достаточного контракта «сходная цель/тай-брейк/толпа» | Radius metric, deterministic tie-break, max candidates, query tests |
| 11. Enemy horde | P0 | Не описаны damage telegraphs, boss FSM, arena borders | EnemyDef.ai, Telegraph lifecycle, spawn fairness, camera bounds |
| 12. Projectiles | P0 | Не завершён hit ledger и правила повторного контакта | Projectile hit lifetime + per-target cooldown + penetration |
| 13. Replay | P0 | «seed + input» не гарантирует cross-platform determinism | Versioned state digests, event logs, deterministic tier promise |
| 14. Presentation | P0 | MultiMesh/CanvasItem гибрид без правил сортировки/UV | Visual family renderer, material buckets, GPU overdraw tests |
| 15. VFX/UI | P1 | Нет собственно UX-модели внимания игрока | Enemy warning on top, color/shape redundancy, aggregate labels |
| 16. AI art | P1 | Отсутствует стратегия согласованности и повторной анимации | Character bible + frame QC + regenerate-or-fix rubric |
| 17. Atlases | P1 | VRAM бюджет без source-vs-runtime policy | Sprite atlas schemas, padding/extrusion, memory audit |
| 18. Xianxia design | P1 | Интересные идеи, но нет законченного контент-графа | Dao branch taxonomy, stages, tribulation gates, anti-brick draft |
| 19. Balance | P0 | Метрики есть, нет уравнений прогрессии и автоигровых орacles | Per-build tests, TTK distributions, fairness/variance measures |
| 20. Saves | P1 | Невнятно поведение при обрыве и изменении каталога | Snapshot boundary, checksum, rollback, migration fixtures |
| 21. Dependencies | P1 | Список похож на желаемую установку; часть версий без smoke | Minimal lock + one-at-a-time qualification + removal plan |
| 22. MCP/skills | P1 | Много абстракций; нет оплаты/лимитов и облачного исполнения | Existing-subscriptions only, 1 editor MCP optional, CLI fallback |
| 23. RE | P0 | Неявная вера в то, что IL2CPP decompile даёт формулы | Evidence ladder and build-specific native validation |
| 24. Performance | P0 | Бюджеты не привязаны к измеренному hardware, сим не testable | Repro fixtures with CSV samples, rendered export vs headless |
| 25. CI | P1 | Команды и runner gates оставлены условными | Scriptable smoke, import, unit, export, test-fail sentinel |
| 26. Repo/ADR | P1 | Нет отдельного контракта art, core, scene changes | CODEOWNERS-by-policy + folders + AGENTS.md + ADR templates |
| 27. Roadmap | P1 | Срезы измеримы, но нет критического пути между ними | PR-00→PR-08 with gates and parallel lanes |
| 28. Risks | P1 | Упущены игровые UX-риски и арт-консистентность | New quantified risk registry |
| 29. Agent tasks | P1 | Промпты есть, но не описаны инструменты проверки evidence | Mandatory diffs, exact commands, artifact bundles |
| 30. Sources | P1 | Некоторые ссылки зависят от mutable `stable/latest` | Verifiable 4.7 official URLs, dates and evidence tiers |
| 31. CURRENT_STATE | P0 | «готовность к PR» легко спутать с доказанной реализацией | Strictly research-only status until CI / game repo exists |

**Итог аудита:** предыдущая работа сильна как *архитектурный перечень*, но не выдерживает теста «пусть другой агент реализует без уточнений». Исправление — фиксировать не только названия компонентов, но и правила, граничные случаи и подтверждающие тесты. Не нужно добавлять сторонний ECS или API ради ощущения современности: Godot 4.7 уже содержит нужные базовые 2D системы. [R04](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)[R20](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html)[R40](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)
