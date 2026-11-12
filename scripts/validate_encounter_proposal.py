#!/usr/bin/env python3
"""GAME-ARCH-02 reference oracle: arena geometry, waves, telegraphs, boss pattern, escape routes,
special reward sources and event order (GAME-ARCH-04 adjacent checks).

Design-only. Reads canonical v7 attacks, enemies, rosters, bosses and stages without
changing them; every geometric constant is a declared hypothesis in the fixture.
No Godot runtime, no pathfinding claims beyond a grid model, no balance. Stdlib only.
"""
from __future__ import annotations

import argparse
import heapq
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / ".work/proposals/game-arch-02-encounters/reference_stage.json"
ARCH02 = ROOT / ".work/proposals/arch-02-recipe-graph/reference_graph.json"
CANONICAL = ROOT / ".work/config/v7"
ORIGINS = {"primary", "echo", "proc", "zone", "summon", "dot", "reaction"}
CAP_FOR_KIND = {"PROJECTILE": "simultaneous_projectile_casts_winding_up", "CHARGE": "simultaneous_charge_windups",
                "GROUND_ZONE": "active_control_zones", "ON_DEATH_ZONE": "active_death_hazards"}


class ContractError(ValueError):
    pass


def must(cond: bool, code: str, message: str) -> None:
    if not cond:
        raise ContractError(code + ": " + message)


