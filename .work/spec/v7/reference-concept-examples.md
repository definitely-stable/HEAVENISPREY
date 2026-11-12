# REF-EXAMPLES-001 — концепции с референсов, которых нет в v7 (только примеры)

- **Статус:** **EXAMPLE, не нормативно и не обязательно.** Решение пользователя от 2026-11-12: концепции, которые есть только на изображениях `ref/`, оформляются как примеры для вдохновения. Они не входят в roadmap-гейты, не создают ID в `.work/config/v7` и не обязывают реализовывать что-либо.
- **Источник:** [ref/catalog.json](../../../ref/catalog.json) (ART-REF-001), раздел findings. Идентификаторы ниже с префиксом `example.` — **не** игровые ID; при принятии концепции получают обычный ID через спецификацию и [ADR-006](../../decisions/ADR-006-content-catalog.md).
- **Правило:** если концепция понадобится, она проходит обычный путь: TASK_SPEC → спецификация/ADR → `.work/config/v7` → валидатор. До этого текущий канон остаётся без изменений.

## Примеры

| Пример | Что на референсе | Ближайший канон сейчас | Если когда-нибудь принимать |
|---|---|---|---|
| `example.arena.ancient_sect_courtyard` | двор древней секты, кадр «Этап 3» с HUD и ордой — REF-001, REF-023 | [stages.json](../../config/v7/stages.json): `stage.jade_grove`, `stage.mist_cliffs` | GAME-ARCH-02: топология, волны, окна угроз |
| `example.arena.cultivator_graveyard` | кладбище культиваторов — REF-001 | то же | то же |
| `example.arena.tainted_swamp` | заражённое болото — REF-001 | то же | то же; зоны замедления — через статусы |
| `example.arena.sect_ruins` | руины секты: план, потоки движения, зоны — REF-001, REF-033 | то же | хороший образец для разметки escape routes |
| `example.arena.yinyang_monastery` | заброшенный монастырь Иньян: карта, тайлы, свет — REF-056 | то же | то же |
| `example.mode.event` | пункт «Событие» в главном меню — REF-047 | [modes.json](../../config/v7/modes.json): 8 режимов, «События» нет | [modes-and-compatibility](modes-and-compatibility.md) + RulesHash; правила наград по `reward_event_id` |
| `example.class.specializations` | «будущие специализации» Мечника: Sword Saint / Sky Cleaver / Voidblade — REF-062 | классы и техники в [classes.json](../../config/v7/classes.json), [BUILD-SKILL](build-skill-architecture-proposal.md) | GAME-ARCH-03 или отдельная спецификация; совместимость со слотами и Evolution |
| `example.class.difficulty_rating` | рейтинг сложности класса на экране выбора — REF-062 | нет | UX-поле ChoiceViewModel/экрана класса, без влияния на правила |
| `example.meta.equipment_inventory` | экран экипировки: слоты, инвентарь — REF-019 | нет; мета-прогресс — таланты секты ([late-game](late-game-progression.md)) | отдельное решение о scope; риск конфликта с flexibility-first билдами |
| `example.meta.quests` | список заданий, сундуки, свитки — REF-053 | нет | отдельное решение о scope; награды только через RewardSettlement |
| `example.menu.sect_progress_arsenal_bestiary` | кнопки «Прогресс секты», «Арсенал», «Бестиарий» — REF-046, REF-047 | таланты секты; discovery/grimoire — GAME-ARCH-07/08 | экраны поверх существующих контрактов |
| `example.boss.heavenly_lord` | «Небесный владыка в тронном зале» — REF-048 | [bosses.json](../../config/v7/bosses.json): `boss.jade_warden`, `boss.mist_sentinel`, `boss.tribulation_avatar` | визуальное настроение для существующего босса или новый босс через enemy-threat-contract |
| `example.visual.currency_icons` | кристалл, нефрит, слиток — REF-007 | [currencies.json](../../config/v7/currencies.json): `currency.spirit_stones`, `currency.dao_seals` | только визуал существующих валют; новых валют не вводить |

## Что на референсах уже согласуется с каноном (не примеры)

Карточки улучшений с редкостью и Выбрать/Пропустить (REF-011) соответствуют [CHOICE-VIEWMODEL-001](choice-viewmodel-001.md) и [DRAFT-CONTRACT-002](draft-contract-002.md); 4 класса имеют листы персонажей; у 3 из 13 обычных врагов есть листы (Мертвец Инь, Кровавый волк, Осквернённый культиватор).
