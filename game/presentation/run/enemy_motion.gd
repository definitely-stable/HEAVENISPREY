class_name EnemyMotion
extends RefCounted
## How an enemy sprite moves beyond its looping clips (ADR-014 A5c), presentation only:
## - an attack with a telegraph (MELEE_ARC, CHARGE and the other forms with an attack state) plays its
##   clip by the simulation's state instead of a loop: the first third of the frames over
##   `tell` (the wind-up), the second third over `active` (its first frame is the strike, the
##   tick the hit lands), the rest over `recover`; the body faces the direction the attack
##   locked, not the hero;
## - an ethereal kind hovers above its contact shadow, bobbing, and is drawn a little see-through.

## Asset -> [lift px, bob px, bob period s] of a body that floats above the ground.
const HOVER: Dictionary = {"asset.enemy.wandering_spirit": [7.0, 2.5, 1.7]}
## Asset -> opacity of a ghost body; the floor shows through its pale robe a little.
const OPACITY: Dictionary = {"asset.enemy.wandering_spirit": 0.84}


## Frame of the attack clip (of `frames` frames) the enemy in `slot` shows by its attack
## state; -1 while it approaches (or the clip is too short to split into three phases).
static func attack_frame(config: SimConfig, world: WorldState, slot: int, frames: int) -> int:
	var state: int = world.enemy_state[slot]
	if state == EnemyAttackSystem.ST_APPROACH or frames < 3:
		return -1
	var field: int = SimConfig.ATTACK_TELEGRAPH
	if state == EnemyAttackSystem.ST_ACTIVE:
		field = SimConfig.ATTACK_ACTIVE
	elif state == EnemyAttackSystem.ST_RECOVER:
		field = SimConfig.ATTACK_RECOVERY
	var span: int = maxi(config.attack_value(world.enemy_kind[slot], field), 1)
	var progress: float = clampf(float(span - world.enemy_left[slot]) / float(span), 0.0, 0.999)
	@warning_ignore("integer_division")
	var third: int = frames / 3
	var count: int = third if state != EnemyAttackSystem.ST_RECOVER else frames - 2 * third
	return (state - 1) * third + floori(progress * count)


## Screen-diagonal signs of the direction the attack in `slot` faces (SpriteSet.diagonal): the
## locked direction; a charge or a shot aims at the hero until the end of `tell` (ADR-011 E3,
## E4), so it faces the hero while it winds up.
static func attack_signs(config: SimConfig, world: WorldState, slot: int) -> Vector2i:
	var aim: Vector2 = Vector2(world.enemy_dir_x[slot], world.enemy_dir_y[slot])
	var form: int = config.attack_value(world.enemy_kind[slot], SimConfig.ATTACK_FORM)
	if form != SimConfig.FORM_ARC and world.enemy_state[slot] == EnemyAttackSystem.ST_TELL:
		aim = Vector2(world.player_x - world.enemy_x[slot], world.player_y - world.enemy_y[slot])
	var screen: Vector2 = IsoProjection.to_screen(aim)
	return Vector2i(-1 if screen.x < 0.0 else 1, -1 if screen.y < 0.0 else 1)


## Screen px the body of `asset` floats above its feet at `seconds` (0 for a grounded kind);
## each enemy bobs at its own phase.
static func lift(asset: String, uid: int, seconds: float) -> float:
	if not HOVER.has(asset):
		return 0.0
	var hover: Array = HOVER[asset]
	return float(hover[0]) + float(hover[1]) * sin(TAU * seconds / float(hover[2]) + float(posmod(uid * 5, 13)))


static func opacity(asset: String) -> float:
	return float(OPACITY.get(asset, 1.0))