def load(path: Path = FIXTURE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical(path: Path = CANONICAL) -> dict:
    def rows(name, key):
        return {x["id"]: x for x in json.loads((path / name).read_text(encoding="utf-8"))[key]}
    return {"attacks": rows("enemy_attacks.json", "attacks"), "enemies": rows("enemies.json", "enemies"),
            "rosters": rows("enemy_rosters.json", "rosters"), "bosses": rows("bosses.json", "bosses"),
            "stages": rows("stages.json", "stages"), "statuses": rows("statuses.json", "statuses")}


# ---------------------------------------------------------------- grid

class Grid:
    def __init__(self, topo: dict):
        self.rows = topo["terrain"]
        self.h, self.w = len(self.rows), len(self.rows[0])
        must(all(len(r) == self.w for r in self.rows), "E_TERRAIN", "ragged terrain rows")
        must(set("".join(self.rows)) <= set(topo["legend"]), "E_TERRAIN", "unknown terrain symbol")
        self.soft = topo["soft_speed_multiplier"]

    def at(self, c):
        x, y = c
        return self.rows[y][x] if 0 <= x < self.w and 0 <= y < self.h else "#"

    def walkable(self, c):
        return self.at(c) != "#"

    def cells(self):
        return [(x, y) for y in range(self.h) for x in range(self.w) if self.walkable((x, y))]

    def neighbours(self, c):
        x, y = c
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if self.walkable(n):
                yield n

    def step_cost(self, c):
        return 1 / self.soft if self.at(c) == "~" else 1.0

    def costs(self, start, budget=math.inf):
        """Movement cost in cells (soft cells cost more) from start, up to budget."""
        dist, heap = {start: 0.0}, [(0.0, start)]
        while heap:
            d, c = heapq.heappop(heap)
            if d > dist[c]:
                continue
            for n in self.neighbours(c):
                nd = d + self.step_cost(n)
                if nd <= budget + 1e-9 and nd < dist.get(n, math.inf):
                    dist[n] = nd
                    heapq.heappush(heap, (nd, n))
        return dist


def max_corridor(grid: Grid) -> int:
    """Longest straight run of 1-wide cells (open along one axis, walled on the other)."""
    best = 0
    for horizontal in (True, False):
        for y in range(grid.h):
            run = 0
            for x in range(grid.w):
                c = (x, y) if horizontal else (y, x)
                if not (0 <= c[0] < grid.w and 0 <= c[1] < grid.h):
                    run = 0
                    continue
                side = [(c[0], c[1] - 1), (c[0], c[1] + 1)] if horizontal else [(c[0] - 1, c[1]), (c[0] + 1, c[1])]
                corridor = grid.walkable(c) and not any(grid.walkable(s) for s in side)
                run = run + 1 if corridor else 0
                best = max(best, run)
    return best


def check_topology(fx: dict) -> dict:
    a, topo = fx["assumptions"], fx["topology"]
    grid = Grid(topo)
    cells = grid.cells()
    start = tuple(topo["player_start"])
    must(grid.walkable(start), "E_TOPOLOGY", "player start is blocked")
    reach = grid.costs(start)
    must(len(reach) == len(cells), "E_ISOLATED_POCKET", f"{len(cells) - len(reach)} walkable cells unreachable from start")
    corridor = max_corridor(grid)
    must(corridor <= a["max_corridor_length"], "E_TRAP_CORRIDOR", f"1-wide corridor of length {corridor}")
    lanes = [c for c in cells if grid.at(c) == "S"]
    must(bool(lanes), "E_SPAWN", "no spawn lane")
    for c in cells:
        must(any(math.dist(c, s) >= a["min_spawn_distance_cells"] for s in lanes), "E_SPAWN",
             f"no legal spawn lane for a player at {c}")
    arena = topo["boss_arena"]
    centre = tuple(arena["center"])
    for y in range(grid.h):
        for x in range(grid.w):
            if math.dist((x, y), centre) <= arena["radius_cells"]:
                must(grid.walkable((x, y)), "E_ARENA_BLOCKER", f"solid cell {(x, y)} inside boss arena")
    return {"grid": grid, "walkable_cells": len(cells), "max_corridor": corridor, "spawn_cells": len(lanes)}


def check_pois(fx: dict, grid: Grid, duration: int) -> dict:
    a = fx["assumptions"]
    tps, speed = a["ticks_per_second"], a["player_speed_cells_per_tick"]
    worst = {}
    for poi in fx["pois"]:
        cell = tuple(poi["cell"])
        must(grid.walkable(cell), "E_POI", poi["id"] + " on a blocked cell")
        must(0 <= poi["reveal_second"] < poi["expire_second"] <= duration, "E_POI", poi["id"] + " window outside run")
        window = (poi["expire_second"] - poi["reveal_second"]) * tps
        far = max(grid.costs(cell).values())
        travel = math.ceil(far / speed)
        must(travel <= a["poi_travel_share_of_window"] * window, "E_POI_REACH",
             f"{poi['id']}: worst travel {travel} ticks exceeds share of window {window}")
        must(travel + poi["channel_ticks"] <= window, "E_POI_REACH", poi["id"] + ": travel + channel exceeds window")
        worst[poi["id"]] = travel
    return worst


# ---------------------------------------------------------------- telegraphs (canonical attacks)

def escape_need(attack: dict, a: dict) -> float:
    kind, p = attack["kind"], attack["params"]
    if kind in ("MELEE_ARC", "GROUND_ZONE"):
        return p["radius_mult"] * a["hazard_base_radius_cells"]
    if kind == "ON_DEATH_ZONE":
        return p.get("radius_mult", 1) * a["hazard_base_radius_cells"]
    if kind == "CHARGE":
        return a["charge_lane_half_width_cells"]
    if kind == "PROJECTILE":
        return a["projectile_sidestep_cells"]
    raise ContractError("E_ATTACK_KIND: " + kind)


def check_attacks(fx: dict, canon: dict) -> dict:
    a = fx["assumptions"]
    speed = a["player_speed_cells_per_tick"]
    slack = {}
    for aid, atk in sorted(canon["attacks"].items()):
        p = atk["params"]
        if atk["kind"] == "CONTACT":
            must(p["hit_interval_ticks"] >= a["min_contact_interval_ticks"], "E_CONTACT", aid + " hits too often")
            continue
        must(atk["telegraph_ticks"] >= a["min_telegraph_ticks"], "E_TELEGRAPH", aid + " telegraph below minimum")
        if atk["kind"] in ("MELEE_ARC", "CHARGE", "PROJECTILE"):
            must(atk["recovery_ticks"] > 0, "E_PUNISH", aid + " has no recovery window")
        if atk["kind"] == "CHARGE":
            must(p["can_retarget"] is False, "E_RETARGET", aid + " retargets after tell")
        if atk["kind"] == "PROJECTILE":
            must(p["homing"] is False and p["aim_lock"] == "telegraph_end", "E_RETARGET", aid + " tracks after tell")
        slack[aid] = round(speed * atk["telegraph_ticks"] - escape_need(atk, a), 3)
        must(slack[aid] >= 0, "E_NO_ESCAPE", f"{aid}: {speed * atk['telegraph_ticks']:.2f} cells < {escape_need(atk, a):.2f}")
    return slack


def check_waves(fx: dict, canon: dict) -> dict:
    """Roster windows, threat-cap coverage, timeline spikes and the MIXED slow scenario."""
    a, stage = fx["assumptions"], canon["stages"][fx["stage_id"]]
    duration = stage["duration_minutes"] * 60
    roster = canon["rosters"][stage["enemy_roster_id"]]
    edge = 0
    mixed = {}
    for w in roster["windows"]:
        must(w["start_second"] == edge and w["end_second"] > edge, "E_WINDOWS", w["id"] + " leaves a gap or overlap")
        edge = w["end_second"]
        attacks = [canon["attacks"][x] for e in w["weighted_enemies"] for x in canon["enemies"][e["enemy_id"]]["attack_ids"]]
        for atk in attacks:
            cap = CAP_FOR_KIND.get(atk["kind"])
            must(cap is None or cap in roster["threat_caps"], "E_THREAT_CAP", f"{w['id']}: {atk['id']} has no governing cap")
        slows = [canon["statuses"][x["apply_status_id"]].get("movement_speed_multiplier", 1)
                 for x in attacks if x["apply_status_id"]]
        slow = min(slows, default=1)
        if slow < 1:
            for atk in attacks:
                if atk["kind"] == "CONTACT":
                    continue
                budget = a["player_speed_cells_per_tick"] * slow * atk["telegraph_ticks"]
                mixed[f"{w['id']}:{atk['id']}"] = round(budget - escape_need(atk, a), 3)
                must(budget >= escape_need(atk, a), "E_NO_ESCAPE",
                     f"{w['id']}: {atk['id']} under slow {slow} needs {escape_need(atk, a)} cells, has {budget:.2f}")
    must(edge == duration, "E_WINDOWS", "roster windows do not cover the stage")
    spikes = sorted(e["second"] for e in fx["timeline"] if e["spike"])
    last = None
    for e in sorted(fx["timeline"], key=lambda e: e["second"]):
        must(0 < e["second"] <= duration, "E_TIMELINE", e["id"] + " outside stage")
        if e["kind"] == "chest_carrier":
            must(e["carrier_enemy_id"] in canon["enemies"], "E_TIMELINE", "unknown carrier enemy")
    for x, y in zip(spikes, spikes[1:]):
        must(y - x >= a["spike_min_gap_seconds"], "E_NO_RECOVERY", f"spikes at {x}s and {y}s leave no recovery window")
    return {"duration": duration, "mixed_slow_slack": mixed, "spikes": spikes}


# ---------------------------------------------------------------- boss pattern

def hazard_cells(grid: Grid, attack: dict, centre, player) -> set:
    shape = attack["shape"]
    out = set()
    if shape == "summon":
        return out
    for c in grid.cells():
        d = math.dist(c, centre)
        if shape == "circle" and d <= attack["radius"]:
            out.add(c)
        elif shape == "ring" and attack["inner"] <= d <= attack["outer"]:
            out.add(c)
        elif shape == "lane":
            dx, dy = player[0] - centre[0], player[1] - centre[1]
            norm = math.hypot(dx, dy) or 1.0
            ux, uy = (dx / norm, dy / norm) if (dx or dy) else (1.0, 0.0)
            rx, ry = c[0] - centre[0], c[1] - centre[1]
            along = rx * ux + ry * uy
            across = abs(rx * uy - ry * ux)
            if 0 <= along <= attack["length"] and across <= attack["half_width"]:
                out.add(c)
    return out


def escape_slack(fx: dict, grid: Grid, attacks: list) -> float:
    """Minimum over player cells in the arena of (movement budget - cost to the nearest safe cell)."""
    arena = fx["topology"]["boss_arena"]
    centre = tuple(arena["center"])
    budget = fx["assumptions"]["player_speed_cells_per_tick"] * min(x["telegraph_ticks"] for x in attacks)
    worst = math.inf
    for p in grid.cells():
        if math.dist(p, centre) > arena["radius_cells"] or p == centre:
            continue
        danger = set().union(*(hazard_cells(grid, x, centre, p) for x in attacks))
        reach = grid.costs(p, budget)
        safe = [d for c, d in reach.items() if c not in danger]
        must(bool(safe), "E_NO_ESCAPE", f"no safe cell within {budget:.1f} from {p} for "
             + "+".join(x["id"] for x in attacks))
        worst = min(worst, budget - min(safe))
    return round(worst, 3)


def check_boss(fx: dict, canon: dict, grid: Grid) -> dict:
    bp = fx["boss_pattern"]
    boss = canon["bosses"].get(bp["boss_ref"])
    must(boss is not None and fx["stage_id"] in boss["stages"], "E_BOSS_REF", bp["boss_ref"])
    must(not set(bp["immunities"]) & ORIGINS, "E_BUILD_FAMILY", "boss immune to a whole damage origin")
    must(bool(bp["control_policy"].get("fallback")), "E_BUILD_FAMILY", "control resistance needs a fallback")
    attacks = {x["id"]: x for x in bp["attacks"]}
    for x in attacks.values():
        must(x["telegraph_ticks"] >= bp["min_telegraph_ticks"], "E_TELEGRAPH", x["id"])
        must(x["recovery_ticks"] > 0, "E_PUNISH", x["id"] + " has no recovery")
        if x["shape"] == "summon":
            must(x["enemy_id"] in canon["enemies"], "E_BOSS_REF", x["id"] + " summons unknown enemy")
    hp = 100
    slacks, breathers = {}, {}
    for ph in bp["phases"]:
        must(ph["hp_from"] == hp and ph["hp_to"] < ph["hp_from"], "E_PHASES", ph["id"] + " hp thresholds not contiguous")
        hp = ph["hp_to"]
        must(0 < ph["transition_ticks"] <= bp["max_transition_ticks"], "E_TRANSITION", ph["id"] + " transition too long")
        windows = []
        for aid, start in ph["rotation"]:
            x = attacks[aid]
            end = start + x["telegraph_ticks"] + x["active_ticks"]
            must(end + x["recovery_ticks"] <= ph["rotation_ticks"], "E_ROTATION", f"{ph['id']}: {aid} spills past rotation")
            windows.append((start, end, aid))
        declared = {frozenset(o) for o in ph["overlaps"]}
        for i, (s1, e1, a1) in enumerate(windows):
            for s2, e2, a2 in windows[i + 1:]:
                if s1 < e2 and s2 < e1 and attacks[a1]["shape"] != "summon" and attacks[a2]["shape"] != "summon":
                    must(frozenset((a1, a2)) in declared, "E_UNDECLARED_OVERLAP", f"{ph['id']}: {a1} + {a2}")
        busy = sorted((s, e) for s, e, _ in windows)
        gaps, cursor = [], 0
        for s, e in busy:
            gaps.append(s - cursor)
            cursor = max(cursor, e)
        gaps[0] += ph["rotation_ticks"] - cursor   # the rotation loops: tail gap joins the head gap
        breathers[ph["id"]] = max(gaps)
        must(max(gaps) >= bp["min_punish_ticks"], "E_NO_PUNISH_WINDOW", ph["id"] + " never pauses")
        for aid, _ in ph["rotation"]:
            if attacks[aid]["shape"] != "summon":
                slacks[aid] = escape_slack(fx, grid, [attacks[aid]])
        for group in ph["overlaps"]:
            slacks["+".join(sorted(group))] = escape_slack(fx, grid, [attacks[a] for a in group])
    must(hp == 0, "E_PHASES", "phases do not reach 0 hp")
    return {"escape_slack": slacks, "breather_ticks": breathers}


# ---------------------------------------------------------------- rewards and event order

def process_log(fx: dict, events: list) -> dict:
    """Deterministic reward resolution: dedupe by uid, order by (tick, phase, uid), gate every grant."""
    tps = fx["assumptions"]["ticks_per_second"]
    rank = {p: i for i, p in enumerate(fx["event_phases"])}
    pois = {p["id"]: p for p in fx["pois"]}
    encounters = {e["id"]: e for e in fx["timeline"]}
    sources = fx["reward_sources"]
    run_uid = fx["golden_log"]["run_uid"]
    unique = {}
    for ev in events:
        if ev["uid"] in unique:
            must(unique[ev["uid"]] == ev, "E_EVENT_CONFLICT", "uid " + ev["uid"] + " reused with different payload")
            continue
        must(ev["phase"] in rank, "E_EVENT_PHASE", ev["uid"])
        unique[ev["uid"]] = ev
    ordered = sorted(unique.values(), key=lambda e: (e["tick"], rank[e["phase"]], e["uid"]))
    revealed, completed, dead, drops, picked = {}, set(), {}, {}, set()
    rewards, queue, gate_count = [], [], {}

    def grant(source, instance):
        rid = f"{source['id']}:{run_uid}:{instance}"
        must(rid not in rewards, "E_REWARD_TWICE", rid)
        rewards.append(rid)
        queue.append(source["gate"])
        gate_count[source["gate"]] = gate_count.get(source["gate"], 0) + 1

    for ev in ordered:
        k = ev["kind"]
        if k == "POI_REVEALED":
            poi = pois.get(ev["poi_id"])
            must(poi is not None and ev["tick"] >= poi["reveal_second"] * tps, "E_POI_GATE", ev["uid"] + " early reveal")
            revealed[ev["poi_id"]] = ev["tick"]
        elif k == "POI_CHANNEL_COMPLETE":
            poi = pois[ev["poi_id"]]
            must(ev["poi_id"] in revealed, "E_POI_GATE", ev["uid"] + " channel on hidden POI")
            must(ev["tick"] - revealed[ev["poi_id"]] >= poi["channel_ticks"], "E_POI_GATE", ev["uid"] + " channel too short")
            must(ev["tick"] <= poi["expire_second"] * tps, "E_POI_GATE", ev["uid"] + " after expiry")
            must(ev["poi_id"] not in completed, "E_REWARD_TWICE", ev["poi_id"])
            completed.add(ev["poi_id"])
            for s in sources:
                if s["trigger"] == k and s["poi_id"] == ev["poi_id"]:
                    grant(s, ev["poi_id"])
        elif k == "ENTITY_DIED":
            must(ev["entity_uid"] not in dead, "E_DEATH_TWICE", ev["entity_uid"])
            enc = encounters.get(ev["encounter_id"])
            must(enc is not None and ev["tick"] >= enc["second"] * tps, "E_ENCOUNTER_GATE", ev["uid"])
            dead[ev["entity_uid"]] = ev["encounter_id"]
            for s in sources:
                if s["trigger"] == k and s["encounter_id"] == ev["encounter_id"]:
                    grant(s, ev["entity_uid"])
        elif k == "DROP_SPAWNED":
            must(ev["from_entity_uid"] in dead, "E_DROP_GATE", ev["uid"] + " drop from a living entity")
            drops[ev["drop_uid"]] = dead[ev["from_entity_uid"]]
        elif k == "PICKUP":
            must(ev["drop_uid"] in drops and ev["drop_uid"] not in picked, "E_DROP_GATE", ev["uid"] + " unknown or repeated pickup")
            picked.add(ev["drop_uid"])
            for s in sources:
                if s["trigger"] == k and s["encounter_id"] == drops[ev["drop_uid"]]:
                    grant(s, ev["drop_uid"])
        elif k == "LEVEL_UP":
            queue.append("LEVEL_UP")
        else:
            raise ContractError("E_EVENT_KIND: " + k)
    return {"rewards": rewards, "queue": queue, "gate_count": gate_count}


def check_arch02_consistency(fx: dict, arch02: dict) -> dict:
    """Stage reward sources must supply exactly the gate budget ARCH-02 assumed, no earlier than assumed."""
    out = {}
    pois = {p["id"]: p for p in fx["pois"]}
    encounters = {e["id"]: e for e in fx["timeline"]}
    for gate, spec in arch02["event_gates"].items():
        srcs = [s for s in fx["reward_sources"] if s["gate"] == gate]
        if not srcs:
            continue
        seconds = [pois[s["poi_id"]]["reveal_second"] if "poi_id" in s else encounters[s["encounter_id"]]["second"]
                   for s in srcs]
        must(len(srcs) == spec["max_per_run"], "E_GATE_BUDGET", f"{gate}: stage supplies {len(srcs)}, ARCH-02 assumes {spec['max_per_run']}")
        must(min(seconds) == spec["first_second"], "E_GATE_BUDGET", f"{gate}: first at {min(seconds)}s, ARCH-02 assumes {spec['first_second']}s")
        out[gate] = {"sources": len(srcs), "first_second": min(seconds)}
    return out


def verify(fx: dict | None = None, arch02: dict | None = None) -> dict:
    fx = load() if fx is None else fx
    arch02 = load(ARCH02) if arch02 is None else arch02
    must(fx.get("schema_version") == 1 and fx.get("kind") == "stage_encounter_fixture", "E_FIXTURE", "kind/version")
    must(fx.get("status") == "proposal-only-not-canonical", "E_FIXTURE", "must stay proposal-only")
    canon = canonical()
    must(fx["stage_id"] in canon["stages"], "E_STAGE", fx["stage_id"])
    topo = check_topology(fx)
    waves = check_waves(fx, canon)
    result = {
        "walkable_cells": topo["walkable_cells"], "max_corridor": topo["max_corridor"],
        "poi_worst_travel_ticks": check_pois(fx, topo["grid"], waves["duration"]),
        "attack_escape_slack": check_attacks(fx, canon),
        "mixed_slow_slack": waves["mixed_slow_slack"],
        "boss": check_boss(fx, canon, topo["grid"]),
        "gates": check_arch02_consistency(fx, arch02),
    }
    log = process_log(fx, fx["golden_log"]["events"])
    must(log["rewards"] == fx["golden_log"]["expected_rewards"], "E_GOLDEN", f"rewards {log['rewards']}")
    must(log["queue"] == fx["golden_log"]["expected_choice_queue"], "E_GOLDEN", f"queue {log['queue']}")
    result["rewards"] = len(log["rewards"])
    if "expected" in fx:
        for key, want in fx["expected"].items():
            must(result[key] == want, "E_GOLDEN", f"{key}: expected {want}, got {result[key]}")
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = verify(load(args.fixture))
    except (ContractError, KeyError, TypeError, ValueError) as exc:
        print("FAIL GAME-ARCH-02:", exc)
        return 1
    if args.report:
        print(json.dumps(result, indent=1, sort_keys=True))
    print("PASS GAME-ARCH-02 encounters", json.dumps({"walkable_cells": result["walkable_cells"],
          "boss_checks": len(result["boss"]["escape_slack"]), "attacks": len(result["attack_escape_slack"]),
          "rewards": result["rewards"], "gates": sorted(result["gates"])}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
