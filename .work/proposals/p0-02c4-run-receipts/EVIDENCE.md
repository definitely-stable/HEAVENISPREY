# P0-02 C4 · receipt and run cycle evidence

- On 2026-11-18 the combined C1–C4 Godot 4.7.2 run passed 22 focused tests and 180 assertions after the duration fixture accounted for the new chain shape fields.
- Results and Rewards captured at 1280×720 in Russian and English with `game/tools/capture_run.gd` and seed 101. The capture completes the final simulation tick and builds a real receipt.
- The focused suite covers victory, natural defeat, and abandonment while the choice menu is open, then restarts from Results and Rewards. It checks focus, the confirmation delays, one receipt per run UID, both language files, and the stable digests stored in the receipt.
- The shared preview vectors cover milestone time and kill boundaries, normal difficulty, multiplier rounding, duplicate modes, ineligible runs and unsupported reward multipliers.
- Session progress and the reward preview expire when the app closes. Wallet settlement belongs to P0-03.
