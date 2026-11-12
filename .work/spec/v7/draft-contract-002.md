# DRAFT-CONTRACT-002 — воспроизводимый драфт, anti-brick и постоянные Banish

**Статус:** DESIGN PROPOSAL, синтетический Python reference, НЕ Godot/DraftService, НЕ утверждённый баланс. **Дата:** 2026-11-12.

**Связи:** [CHOICE-VIEWMODEL-001](choice-viewmodel-001.md), [BUILD-SKILL-001](build-skill-architecture-proposal.md), [SAVE-CONTRACT-001](save-contract-001.md), [GAME-UX-001](game-ux-001-oct-2026.md), [FOUNDATION-2026](foundation-research-2026.md). [Эталонная фикстура](../../proposals/draft-contract-002/README.md), [валидатор](../../../scripts/validate_draft_contract_proposal.py), [тесты](../../../tests/test_draft_contract_proposal.py).

## 1. Критический аудит прежнего состояния

Предшествующий CHOICE-VIEWMODEL-001 корректно разделил заработанную награду и показанную карточку, а также проверки Select, Skip, Reroll, Banish и Lock. Однако прежний эталон использовал взятие остатка SHA256 по сумме весов без отброса хвоста, хранил RNG cursor и ban-list главным образом на уровне одной руки и не формализовал защиту от последовательных неудачных предложений.

Смещение остатка при 256 битах для малых весов ничтожно, но **математически ненулевое** при некратном размере диапазона. Для воспроизводимого межъязыкового контракта полезнее сразу специфицировать rejection sampling и версию точного байтового ввода. Исправление здесь — **отдельная design-only модель**, а не утверждение, что боевой движок должен считать SHA256 для каждой карточки.

## 2. Источники истины и ограничения полномочий

Разделяем два объекта:

| Объект | Поля | Срок действия |
|---|---|---|
| **RunDraftState** | run UID, content/policy hash, algorithm/seed/counter, persistent banned IDs, reroll/banish charges, pity misses, action receipts | Весь забег |
| **ActiveDraftHand** | choice UID, source event, build revision, visible offer IDs, hand revision, locked ID, причина пустого пула, факт pity | Одно заработанное решение |

В дальнейшем один авторитетный RunSnapshot должен содержать оба. Сейчас отдельный checkpoint overlay ссылается на проверенный SAVE-CONTRACT-001 checksum; склейка схем без миграции запрещена.

**Число карточек, зарядов, количество рангов и слотов — правила режима, а не технические ограничения движка.** В синтетическом примере есть 2 карты и 2 Reroll; эти числа не должны попадать в канонический игровой баланс.

## 3. Чёткий контракт RNG

Кандидат v1 — domain-separated SHA-256 counter stream. Для каждого raw 256-bit блока входные байты:

1. ASCII префикс HEAVENISPREY/DRAFT-CONTRACT-002/v1 и один нулевой байт.
2. UTF-8 run UID в формате uint32 big-endian длина + bytes.
3. UTF-8 seed: каноническое десятичное unsigned uint64, также length-prefixed.
4. UTF-8 строка offers с length prefix.
5. UTF-8 choice UID с length prefix.
6. uint64 big-endian counter, общий для всех ordinary level choices в данном run.

Каждый блок увеличивает counter, включая отвергнутый. Вражеские волны, лут, эффекты, интерфейс и локализация **не потребляют offers cursor**. Изменение seed, choice UID, версии алгоритма или последовательности команд меняет воспроизводимую последовательность.

**Unbiased bounded integer:** для диапазона total weight от 1 до 2^64−1 вычисляем T = 2^256 − (2^256 mod total). Если raw меньше T, выбираем raw mod total. Иначе отвергаем блок и берём следующий. При идеальном равномерном raw математически исключается modulo bias. Это не доказательство случайности всех возможных seed и не NIST-верификация нашего генератора.

Кандидаты всегда сортируются по ID; веса — положительные целые 1..2^32−1, общий вес ограничен uint64. Выбор последовательный weighted **без возвращения**: каждый следующий слот выбирается из оставшихся законных ID. Такую процедуру нельзя путать с независимыми Бернулли включениями или с гарантированной вероятностью включения пропорционально весу — это разные распределения.

**Godot 4.7 caveat:** [RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html) в текущей версии использует PCG32, но документация прямо называет underlying algorithm implementation detail. rand_weighted оперирует PackedFloat32Array; без cross-language golden vectors нельзя объявлять её эквивалентной нашей integer weighted policy. После определения производительности возможно заменить SHA counter другим закреплённым PRNG, изменив version/hash и проверив сохранения.

## 4. Legal offer pipeline и безопасность сильных билдов

Pipeline:
1. **BUILD-SKILL.eligible_offers** проверяет реальные ранги, вместимость, требования и ограничения (одна реализация eligibility).
2. Run-scoped Banish убирает запрещённые OfferId из конкретного набора.
3. Применяется версия авторской draft policy, веса и soft-pity.
4. В hand выводится не более числа законных предложений, без вымышленных/дублированных карт.
5. SELECT проверяет, что выбранная карта **и сейчас показана, и всё ещё законна** относительно BuildRevision.
6. Commit обновляет один BuildTransaction и одну EarnedChoice; Reroll/Banish/Lock **не оплачивают уровень**.

