---
id: v5_risk
title: "Дополнение O. Приоритеты рисков и вывод после пересмотра"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_risk"></a>
## Дополнение O. Приоритеты рисков и вывод после пересмотра

| Риск | Тяжесть | Вероятность (проектная оценка) | Контроль |
|---|---|---|---|
| Экспоненциальные proc chains | критическая | высокая при свободных upgrade | compiler bounds + golden + rejection |
| Invalid repeated hits / stale handles | критическая | высокая до строгого контракта | hit ledger + generation + collision tests |
| Игрок не видит опасные атаки | критическая | высокая с xianxia VFX | separate telegraph layer + playtest |
| Редкий game loop, слишком много формул | высокая | высокая | P0-04 до content scale |
| MultiMesh ломает сортировку/анимацию | высокая | средняя | occlusion gauntlet + render A/B |
| Несогласованная AI-анимация | высокая | высокая | keyframe QC + reusable anchors |
| Headless benchmark ошибочно принят за FPS | высокая | высокая | tagged metrics and exported test |
| MCP доступен только в live editor | средняя | средняя | CLI headless fallback |
| Обновление движка меняет replay | высокая | средняя | engine/content hash, upgrade branch |
| Выбор дополнительного native до профиля | средняя | средняя | measured C++/Rust gate |
| RE реконструкция старой сборки | средняя | высокая | evidence tier and game build ID |
| Билд разваливается от выбора upgrades | высокая | высокая | draft validator + 1000-seed property runs |

**Порядок дальнейшей работы:** `P0-00` с CI → `P0-01/02/03` с доказанной семантикой → `P0-04` с реальным геймплеем → `P0-05/06` с проверенной графикой → интеграция результатов code-first RE → M1. Это не отказ от research: это ограничение объёма research теми вопросами, ответ на которые реально меняет архитектуру или тест.

---
