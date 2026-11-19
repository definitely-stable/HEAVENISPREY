# TASK_SPEC: COMBAT-TELEGRAPH-READABILITY-001

- **Status:** IN_PROGRESS
- **Goal:** распознавать рывок `enemy.sickle_mantis` и выстрел `enemy.cursed_spirit_lantern` по силуэту в тени и в пятне жаровни, в том числе при перекрытии.
- **Non-goals:** правила попаданий, прицел, геометрия зон, тайминги, слои арены, боевой HUD REF-067 и игровые ассеты.
- **Inputs:** [ADR-011 §3](../../decisions/ADR-011-p0-02e-enemy-attacks.md), [контракт угроз](../../spec/v7/enemy-threat-contract.md), [ADR-014 A2](../../decisions/ADR-014-art-02-isometric-light.md).
- **Files allowed:** `game/presentation/run/attack_telegraph.gd`, `game/tools/capture_run.gd`, `.work/CURRENT_STATE.md`, этот контракт и его evidence. Для бюджета A2 разрешены `ground_layer.gd`, `arena_dressing.gd` и `run_view.gd` для отсечения геометрии за пределами кадра.
- **Dependencies:** база `6e7bed6`, Godot 4.7.2 Compatibility, атласы из Git LFS, стандартный GUT.
- **Contracts:** граница полосы рывка видна с первого тика поверх тёмной подложки. Один внутренний шеврон указывает направление, заливка растёт до удара. Узкая яркая ось выстрела с поперечной меткой показывает источник. Tell/active и aim читаются из прежних полей симуляции.
- **Acceptance:** парные 1280×720 кадры начала, середины и конца предупреждения в двух условиях света, плюс кадр выпуска. Силуэты различаются в градациях серого. Симуляция даёт прежние дайджесты. Проверить пиксели арены до и после отсечения у центра и края, сохранив тайминг, порядок глубины, освещение и атласы. Бюджет ADR-014 A2 при 300 врагах и активных лимитах предупреждений составляет p95 ≤ 8 мс и максимум 80 draw calls в 1920×1080.
- **Risks / rollback:** толстый контур может закрыть узкий центр в ракурсе изометрии. Откатить изменение отрисовки одним revert.
- **Test commands:** `python scripts/validate_work.py`, `python -m unittest discover -s tests -v`, `python scripts/validate_encounter_proposal.py`, GUT для атак и паритета, режимы `telegraphs` и `telegraph_perf` в `capture_run.gd`.
- **Evidence links:** [локальный протокол](EVIDENCE.md).
- **Next action:** проверить кадры, равенство дайджестов и бюджет на базе и кандидате.
