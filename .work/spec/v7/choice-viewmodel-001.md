# CHOICE-VIEWMODEL-001 — драфт, объяснимость карточек и безопасный выбор

- **ID:** CHOICE-VIEWMODEL-001
- **Статус:** DESIGN PROPOSAL / STATIC ORACLE VERIFIED WHEN CI PASSES / NO GODOT GAME OR UI.
- **Дата:** 2026-11-12
- **Цель:** встроить понятный выбор улучшений в автоатакующий xianxia survivor-like, не ограничивая классы, билды, Union, Powers и количество уровней.
- **Границы:** [GAME-ARCH-00](game-arch-00-run-orchestration.md) (очередь и pause), [GAME-ARCH-01](game-arch-01-xp-pickups.md) (XP source), [GAME-UX-001](game-ux-001-oct-2026.md) (исследование UX на октябрь 2026), [ARCH-01](build-skill-type-contract.md) (RunBuild/eligible offers), [SAVE-CONTRACT-001](save-contract-001.md) (versioned checkpoint/replay), [FOUNDATION-2026](foundation-research-2026.md).
- **Доказательства:** [reference fixture](../../proposals/choice-viewmodel-001/reference_plan.json), [design-only oracle](../../../scripts/validate_choice_viewmodel_proposal.py), [negative tests](../../../tests/test_choice_viewmodel_proposal.py).
- **Важно:** эти правила пока не утверждены как баланс/релизные настройки. «3 карточки», «2 Reroll», «1 Lock» — числа/ограничения **из тестового сценария**, не предельные возможности будущей игры. В runtime пока не создана ни одна карточка.

## 1. Аудит исходного состояния

