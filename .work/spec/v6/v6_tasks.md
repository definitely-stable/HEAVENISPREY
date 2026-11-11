---
id: v6_tasks
title: "AB. Конкретные задачи, независимые от модели AI"
source: architecture-v6-2026-11-11
status: adapted-role-neutral
last_review: "2026-11-11"
---

> **Адаптация v7:** текстовые назначения задач конкретным моделям отменены. [Единый регламент](../../guides/WORKFLOW.md) применим к любому исполнителю. [Историческая версия](../../archive/architecture-v6-original.md) сохранена без правок.

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> **Правила частично переопределены:** [v7 — поздняя прогрессия](../v7/late-game-progression.md) и [ADR-003](../../decisions/ADR-003-late-game.md).

<a id="v6_tasks"></a>
## AB. Конкретные задачи для Codex / Claude Code / OpenCode Go

### `TASK META-I18N-001` — LanguageService

Создать `LocalizationContract` (`*_key` + placeholders), `TranslationServer` adapter, `localization/strings.csv`, `GLOSSARY.md`, `i18n_lint.py`, UI language selector и smoke `en/ru`. Не обращаться к локализованным строкам из `sim/`. Acceptance: переключение языка mid-run не меняет replay state; все test keys найдены; тесты скриншотов на двух разрешениях с зафиксированной версией Godot.

### `TASK MODE-001` — Content configs и Immutable RunRules

Определения `DifficultyProfile`, `GameMode`, `StageDef`, `RewardTable`, builder `RunRulesResolver`. Реализовать `requires/excludes`, типовые профили `apprentice/standard/hard`, режим `normal`; добавить пример `hurry`, но не считать его играбельным до теста трёх clock domains. Acceptance: unknown/invalid combination fail fast; сериализуемый hash; изменение графического качества не меняет rules hash.

### `TASK META-001` — Wallet, talents, profile

`PlayerProfile v1`, `ClassProgress`, `TalentDef`, `UnlockDef`, `RunResultReceipt` и `settle_once`; духовные камни и классовое XP, первые 3 узла общих талантов. Acceptance: save/load, double-result/no-double-award, power-loss fixture, respec no mint, class unlock condition, пересмотренная стоимость через JSON без правки кода.

### `TASK CLASS-001` — Class Definition Bridge

Два класса (меч/гром), применение immutable `CharacterSnapshot`, ограниченные `EffectOp`, навигация `ClassSelect`. Acceptance: стартовый класс меняет реальные атаки/статусы и save class XP; условие открытия второго класса; нелегальный start skill отклоняется валидатором.

### `TASK BOT-META-001` — 5 bots + simulation report

Реализовать `PlayerCommand` path, `idle/random/beginner/survival/progression`, вариант `farmer`, replay fixtures и CSV telemetry. Acceptance: 20 последовательных забегов, изменения в покупках отражаются в win-rate/trace, подставленные duplicate receipts не порождают валюту, script выходит с ненулевым кодом при нарушенном инварианте.

### `TASK BALANCE-001` — Parameter-only workflow

Сделать процедуру изменения одной карты, одного профиля сложности и одного ряда стоимости талантов **без редактирования боевых `.gd` файлов**, сохранить before/after таблицу: win-rate, death causes, rewards/min, max event queue, time-to-upgrade. Приёмка — валидные ссылки, неравновесный тест найден, CI regression/report сохраняются. Параметры accept/reject определяются человеком, а не автоподгоном под любой успех бота.

### `TASK RE-002` — Исследование прогрессии обеих игр

Проверить редакцию конкретных установленных сборок, публичные game-data и доступные modding refs; собрать таблицу stages/modes/perks/economy, каждую механику пометить как `DOC`, `CODE`, `TRACE`, `UNVERIFIED`. Нельзя создавать issue «RE complete», пока не приложены ссылки на конкретную версию/класс и воспроизводимый пример.
