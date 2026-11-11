# CURRENT_STATE — проверяемый архитектурный снимок

- **Last verified HEAD:** `main: 07a6630582adb5efab06a818c5daca6a3d3a430d` (merge PR #15; до служебного обновления данного снимка).
- **Current milestone:** ARCH — проектирование, независимые статические модели и CI, без Godot runtime, сцен, ассетов или игрового кода.
- **Current slice:** [DRAFT-CONTRACT-002](spec/v7/draft-contract-002.md) — модель взвешенных предложений с отдельным versioned SHA256-counter/rejection RNG, persistent Banish/charges/pity на уровне забега, объяснимым пустым пулом, exactly-once выбором и [replay overlay](proposals/draft-contract-002/README.md). Синтетический sample, **не принятый баланс**.
- **Open PR:** [#15](https://github.com/definitely-stable/HEAVENISPREY/pull/15) — MERGED `07a6630582adb5efab06a818c5daca6a3d3a430d`; открытых PR этого реализованного среза нет. Другие PR необходимо проверять отдельно.
- **Last CI:** [#43107393853](https://github.com/definitely-stable/HEAVENISPREY/actions/runs/43107393853) — SUCCESS, **242/242** Python design/static tests на GitHub-hosted Ubuntu + Windows-2022 для HEAD PR #15 `113244972e6869a82d544f67cf9766d9afd79428`. Это не отдельное подтверждение post-merge push-коммита.
- **Acceptance:** 36 новых тестов; 256-bit rejection sampling, deterministic sorted weighted without replacement, доменное разделение RNG, последовательные две earned choices, run-scoped bans/charge, Reroll fresh guarantee/no-charge when exhausted, optional eligible-only pity, явный SKIP при пустом пуле, replay journal, JSON roundtrip и отклонение подменённого cursor после reseal. Следующая награда после двух обычных уровней — RITUAL_REWARD. **Не** подтверждает реальный Godot RNG или UX-показатели.
- **Known blockers:** draft RNG cursor и global bans пока существуют в отдельном overlay, а строгий SAVE-CONTRACT-001 имеет другой offers cursor; нет принятого end-to-end RNG/SaveEnvelope migration. Sample pity_after и EXPLICIT_SKIP не утверждены как идеальные gameplay policies; полноценный fallback, источники редкости, реальная вероятность/достижимость рецептов и runtime DraftService отсутствуют.
- **Next allowed action:** `CHOICE-SAVE-002` (один versioned SaveEnvelope с RunDraftState и авторитетным offers RNG counter, миграции, replay); затем `ARCH-02` (bounded reachability рецептов/Union) и `GAME-ARCH-02` (stage topology / bosses). Только архитектура и статические тесты.
- **Last updated from repository:** 2026-11-12.

**Governance:** DESIGN PROPOSAL после merge остаётся проектным предложением. Не переносить автоматически в игру SHA256-based RNG, pity-after-2 или sample caps. Перед новой работой перепроверить HEAD/CI/PR live. Не оставлять обычные готовые PR открытыми после зелёного CI/diff-review.

[Draft contract](spec/v7/draft-contract-002.md) · [Reference and tests](proposals/draft-contract-002/README.md) · [Roadmap](roadmap/NEXT_SLICES.md) · [Choice ViewModel](spec/v7/choice-viewmodel-001.md)
