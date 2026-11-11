# Content Registry Contract — канонические данные v7

**Status:** ACCEPTED DESIGN / NOT IMPLEMENTED. **Дата:** 2026-11-11.

## Источник истины и разделение слоёв

- Единственный активный дизайн-каталог: [`.work/config/v7/`](../../config/v7/README.md), включающий классы, навыки, статусы, карты, боссов, таланты, валюты, режимы, награды и ботов. Конфиги здесь — **не** Godot runtime.
- Прежний ZIP v6 имел `schema_version:1` и противоречил v7 по условиям Небесной кары/Бездны Дао. Его данные **нормализованы**, не скопированы поверх действующих определений. [Точное разрешение конфликтов](../../guides/PACKAGE_RECONCILIATION.md).
- После реализации `game/`, импортёр строит проверенные **typed definitions** из канонического каталога. Не дублировать числа в GDScript или втором JSON без генерации и проверки digest.
- `ContentRegistry` обязан завершить валидацию **до** создания `RunRulesHash`, `RunBuild`, `PlayerCommand` и наград. Неизвестные ссылки и дублированные ID — ошибка сборки, не fallback на пустое действие.

## Структурные связи

```text
class -> starting_skill -> skill.effect_ops -> status
     -> class_unlock ----------> unlock_conditions -> stage / boss / difficulty
     -> mastery_tree -> class_talents

stage -> supported_difficulties -> difficulty -> unlock
      -> boss_by_difficulty -> boss

mode -> mode_unlock + exclusions
     -> RunRulesHash <- stage + difficulty + content digest + seed

reward_contract -> difficulty + mode + validated_milestone
                -> stable run_uid / reward_event_id -> profile currency ledger

bot_scenario -> policy + profile_fixture + class + stage + difficulty + modes

all name_key -> translations.csv (RU/EN)
```

## Нормативные требования

1. Все IDs стабильны; `schema_version` для текущих дизайн-данных равен 2.
2. Единый каталог локализации `translations.csv` имеет **ровно** `keys,en,ru` по нашей конвенции. По Godot 4.7 дополнительные `_context` колонки-комментарии допустимы, а для структурированных текстов доступны `?context` и `?plural`. Контекст перевода отдельно; `localization_additions.csv` — исторический промежуточный слой, не второй импортируемый источник.
3. Два класса (`sword`, `thunder`) и две карты определены для будущих тестов, но каждая карта, босс и техника помечены `design-only`; в исполняемой игре их пока нет.
4. Классовое мастерство — не расходуемая валюта. Таланты `acquisition=mastery_level` **не имеют** цены и `rank_costs`.
5. Мультикасты, DoT и эффекты не кодируются произвольным GDScript в JSON. Допустимы только валидируемые `effect_ops` с явно поддерживаемыми операторами и ссылками.
6. Время само по себе не даёт позднюю валюту; награды за минуты для обычных камней дополнительно требуют подтверждённого прогресса (киллы в пилоте — предварительный критерий, не проверенная баланс-модель).
7. Не запускать режимы или сложности без соответствующих unlock. Граф должен содержать **реально определённые** карты и боссов. Определённый JSON-босс не означает готовый бой; выпуск проверяет `runtime_implemented` отдельно от статической доступности.
8. Сохранения и возобновление забега должны привязываться к `content_hash`, `RunRulesHash` и `schema_version`. Старые run snapshots с неэквивалентной семантикой `mode.frenzy` не мигрируют молча.

## Проверки

- `python scripts/validate_content.py`: связность классов, навыков, статусов, карт, боссов, unlock, условий позднего гейта, режимов, talents, reward и RU/EN.
- `python scripts/validate_work.py`: базовый v7 invariant validation.
- `python scripts/validate_migration.py`: целостность исторического v6.
- `python -m unittest discover -s tests -v`: design-contract tests.

**Ограничение:** Python-валидация доказывает связность **описаний**, не то, что эффекты реализованы или gameplay сбалансирован. После bootstrap требуются Godot import/headless tests, визуальные проверки и ProgressionBot.
