class_name UpgradeCard
extends RefCounted
## Text of one level-up card (ADR-010 section 6): the name, the stat line "before -> after"
## and the rank after the pick. The "after" value comes from applying the upgrade to a copy
## of the world, so the card always shows what the simulation will do. Presentation only.


## HUD kit illustration of each upgrade code (ADR-014 section 16), in UpgradeSystem code order.
const ART_PIECES: Array[String] = [
	"art_speed", "art_vitality", "art_pickup", "art_count", "art_damage", "art_haste", "art_pierce", "art_recover",
]
const THUNDER_ART_PIECES: Array[String] = [
	"art_thunder_damage", "art_thunder_haste", "art_thunder_jumps", "art_thunder_reach",
]


## Name of the card illustration of `code` in the HUD kit.
static func art_piece(code: int, form: int = SimConfig.SKILL_PROJECTILE) -> String:
	if form == SimConfig.SKILL_CHAIN and code >= UpgradeSystem.THUNDER_DAMAGE and code <= UpgradeSystem.THUNDER_REACH:
		return THUNDER_ART_PIECES[code - UpgradeSystem.THUNDER_DAMAGE]
	return ART_PIECES[code] if code >= 0 and code < ART_PIECES.size() else ""


## Translation key stem of a card: upgrade.p0.sword_damage -> UPGRADE_P0_SWORD_DAMAGE.
static func key_stem(code: int, form: int = SimConfig.SKILL_PROJECTILE) -> String:
	return UpgradeSystem.card_id(code, form).replace(".", "_").to_upper()


## {"name", "stat", "label", "change", "rank"} in the current locale. "stat" is the whole line
## ("Max health 100 -> 120 and heal"); "change" is its values ("100 -> 120") and "label" the
## words around them ("Max health and heal"), so a card can set them on two lines. "rank" is empty for
## recover.
static func describe(config: SimConfig, world: WorldState, code: int) -> Dictionary:
	var after: WorldState = world.copy()
	UpgradeSystem.apply_upgrade(after, code)
	var stem: String = key_stem(code, config.skill_form)
	var rank: String = ""
	var ranks: PackedInt64Array = UpgradeSystem.RANK_TABLES[config.skill_form]
	if code < ranks.size():
		rank = UiText.text("UI_UPGRADE_RANK") % [after.ranks[code], ranks[code]]
	var values: Array = [stat(config, world, code), stat(config, after, code)]
	var template: String = UiText.text(stem + "_DESC")
	var first: int = template.find("%s")
	var last: int = template.rfind("%s")
	var label: String = template
	var change: String = ""
	if first >= 0:
		label = (template.substr(0, first).strip_edges() + " " + template.substr(last + 2).strip_edges()).strip_edges()
		change = template.substr(first, last + 2 - first) % values
		if values[0] == values[1]:
			# Recovery at full health: the card says the value stays, not "100 -> 100".
			change = UiText.text("UI_UPGRADE_UNCHANGED") % values[0]
	return {
		"name": UiText.text(stem + "_NAME"),
		"stat": template % values,
		"label": label,
		"change": change,
		"rank": rank,
	}


## The value the card changes, in player units: px/s, HP, arena cells, swords, attacks/s, enemies.
static func stat(config: SimConfig, world: WorldState, code: int) -> String:
	if config.skill_form == SimConfig.SKILL_CHAIN:
		match code:
			UpgradeSystem.THUNDER_DAMAGE:
				return _hp(UpgradeSystem.skill_damage(config, world))
			UpgradeSystem.THUNDER_HASTE:
				return _casts_per_second(config, world)
			UpgradeSystem.THUNDER_JUMPS:
				return str(UpgradeSystem.chain_hits(config, world))
			UpgradeSystem.THUNDER_REACH:
				return _cells(UpgradeSystem.chain_reach(config, world))
	match code:
		UpgradeSystem.SPEED:
			var per_second: float = UpgradeSystem.hero_speed(config, world) * float(Fx.TICKS_PER_SECOND)
			return str(roundi(per_second / Fx.FX_ONE))
		UpgradeSystem.VITALITY:
			return _hp(world.hero_hp_max)
		UpgradeSystem.PICKUP:
			return _cells(UpgradeSystem.pickup_radius(config, world))
		UpgradeSystem.COUNT:
			return str(UpgradeSystem.projectile_count(world))
		UpgradeSystem.DAMAGE:
			return _hp(UpgradeSystem.skill_damage(config, world))
		UpgradeSystem.HASTE:
			return _casts_per_second(config, world)
		UpgradeSystem.PIERCE:
			return str(UpgradeSystem.projectile_pierce(config, world) + 1)
		UpgradeSystem.RECOVER:
			return _hp(world.hero_hp)
	return "?"


static func _casts_per_second(config: SimConfig, world: WorldState) -> String:
	var rate: float = float(UpgradeSystem.skill_rate(config, world)) * Fx.TICKS_PER_SECOND
	return "%.2f" % (rate / maxf(1.0, float(config.skill_period_mt)))


static func _cells(su: int) -> String:
	return String.num(float(su) / float(P0Tuning.CELL_PX * Fx.FX_ONE), 2).trim_suffix(".0")


## Milli-HP shown as whole HP.
static func _hp(mhp: int) -> String:
	return str(roundi(mhp / 1000.0))
