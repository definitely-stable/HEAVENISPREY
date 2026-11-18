"""ADR-012 §6 oracle for the P0 Spirit Stones preview (no currency settlement)."""
from __future__ import annotations

import hashlib
import re
from decimal import Decimal, InvalidOperation

POLICY_ID = "hip-reward-preview-v1"
MILESTONE_ID = "reward.minute3"
RUN_UID = re.compile(r"[0-9a-f]{32}")


def test_run_uid(scenario_id: str, seed: str) -> str:
    data = f"hip-run-uid-test-v1\n{scenario_id}\n{seed}".encode("utf-8")
    return hashlib.sha256(data).hexdigest()[:32]


def compute(receipt_fields: dict, catalogs: dict) -> dict:
    uid = receipt_fields["run_uid"]
    if not RUN_UID.fullmatch(uid):
        raise ValueError("invalid_run_uid")
    if receipt_fields["result"] not in ("victory", "defeat", "abandoned"):
        raise ValueError("invalid_result")
    difficulties = {row["id"]: row for row in catalogs["difficulty_profiles"]["profiles"]}
    difficulty = difficulties.get(receipt_fields["difficulty_id"], {})
    multiplier = difficulty.get("spirit_stones_mult")
    if type(multiplier) not in (int, float):
        raise ValueError("invalid_difficulty_multiplier")
    try:
        diff_milli = Decimal(str(multiplier)) * 1000
    except InvalidOperation as exc:
        raise ValueError("invalid_difficulty_multiplier") from exc
    if not diff_milli.is_finite() or not 0 <= diff_milli <= 9007199254740991 or diff_milli % 1 != 0:
        raise ValueError("invalid_difficulty_multiplier")
    modes = {row["id"]: row for row in catalogs["modes"]["profiles"]}
    eligible = True
    for mode_id in receipt_fields["mode_ids"]:
        mode = modes.get(mode_id, {})
        if type(mode.get("reward_eligible")) is not bool or not isinstance(mode.get("effect", {}), dict):
            raise ValueError("invalid_mode")
        if "spirit_stones_reward_mult" in mode.get("effect", {}):
            raise ValueError("unsupported_mode_multiplier")
        eligible = eligible and mode["reward_eligible"]
    milestone = next(
        item for item in catalogs["economy_milestones"]["milestones"] if item["id"] == MILESTONE_ID
    )
    if not eligible or (
        receipt_fields["survived_ticks"] < milestone["at_game_minute"] * 3600
        or receipt_fields["kills"] < milestone["minimum_kills"]
    ):
        return {"reward_events": [], "stones_preview": 0}
    stones = milestone["stones"]
    return {
        "reward_events": [{"source_id": MILESTONE_ID, "reward_event_id": f"{MILESTONE_ID}:{uid}:0", "stones": stones}],
        "stones_preview": stones * int(diff_milli) // 1000,
    }
