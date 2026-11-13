class_name UpgradeCard
extends RefCounted
## Text of one level-up card (ADR-010 section 6): the name, the stat line "before -> after"
## and the rank after the pick. The "after" value comes from applying the upgrade to a copy
## of the world, so the card always shows what the simulation will do. Presentation only.


## Translation key stem of a card: upgrade.p0.sword_damage -> UPGRADE_P0_SWORD_DAMAGE.
static func key_stem(code: int) -> String:
	return UpgradeSystem.card_id(code).replace(".", "_").to_upper()


## {"name", "stat", "rank"} in the current locale; "rank" is empty for recover.
static func describe(config: SimConfig, world: WorldState, code: int) -> Dictionary:
	var after: WorldState = world.copy()
	UpgradeSystem.apply_upgrade(after, code)
	var stem: String = key_stem(code)
	var rank: String = ""
	if code < UpgradeSystem.MAX_RANKS.size():
		rank = UiText.text("UI_UPGRADE_RANK") % [after.ranks[code], UpgradeSystem.MAX_RANKS[code]]
	return {
		"name": UiText.text(stem + "_NAME"),
		"stat": UiText.text(stem + "_DESC") % [stat(config, world, code), stat(config, after, code)],
		"rank": rank,
	}


## The value the card changes, in player units: px/s, HP, px, swords, attacks/s, enemies.
static func stat(config: SimConfig, world: WorldState, code: int) -> String:
	match code:
		UpgradeSystem.SPEED:
			var per_second: float = UpgradeSystem.hero_speed(config, world) * float(Fx.TICKS_PER_SECOND)
			return str(roundi(per_second / Fx.FX_ONE))
		UpgradeSystem.VITALITY:
			return _hp(world.hero_hp_max)
		UpgradeSystem.PICKUP:
			return str(roundi(float(UpgradeSystem.pickup_radius(config, world)) / Fx.FX_ONE))
		UpgradeSystem.COUNT:
			return str(UpgradeSystem.projectile_count(world))
		UpgradeSystem.DAMAGE:
			return _hp(UpgradeSystem.skill_damage(config, world))
		UpgradeSystem.HASTE:
			var rate: float = float(UpgradeSystem.skill_rate(world)) * Fx.TICKS_PER_SECOND
			return "%.2f" % (rate / maxf(1.0, float(config.skill_period_mt)))
		UpgradeSystem.PIERCE:
			return str(UpgradeSystem.projectile_pierce(config, world) + 1)
		UpgradeSystem.RECOVER:
			return _hp(world.hero_hp)
	return "?"


## Milli-HP shown as whole HP.
static func _hp(mhp: int) -> String:
	return str(roundi(mhp / 1000.0))
