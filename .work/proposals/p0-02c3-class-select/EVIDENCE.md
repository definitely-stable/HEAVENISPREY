# EVIDENCE: P0-02 C3 class selection

- **Observed date (UTC):** 2026-11-18.
- **Environment:** Windows, Godot 4.7.2 Stable, Compatibility renderer.
- **Capture:** `godot --path game --resolution 1280x720 -s res://tools/capture_run.gd -- <out>.png 101 class-select <en|ru>`. Both locale captures show the empty arena, Sword focused and a readable locked Thunder card. Key and controller focus and mouse selection are exercised by [test_class_select.gd](../../../game/tests/integration/test_class_select.gd).
- **Catalog and strings:** `python scripts/validate_work.py`, `python scripts/validate_content.py`, and `python tools/content/ui_strings.py --check` passed.
- **Limits:** The capture covers display and text. Automated input uses engine events. Physical controllers and a new playthrough remain manual acceptance.
