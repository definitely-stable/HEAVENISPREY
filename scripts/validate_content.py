#!/usr/bin/env python3
"""Cross-catalog v7 static content validation. No Godot runtime is asserted."""
import csv, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/".work/config/v7"
ERRORS=[]
def problem(message): ERRORS.append(message)
def load(file):
    def reject_dupes(pairs):
        d={}
        for k,v in pairs:
            if k in d:raise ValueError("duplicate JSON key %s in %s"%(k,file))
            d[k]=v
        return d
    obj=json.loads((DATA/file).read_text(encoding="utf-8"),object_pairs_hook=reject_dupes)
    if obj.get("schema_version")!=2:problem("schema_version != 2 in "+file)
    return obj
def catalog(file,key):
    result={}
    for x in load(file)[key]:
        id=x["id"]
        if id in result:problem("duplicate id "+id+" in "+file)
        result[id]=x
    return result
def check_graph(catalog,parents,scope):
    visiting=set(); visited=set()
    def walk(node):
        if node in visiting:problem("cycle %s -> %s"%(scope,node));return
        if node in visited:return
        visiting.add(node)
        for prev in parents(catalog[node]):
            if prev not in catalog:problem("missing %s prerequisite %s from %s"%(scope,prev,node))
            else:walk(prev)
        visiting.remove(node);visited.add(node)
    for node in catalog:walk(node)
