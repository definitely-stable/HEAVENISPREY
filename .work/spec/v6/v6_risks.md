---
id: v6_risks
title: "AC. Риски v6 и критерии отказа от выбранного решения"
source: architecture-v6-2026-11-11
status: normative-v6
last_review: "2026-11-11"
---

[Индекс](../../INDEX.md) · [Исходник v6](../../archive/architecture-v6-original.md) · [Манифест](../../MANIFEST.json)

<a id="v6_risks"></a>
## AC. Риски v6 и критерии отказа от выбранного решения

| Риск | Вероятность/влияние | Механизм обнаружения | Исправление |
|---|---|---|---|
| AI сгенерирует красивые, но непереводимые спрайтовые карточки с текстом | высокая / среднее | asset QA + screenshot translations | текст выводить UI-компонентами, не в картинке |
| Сложность сведётся к росту HP и TTK | высокая / высокое | сравнение боссов, `hit/dodge` статистика | новые паттерны и угрозы, не только множитель |
| Metaprogression превратится в обязательный гринд | высокая / высокое | `zero-meta` vs full-meta bots, human playtest | горизонтальные открытия, уменьшить flat power |
| Лучший фарм — выход на 3-й минуте | средняя / высокое | `farmer` bot, stones/min | milestone-only reward, бонус за boss/finish |
| Пользователь случайно активирует несовместимые режимы | средняя / среднее | mode resolver tests, UI disabled reason | explicit compatibility matrix |
| Награда начислится дважды после сбоя | средняя / критическое | replay settlement/corrupt-save test | run_uid ledger, atomic write + backup |
| Открытая сессионная конфигурация поменяется во время забега | средняя / высокое | content_hash replay-diff | immutable `RunConfigSnapshot` |
| Русский/китайский текст обрежется или потеряет глифы | высокая / высокое для локали | pseudo locale + font coverage + screenshots | font fallback, responsive UI, locale smoke |
| Бот «докажет», что игра интересная | высокая / критическое для продукта | обязательные человеческие playtests | разделение QA от субъективного UX |
| Фильтр оптимизации удаляет события урона в сложном режиме | средняя / критическое | high-tier status/proc golden tests | формальные event budget rules, без drop() |
| Конфиги станут слабоструктурированными словарями везде | средняя / высокое | typed `*Def` review + schema lint | strict loaders, fail-fast unknown IDs |
| Количество комбинаций тестов взорвёт CI | средняя / среднее | runtime budget CI; cache hot spot | pairwise + рисковые triples + nightly suites |
| Один режим даёт валюту быстрее всех и обесценивает остальной контент | высокая / высокое | rewards per minute with matched policy/seed | revision reward table, а не скрытая сложность |

**Не реализовывать** пользовательские произвольные формулы в конфиге через `eval`, динамическую загрузку AI-кода в релиз и серверную экономику: игра однопользовательская, все конфиги проходят commit/review и включаются в build. Для M0–M3 достаточно версии и статического валидатора.
