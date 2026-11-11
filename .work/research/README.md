# Evidence registry для reverse engineering

[Исходный CSV-шаблон v5](claim_evidence.csv) содержит поля `claim_id,game,game_build,mechanic,hypothesis,evidence_tier,source_uri,file_or_symbol,confidence,godot_contract,verification_test,status`.

**Все поля требуют подтверждения источниками конкретной версии игры.** Начальная строка `SS-STAT-001` отмечена `UNKNOWN/E0`. Нельзя конвертировать неподтверждённую гипотезу в обязательную реализацию боевой системы без архитектурного решения.

См. [протокол RE v5](../spec/v5/v5_re.md) · [исходники](SOURCES.md) · [единые правила evidence](../templates/EVIDENCE.md).
