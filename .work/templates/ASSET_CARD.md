# ASSET_CARD: <asset_id>

Карточка одного визуального ассета. Процесс — [ART_LOOKDEV](../guides/ART_LOOKDEV.md); поля совпадают с manifest из [s16](../spec/core/s16.md).

- **asset_id (stable):** 
- **Content IDs (class / enemy / skill / ui):** 
- **Type / layer:** sprite · spritesheet · icon · ui-panel · tile · vfx
- **Reference anchors (`REF-xxx` + sha256 из [catalog](../../ref/catalog.json)):** 
- **Style passport version:** 
- **Generation:** capability · prompt hash · seed (если есть) · дата · исходный путь
- **Geometry:** frame size · frames · pivot · foot anchor · направления
- **Rules:** без запечённых glow/теней/текста · alpha корректна · силуэт читается на фоне арены
- **Metrics vs reference:** palette ΔE · tones · lowfreq · side/grid · diff (пороги из паспорта)
- **Godot import:** headless import OK · screenshot diff OK
- **Decision:** draft · rejected (причина) · approved (кем, дата, PR)
- **License / provenance:** 
