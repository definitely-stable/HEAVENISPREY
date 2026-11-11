---
id: v5_re
title: "Дополнение J. Reverse engineering: конкретная программа поиска кода, данных, формул, а не видеоигра по памяти"
source: architecture-v6-2026-11-11
status: adapted-role-neutral
last_review: "2026-11-11"
---

> **Адаптация v7:** текстовые назначения задач конкретным моделям отменены. [Единый регламент](../../guides/WORKFLOW.md) применим к любому исполнителю. [Историческая версия](../../archive/architecture-v6-original.md) сохранена без правок.

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="v5_re"></a>
## Дополнение J. Reverse engineering: конкретная программа поиска **кода, данных, формул**, а не видеоигра по памяти

В предыдущем отчёте перечислены Cpp2IL, Il2CppDumper и Ghidra, но не определено, что именно результат каждой стадии *доказывает*. В первую очередь следует проверять публичные проекты моддеров и актуальные game version build IDs. Код, полученный из IL2CPP, часто является лишь type/proxy metadata; сама native арифметика и порядок операций не восстановлены из interop stubs — это прямо объясняют Vampire Survivors modders. [R49](https://github.com/lukeod/vampiresurvivors-modding/blob/main/il2cpp-guide.md)[R61](https://github.com/Salmacis32/VampireSurvivorsRefCompilationProject)

### 32J.1. Два потока по разной цене знания

**VS (механика оружия):** публичная вики/моддинг/референс-проект → `WeaponData`/`ProjectileData` и их поля → версия/наследование → проверка hot path в доступной сборке. Уже известно о `Cooldown`, `Duration`, `Amount`, `Hitbox Delay`, `Pool Limit`; при этом часть игровых значений UI (например, показанные numbers) может быть чисто визуальной. [R62](https://vampire.survivors.wiki/w/Weapons)[R63](https://vampire.survivors.wiki/w/Cooldown)

**SS (мультикаст/синергии):** официальные патч-ноты 2026 → список конкретных skills/runes и изменённой логики → API hooks модов/Skada → build-specific IL2CPP metadata → native body и instrumentation, когда без этого нельзя подтвердить формулу. Например, июньский патч 2026 переработал `Elemental Flow` так, что статусы Burn/Bleed/Poison/Doom стали наносить дополнительные instant effects при наложении, а `Multicast Mastery` изменил множитель. Нельзя делать неизменную копию поведения из гайда 2023 года. [R56](https://steamdb.info/patchnotes/23706374/)

### 32J.2. Evidence ladder для каждой формулы

| Tier | Доказательство | Допустимый вывод |
|---|---|---|
| E0 | форум/дискуссия без указания версии | гипотеза для поиска |
| E1 | официальные патч-ноты или официальное описание игроку | заявленная механика, не точная внутренняя формула |
| E2 | repo моддера со ссылкой на конкретную сборку/символы | присутствие структуры/точки входа в указанной версии |
| E3 | build-specific metadata + native method body trace | возможный порядок операций; нужно учесть branch conditions |
| E4 | воспроизведённый игровой тест/инструментирование | фактическая проверка целевого утверждения для данной сборки |

Из E2 не делать утверждения «крит у Poison всегда рассчитывается так-то»: metadata может не содержать соответствующей математики. Из E4 нельзя восстановить единственный внутренний алгоритм, если множество реализаций имеют одинаковое наблюдаемое поведение.

### 32J.3. Структура отчёта агента по каждой механике

```json
{"claim_id":"SS-STAT-001","game":"Soulstone Survivors","build_id":"UNKNOWN",
 "question":"Does applying an extra stack reset tick phase?",
 "finding":"UNKNOWN","tier":"E0","evidence":[],
 "contradictions":[],"godot_design_choice":"INDEPENDENT_TICK_PHASE",
 "verification_test":"test_status_refresh_preserves_tick_phase"}
```

На момент этого архитектурного отчёта у нас **нет файлов игровых сборок** и **нет выполненного декомпилирования**. Поэтому оставить ответы `UNKNOWN`, а не «Codex уже посмотрел методы». Результат RE — компактная `mechanic→godot_contract` таблица, обновляемая отдельно от runtime. **Не блокировать** базовый Godot combat test RE, если интерфейс нашей системы определён независимой проектной политикой.

### 32J.4. Дополнительные конкретные задачи RE

1. Как каждый тип оружия проверяет `Pool Limit`: до cast или при spawn?
2. Когда запускается cooldown: в момент commit, в конце duration или после projectile interval?
3. Меняется ли число hits при изменении visibility VFX?
4. Сохраняется ли старый damage snapshot после изменения rank?
5. Что первично: Damage, Status Apply, Instant Reaction, OnKill?
6. Использует ли Soulstone generalized proc stack и какие family flags исключают повторный proc?
7. Имеются ли per-target hit cooldown и отдельные источники мультикаста?
8. На каком этапе UI применяет display rounding и не отличается ли от фактического HP delta?
9. Как после балансных патчей 2026 изменились условные типы rune effects?
10. Как оптимизировали projectile-heavy skills: batch hits, уменьшение количества visual projectiles, изменение collision checks или несколько методов вместе?

### 32J.5. Что считать **неудовлетворительным** RE

- Просто привести классы из GitHub без проверки версии.
- Назвать decompiled IL2CPP C# proxy «полным исходным кодом».
- Получить численную формулу из комментария Reddit без повторения.
- Не сохранить SHA256 build и content version.
- Пообещать точную архитектуру и бизнес-логику игр без доступа к их программным файлам.