def validate_enemies(difficulty, stages, statuses, modes, scenarios, trs):
    """Check the new *ordinary* enemy catalogs and the stage/threat contracts."""
    enemies = catalog("enemies.json", "enemies")
    attacks = catalog("enemy_attacks.json", "attacks")
    rosters = catalog("enemy_rosters.json", "rosters")
    variants = catalog("enemy_variants.json", "variants")
    expected_ids = {
        "enemy.yin_corpse", "enemy.blood_wolf", "enemy.wandering_spirit",
        "enemy.ruined_jade_guardian", "enemy.sickle_mantis", "enemy.paper_puppet",
        "enemy.venom_spirit_snake", "enemy.fallen_sword_disciple", "enemy.omen_crow",
        "enemy.corruption_centipede", "enemy.cursed_spirit_lantern",
        "enemy.root_abomination", "enemy.corrupted_cultivator"
    }
    if set(enemies) != expected_ids:
        problem("ordinary roster must include all 12 screenshot enemies and corrupted cultivator")
    if "boss.jade_warden" in enemies or "enemy.jade_warden" in enemies:
        problem("normal jade guardian must not alias the boss")
    all_names = set()
    for id, enemy in enemies.items():
        if enemy["combat_tier"] != "normal":
            problem("ordinary enemy escalated to elite/boss: " + id)
        if enemy["stats"]["health_mult"] <= 0 or enemy["stats"]["speed_mult"] <= 0:
            problem("invalid ordinary enemy stats: " + id)
        if enemy["spawn_cost"] < 1 or not enemy["attack_ids"]:
            problem("ordinary enemy lacks spawn cost or attacks: " + id)
        if enemy["movement_mode"] not in ("ground", "flying", "ethereal"):
            problem("unknown enemy movement mode: " + id)
        if not enemy["visual_brief_ru"].strip():
            problem("missing ordinary enemy art brief: " + id)
        for attack_id in enemy["attack_ids"]:
            if attack_id not in attacks:
                problem("enemy missing attack: " + id + "/" + attack_id)
        name_key = enemy["name_key"]
        if name_key in all_names or name_key not in trs:
            problem("enemy name_key lacks translation or is duplicate: " + id)
        all_names.add(name_key)
    allowed_kinds = {"CONTACT", "MELEE_ARC", "CHARGE", "ON_DEATH_ZONE", "PROJECTILE", "GROUND_ZONE"}
    for id, attack in attacks.items():
        kind = attack["kind"]
        if kind not in allowed_kinds:
            problem("enemy attack unknown kind: " + id)
        if attack["active_ticks"] <= 0 or attack["cooldown_ticks"] < 0:
            problem("enemy attack invalid timing: " + id)
        if kind != "CONTACT" and attack["telegraph_ticks"] < 18:
            problem("enemy attack insufficient telegraph: " + id)
        if kind in ("CHARGE", "GROUND_ZONE", "ON_DEATH_ZONE") and attack["telegraph_ticks"] < 24:
            problem("enemy attack insufficient danger warning: " + id)
        if attack["damage_mult"] < 0:
            problem("enemy attack negative damage: " + id)
        if attack["hit_policy"] != "once_per_target_per_attack_instance":
            problem("enemy attack unsafe hit policy: " + id)
        if attack["name_key"] in all_names or attack["name_key"] not in trs:
            problem("enemy attack name_key lacks translation or is duplicate: " + id)
        all_names.add(attack["name_key"])
        status_id = attack["apply_status_id"]
        if status_id is not None and status_id not in statuses:
            problem("enemy attack references undefined status: " + id + "/" + str(status_id))
        params = attack["params"]
        if kind == "CONTACT" and (params.get("hit_interval_ticks", 0) < 12 or attack["telegraph_ticks"] != 0):
            problem("enemy contact attack may not hit every frame: " + id)
        if kind == "CHARGE" and params.get("can_retarget") is not False:
            problem("enemy charge re-targets after telegraph: " + id)
        if kind == "PROJECTILE":
            speed = params.get("projectile_speed_as_player_mult", 0)
            if not 0 < speed < 1 or params.get("homing") is not False or params.get("aim_lock") != "telegraph_end":
                problem("enemy projectile violates slow locked-path rule: " + id)
        if kind == "ON_DEATH_ZONE" and (
            params.get("requires_death") is not True or
            params.get("no_retrigger_by_death_proc") is not True
        ):
            problem("enemy on-death hazard lacks safe proc origin: " + id)
        if kind == "GROUND_ZONE":
            if params.get("solid_barrier") is True:
                problem("unsafe solid root barrier: " + id)
            if params.get("persistent_ticks", 0) < 1:
                problem("enemy ground zone lacks duration: " + id)
        if id == "enemy_attack.root_growth" and params.get("solid_barrier") is not False:
            problem("unsafe solid root barrier: " + id)
    for id, status in statuses.items():
        if status.get("target") != "player":
            continue
        if status.get("duration_ticks", 0) <= 0:
            problem("player debuff missing duration: " + id)
        for modifier in ("movement_speed_multiplier", "shield_regen_multiplier"):
            if modifier in status and not 0 < status[modifier] <= 1:
                problem("player debuff invalid multiplier: " + id)
    appearing = set()
    used_stages = set()
    for id, roster in rosters.items():
        stage_id = roster["stage_id"]
        if stage_id not in stages:
            problem("enemy roster missing stage: " + id)
            continue
        if stages[stage_id].get("enemy_roster_id") != id:
            problem("stage enemy roster reverse link missing: " + id)
        if stage_id in used_stages:
            problem("duplicate stage enemy roster: " + stage_id)
        used_stages.add(stage_id)
        caps = roster["threat_caps"]
        required_caps = ("simultaneous_projectile_casts_winding_up",
                         "simultaneous_charge_windups", "active_control_zones",
                         "active_death_hazards", "ordinary_ranged_on_screen")
        if any(type(caps.get(k)) is not int or caps[k] < 0 for k in required_caps):
            problem("invalid ordinary threat budget: " + id)
        previous = 0
        for window in roster["windows"]:
            if window["start_second"] != previous:
                problem("enemy roster window gap/overlap: " + window["id"])
            if window["end_second"] <= window["start_second"]:
                problem("enemy roster window not increasing: " + window["id"])
            previous = window["end_second"]
            if window["max_control_enemies_near_player"] > caps["active_control_zones"]:
                problem("enemy roster control exceeds allowed threat cap: " + window["id"])
            if not window["weighted_enemies"]:
                problem("empty enemy roster window: " + window["id"])
            for entry in window["weighted_enemies"]:
                enemy_id = entry["enemy_id"]
                if enemy_id not in enemies:
                    problem("enemy roster references missing enemy: " + window["id"] + "/" + enemy_id)
                elif entry["weight"] <= 0:
                    problem("enemy roster nonpositive weight: " + window["id"] + "/" + enemy_id)
                appearing.add(enemy_id)
        if previous != stages[stage_id]["duration_minutes"] * 60:
            problem("enemy roster does not cover full stage: " + id)
    for stage_id, stage in stages.items():
        if stage_id not in used_stages or stage.get("enemy_roster_id") not in rosters:
            problem("stage missing ordinary enemy roster: " + stage_id)
    if appearing != set(enemies):
        problem("ordinary enemies not represented in stage rosters: " + str(sorted(set(enemies) - appearing)))
    for id, variant in variants.items():
        if variant["enemy_id"] not in enemies:
            problem("enemy variant references missing enemy: " + id)
        diff_id = variant["difficulty_id"]
        if diff_id not in difficulty or difficulty[diff_id]["tier"] < 3:
            problem("enemy variant requires locked late difficulty: " + id)
    for id, scenario in scenarios.items():
        target = scenario.get("target_enemy_id")
        if target is None:
            continue
        if target not in enemies:
            problem("enemy bot scenario references missing enemy: " + id)
            continue
        stage = stages.get(scenario["stage_id"])
        if stage is None:
            continue
        roster = rosters.get(stage.get("enemy_roster_id"))
        if roster is not None and not any(
            entry["enemy_id"] == target
            for wave in roster["windows"] for entry in wave["weighted_enemies"]
        ):
            problem("enemy bot scenario target not present on stage: " + id)
    print("Ordinary enemies:", len(enemies), "attacks:", len(attacks),
          "stage rosters:", len(rosters), "difficulty variants:", len(variants))