Важна граница: это ещё не доказательство достижимости конкретной эволюции. Для неё понадобится ARCH-02 со stage reward schedule, слотами, взаимным исключением и максимальным числом заработанных улучшений.

## 5. Reroll, Banish, Lock и защита от пустого пула

**Reroll:** при наличии другого законного ID новая рука показывает хотя бы один ранее не показанный ID; locked card сохраняется. Это **условное распределение** с гарантией свежего варианта, не «просто перетасовали обычный весовой драфт». Если новых карточек нет или locked policy не оставляет свободного слота — кнопка недоступна, заряд не списывается.

**Banish:** ID исключается для **всего RunDraftState**, не только текущего hand; следующий EarnedChoice не может предложить тот же ID. Banish locked запрещён до Unlock. Преобразования skill instance и дальнейшие изменения каталога потребуют отдельно определённой политики, а не снятия запрета по умолчанию.

**Lock:** в текущей reference policy закрепляет одну карту только до финального выбора. Это не обещание, что во всех будущих режимах невозможно удерживать две карты или переносить Lock через уровни.

**Пустой пул:** отображать явную причину NO_BUILD_ELIGIBLE_OFFERS или ALL_ELIGIBLE_BANNED. В тестовом эталоне только EXPLICIT_SKIP — игрок **явно** расходует уровень, авто-Skip отсутствует. Это НЕ рекомендуемое универсальное дизайнерское решение. Необходимо отдельно выбрать authored fallback, например разрешённую альтернативную награду, post-max scaling или прозрачную conversion policy, без выдумывания валюты из UI.

**Anti-brick не означает «подкрутить RNG так, чтобы игрок выиграл»**. Нужно явно объяснять, когда предложение законно недоступно, и не забирать заряд/уровень скрытно.

## 6. Мягкая защита от серии неудачных рук (soft pity)

Test-policy задаёт protected offer IDs и порог pity_after. При открытии **новой EarnedChoice**:
- если есть законные protected IDs и предыдущие первоначальные руки подряд их не содержали, на пороговом открытии один слот заполняется авторизованным protected предложением;
- если protected уже показан, счётчик сбрасывается;
- Reroll **не увеличивает** число открытий и не меняет право на pity;
- ban/cap/class/gate всегда имеют приоритет; запретный или завершённый навык не создаётся «из воздуха»;
- при отсутствии legal protected ID никакой guaranteed grant не выполняется.

Эта механика сама по себе может уменьшить разнообразие билдов и потому остаётся **опциональной** и подлежит человеческому UX-тестированию. Число 2 из fixture — не одобренное значение.

## 7. Replay, exactly-once, версии

Все draft-команды имеют InteractionUid, Kind, optional OfferId и ожидаемую HandRevision. Точный повтор той же команды — idempotent, конфликтующий UID отклоняется. Старое подтверждение не может оплатить новый уровень. Run-scoped RNG counter, banlist, charges и pity не сбрасываются между двумя обычными выборами.

DraftOverlay связывается с конкретным **валидированным** базовым SaveSnapshot. При загрузке повторно применяются все OPEN/REROLL/BANISH/LOCK/SELECT/SKIP из журнала и сравниваются все поля: RunBuild, pending queue, RNG, banlist, charges и hand. Подмена курсора или hand даже с пересчитанным checksum должна отклоняться.

**Честная граница:** старый SAVE-CONTRACT-001 хранит только synthetic offers seed/cursor 0. Новый поток фактически потребляет draws, но физически не встроен в прежнюю SaveEnvelope. Это архитектурный долг CHOICE-SAVE-002: требуются schema migration, единый authoritative cursor и atomically persisted Run/Build/Draft. **Обновление:** закрыт предложением [CHOICE-SAVE-002](choice-save-002.md) (SaveEnvelope v2, курсор только в `rng_policy.streams.offers`).

## 8. Что проверено и не проверено

**Статически проверяемо:** integer rejection tail, deterministic sorted weighted without replacement, run UID domain separation, действительность весов и protected IDs, постоянные ban across multiple choices, отсутствие оплаты бесполезного reroll, soft-pity только для eligible, явное разрешение пустого пула, replay overlay и негативные мутации.

**Не проверено:** Godot RNG parity, реальная физика, редактор контента, fairness/rarity в реальном забеге, временная достижимость Union, человеческое восприятие pity, фактические сохранения на диск, gameplay/UI реализация.

## 9. Критерии следующего этапа

Сначала CHOICE-SAVE-002: встроить draft state в версионированный SaveEnvelope, объединить offers RNG и выполнить migration/replay golden tests. Затем ARCH-02: bounded graph reachability навыков, даров и много-компонентных Union с ограничениями реальной частоты наград. После этого GAME-ARCH-02: topology, waves/bosses и gated-reward sources.

Не вводить RL-директора или скрытый auto-pick редких путей. Для UX сначала мерить доступность рецептов, число невостребованных уровней, рукопашные/магические пути и долю пустых рук. Боты годятся для распределений, но не доказывают удовольствие игрока.

## Источники

- [Godot 4.7 RNG — официальная документация](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html).
- [Python secrets.randbelow — пример диапазонной генерации](https://docs.python.org/3/library/secrets.html#secrets.randbelow) (мы не используем недетерминированный secrets).
- [NIST SP 800-90A Rev.1](https://csrc.nist.gov/pubs/sp/800/90/a/r1/final) — общие стандарты DRBG; наша статическая модель НЕ является NIST-одобренной реализацией.
