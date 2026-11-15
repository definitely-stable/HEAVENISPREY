class_name UpgradeCard
extends RefCounted
## Text of one level-up card (ADR-010 section 6): the name, the stat line "before -> after"
## and the rank after the pick. The "after" value comes from applying the upgrade to a copy
## of the world, so the card always shows what the simulation will do. Presentation only.


## HUD kit illustration of each upgrade code (ADR-014 section 16), in UpgradeSystem code order.
const ART_PIECES: Array[String] = [
	"art_speed", "art_vitality", "art_pickup", "art_count", "art_damage", "art_haste", "art_pierce", "art_recover",
]


## Name of the card illustration of `code` in the HUD kit.
static func art_piece(code: int) -> String:
	return ART_PIECES[code] if code >= 0 and code < ART_PIECES.size() else ""


## Translation key stem of a card: upgrade.p0.sword_damage -> UPGRADE_P0_SWORD_DAMAGE.
static func key_stem(code: int) -> String:
	return UpgradeSystem.card_id(code).replace(".", "_").to_upper()


## {"name", "stat", "label", "change", "rank"} in the current locale. "stat" is the whole line
## ("Max health 100 -> 120 and heal"); "change" is its values ("100 -> 120") and "label" the
## words around them ("Max health and heal"), so a card can set them on two lines. "rank" is empty for
## recover.
static func describe(config: SimConfig, world: WorldState, code: int) -> Dictionary:
	var after: WorldState = world.copy()
	UpgradeSystem.apply_upgrade(after, code)
	var stem: String = key_stem(code)
	var rank: String = ""
	if code < UpgradeSystem.MAX_RANKS.size():
		rank = UiText.text("UI_UPGRADE_RANK") % [after.ranks[code], UpgradeSystem.MAX_RANKS[code]]
	var values: Array = [stat(config, world, code), stat(config, after, code)]
	var template: String = UiText.text(stem + "_DESC")
	var first: int = template.find("%s")
	var last: int = template.rfind("%s")
	var label: String = template
	var change: String = ""
	if first >= 0:
		label = (template.substr(0, first).strip_edges() + " " + template.substr(last + 2).strip_edges()).strip_edges()
		change = template.substr(first, last + 2 - first) % values
	return {
		"name": UiText.text(stem + "_NAME"),
		"stat": template % values,
		"label": label,
		"change": change,
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