SETTINGS_SCHEMA={
    "localization":{"preferred_locale":("enum",("auto","en","ru"))},
    "graphics":{"vfx_intensity":("unit",),"screenshake":("unit",)},
    "accessibility":{"font_scale":("positive",)},
}
def check_localization_context(ctx,trs):
    """localization_context.json: every hint names an existing key or a key prefix (ending with _)."""
    out=[]
    if ctx.get("kind")!="localization_hints":out.append("localization_context.json: unexpected kind")
    if ctx.get("translation_file")!="translations.csv":out.append("localization_context.json: translation_file must be translations.csv")
    for key,hint in ctx.get("contexts",{}).items():
        hit=any(k.startswith(key) for k in trs) if key.endswith("_") else key in trs
        if not hit:out.append("localization_context.json: no translation key for "+key)
        if not isinstance(hint,str) or not hint.strip():out.append("localization_context.json: empty hint for "+key)
    return out
def check_settings(text):
    """settings.example.cfg: Godot ConfigFile subset; known sections/keys only, typed values in range."""
    out,seen,section=[],{},None
    for n,raw in enumerate(text.splitlines(),1):
        line=raw.strip()
        if not line or line.startswith(";"):continue
        if line.startswith("[") and line.endswith("]"):
            section=line[1:-1]
            if section not in SETTINGS_SCHEMA:out.append("settings.example.cfg:%d unknown section %s"%(n,section))
            continue
        key,_,value=line.partition("=")
        rule=SETTINGS_SCHEMA.get(section,{}).get(key.strip())
        if rule is None:
            out.append("settings.example.cfg:%d unknown key %s.%s"%(n,section,key.strip()));continue
        seen[(section,key.strip())]=True
        value=value.strip()
        if rule[0]=="enum":
            if not (value.startswith('"') and value.endswith('"') and value[1:-1] in rule[1]):
                out.append("settings.example.cfg:%d %s must be one of %s"%(n,key.strip(),rule[1]))
            continue
        try:number=float(value)
        except ValueError:
            out.append("settings.example.cfg:%d %s is not a number"%(n,key.strip()));continue
        if rule[0]=="unit" and not 0<=number<=1:out.append("settings.example.cfg:%d %s outside 0..1"%(n,key.strip()))
        if rule[0]=="positive" and not number>0:out.append("settings.example.cfg:%d %s must be > 0"%(n,key.strip()))
    for section,keys in SETTINGS_SCHEMA.items():
        for key in keys:
            if (section,key) not in seen:out.append("settings.example.cfg: missing %s.%s"%(section,key))
    return out
