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
    print("Checked catalogs:",sum(map(len,(classes,skills,statuses,bosses,stages,talents,late,scenarios,profiles,unlocks,modes,difficulty))),"definitions")
    print("Checked RU/EN keys:",len(trs))
def main():
    try:run()
    except Exception as e:problem("validator crashed: "+repr(e))
    for msg in ERRORS:print("FAIL:",msg,file=sys.stderr)
    if ERRORS:raise SystemExit(1)
    print("PASS: connected v7 game-design catalogs and anti-farm rules (not runtime)")
if __name__=="__main__":main()
