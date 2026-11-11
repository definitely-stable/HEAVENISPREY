"""Design-data integration tests; does not simulate a Godot run."""
import importlib.util, json, shutil, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts/validate_content.py"
DATA=ROOT/".work/config/v7"

def validator_at(data):
    spec=importlib.util.spec_from_file_location("content_validator",SCRIPT)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.DATA=data
    return module

class ContentLinkageTests(unittest.TestCase):
    def test_canonical_catalogs_valid(self):
        module=validator_at(DATA)
        module.run()
        self.assertEqual(module.ERRORS,[])

    def mutate(self,filename,callback):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            for src in DATA.iterdir():
                if src.is_file():
                    shutil.copy2(src,folder/src.name)
            target=folder/filename
            document=json.loads(target.read_text(encoding="utf-8"))
            callback(document)
            target.write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding="utf-8")
            module=validator_at(folder)
            module.run()
            return list(module.ERRORS)

    def test_unknown_status_rejected(self):
        errors=self.mutate("skills.json",lambda d:d["skills"][0]["effect_ops"][1].update(status_id="status.not_found"))
        self.assertTrue(any("undefined skill status" in e for e in errors),errors)

    def test_stage_deletion_breaks_late_unlock(self):
        errors=self.mutate("stages.json",lambda d:d["stages"].pop())
        self.assertTrue(any("unreachable multi-stage unlock" in e or "boss unknown stage" in e for e in errors),errors)

    def test_talent_self_cycle_rejected(self):
        errors=self.mutate("talents.json",lambda d:d["talents"][2]["prerequisites"].append("talent.global.banish"))
        self.assertTrue(any("cycle" in e for e in errors),errors)

    def test_late_currency_only_high_tiers(self):
        data=json.loads((DATA/"difficulty_profiles.json").read_text(encoding="utf-8"))
        rewards=json.loads((DATA/"reward_contract.json").read_text(encoding="utf-8"))
        allowed=set(rewards["dao_seals_allowed_difficulties"])
        self.assertEqual(allowed,{"difficulty.tribulation","difficulty.abyss"})
        for v in data["profiles"]:
            self.assertEqual(v["dao_seals_on_clear"]>0,v["id"] in allowed)

    def test_starter_classes_and_scenarios_valid(self):
        classes={v["id"]:v for v in json.loads((DATA/"classes.json").read_text(encoding="utf-8"))["classes"]}
        scenarios=json.loads((DATA/"bot_scenarios.json").read_text(encoding="utf-8"))["scenarios"]
        self.assertEqual({x for x,v in classes.items() if v["planned_first_playable"]},{"class.sword","class.thunder"})
        self.assertGreaterEqual(len(scenarios),7)

if __name__=="__main__":
    unittest.main()
