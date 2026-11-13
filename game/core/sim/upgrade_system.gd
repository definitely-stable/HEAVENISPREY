class_name UpgradeSystem
extends RefCounted
## Level-up choice (ADR-010 section 6). Exact port of tools/content/sim_core.py.
##
## P0 policy, not engine limits: seven upgrades in ASCII ID order (the code of an upgrade is
## its position) with a maximum rank each; RECOVER is offered alone once every upgrade is at
## its maximum and has no rank. Derived stats are the config base plus rank x step and live in
## the world state, never in SimConfig.
## Hand: candidates are the upgrades below their maximum rank in code order; for i in 0..k-1
## with k = min(HAND_SIZE, n) the card j = below(n - i) of the `offers` stream of the run seed
## moves from the candidates into the hand (remove-at, the rest keep their order); no
## candidate -> [RECOVER] without drawing a word. The enemy stream is never touched.
## Choose: one CHOOSE resolves one earned choice atomically (rank, pending - 1, choices_done
## + 1, build_revision + 1) and builds the next hand while choices are pending; a CHOOSE
## outside a pause, with an index outside the hand or for another build_revision is rejected
## without changes.

const IDS: PackedStringArray = [
	"upgrade.p0.hero_speed",
	"upgrade.p0.hero_vitality",
	"upgrade.p0.pickup_radius",
	"upgrade.p0.sword_count",
	"upgrade.p0.sword_damage",
	"upgrade.p0.sword_haste",
	"upgrade.p0.sword_pierce",
]
const MAX_RANKS: PackedInt64Array = [3, 5, 3, 2, 2, 5, 2]
const SPEED: int = 0
const VITALITY: int = 1
const PICKUP: int = 2
const COUNT: int = 3
const DAMAGE: int = 4
const HASTE: int = 5
const PIERCE: int = 6
const RECOVER: int = 7
const RECOVER_ID: String = "upgrade.p0.recover"
const HAND_SIZE: int = 3
const NO_CARD: int = -1
const SPEED_PER_RANK: int = 240
const VITALITY_PER_RANK: int = 20000
const RECOVER_HEAL: int = 20000
const PICKUP_PER_RANK: int = 24000
const DAMAGE_PER_RANK: int = 3000
const HASTE_PER_RANK: int = 150
const OFFERS_STREAM: String = "offers"


static func card_id(code: int) -> String:
	if code == RECOVER:
		return RECOVER_ID
	return IDS[code]


static func hero_speed(config: SimConfig, world: WorldState) -> int:
	return config.speed_su_per_tick + SPEED_PER_RANK * world.ranks[SPEED]


static func pickup_radius(config: SimConfig, world: WorldState) -> int:
	return config.pickup_radius_su + PICKUP_PER_RANK * world.ranks[PICKUP]


static func skill_rate(world: WorldState) -> int:
	return SimConfig.RATE_ONE + HASTE_PER_RANK * world.ranks[HASTE]


static func skill_damage(config: SimConfig, world: WorldState) -> int:
	return maxi(1, config.skill_damage_mhp + DAMAGE_PER_RANK * world.ranks[DAMAGE])


static func projectile_count(world: WorldState) -> int:
	return 1 + world.ranks[COUNT]


static func projectile_pierce(config: SimConfig, world: WorldState) -> int:
	return mini(SimConfig.MAX_PIERCE, config.projectile_pierce + world.ranks[PIERCE])


static func build_hand(config: SimConfig, world: WorldState) -> void:
	var candidates: PackedInt64Array = PackedInt64Array()
	for code: int in MAX_RANKS.size():
		if world.ranks[code] < MAX_RANKS[code]:
			candidates.append(code)
	world.hand = PackedInt64Array()
	if candidates.is_empty():
		world.hand.append(RECOVER)
		return
	var rng: HipRng = HipRng.create(config.run_seed, OFFERS_STREAM, str(world.offers_rng_cursor))
	for _i: int in mini(HAND_SIZE, candidates.size()):
		var pick: int = rng.below(candidates.size())
		world.hand.append(candidates[pick])
		candidates.remove_at(pick)
	world.offers_rng_cursor = rng.cursor()


static func apply_upgrade(world: WorldState, code: int) -> void:
	if code == RECOVER:
		world.hero_hp = mini(world.hero_hp_max, world.hero_hp + RECOVER_HEAL)
		return
	world.ranks[code] += 1
	if code == VITALITY:
		world.hero_hp_max += VITALITY_PER_RANK
		world.hero_hp += VITALITY_PER_RANK


static func choose(config: SimConfig, world: WorldState, index: int, revision: int) -> bool:
	if not world.is_paused() or index < 0 or index >= world.hand.size():
		return false
	if revision != world.build_revision:
		return false
	apply_upgrade(world, world.hand[index])
	world.pending_level_choices -= 1
	world.choices_done += 1
	world.build_revision += 1
	world.hand = PackedInt64Array()
	if world.pending_level_choices > 0:
		build_hand(config, world)
	return true
