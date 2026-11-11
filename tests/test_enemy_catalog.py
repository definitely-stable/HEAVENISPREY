"""Static tests for ordinary-enemy design catalogs. No Godot runtime or bot runs."""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / ".work" / "config" / "v7"
VALIDATOR = ROOT / "scripts" / "validate_content.py"

def load_validator(data):
    spec = importlib.util.spec_from_file_location("enemy_content_validation", VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.DATA = data
    return module

class OrdinaryEnemyContractTests(unittest.TestCase):
    def mutate(self, filename, change):
        with tempfile.TemporaryDirectory() as d:
            destination = Path(d)
            for src in DATA.iterdir():
                if src.is_file():
                    shutil.copy2(src, destination / src.name)
            file = destination / filename
            value = json.loads(file.read_text(encoding="utf-8"))
            change(value)
            file.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
            module = load_validator(destination)
            module.run()
            return module.ERRORS

    def test_all_twelve_screenshots_and_cultivator_are_normal(self):
        data = json.loads((DATA / "enemies.json").read_text(encoding="utf-8"))
        ids = {e["id"] for e in data["enemies"]}
        self.assertEqual(len(ids), 13)
        self.assertTrue(all(e["combat_tier"] == "normal" for e in data["enemies"]))
        self.assertIn("enemy.cursed_spirit_lantern", ids)
        self.assertIn("enemy.root_abomination", ids)
        self.assertIn("enemy.corrupted_cultivator", ids)
        self.assertNotIn("boss.jade_warden", ids)

    def test_missing_enemy_attack_is_rejected(self):
        errors = self.mutate("enemies.json", lambda d: d["enemies"][0]["attack_ids"].append("enemy_attack.not_real"))
        self.assertTrue(any("enemy missing attack" in x for x in errors), errors)

    def test_upgrading_common_enemy_to_elite_is_rejected(self):
        errors = self.mutate("enemies.json", lambda d: d["enemies"][3].update(combat_tier="elite"))
        self.assertTrue(any("ordinary enemy escalated" in x for x in errors), errors)

    def test_missing_attack_status_is_rejected(self):
        def change(d):
            next(a for a in d["attacks"] if a["id"] == "enemy_attack.snake_bite")["apply_status_id"] = "status.unknown_poison"
        errors = self.mutate("enemy_attacks.json", change)
        self.assertTrue(any("undefined status" in x for x in errors), errors)

    def test_instant_mantis_charge_is_rejected(self):
        def change(d):
            next(a for a in d["attacks"] if a["id"] == "enemy_attack.mantis_lunge")["telegraph_ticks"] = 0
        errors = self.mutate("enemy_attacks.json", change)
        self.assertTrue(any("insufficient telegraph" in x for x in errors), errors)

    def test_homing_projectile_without_lock_is_rejected(self):
        def change(d):
            next(a for a in d["attacks"] if a["id"] == "enemy_attack.lantern_wisp")["params"]["homing"] = True
        errors = self.mutate("enemy_attacks.json", change)
        self.assertTrue(any("slow locked-path rule" in x for x in errors), errors)

    def test_root_instant_hard_wall_is_rejected(self):
        def change(d):
            next(a for a in d["attacks"] if a["id"] == "enemy_attack.root_growth")["params"]["solid_barrier"] = True
        errors = self.mutate("enemy_attacks.json", change)
        self.assertTrue(any("unsafe solid root barrier" in x for x in errors), errors)

    def test_dangling_roster_enemy_is_rejected(self):
        errors = self.mutate("enemy_rosters.json", lambda d: d["rosters"][0]["windows"][0]["weighted_enemies"][0].update(enemy_id="enemy.nope"))
        self.assertTrue(any("enemy roster references missing enemy" in x for x in errors), errors)

    def test_gap_between_spawn_windows_is_rejected(self):
        errors = self.mutate("enemy_rosters.json", lambda d: d["rosters"][0]["windows"][1].update(start_second=96))
        self.assertTrue(any("enemy roster window gap" in x for x in errors), errors)

    def test_missing_translation_is_rejected(self):
        errors = self.mutate("enemies.json", lambda d: d["enemies"][0].update(name_key="ENEMY_TRANSLATION_NOT_DEFINED"))
        self.assertTrue(any("enemy name_key lacks translation" in x for x in errors), errors)

    def test_bot_target_must_exist_in_stage_roster(self):
        def change(d):
            next(x for x in d["scenarios"] if x["id"] == "bot.enemy.root_escape.001")["target_enemy_id"] = "enemy.corruption_centipede"
        errors = self.mutate("bot_scenarios.json", change)
        self.assertTrue(any("target not present on stage" in x for x in errors), errors)

    def test_early_difficulty_variant_is_rejected(self):
        errors = self.mutate("enemy_variants.json", lambda d: d["variants"][0].update(difficulty_id="difficulty.standard"))
        self.assertTrue(any("requires locked late difficulty" in x for x in errors), errors)

if __name__ == "__main__":
    unittest.main()
