# SAVE-CONTRACT-001 — версии забега, контроль состояния, checkpoint и replay

- **ID:** SAVE-CONTRACT-001
- **Дата:** 2026-11-12
- **Статус:** DESIGN PROPOSAL / STATIC REFERENCE ONLY. Не утверждённый формат релизных сохранений и не Godot runtime.
- **Scope:** архитектурные контракты и воспроизводимые статические проверки без создания игры, сцен, ассетов, cloud-save, неткода или нового пользовательского интерфейса.
- **Зависимости:** [GAME-ARCH-00](game-arch-00-run-orchestration.md), [GAME-ARCH-01](game-arch-01-xp-pickups.md), [GAME-UX-001](game-ux-001-oct-2026.md), [ARCH-01 RunBuild](build-skill-type-contract.md), [FOUNDATION-2026](foundation-research-2026.md), [v7 economy](economy-and-talent-sinks.md), [historical replay s13](../core/s13.md).
- **Проверяемый пример:** [readme / fixture](../../proposals/save-contract-001/README.md), [reference checker](../../../scripts/validate_save_contract_proposal.py), [negative tests](../../../tests/test_save_contract_proposal.py).
- **Правило:** предложение не изменяет нормативные выплаты за забег, не утверждает корректность реального Godot replay и не определяет автоматически правила смерти в тик выбора.

## 1. Почему это важно уже сейчас

У нас отдельно проверены:
- логические XP pickup и источники начисления;
- пять ожидающих выборов в одном тике;
- смена ранга навыка, после которой доступна эволюция;
- версии правил и наличие нескольких потоков RNG как архитектурное требование.

