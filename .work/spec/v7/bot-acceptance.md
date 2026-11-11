# BOT-QA v7 — готовность поздней игры

**Различать:** (A) быстрые headless simulation tests, (B) интеграционные тесты полной Godot-сцены, (C) визуальные кадры; сценарные боты не измеряют субъективное удовольствие.

Политики: IdleBot, RandomBot, BeginnerBot, SurvivalBot, AggressiveBot, SynergyBot, ClassMasterBot, AdversarialBot, ProgressionBot, StressBot. Все используют общий PlayerCommand, не обходят игровые ограничения.

## Механические инварианты
- Hard/Tribulation/Abyss открываются только по установленным достижениям.
- Печати Дао невозможны на ранних сложностях или в Training/Custom.
- Settlement — exactly once; ресет талантов возвращает только потраченное.
- Replay с одним seed + RulesHash не меняет результат при смене языка.
- Endless и Hurry не создают неограниченный фарм поздней валюты.

## После появления реального runtime
ProgressionBot — последовательности 20–100 забегов: скорость открытия поздних режимов, награды/минуту, гринд, тупики и доминирующие классы. StressBot — крайние комбинации мультикаста и эффектов; AdversarialBot — попытки эксплойтов. Отчёт содержит seed, класс, сложность, modes, build, победу, длительность, reward events, p95/p99 sim time и свидетельства.

**Никакие показатели не объявлять прошедшими без игровых прогонов и CI.** [Roadmap](../../roadmap/NEXT_SLICES.md).
