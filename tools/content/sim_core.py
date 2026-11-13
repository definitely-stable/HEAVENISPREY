"""Reference of the P0-01b simulation core: PlayerCommand log + hero movement (ADR-008).

Oracle for game/core/sim/{command_log,world_state,sim_kernel}.gd. Integers only
(hip-fx-v1 via tools/content/fx.py). Golden traces:
    python tools/content/sim_core.py            # rewrite game/tests/fixtures/sim_core_vectors.json
    python tools/content/sim_core.py --check    # fail if the committed file differs
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VECTORS_PATH = ROOT / "game" / "tests" / "fixtures" / "sim_core_vectors.json"
VECTORS_SCHEMA_VERSION = 1

_spec = importlib.util.spec_from_file_location("hip_fx", Path(__file__).with_name("fx.py"))
fx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fx)

AXIS_Q14 = 16384
DIAG_Q14 = 11585

OK = "ok"
INVALID = "invalid_command"
PAST_TICK = "past_tick"
TICK_NOT_MONOTONIC = "tick_not_monotonic"
SEQUENCE_NOT_INCREASING = "sequence_not_increasing"


def ints_digest(values: list[int]) -> str:
    """SHA-256 of little-endian int64 bytes (PackedInt64Array.to_byte_array())."""
    return hashlib.sha256(struct.pack("<%dq" % len(values), *values)).hexdigest()


class CommandLog:
    def __init__(self):
        self.records: list[tuple[int, int, int, int]] = []

    def append(self, command: tuple[int, int, int, int], next_tick: int) -> str:
        tick, sequence, move_x, move_y = command
        if tick < 0 or sequence < 0 or abs(move_x) > 1 or abs(move_y) > 1:
            return INVALID
        if tick < next_tick:
            return PAST_TICK
        if self.records:
            if tick < self.records[-1][0]:
                return TICK_NOT_MONOTONIC
            if sequence <= self.records[-1][1]:
                return SEQUENCE_NOT_INCREASING
        self.records.append(command)
        return OK

    def digest(self) -> str:
        return ints_digest([v for record in self.records for v in record])


def config_valid(c: list[int]) -> bool:
    speed, r, min_x, min_y, max_x, max_y, start_x, start_y = c
    return (all(abs(v) <= fx.COORD_MAX for v in c) and speed >= 0 and r > 0
            and max_x - min_x >= 2 * r and max_y - min_y >= 2 * r
            and min_x + r <= start_x <= max_x - r and min_y + r <= start_y <= max_y - r)


def direction_q14(move_x: int, move_y: int) -> tuple[int, int]:
    if move_x != 0 and move_y != 0:
        return (fx.sign(move_x) * DIAG_Q14, fx.sign(move_y) * DIAG_Q14)
    return (fx.sign(move_x) * AXIS_Q14, fx.sign(move_y) * AXIS_Q14)


class World:
    def __init__(self, config: list[int]):
        self.tick = 0
        self.player_x, self.player_y = config[6], config[7]
        self.move_x = self.move_y = 0
        self.command_cursor = 0

    def ints(self) -> list[int]:
        return [self.tick, self.player_x, self.player_y, self.move_x, self.move_y,
                self.command_cursor]

    def digest(self) -> str:
        return ints_digest(self.ints())


def step(config: list[int], world: World, log: CommandLog) -> None:
    while world.command_cursor < len(log.records) and \
            log.records[world.command_cursor][0] <= world.tick:
        _, _, world.move_x, world.move_y = log.records[world.command_cursor]
        world.command_cursor += 1
    qx, qy = direction_q14(world.move_x, world.move_y)
    speed, r, min_x, min_y, max_x, max_y = config[:6]
    world.player_x = min(max(world.player_x + fx.mul_q14(speed, qx), min_x + r), max_x - r)
    world.player_y = min(max(world.player_y + fx.mul_q14(speed, qy), min_y + r), max_y - r)
    world.tick += 1


# Movement hypothesis for traces only (not canon): 0.1 cell/tick with cell = 2 radii
# (GAME-ARCH-02 fixture assumptions), radius 24 px -> 4800 su/tick.
BASE = [4800, 24000, 0, 0, 1536000, 960000, 768000, 480000]

SCENARIOS = [
    ("idle", BASE, [], 120),
    ("east_one_second", BASE, [(0, 0, 1, 0)], 60),
    ("diagonal_north_west", BASE, [(0, 0, -1, -1)], 60),
    ("held_then_released", BASE, [(0, 0, 0, 1), (30, 1, 0, 0)], 90),
    ("clamp_east_wall", BASE, [(0, 0, 1, 0)], 400),
    ("clamp_corner", BASE, [(5, 0, 1, 1)], 600),
    ("same_tick_last_wins", BASE, [(10, 0, 1, 0), (10, 1, -1, 0), (10, 2, 0, -1)], 40),
    ("zigzag", BASE, [(t, t // 7, (1, -1)[(t // 7) % 2], (t // 14) % 3 - 1)
                      for t in range(0, 700, 7)], 720),
    ("odd_speed_symmetry", [4801, 1000, -500000, -500000, 500000, 500000, 0, 0],
     [(0, 0, 1, 1), (100, 1, -1, -1)], 200),
    ("five_minutes", BASE, [(t, t // 90, ((t // 90) % 3) - 1, ((t // 270) % 3) - 1)
                            for t in range(0, 18000, 90)], 18000),
]

APPEND_CASES = [
    ("accepts_first", [], (0, 0, 1, 0), 0, OK),
    ("rejects_past_tick", [], (4, 0, 1, 0), 5, PAST_TICK),
    ("rejects_bad_axis", [], (0, 0, 2, 0), 0, INVALID),
    ("rejects_negative_tick", [], (-1, 0, 0, 0), 0, INVALID),
    ("rejects_older_tick", [(10, 0, 1, 0)], (9, 1, 0, 0), 0, TICK_NOT_MONOTONIC),
    ("rejects_repeated_sequence", [(10, 3, 1, 0)], (11, 3, 0, 0), 0, SEQUENCE_NOT_INCREASING),
    ("accepts_same_tick_next_sequence", [(10, 3, 1, 0)], (10, 4, 0, 1), 0, OK),
]


def _checkpoints(ticks: int) -> list[int]:
    marks = {1, 2, 30, 60, ticks}
    marks.update(range(600, ticks, 600))
    return sorted(m for m in marks if m <= ticks)


def build_vectors() -> dict:
    traces = []
    for name, config, commands, ticks in SCENARIOS:
        assert config_valid(config), name
        log, world = CommandLog(), World(config)
        for command in commands:
            assert log.append(command, 0) == OK, (name, command)
        marks, checkpoints = _checkpoints(ticks), []
        for t in range(1, ticks + 1):
            step(config, world, log)
            if t in marks:
                checkpoints.append({"tick": world.tick, "player_x": str(world.player_x),
                                    "player_y": str(world.player_y), "digest": world.digest()})
        traces.append({"name": name, "config": [str(v) for v in config],
                       "commands": [[str(v) for v in c] for c in commands], "ticks": ticks,
                       "log_digest": log.digest(), "checkpoints": checkpoints})
    appends = []
    for name, existing, command, next_tick, expected in APPEND_CASES:
        log = CommandLog()
        for record in existing:
            assert log.append(record, 0) == OK
        got = log.append(command, next_tick)
        assert got == expected, (name, got)
        appends.append({"name": name, "existing": [list(r) for r in existing],
                        "command": list(command), "next_tick": next_tick, "expected": expected})
    return {"schema_version": VECTORS_SCHEMA_VERSION, "kind": "hip-sim-core-vectors",
            "policy_id": fx.POLICY_ID, "generator": "tools/content/sim_core.py",
            "note": "movement constants here are trace inputs, not canonical tuning",
            "traces": traces, "append_cases": appends}


def vectors_bytes() -> bytes:
    return (json.dumps(build_vectors(), sort_keys=True, indent=1) + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    expected = vectors_bytes()
    rel = VECTORS_PATH.relative_to(ROOT).as_posix()
    if "--check" in argv:
        if not VECTORS_PATH.is_file() or VECTORS_PATH.read_bytes() != expected:
            print("FAIL: " + rel + " differs from the reference")
            return 1
        print("OK: sim core vectors match the reference")
        return 0
    VECTORS_PATH.write_bytes(expected)
    print("written " + rel + " (%d bytes)" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
