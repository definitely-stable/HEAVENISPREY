---
id: v6_re
title: "Z. Дополнение к reverse engineering: искать не только урон, но и метаэкономику, трудность и UI"
source: architecture-v6-2026-11-11
status: normative-v6
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

<a id="v6_re"></a>
## Z. Дополнение к reverse engineering: искать **не только урон**, но и метаэкономику, трудность и UI

**Vampire Survivors RE-VS-002**: по текущей сборке и версиям моддинг-документации установить, какие режимы участвуют в StageSelect, где хранятся unlock flags/PowerUps, как работают Reroll/Skip/Banish, как считают reward gold, чем различаются таймеры Hurry/Endless и как совмещаются stage/mode modifiers. Начать с публичных описаний режимов и PowerUps [R69](https://vampire.survivors.wiki/w/Stages)[R81](https://vampire.survivors.wiki/w/PowerUps), затем продолжать анализом конкретных данных/метаданных/методов сборки (только если доступна). Для каждого результата: `game_build`, `source_path`, `class/method`, `hypothesis`, `evidence_grade`, `reproduction_fixture`. Ни числовые значения другой игры, ни её имена классов не копировать в наши конфиги автоматически.

**Soulstone Survivors RE-SS-002**: отдельно исследовать доступные карты и режимы, Curses, talent trees, class mastery/prestige, runes, способ выдачи ресурсов и unlock eligibility; в 2026 официальные изменения напрямую затрагивали множители multicast, DoT, руны и классовые таланты. Это подтверждает необходимость внешней data configuration и автоматических regression fixtures, но не даёт исходный код формул без анализа версии игры. [R70](https://www.soulstonesurvivors.com/)[R71](https://www.soulstonesurvivors.com/news/)

**RE-evidence ladder:** официальные патчи/документация → проверяемые game-data таблицы → call graph/decompiled method в конкретной сборке → runtime trace → повторный независимый эксперимент → только после этого `CONFIRMED`. Wiki, reddit и чей-то decompilation repo — полезный источник гипотез, но не автоматическое доказательство метода релизной сборки. Каталог сохраняется в `research/re/vs/` и `research/re/soulstone/` с раздельными файлами `meta_progression.md`, `difficulty_modes.md`, `reward_economy.md`.

**Результат RE** — не клон: таблица продуктовых решений `adopt / adapt / reject` и сценарные тесты наших правил. Например, принять принцип комбинируемых модификаторов VS, но не переносить точные проценты или бесконечную прогрессию Golden Eggs; принять ширину дерева Soulstone, но начать с 6–10 уникальных классовых узлов.
