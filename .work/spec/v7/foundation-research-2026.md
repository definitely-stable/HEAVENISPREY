# FOUNDATION-2026 — научно-обоснованный архитектурный фундамент HEAVEN IS PREY

**Дата актуализации:** 2026-11-11  
**Статус:** DESIGN PROPOSAL; НЕ принятое игровое правило, НЕ реализованная игра  
**Объект:** одиночная xianxia survivor-like с автоатакой/автонаведением, активным перемещением и уклонением, сложной культивацией, сильными сборками и 2.5D-представлением на Godot 4.7.2  
**Scope:** только архитектура, документация, независимые статические модели/тесты; никакого \`game/\`, сцен, визуальных ассетов, нативного движка, телеметрии пользователей, симуляции реального боя  
**Привязка:** [GAME-UX-001](game-ux-001-oct-2026.md), [GAME-ARCH-00](game-arch-00-run-orchestration.md), [GAME-ARCH-01](game-arch-01-xp-pickups.md), [ARCH-01](build-skill-type-contract.md), [FLEXIBILITY-FIRST](flexibility-first-build-policies.md), [в5 event budget](../v5/v5_budget.md), [roadmap](../../roadmap/NEXT_SLICES.md)  
**Машинно проверяемый реестр:** [15 foundation gates](../../proposals/foundation-2026/gates.json); [validator](../../../scripts/validate_foundation_gates.py); [metamorphic tests](../../../tests/test_foundation_2026.py). Существующие статические design tests остаются независимыми.

## 1. Главное различие: foundation / capability / policy / measured result

Для одиночного 2.5D roguelite ошибка — до первого прототипа строить «передовой ECS, AI-директор, RL-балансер и распределённый event store». **Действительно современная архитектура начинается с формализованных границ** и возможности *сменить* алгоритм, когда измерение это оправдает.

1. **Foundation invariant — обязателен:** определённая семантика времени и событий; уникальность источников наград; отсутствие потери XP; корректные ссылки; конечность реакций и атомарные решения; воспроизводимые журналы.
2. **Capability — представима системой, не обязательно включена в каждом режиме:** бесконечные по заранее фиксированному числу ранги, дополнительные слоты, N→M Union, конечные циклы статусов, повторные экземпляры навыка, опциональный банк уровней.
3. **Mode/product policy — изменяется без переписывания engine:** сколько слотов/карточек, какие трансформации и награды доступны, как часто награда заставляет остановиться, какие модификаторы сложности включаются.
4. **Empirical conclusion — только после реальных измерений:** реальный FPS, удержание, оптимальное число врагов, насколько пользователю приятна автоатака, эффективность 30 Hz vs 60 Hz, разнообразие жизнеспособных билдов.

**Нет правила:** «высокая нагрузка => удалить попадания». Валидация может сигнализировать \`PROFILE_EXCEEDED\`, но изменение игровой семантики требует явной policy/контентного решения.

## 2. Карта применимости 2026

| ID | Приоритет | Заложить сегодня | Не внедрять сейчас |
|---|---|---|---|
| FND-01 | P0 | tick, command log, стабильный порядок, независимые RNG и digest | rollback-netcode |
| FND-02 | P0 | версия JSON/типов, schema + semantic checker, миграция, RulesHash | универсальный язык программирования в контенте |
| FND-03 | P0 | происхождение статусов/эффектов, finite bound, snapshot | hardcoded число проков/скиллов |
| FND-04 | P0 | XP source receipt, выбор и пауза, source-value проверка | поведенческая логика в UI |
| FND-05 | P0 | metamorphic seeded tests, negative/mutation controls | ML вместо тестов |
| FND-06 | P0 | граф достижимости эволюций, typed grants/consumes | конечный каталог рецептов сегодня |
| FND-09 | P0 | ViewModel, focus, cues, безопасная пауза | принудительный авто-выбор билдов |
| FND-07/08 | P1 | точки измерений и условный гибридный data layout | тотальный ECS/многопоточность/переписывание Godot |
| FND-10/14 | P1 | протокол persona/scenario playtests и UX метрик | утверждение «всем нравится» из ботов |
| FND-11 | P1 | agent brief, fixture, negative control, независимый CI | гонку агентов без ownership и diff review |
| FND-13 | P1 | идентичность снимка сохранения и семантика миграций | cloud backend / event-sourcing platform |
| FND-12/15 | P2 | исследовательские hooks | RL PCG, нативный движок, онлайновый co-op |

Следовать зависимостям в реестре: например, не разрабатывать RL-балансер до симуляции, воспроизводимых сценариев, измерений и человеческого тестирования.

## 3. FND-01 — одна каноническая модель времени и воспроизводимости

Уже есть \`GAME-ARCH-00\` и исторический \`s04\`: simulation tick и очередь событий. Необходимо до runtime утвердить:

- \`PlayerCommand(tick, command_seq, player_uid, movement, dodge, optional_ui_action)\` — команда, не прямой доступ кнопки к сцене;
- \`RunRulesSnapshot\` содержит catalog/schema versions, mode policy, stage, class, modifiers, RNG algorithm/version, tick policy;
- порядок: \`input→movement→enemy intentions→cast/target→hit→status→death→drops→XP→reward arbitration→snapshot\` — **предложение**, до утверждения сверить с уже принятым [ADR-002](../../decisions/ADR-002-combat.md);
- отдельные именованные потоки RNG для enemy, drops, offers, stage, visual; UI/представление не продвигают gameplay RNG;
- \`EntityHandle = (index, generation)\`, event UID + source UID + root UID; запрет повторного использования без generation;
- \`ReplayTrace\`: seed, input commands, deterministic event decisions/choice receipts, digests at checkpoints and first diverging step;
- при нескольких платформах сначала проверять **семантическую** эквивалентность и канонические целочисленные события; exact floating-point bit identity между разными CPU/OS **не обещать**, пока не выбран fixed-point/quantization/floating-point contract.

**Почему:** Godot официально разделяет фиксированный physics tick и частоту rendering frames; интерполяция сглаживает визуальное движение, не заменяя логику. Фиксированный тик уменьшает зависимость поведения от FPS, но сам по себе **не доказывает** глобальную детерминированность из-за неопределённого порядка и вычислений с плавающей точкой. [Godot physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).

Не разрабатывать rollback или lockstep-сетевой слой для одиночной игры. Версия симуляции и golden replay дают большую часть нужной ценности значительно дешевле.

## 4. FND-02 — контентные контракты, версии и миграции

Использовать **две разные проверки**, не смешивая их:
- JSON Schema Draft 2020-12: типы, обязательные поля, \`additionalProperties/unevaluatedProperties\`, \`oneOf\`, допустимые диапазоны, версия документа;
- семантический валидатор: уникальные IDs, ссылки на классы и статусы, совместимость слотов, циклы и достижимость рецептов, математические границы, source ownership.

Schema не может доказать, что Union достижим или что XP со всех источников начислен однократно; это отдельные проверки. См. [официальную спецификацию JSON Schema](https://json-schema.org/draft/2020-12).

**Предлагаемые стадии контентного pipeline:**
\`author JSON→schema validate→cross-ref validate→graph/check invariants→positive/negative fixtures→impact graph→build catalog digest→human approval→release\`.

Единый ID/версия для SkillDef, EffectDef, StatusDef, RewardDef, ClassIntrinsicDef, StagePOIDef и Recipes. Не создавать второй ручной каталог в UI; ChoiceViewModel и справочник должны читать их через одну границу.

**Сохранения:** \`SaveEnvelope\` должен хранить ID версии схемы, семантическую версию контента или RulesHash, source ledger claims, очередь незавершённых выборов, RNG streams и текущий build revision. При изменении смысла рецепта нужен migration или read-only fallback; не применять новый рецепт к старому сейву незаметно.

Нельзя объявлять JSON Schema более свежей, чем Draft 2020-12, без верификации стандарта.

## 5. FND-03 — граф эффектов и происхождение (самый дорогой будущий баг)

В сочетании sword+thunder+DoT+Multicast+Summon+Union урон можно посчитать дважды либо потерять после трансформации. Нужен \`EffectProvenance\`:
\`root_cast_uid / event_uid / parent_uid / owner_handle / skill_instance_uid / run_build_revision / snapshot_policy / modifier_stages / hit_generation / target_handle\`.

**Семантика имеет приоритет:** DoT snapshot или dynamic решается на уровне конкретного эффекта; суммоны наследуют определённый набор модификаторов, а не все автоматически; урон из Chain имеет авторизованный source stage; in-flight attacks продолжают существовать с прежним snapshot, если только явно не написано обратное.

**Graph safety:** static conservative bound для ациклических веток и явное уменьшающееся поколение/ресурс для разрешённых циклов. Никакого автоматического \`if events>128: drop()\`. Превышение workload profile = проблема пригодности для профиля, а не неверная математическая механика.

Перед N→M Union нужен тест столкновения двух рецептов, которые пытаются расходовать один skill instance; atomic commit и rollback.

## 6. FND-04/05 — model-based, property-based и metamorphic testing

Ранее тесты проверяли выборочные happy paths: «40 XP → три уровня → одна эволюция». Это полезно, но недостаточно для сотен комбинаций.

**Уже применено в новом срезе:** seeded metamorphic checks для (a) перестановки событий без изменения результата, (b) схлопывания совместимых XP и сохранения collectible source IDs/value при разных позициях/радиусах, (c) запрета forged amount и (d) негативных изменений источника, ссылки, зависимостей, версии. Это выполняется Python stdlib на GitHub-hosted CI.

**Рекомендуемый эволюционный путь:**
1. сейчас — deterministic pseudo-random property fixtures и небольшая независимая референтная модель;
2. после стабилизации схем — \`Hypothesis\` stateful models + shrinking найденных counterexamples (по необходимости, в CI с зафиксированной версией; не обязателен);
3. перед игровым выпуском — differential replay \`reference model vs Godot\`, mutation tests, platform consistency, нагрузочные сценарии;
4. позже — player-policy bots с независимыми reward heuristics + человеческий playtest.

[Hypothesis stateful docs](https://hypothesis.readthedocs.io/en/latest/stateful.html) объясняет генерацию **последовательностей действий**, а не случайного несвязанного JSON. Это важно: многие ошибки RewardLedger проявляются только как \`merge→collect→save→replay→collect again\`.

**Двусторонняя проверка для AI-агентов:** эталонная fixture должна проходить, а заведомо некорректная — проваливаться. Автоматическая «зелень» без негативного контроля недостаточна. Актуальный сентябрьский [SWE-bench Pro V2](https://labs.scale.com/leaderboard/swe_bench_pro_public_v2?tab=full) отдельно отмечает валидацию эталонного и пустого патчей и очистку некорректных тестовых задач. Переносимый принцип — **независимое свидетельство качества, а не просто число тестов**. Не переносить напрямую их оценки на наш репозиторий.

## 7. FND-06 — проверка достижимости сложных билдов

Свобода билдов означает не отсутствие контракта, а отсутствие искусственных глобальных ограничений. Система должна описывать:
- 1/2/много активных навыков, особые дополнительные слоты, независимые копии \`instance_uid\`;
- authored ranks + post-max growth, включая сильные одиночные техники;
- альтернативные эволюции, N→M Union и Gift, нерасходуемые/расходуемые катализаторы;
- различие между доступностью рецепта в текущем состоянии и **достижимостью через реальный последовательный драфт**;
- одновременные награды, не допускающие двойного расходования одного компонента.

Проверка: bounded search из \`RunLoadout\` по допустимым \`LevelUp/Reward/Transform\`, с witness path и объяснением \`unreachable because missing source/slot/gate\`. При росте сложности — SAT/SMT как опция **после измерения**, не сразу. Искать не только «средний DPS», а несколько жизнеспособных игровых фантазий (focused / arsenal / reaction). Игра не обязана уравнивать каждую их характеристику.

## 8. FND-07/08 — производительность: гибридный Godot вместо модного ECS

**Рекомендую для будущего runtime:**
- авторские сцены/Nodes: UI, 2–4 класса, большие уникальные боссы, POI, визуальные особые объекты;
- плоские logical stores/packed arrays/handles: плотные обычные враги, снаряды, hits, status instances, XP drops;
- spatial grid/CellIndex для поиска целей/подбора вместо многократного brute-force \`O(N×M)\` по всем врагам и атакам;
- rendering bridge читает snapshots и выбирает визуальные представления; \`MultiMesh\` или прямой RenderingServer **только для типов объектов, где измерено много одинаковых draw calls**;
- пул объектов — для визуальной реализации и ограниченной логической аллокации, **не** источник идентичности reward/source UID.

**Почему:** Godot официально предупреждает о накладных расходах множества Node и полезности Servers, но также указывает на цену обратных синхронных вызовов Server. MultiMesh эффективно рисует много одинаковых объектов одним draw call, но **не делает индивидуальный culling** внутри одного MultiMesh. Для длинной арены разделять на spatial tiles / несколько MultiMesh batches, если измерение это оправдывает. [Using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html), [MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

**Запрещено утверждать без профиля:** «полностью ECS быстрее», «60 Hz обязательно», «все враги должны быть без Node», «один MultiMesh решит проблему». Фиксированный tick 60 Hz — разумная исходная гипотеза, но её проверяют на реальных CPU и числах врагов.

**Отдельные измерения, не один FPS:** \`sim_tick_ms p50/p95/p99\`, \`render_CPU_ms\`, \`GPU_ms\`, \`alloc_bytes/tick\`, \`active_enemies\`, \`logical_hits/tick\`, \`status_instances\`, \`pickup_queries\`, \`draw_calls\`, \`VFX/SFX\`. Бюджеты задаются **для профиля платформы и качества** после нагрузочного baseline.

## 9. FND-09/14 — UX, доступность и доказательство пользовательского качества

Исследование Caroux/Pujol 2026 анализирует факторы иммерсии и методы измерения. Это **не** доказательство оптимального количества карточек или XP. Использовать его как обоснование требовать человеческое измерение агентности/читаемости, но не подменять конкретный playtest. [2026 systematic review/meta-analysis](https://www.tandfonline.com/doi/full/10.1080/1463922X.2026.2706451).

**Для нас:**
- \`ChoiceViewModel\` с точным effect delta, catalyst readiness, rarity, source, consumes/grants и rank/current values; нет duplicated formulas in UI.
- Bank Levels — выбор *когда открыть*, не автоматический подбор *какой бонус выбрать*. Auto-pick отдельный opt-in. Нельзя отбирать заработанные выборы, даже если их 100.
- safe input focus: свежий key-down после открытия; накапливаемые кнопки dodge/confirm не вызывают случайную карточку.
- \`DangerOverlay\` изолирован от VFX игрока и сохраняет читаемые телеграфы, размеры hitbox и доступный контраст.
- звук предупреждения не заглушает/не теряется среди сотен routine hit clips, возможно разные визуальные и аудиальные категории.
- эффекты меча, молнии, огня различаются **силуэтом/паттерном**, а не только цветом; настройки UI scale, remap, reduced flashing, controller focus.
- при смерти — разбор главных источников полученного урона и конкретная следующая цель; не просто общий DPS.

[IGDA Game Accessibility SIG](https://igda-gasig.org/get-involved/sig-initiatives/resources-for-game-developers/sig-guidelines/) и [Microsoft gaming accessibility](https://learn.microsoft.com/en-us/windows/uwp/gaming/accessibility-for-games) требуют много-канального обозначения важных сигналов. Игровая доступность — проектный UX контракт до производства эффектов, не «фильтр цветов в конце».

**Критика предлагаемой аналитики:** автоматические клики и когортная аналитика без согласия игрока не нужны; telemetry в раннем пилоте локальная, опциональная, exportable. Метрики: пауз/мин, время выбора, ошибочные отмены, неполученные XP, телеграфы/смерти после выхода из меню, coverage билдов, provenance статусов. Исследовать комфорт по разным группам игроков, а не только своим ботом.

## 10. FND-10/12 — AI/PCG/RL для балансировки, но поэтапно

Обзор автоматизированного game testing 2026 рассматривает RL, imitation, model-based и гибридные подходы и отдельно отмечает ограничения обобщения, затрат и объяснимости: [ICAC 2026 survey](https://ieeexplore.ieee.org/abstract/document/11712397).

Работа Florian Rupp для AAAI AIIDE 2025 рассматривает game economy as graph и level generation/search/RL, **главным образом для конкурентных окружений**; перенос на наш одиночный survivor-like — гипотеза, а не опубликованное подтверждение качества. [AIIDE 2025](https://ojs.aaai.org/index.php/AIIDE/article/view/36856).

Препринт Jiang и соавторов (апрель, пересмотр 20 октября 2026) рассматривает tool-using LLM, который редактирует PCG-окружения и проверяет ограничения. Он интересен для **будущего авторского конвейера**, но не доказывает лучшего баланса/ретеншена именно HEAVEN IS PREY. [Agentic PCG 2026](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6499021).

**Стратегия:**
1. Сначала ограниченное количество вручную спроектированных волн/боссов/арен.
2. Затем headless deterministic scenario runner и набор независимых persona policies: focused sword, AoE thunder, low mobility, high mobility, status chain, no-reroll, skill-starved.
3. Собирать распределения по нескольким осям: живучесть, темп XP, P50/P95 time to evolve, single-target, horde coverage, hazard compliance, события/тик.
4. Поиск доминирующих/невозможных билдов и авторских конфигураций; граф достижимости рецептов и совместимость с reward schedule.
5. **Только потом** search-based optimization/PCG/RL как генератор **кандидатов**, а не автопубликация баланса. Human evaluation — обязательный независимый канал.

Отказаться от преждевременного нейросетевого «AI Director»: детерминированная authored timeline с прозрачными модификаторами даёт лучший контроль и сравнимость на P0.

## 11. FND-11 — ускорение разработки с AI-агентами без ухудшения качества

Уже есть \`AGENTS.md\`, [START_HERE](../../guides/START_HERE.md), task routing, traceability и CI. Закладываем **контракт рабочего среза**:
- \`problem/behavior→authoritative source links→IDs touched→invariant→positive witness→negative witness→CI→independent diff review→merge\`;
- агенты загружают только релевантный контекст и соседние контракты, а не все исторические 63 раздела;
- \`main\` — источник истины, draft PR после зелёного CI не оставляют открытым без блокера;
- тест должен падать при явно некорректных изменениях, а не просто выполнять счастливую фикстуру; отдельные golden checks по семантике;
- агент не может объявить \`ACCEPTED\` само описание новой гипотезы. Смена нормативного дизайна требует записи решения.

Исследование Sourcegraph CodeScaleBench (март 2026) сообщает о пользе целевого поиска контекста на своей тестовой выборке. Это индустриальный отчёт с ограничениями переносимости, **не** обещание 30% экономии или +3.5pp качества у нас. [CodeScaleBench](https://github.com/sourcegraph/CodeScaleBench/blob/public/docs/technical_reports/TECHNICAL_REPORT.md).

Современные coding-agent benchmarks (Coding Agent Index 2.0, октябрь 2026) оценивают реальные PR/терминальные задачи и описывают reward-hacking. Для нашего CI важнее независимая проверка корректности эффекта, чем выбор самой высокой позиции в таблице моделей. [Coding Agent Index](https://artificialanalysis.ai/methodology/coding-agents-benchmarking).

## 12. FND-13 — сохранения, версии и протокол восстановления

**Implementation note (architecture-only):** [SAVE-CONTRACT-001](save-contract-001.md) и [reference replay fixtures](../../proposals/save-contract-001/README.md) теперь проверяют JSON checkpoint mid-choice, строгий RulesHash/content digest, source claims, explicit RNG stream policy, roundtrip, fail-closed v0 header migration и independent deterministic replay. Не заявляется реальный Godot RNG/save runtime.

**Нужно спроектировать сразу:** \`RunSnapshotHeader {schema_version, content_digest, rules_hash, rng_algorithm_version, tick_policy, run_uid}\`, \`GameState\`, \`EventLedger checkpoint\`, \`ClaimedSources\`, \`ChoiceQueue\`, \`BuildRevision\`, \`MetaSettlementPending\`.

Изменение UI-презентации, которое не меняет игру, возможно вне \`rules_hash\`. Изменение вероятности драфта, шага RNG, версии рецепта, порядка фаз или количества реальных наград обязательно вызывает новую версию семантики.

**Failure fixtures:** закрытие меню до подтверждения; восстановление пяти уровней; смерть с одновременно готовым ритуалом; повторная загрузка профиля с уже оплаченной метанаградой; попытка использовать старый content ID; обновление контента после создания сейва. Сейчас всё перечисленное — **будущие тестовые сценарии**, не реализованное сохранение.

Не создавать облачный сервер, netcode, полноценную distributed event-sourcing платформу ради одиночной игры. Простая checkpointed state + append-only receipt trace в локальном процессе достаточна для проекта, если выполнены инварианты.

## 13. Решения, которые могут оказаться неправильными при преждевременном внедрении

| Модная технология | Почему риск сейчас выше выгоды | Условие пересмотра |
|---|---|---|
| Полный ECS-фреймворк | Сложнее CI/инструменты Godot/авторство контента | Профиль доказал цену Node/хранения; hybrid stores не хватает |
| GPU compute для логики попаданий | Сложная синхронизация, переносимость и воспроизводимость | Есть изолированный измеренный hotspot и parity tests |
| GDExtension/Rust/C++ немедленно | Усложняет Windows/Linux сборку и отладку агентами | Подтверждённый CPU hotspot и ясная граница нативного API |
| Автоматическая RL-балансировка | Оптимизация proxy-DPS может разрушить веселье | Сценарные боты + человеческая калибровка |
| Полный процедурный мир | Сложно обеспечить POI, пути к XP, честность боссов | Авторские уровни проверены и есть topology validator |
| Runtime plugin system для любого скрипта JSON | Произвольная логика ломает реплеи и safety | Требуется повторно используемый named extension handler |
| Кооператив и rollback | Меняет идентичность ownership, event ordering и AI | Отдельное продуктовое решение и технический прототип |
| 100% автоматический выбор улучшений | Ломает agency и может давать несовместимые билды | Опциональная пользовательская policy, ground-truth eligibility |

Важно: **отложить** не значит исключить из будущего. Каталог foundation gates имеет \`deferred/research_after_playtest\` и зависимости, чтобы к этой идее можно было вернуться без забывания.

## 14. План внедрения с ограниченным scope

**Slice FOUNDATION-2026 (в этом PR):**
- архитектурная матрица 15 gates и 15 ссылок; зависимости, приоритет, применимость, запреты;
- stdlib validator: каждая заявка привязана к существующим документам, источникам, не имеет неявно новых claims/runtime;
- seeded metamorphic tests для **уже существующих эталонных моделей**: equivalence XP collection по выбранной позиции/радиусу, reorder batch, forged amount;
- negative controls: источник, документ, версия, cycle, deferred-to-now change — должны падать;
- CI Ubuntu/Windows, только документация/тесты, не создана игра.

**Следующий P0 (разные PR):**
1. \`SAVE-CONTRACT-001\` header/version/checkpoint/choice state + precise replay trace.
2. \`CHOICE-VIEWMODEL-001\` карточки/отклик + formal focus, reroll/banish/lock.
3. \`ARCH-02\` recipe reachability with slot/source/time/gate constraints.
4. \`GAME-ARCH-02\` spatial topology, waves/bosses, hazard and reward placement.

**После разрешения runtime:** P0-00 Godot bootstrap/CI; P0-01 deterministic combat/targeting; синтетические golden sims; потом реальный пилот и человеческий UX. Не менять этот порядок скрытым PR.

## 15. Источники, границы утверждений и критерий качества

Машинно читабельные source URLs и назначение зафиксированы в [gates.json](../../proposals/foundation-2026/gates.json). Различать:
- **official engineering docs/specs**: описывают возможности/компромиссы платформы, не доказывают FPS нашего проекта;
- **peer-reviewed papers / survey**: сообщают о выводах в указанной выборке, не являются индивидуальным playtest HEAVEN IS PREY;
- **preprint/industry benchmark**: полезный сигнал, с ограниченной внешней валидностью;
- **our own CI**: подтверждает только **названные архитектурные свойства** фикстур, а не удовольствие от игры, точный реальный баланс и скорость Godot.

### Приёмка FOUNDATION-2026

- [ ] 15 gates формально связаны с доказательствами и актуальными нормативными/проектными документами; no missing/duplicate/cyclic edges.
- [ ] Negative-control gates отвергают сознательно неверные ссылки, повреждённые поля, ложные утверждения runtime и циклические зависимости.
- [ ] Рандомизированные, но воспроизводимые тесты подтверждают сохранение collected XP/source при разрешённом схлопывании pickup-представлений.
- [ ] Перестановка пакета событий одного тика не меняет итоговый run state.
- [ ] Синтетический проверенный источник XP не может быть оплачен завышенной суммой.
- [ ] Windows-2022 и Ubuntu GitHub Actions проходят все тесты; репозиторий не пополняется Godot/gameplay runtime.
- [ ] DESIGN-PROPOSAL не объявляется автоматически утверждённым содержанием/балансом.
