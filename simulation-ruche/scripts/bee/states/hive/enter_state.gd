class_name EnterState extends HiveState
## Entrée dans la ruche : marche de la planche d'envol jusqu'à l'entrée, puis sur le plancher
## jusqu'au pied du cadre, et petit saut sur le bas du cadre.
## Mènera à UNLOAD une fois cet état écrit ; IDLE en attendant.

# =============================================================================
# Constantes
# =============================================================================

## Vitesse de virage (rad/s) vers le pied du cadre sur le plancher.
const FLOOR_STEER_RATE := 5.0

## Écart maximal (m) autour du point du cadre le plus proche de l'entrée, pour que
## les abeilles ne montent pas toutes au même endroit.
const CLIMB_SPREAD := 0.03

## Vitesse (m/s) du saut du plancher vers le cadre.
const CLIMB_SPEED := 0.1

## Distance (m) au pied du cadre en dessous de laquelle l'abeille saute.
## Supérieure au rayon de virage, sinon elle tournerait autour du point.
const FOOT_RADIUS := 0.008

## Distance (m) de fin des déplacements en ligne droite (move_toward atteint la cible exactement).
const EXACT_RADIUS := 0.0005

# =============================================================================
# Types
# =============================================================================

## Étapes de l'entrée.
enum Phase {
	TO_ENTRANCE,   ## Marche de la planche jusqu'à l'entrée
	TO_COMB_FOOT,  ## Marche sur le plancher jusqu'au pied du cadre
	CLIMB,         ## Saut sur le bas du cadre en se retournant
}

# =============================================================================
# État interne
# =============================================================================

## Étape en cours.
var _phase := Phase.TO_ENTRANCE

## Point d'arrivée sur le cadre, et point du plancher juste en dessous (pied du cadre).
var _climb_target := Vector3.ZERO
var _comb_foot := Vector3.ZERO

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	bee.play_animation(&"_bee_idle")
	_phase = Phase.TO_ENTRANCE

	# Point d'arrivée sur le cadre : près du bas, côté entrée, un peu au hasard
	var edge := bee.hive.clamp_to_comb(bee.hive.get_entrance_position())
	_climb_target = bee.hive.get_comb_point_near(edge, CLIMB_SPREAD)
	# Pied du cadre : sous ce point, écarté du cadre comme pour la chute en sortie
	var p := _climb_target + bee.hive.get_comb_normal() * bee.hive.drop_clearance
	_comb_foot = Vector3(p.x, bee.hive.get_floor_height(), p.z)

func update(delta: float) -> BeeState:
	match _phase:
		Phase.TO_ENTRANCE:
			# Ligne droite de la planche à l'entrée : courte, avec un dénivelé éventuel
			var entrance := bee.hive.get_entrance_position()
			bee.walk_towards(entrance, delta, Vector3.UP, 1.0)
			if bee.is_near(entrance, EXACT_RADIUS):
				# À l'intérieur, sur le plancher : le walker prend le relais
				bee.walker.reset(CombWalker.Surface.FLOOR)
				bee.walker.current_speed = 1.0   # pas d'arrêt à l'entrée
				_phase = Phase.TO_COMB_FOOT

		Phase.TO_COMB_FOOT:
			bee.walker.steer_towards(_comb_foot, FLOOR_STEER_RATE, delta)
			bee.walker.step(1.0, delta)
			if bee.is_near(_comb_foot, FOOT_RADIUS):
				bee.play_animation(&"_bee_hover")
				_phase = Phase.CLIMB

		Phase.CLIMB:
			# Saut sur le cadre en se retournant : le dos passe à la normale du cadre,
			# la tête vers le haut du cadre
			var normal := bee.hive.get_comb_normal()
			var facing := (_climb_target - bee.global_position).slide(normal)
			if facing.is_zero_approx():
				facing = Vector3.UP
			bee.hop_towards(_climb_target, CLIMB_SPEED, facing, normal, delta)
			if bee.is_near(_climb_target, EXACT_RADIUS):
				return bee.idle   # TODO : bee.unload une fois UNLOAD écrit

	return null

func exit() -> void:
	# De retour sur le cadre : le walker repart de l'orientation actuelle de l'abeille
	bee.walker.reset(CombWalker.Surface.COMB)
