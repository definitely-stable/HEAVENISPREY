---
id: v6_state
title: "AE. CURRENT_STATE / Текущий статус после изменения документа"
source: architecture-v6-2026-11-11
status: superseded-by-v7
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> **Правила частично переопределены:** [v7 — поздняя прогрессия](../v7/late-game-progression.md) и [ADR-003](../../decisions/ADR-003-late-game.md).

<a id="v6_state"></a>
## AE. CURRENT_STATE / Текущий статус после изменения документа

```text
Last verified HEAD: репозиторий собственной игры не предоставлен;
                    локальный архитектурный документ v5 проверен
Current milestone: P0 — Architecture v6: multilingual + meta + difficulty
Current slice: META-001 / CLASS-001 / BOT-QA-001 / I18N-001 / MODE-001
Open PR: отсутствуют (у игры нет репозитория)
Last CI: игровой CI не запускался
Acceptance: все подтверждённые проектные решения описаны,
            конфигурационные контракты и QA определены;
            Godot gameplay/progression не реализован
Known blockers: нет игрового репозитория и целевой GPU-модели;
                отсутствуют измерения бот-прогонов и баланс-тестов
Next allowed action: P0-00/01/02 — bootstrap + CombatSemantics +
                     ContentRegistry/i18n; далее M1 полный игровой цикл
Last updated from repository: 2026-11-11 — публичная документация;
                              HEAD игры отсутствует
```

**Итоговое решение v6:** начинаем с **двух полноценных классов, RU/EN, двух базовых уровней сложности, пяти минут автоатак, одной валюты и первой покупки таланта**. `hurry`, `frenzy`, `endless`, трибуналы, все четыре класса, третья локаль и сотни узлов доступны для дальнейшего расширения через утверждённые data contracts, но не блокируют первый playable. Все правила развития, наград и режимов имеют собственные версии, неизменяемый snapshot забега и автоматические сценарии проверки.


[R64]: https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_spreadsheets.html
[R65]: https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_gettext.html
[R66]: https://docs.godotengine.org/en/4.7/tutorials/i18n/internationalizing_games.html
[R67]: https://docs.godotengine.org/en/4.7/classes/class_translationserver.html
[R68]: https://docs.godotengine.org/en/4.7/tutorials/ui/gui_using_fonts.html
[R69]: https://vampire.survivors.wiki/w/Stages
[R70]: https://www.soulstonesurvivors.com/
[R71]: https://www.soulstonesurvivors.com/news/
[R72]: https://docs.godotengine.org/en/4.7/classes/class_configfile.html
[R73]: https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html
[R74]: https://docs.godotengine.org/en/4.7/classes/class_json.html
[R75]: https://docs.godotengine.org/en/4.7/tutorials/io/saving_games.html
[R76]: https://www.reddit.com/r/roguelites/comments/1ssorwi/opinion_contentbased_meta_progression_is_vastly/
[R77]: https://www.reddit.com/r/roguelites/comments/1vydmcp/do_you_guys_actually_like_metaprogression/
[R78]: https://www.reddit.com/r/roguelites/comments/1wpdjx3/how_do_you_like_meta_progression_in_roguelites/
[R79]: https://media.gdcvault.com/gdc2025/Slides/Fan_Monica_Gameplay%2BSystem%2BDesign.pdf
[R80]: https://www.reddit.com/r/godot/comments/1snfjka/got_localization_working_the_native_support_in/
[R81]: https://vampire.survivors.wiki/w/PowerUps
[R82]: https://steamcommunity.com/app/2066020/announcements/
[R83]: https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html
[R84]: https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html
[R85]: https://steamdb.info/patchnotes/24926490/