def run():
    difficulty=catalog("difficulty_profiles.json","profiles")
    modes=catalog("modes.json","profiles")
    unlocks=catalog("unlock_rules.json","rules")
    classes=catalog("classes.json","classes")
    skills=catalog("skills.json","skills")
    statuses=catalog("statuses.json","statuses")
    stages=catalog("stages.json","stages")
    bosses=catalog("bosses.json","bosses")
    talents=catalog("talents.json","talents")
    late=catalog("late_talents.json","talents")
    currencies=catalog("currencies.json","currencies")
    scenarios=catalog("bot_scenarios.json","scenarios")
    profiles=catalog("profile_fixtures.json","profiles")
    milestone=catalog("economy_milestones.json","milestones")
    reward=load("reward_contract.json")
    compat=load("id_compatibility.json")
    name_keys=[]
    for group in (difficulty,modes,classes,skills,statuses,stages,bosses,talents,late,currencies):
        name_keys += [x["name_key"] for x in group.values() if "name_key" in x]
    with (DATA/"translations.csv").open(encoding="utf-8",newline="") as f:
        reader=csv.DictReader(f)
        if reader.fieldnames!=["keys","en","ru"]:problem("Godot import CSV must have only keys,en,ru")
        trs={}
        for row in reader:
            name=row["keys"]
            if name in trs:problem("duplicate translation key "+name)
            trs[name]=row
            if not row["en"].strip() or not row["ru"].strip():problem("missing translation for "+name)
    for name in name_keys:
        if name not in trs:problem("missing translation key "+name)
    if len(set(name_keys))!=len(name_keys):
        problem("name_key should be globally unique for separate content definitions")
    for cid,cl in classes.items():
        if cl["start_skill_id"] not in skills:problem("missing class skill "+cid)
        if cl["unlock_id"] is not None and cl["unlock_id"] not in unlocks:problem("missing class unlock "+cid)
        if not cl["mastery_tree_id"].startswith("mastery."):problem("invalid mastery tree "+cid)
    for sid,skill in skills.items():
        if skill["base_cooldown_ticks"]<=0:problem("zero skill cooldown "+sid)
        for op in skill["effect_ops"]:
            if op["op"] not in ("damage","apply_status"):problem("unsupported effect opcode "+sid)
            if op["op"]=="apply_status" and op.get("status_id") not in statuses:
                problem("undefined skill status "+sid)
    for sid,st in statuses.items():
        if st["max_stacks"]<=0:problem("invalid stack cap "+sid)
        if st["tick_period_ticks"] is not None and st["tick_period_ticks"]<=0:problem("invalid tick rate "+sid)
    for stage_id,stage in stages.items():
        if stage["duration_minutes"]<=0:problem("invalid stage duration "+stage_id)
        for id in stage["allowed_class_ids"]:
            if id not in classes:problem("stage missing class "+stage_id+"/"+id)
        for id in stage["supported_difficulties"]:
            if id not in difficulty:problem("stage unknown difficulty "+stage_id+"/"+id)
        for id in stage["allowed_modes"]:
            if id not in modes:problem("stage unknown mode "+stage_id+"/"+id)
        for tier,boss in stage["boss_by_difficulty"].items():
            if tier!="default" and tier not in difficulty:problem("stage unknown boss tier "+stage_id+"/"+tier)
            if boss not in bosses:problem("stage missing boss "+stage_id+"/"+boss)
            elif stage_id not in bosses[boss]["stages"]:problem("boss-stage inverse link missing "+boss+"/"+stage_id)
    for boss_id,boss in bosses.items():
        if not boss["stages"]:problem("orphan boss "+boss_id)
        for id in boss["stages"]:
            if id not in stages:problem("boss unknown stage "+boss_id+"/"+id)
        if boss["min_difficulty_tier"]>4:problem("boss impossible tier "+boss_id)
    event_types={"win","boss_defeated","class_mastery","stage_complete","run_finished"}
    for uid,rule in unlocks.items():
        if not rule["all"]:problem("unlock missing AND conditions "+uid)
        for cond in rule["all"]:
            if cond["event"] not in event_types:problem("unknown unlock event "+uid)
            if "stage_id" in cond and cond["stage_id"] not in stages:problem("unknown stage in unlock "+uid)
            if "difficulty_id" in cond and cond["difficulty_id"] not in difficulty:problem("unknown difficulty in unlock "+uid)
            if "boss_id" in cond and cond["boss_id"] not in bosses:problem("unknown boss in unlock "+uid)
            if "distinct_stage_count" in cond and cond["distinct_stage_count"]>len(stages):
                problem("unreachable multi-stage unlock "+uid)
    for id,mode in modes.items():
        if mode["unlock_id"] is not None and mode["unlock_id"] not in unlocks:
            problem("unknown mode unlock "+id)
        for other in mode["excludes"]:
            if other not in modes or id not in modes[other]["excludes"]:
                problem("asymmetric mode exclusion "+id+"/"+other)
    for cls in classes.values():
        if cls["planned_first_playable"] and not any(cls["id"] in st["allowed_class_ids"] for st in stages.values()):
            problem("no stage for first-playable class "+cls["id"])
    for name,t in talents.items():
        if t["acquisition"]=="purchase":
            if t["cost_currency_id"] not in currencies:problem("talent purchase missing currency "+name)
            if len(t["rank_costs"])!=t["max_rank"]:problem("invalid rank cost list "+name)
            if any(v<=0 for v in t["rank_costs"]):problem("invalid talent cost "+name)
        elif t["acquisition"]=="mastery_level":
            if t["cost_currency_id"] is not None or t["rank_costs"] or t["required_mastery_level"]<1:
                problem("mastery talent must not spend currency "+name)
        else:problem("unknown acquisition "+name)
        for op in t["effect_ops"]:
            if "status_id" in op and op["status_id"] not in statuses:problem("unknown effect status "+name)
            if "skill_id" in op and op["skill_id"] not in skills:problem("unknown effect skill "+name)
    check_graph(talents,lambda t:t["prerequisites"],"early talent")
    check_graph(late,lambda t:t["requires"],"late talent")
    for t in late.values():
        if t["cost_currency_id"] not in currencies:problem("late talent unknown currency "+t["id"])
    for scenario_id,scenario in scenarios.items():
        for key,reg in [("class_id",classes),("stage_id",stages),("difficulty_id",difficulty),("profile_fixture",profiles)]:
            if scenario[key] not in reg:problem("bot scenario unknown "+key+" "+scenario_id)
        for mid in scenario["modes"]:
            if mid not in modes:problem("bot scenario unknown mode "+scenario_id+"/"+mid)
        pf=profiles.get(scenario["profile_fixture"])
        if pf and (scenario["difficulty_id"] not in pf["unlocked_difficulty_ids"] or
                   scenario["class_id"] not in pf["unlocked_class_ids"]):
            problem("bot scenario tests locked content without fixture "+scenario_id)
        st=stages.get(scenario["stage_id"])
        if st and scenario["difficulty_id"] not in st["supported_difficulties"]:
            problem("bot scenario invalid stage difficulty "+scenario_id)
    for p in profiles.values():
        for id in p["unlocked_difficulty_ids"]:
            if id not in difficulty:problem("unknown profile difficulty "+id)
        for id in p["unlocked_class_ids"]:
            if id not in classes:problem("unknown profile class "+id)
        for cid in p["mastery_level_by_class"]:
            if cid not in classes:problem("unknown profile mastery class "+cid)
        for cid,v in p["currency_balances"].items():
            if cid not in currencies or v<0:problem("unknown/negative profile currency "+cid)
    if set(reward["dao_seals_allowed_difficulties"])!={"difficulty.tribulation","difficulty.abyss"}:
        problem("late currency allowlist changed")
    for id,d in difficulty.items():
        if (d["dao_seals_on_clear"]>0)!=(id in reward["dao_seals_allowed_difficulties"]):
            problem("late currency available on wrong tier "+id)
    if not load("economy_milestones.json")["requires_verified_progress"]:
        problem("time-only farming enabled")
    for id,x in milestone.items():
        if x["minimum_kills"]<=0:problem("unrestricted time reward "+id)
    if reward["endless_dao_seals"]!="first_complete_cycle_only":
        problem("endless late-currency farm")
    oldids=set()
    for rule in compat["mappings"]:
        if rule["source"] in oldids:problem("duplicate legacy mapping "+rule["source"])
        oldids.add(rule["source"])
        if rule["action"]=="requires_explicit_rules_conversion" and "non-equivalent" not in compat["run_snapshot_migration"]:
            problem("non-equivalent mode mapping must reject old run snapshots")
    for required in ("unlock.tribulation","unlock.abyss"):
        if len(unlocks[required]["all"])<2:problem("late unlock diluted "+required)
    validate_enemies(difficulty, stages, statuses, modes, scenarios, trs)
    for msg in check_localization_context(load("localization_context.json"),trs):problem(msg)
    for msg in check_settings((DATA/"settings.example.cfg").read_text(encoding="utf-8")):problem(msg)
    print("Checked catalogs:",sum(map(len,(classes,skills,statuses,bosses,stages,talents,late,scenarios,profiles,unlocks,modes,difficulty))),"definitions")
    print("Checked RU/EN keys:",len(trs))
def main():
    try:run()
    except Exception as e:problem("validator crashed: "+repr(e))
    for msg in ERRORS:print("FAIL:",msg,file=sys.stderr)
    if ERRORS:raise SystemExit(1)
    print("PASS: connected v7 game-design catalogs and anti-farm rules (not runtime)")
if __name__=="__main__":main()