Однако до этого шага отсутствовала **проверяемая общая граница** «очередь наград + билд + уже оплаченные источники + журнал + точные правила». Если сериализовать только \`level, XP, seed\`, то загрузка во время пяти незавершённых решений может повторно выдать опыт, утратить выбор или применить новый рецепт к прежнему билду.

**Приоритет:** восстановление не должно приводить к появлению или исчезновению игровых решений. Игрок возвращается **в ту же стратегическую точку**, с теми же законно заработанными возможностями.

## 2. Слои будущего формата — не путать

| Слой | Отвечает за | Не должен делать |
|---|---|---|
| \`RunRulesSnapshot\` | фиксировать class/stage/mode, версии каталогов, правила драфта, XP, RNG и схемы | хранить текущую позицию/текущий XP как правила |
| \`RunStateSnapshot\` | состояние мира на tick barrier, билд, XP, source claims, очередь решений, cooldown/status/AI в будущем | самостоятельно выдавать награды и вычислять несуществующие события |
| \`ReceiptJournal\` | уже признанные события, выборы и источник награды в каноническом порядке | принимать частичные UI-клики за честный reward receipt |
| \`RNGStateSnapshot\` | именованные потоки, точную версию алгоритма, state/seed, draw position | предполагать, что просто один seed даёт межверсионную идентичность |
| \`CheckpointSeal\` | обнаружить случайное повреждение сохранения | изображать криптографическую защиту от сознательного редактирования игроком |
| \`MetaSettlementJournal\` | один раз начислить Духовные камни/Печати Дао по \`run_uid/reward_event_id\` | повторно платить за просмотр экрана результата |

Логически это разные структуры, даже если на диске они одна транзакционная запись. Никакой облачной инфраструктуры и распределённого event sourcing на данном этапе не требуется.

## 3. RunRulesHash, digest и семантика версий

Правило: при любой загрузке проверять совместимость **до** восстановления состояния.

Будущий \`RunRulesHash\` включает:
- идентификаторы и semantic versions классов, StageDef, режима/сложности и content bundles;
- правила XP, получения новых навыков, стоимости/лимитов только конкретного режима и источников наград;
- версию \`EventOrderPolicy\` и \`TickPolicy\`;
- \`RngPolicyVersion\`: **алгоритм**, разделение потоков, выбор distribution/weighted draft semantics;
- систему эволюций, статусов, модификаторов, прорывов и транзакций;
- выбор **Bank Levels/Immediate**, потому что он влияет на момент применения награды и последовательность симуляции.

Настройка исключительно декоративного масштаба интерфейса/фонового звука не должна ломать gameplay \`RulesHash\`. Следует отдельно версионировать \`UserPreferencesSchema\`.

### Важная техническая оговорка: JSON-каноникализация

Эталонная модель использует \`SHA-256(json.dumps(sort_keys=True, ensure_ascii=False, separators=...))\`. Это **Python-only reference digest**, не совместимый по определению с любой реализацией JSON-сериализации на GDScript/Windows/других языках при наличии floats/Unicode ordering/large integers.

Для release/межъязыкового hash contract сначала утвердить один формат, например [RFC 8785 JCS](https://www.rfc-editor.org/rfc/rfc8785.html) и протестировать одинаковые golden vectors во всех целевых языках. JCS предъявляет требования к I-JSON и сериализации чисел (особенно вблизи >2^53); игровые целочисленные \`u64\` UID/счётчики при межъязыковом JSON обмене разумно хранить как **десятичные строки** или в строго типизированном бинарном формате.

**Не переносить Reference Digest в Godot без portability proof.**

## 4. Названные RNG-потоки и воспроизводимость

Пример содержит раздельные \`enemy\`, \`drops\`, \`offers\`, \`stage\`, каждую с declared algorithm version, seed и cursor. Seed/cursor представлен десятичной строкой, валидируются формат и диапазон.

В статическом примере нет реальных случайных выборок; **все cursor остаются 0**. Любой искусственно продвинутый cursor отвергается, потому что нет соответствующей авторизованной операции. В будущей игре journal/snapshot обязан хранить либо полное RNG state после реально совершённых draw, либо достаточный проверяемый журнал для восстановления. Текущий тест не доказывает алгоритм генерации случайных чисел.

Godot 4.7 документирует текущий PCG32 в \`RandomNumberGenerator\`, но предупреждает, что базовый алгоритм — деталь реализации. Также \`state\` необходимо сохранять и восстанавливать только из подлинного состояния генератора, а не устанавливать произвольное число. [Godot RNG 4.7](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html).

### Рекомендуемое правило

Если гарантированно воспроизводимые забеги между версиями Godot станут требованием, либо (а) **закрепить собственный версионированный PRNG** с golden vectors, либо (б) сохранять достаточное внутреннее RNG state и объявить ограниченный интервал совместимости. Это отдельное решение, не автоматический переход на кастомную криптографию.

## 5. Когда разрешён checkpoint

В будущем snapshot создаётся только в согласованной фазе \`tick barrier\`, **после полного завершения атомарного пакета событий** и **между**, а не посередине \`BuildTransaction\`.

Особый случай — \`CHOICE_PAUSED\`:
- earned levels могут быть ещё не распределены;
- ритуал/прорыв могут ожидать своей очереди;
- будущие \`DraftService\` offer IDs/reroll RNG/bans и UI Focus требуют отдельного контракта;
- \`ChoiceCoordinator\` должен сохранять receipt UIDs, порядок и build revision;
- \`run_state\` и \`build_state\` должны описывать **один и тот же коммит**.

Сохранение во время визуальной анимации клика не означает, что выбор уже был подтверждён: авторитетна транзакция, а не положение курсора.

В bank-levels режиме допустим snapshot с pending обычными уровнями **без активной паузы**; этот вариант требует отдельного полного golden witness, хотя существующий GAME-UX-001 уже проверяет его состояния.

## 6. Проверяемая цепочка эталонного восстановления

Дизайн-фикстура использует существующие синтетические GAME-ARCH-00/01 и BUILD-SKILL-001 каталоги, не вводит новых игровых техник:

\`\`\`text
tick 100: collected 40 XP, 3 level choices + ritual + breakthrough
RunBuild revision = 6
    ↓ skill rank-up: sword IV → V
SAVE checkpoint: revision 7, 4 choices remain, sim still paused
    ↓ serialize JSON → parse → verify header, checksum, rules/content IDs
    ↓ independent replay from trusted receipts and choice actions
    ↓ restore EXACT same pending choices and existing build
    ↓ Power Echo +1
    ↓ Power Echo +1
    ↓ ritual: evolve spirit sword → thousand swords
RunBuild revision 10; 1 breakthrough choice remains; XP bank = 3
    ↳ Compare result to uninterrupted replay over same authorized journal.
\`\`\`

Две взаимосвязанные проверки:
1. snapshot с валидным \`SHA-256\` **не должен проходить**, если его \`run_state\`, XP, build, source claims, queue или history не совпадают с восстановленной моделью;
2. корректная загрузка и последовательное принятие оставшихся решений должна дать тот же state digest и \`build_revision\`, что и replay без checkpoint.

Это не полноценный боевой replay: модель восстанавливает **XP/reward/choice/build projection**, не position/physics/enemy AI/real RNG. Текущий journal содержит все события эталонного тика, поэтому повторно проигрывается целиком; будущему движку понадобятся checkpoint + bounded tail и сборка world-state snapshots.

## 7. Источники XP, журнал и защита от дублирования

Сохранять **и** \`processed_receipt_uid→digest\`, **и** \`claimed_xp_source_uids\`, а также привязанные к ним authoritative source values/ledger. Это разные идентичности:
- событие сообщает об оплате;
- source UID показывает, **что именно** оплачено;
- source-value manifest подтверждает **сколько** можно оплатить;
- \`run_uid\` отделяет этот забег от другого;
- метанаграда после финала имеет отдельный \`reward_event_id\` и транзакционный журнал.

Статический валидатор восстанавливает run из доверенной синтетической входной модели, проверяет receipt journal, source manifest и выборы. Сам \`checksum\` — от случайной порчи, не против злонамеренного игрока, который может сам изменить файл и пересчитать SHA. Для offline single-player криптографическая защита с секретом на устройстве обычно не нужна.

**Не вводить скрытый сервер проверки и онлайн-требования ради сейвов.**

## 8. Миграции: fail closed при изменении смысла

Различать:
- **Форматная миграция:** поле \`captured_tick\` заменяется на \`tick\`; все остальные семантические данные сохранены. В эталоне имеется *синтетическая* v0→v1 миграция заголовка с проверкой старого checksum и replay после перехода.
- **Семантическая миграция:** изменились порядок фаз, распределение RNG, каталоги рецептов, XP threshold или статусная механика; требуется отдельно определённая процедура, золотые кейсы и, возможно, отказ от resume для старого забега.

Переход с неизвестной версии или отсутствие обязательных данных нельзя лечить угадыванием: например, **запрещено пересоздавать отсутствующее RNG state из исходного seed** и притворяться, что все прежние случайные выборы воспроизведутся.

Сохранение, созданное на старом контенте, не должно молча загружаться с новым \`RunRulesHash\`. Можно предложить restart с новой версией, сохранить для чтения/диагностики или предоставить протестированный migration path — это будущее продуктовое решение.

## 9. Атомарная запись файлов и аварийное завершение — позже

Когда runtime станет разрешён, запись локального файла должна использовать принцип:
\`serialize→validate locally→write temporary file→flush/sync according to platform capability→atomic replace or safe two-slot journal→read-back validation\`.
Предположение, что \`rename\` всегда атомарен на всех путях и ФС, недопустимо без платформенной проверки. Нужно гарантировать, что после внезапного прекращения процесса доступен хотя бы один предыдущий корректный checkpoint.

Отдельно проверить repeated finish/reopen vs payment exactly-once из принятого [v7 economy](economy-and-talent-sinks.md). Текущий checker **не пишет файл на диск** и не симулирует crash на середине реальной операции.

## 10. Ошибки и негативные тесты

| Дефект | Контрактный результат |
|---|---|
| JSON duplicate keys, NaN или нераспознанная версия | reject |
| Неизвестный extra field в header | reject/migrate только по известной схеме |
| Изменён XP после сохранения и обновлён checksum | reject по независимому replay |
| Изменён build / pending queue и обновлён checksum | reject по replay |
| Удалён source claim или подменён receipt source value | reject |
| Источник XP/receipt journal отличается от доверенного синтетического fixture | reject |
| Изменился content digest / XP threshold / skill definition | reject несовместимый snapshot |
| Изменился choice mode, RNG algorithm или sequence policy | reject при иной семантике |
| Изменён RNG seed или необъяснённый cursor | reject |
| Повторная, устаревшая или недопустимая карточка | reject без расхода награды |
| Unknown v99 или v0 без обязательного \`captured_tick\` | reject |
| Известная v0→v1 миграция заголовка | преобразовать и replay-check |

### Чего эти тесты **не** доказывают

- Точный replay между процессорами или версиями Godot.
- Работоспособность автосохранения при падении приложения, fsync, atomic rename.
- Восстановление геометрии врагов, cooldown/DoT/timers, in-flight projectiles, GPU эффектов.
- Реальное применение Rune/Powers/Reroll/Banish/Lock, replay RNG draw или множество сохранений на других языках.
- Реальный баланс/удобство игрока и отсутствие читов.

**CHOICE-VIEWMODEL-001 integration note:** [проектная модель драфта](choice-viewmodel-001.md) добавляет source-grounded карточки, ручные Reroll/Banish/Lock/Skip, separate DraftCheckpointOverlay и safe held-input. Это ещё **не** внутренняя schema migration SaveEnvelope, не единый offers RNG cursor и не релизный DraftService.

**DRAFT-CONTRACT-002 linkage:** [проверяемый run-scoped draft](draft-contract-002.md) теперь имеет собственный offers RNG counter и persistent bans, но **ещё не** обновляет строгую схему этого SAVE-CONTRACT. Требуется CHOICE-SAVE-002 с единым authoritative cursor и migration.

## 11. Следующий проектный шаг после этого среза

- \`CHOICE-VIEWMODEL-001\`: формальные карточки и UX-ввод; persisted offer/RNG hand/cursor, focus policy, reroll/banish/lock.
- \`SAVE-CONTRACT-002\`: если появится необходимость, replay с world-state и tail journal, независимый verifier, crash consistency.
- \`ARCH-02\`: граф достижимости N→M recipe и provenance.
- \`GAME-ARCH-02\`: stage topology, encounters, bosses, POI.
- Godot P0-00 и работа над игрой остаются **отложены** по действующей инструкции.

**Итог:** мы закладываем архитектуру, позволяющую в будущем безопасно продолжать забег с очень сложным билдом, а не ограничиваем число навыков ради удобства сохранений.