Уже существовали:
- \`ChoiceCoordinator\` — честная FIFO-очередь заработанных решений, различие \`IMMEDIATE/BANK_LEVELS\`, optimistic \`build_revision\`;
- \`ARCH-01\` — \`eligible_offers\`, проекция rank-up/acquisition/Power и отдельные эволюции;
- \`SAVE-CONTRACT-001\` — сериализуемый снимок уровня/билда, source claims и проверяемая историческая цепочка выбора;
- \`GAME-UX-001\` — требования к focus, reroll/banish/lock, происхождению карточки и визуальной читаемости.

**Пробел:** отсутствовала единая проверяемая граница \`заработанное решение → набор реально показанных карточек → вспомогательная операция → обоснованная карточка → подтверждённый выбор → изменение RunBuild\`. Не было модели отдельных квитанций Reroll/Banish/Lock, защита от повторной кнопки была только словами, а показанный UI мог бы утверждать то, что не поддерживает \`RunBuild\`.

Этот slice закрывает **узкий статический контракт**, а не создаёт игровой DraftService.

## 2. Четыре разных сущности и владельца

| Сущность | Кто владеет | Идентичность | Что не имеет права делать |
|---|---|---|---|
| \`EarnedChoice\` | Run/ChoiceCoordinator | \`run_uid + choice_uid + source_event_uid\` | UI не может создать или удалить награду по отображению |
| \`DraftHand\` | DraftService | \`choice_uid + build_revision + hand_revision + draw_cursor\` | не выдаёт эффект персонажу |
| \`ChoiceViewModel\` | Pure projection из каталога + RunBuild + DraftHand | \`choice_uid, offer_id, content digest, build revision\` | не решает допустимость в обход сервиса |
| \`BuildTransaction\` | authoritative build | \`choice_uid + expected_build_revision + interaction_uid\` | не исполняет одну квитанцию дважды |

Состояние экрана не является источником истины. Событие получения XP, карточка меню и применённая модификация — **три разных шага**. Между ними обязателен строгий порядок.

## 3. Схема DraftHand (предложение)

\`\`\`text
DraftSession:
  schema_version / rules_hash / content_digest
  run_uid, choice_uid, source_event_uid
  build_revision
  hand_revision                     revision every auxiliary operation
  hand: OfferId[]
  locked_offer: OfferId | null
  banned_offer_ids: OfferId[]       source-owned run-state, not UI local storage
  reroll_charges, banish_charges
  hand_size_policy_id
  draft_rng_policy_id, seed/state, draw_cursor
  action_receipts: InteractionUid → ActionDigest
  action_log: ordered DraftOperation[]
\`\`\`

Эталонный Python-объект содержит только минимальную проекцию без нормативного \`rules_hash/content_digest\` внутри draft. Подписка к \`SAVE-CONTRACT-001\` задаётся отдельным \`DraftCheckpointOverlay\`. Полная интеграция в релизное \`SaveEnvelope\` требует отдельного schema migration и принятого RNG policy.

### Источник карточек и распределение

Сначала \`DraftService\` вычисляет **все законные** \`OfferId\` по текущему RunBuild и policy. Потом исключает запреты, применяет логику доступности/события и только затем выбирает ограниченное число отображаемых карточек. \`hand\` содержит не произвольные ID из UI, а subset \`eligible_offers\`.

Изолированный тест использует **SHA-256(seed|choice_uid|counter) modulo sum(weights)** как воспроизводимый пример weighted-without-replacement. Это **не** одобрение RNG, его стабильности/равномерности/odds для реальной игры, не Godot PCG32, не production anti-brick и не player-fairness guarantee. Доработать и version-lock после утверждения требований, а не переносить код напрямую.

## 4. Reroll, Banish, Lock, Skip — явная семантика

| Действие | Меняет Hand | Расходует ресурсы действия | Потребляет заработанное решение | Предлагаемое правило |
|---|---|---|---|---|
| \`REROLL\` | Да, до лимита \`hand_size\` | 1 charge | **Нет** | Сохраняет locked offer, выдаёт хотя бы одну ранее не показанную допустимую карточку при наличии альтернатив; если альтернатив нет, **запретить расход** |
| \`BANISH\` | Убирает карту, заполняет вакансию при наличии другой допустимой | 1 charge | **Нет** | Запрет для выбранного \`OfferId\` сохраняется на уровне RunDraftState между решениями; нельзя banish locked без unlock |
| \`LOCK\` | Не меняет список | Бесплатно в примере | **Нет** | Одновременно удерживается одна карта **только в тестовой policy**, её можно снять \`UNLOCK\` |
| \`UNLOCK\` | Не меняет список | Нет | **Нет** | Не удаляет, не обновляет и не пересчитывает уже полученную награду |
| \`SELECT\` | Закрывает текущую награду | Нет | **Да, ровно одна** | Только \`OfferId\` из **показанного** hand и заново проверенный против текущего билда |
| \`SKIP\` | Закрывает текущую награду | Нет | **Да, ровно одна** | Явный осознанный отказ игрока, **не скрытый fallback**; в модели увеличивается build_revision без выдачи силы |

**Критическое UX-решение:** если в пуле нет новой доступной карточки, платный Reroll должен быть **недоступен**, иначе меню просто заберёт заряд и покажет то же самое. В справочнике/карточке нужно отображать причину: \`No additional eligible cards\`, а не скрывать кнопку или делать вид, что смена порядка — это новый выбор.

**Открытые дизайнерские вопросы:** стоимость и способы восстановления зарядов, возможность нескольких Lock, Banish по конкретному экземпляру/категории/ID, Skips в обязательных ритуалах, reroll batch с отдельными источниками, гарантии anti-brick. Эти различия задаются **политикой режима**, не hardcoded global caps.

## 5. Exactly-once операции и защита от двойной кнопки

Каждый клик, который меняет draft, включает \`InteractionUid, Kind, OfferId?, ExpectedHandRevision\`. Дополнительные операции создают квитанцию в \`ActionLedger\`: повтор **той же** квитанции возвращает неизменённое состояние, повтор UID с **другими** данными отклоняется, запоздавший expected revision не меняет charge и hand.

\`SELECT/SKIP\` имеют **собственную** квитанцию, которая потребляет только текущий \`EarnedChoice\`. Отдельный \`commit_once\` эталон возвращает тот же результат на повторную одинаковую команду. Это моделирует потерянное подтверждение UI, удержание кнопки и двойной тап. Запрет на повторную оплату должен поддерживаться authoritative run/build ledger в реальном runtime, а не храниться только в UI.

Если игрок нажимает подтверждение дважды, второй клик **не должен** выбрать следующую карточку уже из новой очереди, особенно после открытия пяти уровней одновременно.

## 6. ChoiceViewModel: только проверяемые факты

Каждая карточка в будущей реализации должна иметь:

| Факт | Источник | Почему важно игроку |
|---|---|---|
| тип/название/класс/школа | canonical Skill/Passive/Power + localization registry | моментально различать объект |
| текущий→следующий ранг или Power stack | existing RunBuild + projected BuildTransaction | узнать реальное изменение |
| занимает/освобождает слоты | projected RunBuild | избежать неожиданной нехватки места |
| открытые/закрытые рецепты | TransformationResolver, с ID и source gate | планирование эволюций и Union |
| какие навыки будут израсходованы | TransformationDef | недопущение неожиданной потери сборки |
| происхождение события | \`source_event_uid\` + RewardService | различать XP, ритуал, классовый выбор |
| cooldown/damage/status delta | typed Effect semantics; no copied UI formula | честное объяснение чисел |
| lock/banned/charges/focus | DraftHand + InputPolicy | понятное управление |
| почему предложено/почему нельзя выбрать | eligibility proof | объяснимость и доступность |

**Новое статическое \`view()\`** реализует лишь подтверждённые факты: \`OfferId\`, \`target_id\`, \`school_tags\`, ранг активной техники, изменение Power, slot delta, newly eligible rituals, \`source_event_uid\`, ревизии и флаг lock. \`localized_title\` и \`numerical_damage_delta\` намеренно \`null\`, пока нет источника факта. Не добавлять фиктивное \`+25% damage\` ради «красивой карточки».

Порядок RU/EN переводов не должен менять RNG, доступность карточек, игровые эффекты или статус \`BuildTransaction\`. UI-представление — чистая функция от авторитетного снапшота.

## 7. InputFocusProtocol: защита от случайного подтверждения

Известная проблема survivor-like: окно открывается после XP посреди перемещения/уклонения, и удерживаемый \`CONFIRM\` может подтвердить не ту карту.

Предлагаемая последовательность:
1. \`OPEN\`: фиксируем \`choice_uid\`, \`hand_revision\`, **список удерживаемых кнопок**; до их release новое подтверждение не вооружено.
2. \`RELEASE\` последней удерживаемой кнопки → \`confirm_armed = true\`. Пока игрок держит клавишу/геймпад, никаких действий с картой.
3. \`FOCUS\`: выбранный \`OfferId\` должен **присутствовать** в текущем Hand. Подсветка и озвучивание в будущем не влияют на gameplay RNG.
4. \`PRESS CONFIRM\`: только новый переход после release, с корректным \`hand_revision\`, выдаёт **intent**, не изменяет билд непосредственно.
5. Авторитетный \`ChoiceCoordinator\` проводит \`commit_once\`; при Reroll/Lock/Banish старая focus session **протухает**, перед подтверждением нужен новый scope.

Состояния движения, dodge cooldown, invulnerability, status tick во время паузы не изменяются скрытно. При возвращении к игре UI input context снимается, удерживаемое \`CONFIRM\` не преобразуется в \`DODGE\`. В тестах \`focus_input()\` показывает лишь модель протокола, не реальную обработку Godot \`InputEvent\`.

## 8. Сохранение DraftHand: честная граница с SAVE-CONTRACT-001

\`SAVE-CONTRACT-001\` содержит **строгую** оболочку, которая уже проверяется. Нельзя подложить туда незадокументированное поле \`draft_hand\` или обновить RNG cursor из UI без согласованной миграции.

Поэтому в этом slice есть **отдельный** \`DraftCheckpointOverlay\`:
- \`base_save_checksum\` привязывает overlay к конкретной **синтетической** модели сохранения;
- \`seed, hand_size, rerolls/banishes, initial_bans\` берутся из доверенного test plan;
- история вспомогательных действий хранится с \`InteractionUid\` и \`ExpectedHandRevision\`;
- текущий draft должен **точно совпасть** с независимым replay всех этих действий от исходного hand;
- после serialize/deserialize JSON восстановленный hand/lock/banlist/cursor/charge обязаны быть теми же.

Overlay не подписан криптографически; SHA-256 checksum не обеспечивает защиту от злоумышленника. Нет интеграции в настоящие сохранения Godot. Replay \`offers RNG\` моделируется отдельным синтетическим SHA-256 draw count и не продвигает \`SAVE-CONTRACT-001.rng_policy.offers.cursor\`, который в той модели пока 0 — **это известный межсистемный контракт, который предстоит унифицировать**, а не выполненная совместимость.

Запретные случайные миграции: пересчитать hand после загрузки новым алгоритмом, вернуть потраченные Reroll, забыть Banished, разрешить уже показанную непригодную карточку или изменить происхождение награды.

## 9. Синтетический acceptance witness

Берём существующий checkpoint из \`SAVE-CONTRACT-001\` после первого повышения ранга меча. В нём \`RunBuild.revision=7\`, пять исходных наград уменьшились до четырёх ожидающих решений, на первом месте обычный \`LEVEL_UP\`.

В выбранном sample policy:
1. Открываем набор из трёх допустимых карточек.
2. Блокируем \`sample.offer.echo\` — **без расходования уровня**.
3. Запрещаем \`sample.offer.new_thunder\` — этот оффер больше не присутствует в текущем hand; заряды Banish уменьшаются.
4. Сохраняем overlay, восстанавливаем через JSON roundtrip и воспроизводим те же операции.
5. Запрещаем Reroll в этой конкретной точке: других допустимых карточек нет. **Заряд не теряется.**
6. В отдельной positive fixture ревизии 6, где legal offer pool больше hand size, Reroll обязан показать хотя бы один новый вариант; locked offer сохраняется.
7. \`SELECT\` применяет фактическую проекцию BuildTransaction, \`SKIP\` явно расходует уровень без нового эффекта; обоим подтверждениям присваивается retry-safe квитанция.

**Всё это тестовые действия, не реальные значения механики или production random odds.**

## 10. Контрольные сценарии и ограничения

| Ошибка | Обязательный ответ эталона |
|---|---|
| Повтор Reroll с тем же InteractionUid | вернуть то же состояние, не списывать charge |
| Повтор UID с другим действием | отклонить конфликт |
| Редактирование старого hand revision | отклонить без изменения hand |
| Reroll при отсутствии альтернатив | отклонить без оплаты |
| Banish locked offer | отклонить до Unlock |
| Вторая карта Lock при уже удерживаемой | отклонить в данной sample policy |
| Устаревшая ревизия билда | отклонить карточку |
| SELECT не показанной, но вообще законной карты | отклонить — игнорирование hand нарушает RNG |
| Повторный SELECT / SKIP | тот же результат, без второго расхода |
| Удерживаемый CONFIRM при открытии | не давать intent до release + fresh press |
| Открытый focus после Reroll | отклонить stale focus |
| Подмена hand или cursor с пересчитанным checksum | отклонить при независимом action replay |
| Подмена save checksum при загрузке overlay | отклонить привязку к другому checkpoint |

**Что ещё не проверено:** реальный геймпад/клавиатура, локализация RU/EN, цвет/размер карточек, состояние highlight после анимаций, rendering performance, authoritative weighted DraftService, редкие источники (ритуал, Breakthrough), альтернативные источники наград, UX-метрики и human playtest. Reroll/Banish/Lock policies пока предложения.

**DRAFT-CONTRACT-002 integration:** [новый независимый эталон](draft-contract-002.md) сохраняет Banish на уровне забега, использует integer rejection sampling с доменным разделением, показывает явную причину пустого пула и моделирует optional soft pity. Предыдущая модель карточки/Focus остаётся самостоятельной. Полное объединение RNG, RunDraftState и SaveEnvelope — отдельный CHOICE-SAVE-002.

## 11. Следующее правильное направление

Не начинать массовый новый контент после одной UI-модели. Нужны:
1. \`DRAFT-CONTRACT-002\`: единый RNG policy / domain-separated streams, anti-brick, правила весов, редкости, защиты от повторов; сохранение банов **во всём забеге**, не только одной hand.
2. \`CHOICE-SAVE-002\`: законная schema migration \`SAVE-CONTRACT-001\` для активной руки, blocked/persistent offer IDs, focus lifecycle и draw cursor.
3. \`ARCH-02\`: доказательство достижимости эволюций/Union с учётом реального количества получаемых наград за забег.
4. \`GAME-ARCH-02\`: topology / waves / bosses / POI / stages и UX проверка того, что игрок в состоянии собрать билд в бою.

Возможность автоматического выбора типовых рангов должна быть отдельной **opt-in** policy, не навязанной всем игрокам. Взаимоисключающие меридианы/эволюции по умолчанию остаются ручными стратегическими решениями.

**CI acceptance:** \`python scripts/validate_choice_viewmodel_proposal.py\` + полный unittest discovery (Windows-2022 и Ubuntu), корректная навигация и совместимость с ранее пройденными SAVE/GAME-UX/ARCH-01 статическими тестами.
