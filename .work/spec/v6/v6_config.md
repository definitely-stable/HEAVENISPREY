---
id: v6_config
title: "T. Конфигурация как продуктовый API: что агентам разрешено менять без правки кода"
source: architecture-v6-2026-11-11
status: superseded-by-v7
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> **Правила частично переопределены:** [v7 — поздняя прогрессия](../v7/late-game-progression.md) и [ADR-003](../../decisions/ADR-003-late-game.md).

<a id="v6_config"></a>
## T. Конфигурация как продуктовый API: что агентам разрешено менять без правки кода

### T.1. Типы конфигураций и их жизненный цикл

| Данные | Где живут | Кто меняет | Когда считываются | Нужен ли version gate |
|---|---|---|---|---|
| `SkillDef`, `EnemyDef`, `StatusDef` | `res://data/defs/` JSON либо `.tres` после импорта | Контент-агент; review | при запуске билда, затем immutable для run | да |
| `ClassDef`, `TalentDef`, `UnlockDef` | `res://data/progression/` | геймдизайн/AI | на старте/при входе в меню, snapshot в run | да |
| `DifficultyProfile`, `ModeDef`, `StageDef`, `RewardDef` | `res://data/rules/` | баланс-агент | **до** начала нового забега | да |
| `Localization` | `res://localization/` CSV/PO | Codex + ревью | runtime `TranslationServer`, без изменения симуляции | версионирование ключей |
| `Settings` | `user://settings.cfg` | игрок | сразу и по согласованным runtime hooks | миграция настроек |
| `PlayerProfile` | `user://profiles/<id>.json` | игра | смена меню, транзакции наград, сейв | строго да |
| `RunSuspend` | `user://runs/<id>.json` или компактный бинарный формат | игра | только в безопасной точке snapshot | `RunRulesHash`, `schema_version` |
| `BotScenarioDef` | `res://qa/scenarios/` | агент тестов | из CI/команды test runner | версия fixture |

**Не использовать один `config.json` на всё.** У разработческого контента, пользовательских предпочтений, save-прогресса и сессионных правил противоположные требования к мутируемости. `ConfigFile` официально предназначен для INI-подобных настроек, а `JSON` — для обмена/сериализации структур; `user://` — постоянное место хранения сохранений. [R72](https://docs.godotengine.org/en/4.7/classes/class_configfile.html)[R73](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)[R74](https://docs.godotengine.org/en/4.7/classes/class_json.html)

**Принцип «один источник правды»:** JSON — исходный контент для редактирования AI, валидированный и преобразованный при загрузке в typed `*Def`. `.tres` можно использовать для editor-friendly презентационных ресурсов или как конечный импорт, но не дублировать числовые значения одновременно в `.tres` и JSON. Допустима будущая миграция к `.tres` после сравнительного теста инструментария — это ADR, а не необходимость сейчас.

### T.2. Versioned schema и typed runtime

```text
ContentRegistry.load(validated_json)
  ├── SkillDef / StatusDef / EnemyDef
  ├── StageDef / SpawnTable
  ├── ClassDef / TalentDef / UnlockDef
  ├── DifficultyProfile / ModeDef / TrialDef
  ├── RewardTable / CurrencyDef
  └── Localization key catalog (not combat data)
       ↓ validate references, cycles, ranges
       ↓ build canonical content digest
RunFactory(profile, selections, seed)
  → RunConfigSnapshot (immutable)
  → CombatWorld + ProgressionRunState
  → RunResultReceipt
  → MetaProgressionService.settle_once(receipt)
```

Каждый JSON корневой объект несёт `schema_version` и `id`. **Два независимых version gate**: `schema_version` описывает форму полей, `content_revision` — игровые цифры/состав. Результат содержит `rules_hash` и `content_hash`, причём второй не зависит от текста локализации. Для воспроизведения старого реплея по возможности хранить снимок необходимых правил; отсутствие старой версии не должно маскироваться загрузкой новых.

При чтении: требовать `known id`, допустимый тип данных, конечные `float` (`NaN`/`Inf` недопустимы), диапазоны и отсутствие неизвестных ключей без явной политики. `JSON.parse` Godot допускает некоторые нестрогие формы JSON, поэтому для исходников CI дополнительно использует строгий Python-парсер. Для save требуется входная проверка типов, а не слепой `Dictionary`-доступ. [R74](https://docs.godotengine.org/en/4.7/classes/class_json.html)

### T.3. Порядок валидации конфигураций

1. **Синтаксис**: UTF-8, корректный JSON/CSV, отсутствие повторных ключей и незаявленных полей.
2. **Schema**: `schema_version`, допустимые enum, `min/max`, типы чисел, обязательные поля; неизвестная версия — явная ошибка.
3. **Ссылки**: `ClassDef.start_skill_id` существует, все `TalentDef.effect_ops` поддерживаются, `mode.requires/excludes` ссылаются на режимы, `StageDef` — на существующие waves/bosses, localization keys есть.
4. **Graph rules**: циклы prerequisite талантов запрещены; self-referential unlocks запрещены; status-proc graph проверяется существующим `EventBudgetAnalyzer`.
5. **Economy**: стоимость rank растёт строго по таблице, награды неотрицательны, respec обратим и не порождает валюту.
6. **Composability**: mode/priority/field ownership валидируются для выбранной комбинации; во время забега конфиги не перечитываются.
7. **Simulation**: фиксированные seed + сценарные боты, negative tests и balance fixtures; draw-call и FPS тесты отдельно на реальном GPU.
8. **Review**: AI агент публикует changed IDs, изменённые кривые наград, таблицу before/after и ожидаемые риски, а не только diff чисел.

### T.4. Пример разделения source-of-truth

```json
{
  "schema_version": 1,
  "id": "difficulty.hard",
  "name_key": "DIFFICULTY_HARD_NAME",
  "unlock_id": "unlock.hard",
  "enemy_hp_mult": 1.20,
  "enemy_damage_mult": 1.15,
  "spawn_budget_mult": 1.20,
  "elite_frequency_mult": 1.25,
  "telegraph_min_ticks": 36,
  "reward_mult": 1.20
}
```

`1.20` — **не подтверждённый баланс**, а число в примере проектной схемы. Правила загрузки должны обеспечивать, что `telegraph_min_ticks` не уменьшается ниже проверенного человеческими playtests порога. Изменение одного `difficulty.hard.json` должно менять только будущие забеги, не результаты уже сохранённого/начатого.

### T.5. Дисциплина AI content PR

Codex получает: `TASK_SPEC`, ID затронутых классов/карт/режимов, разрешённые пути (`data/`, `localization/`, `tests/fixtures/`), ссылку на актуальную schema и требования acceptance. Он **не редактирует** базовые боевые формулы без отдельного архитектурного PR. Бот-пакет запускается в headless CI, выдаёт JSON/CSV с `config_hash`, seed, классом, профилем и результатами. Ручная настройка каждого уровня сводится к конфигам: `pressure_curve`, `spawn_set`, `boss_timeline`, `trial_tags`, `rewards`, `unlock_rules`, `localized_strings`.
