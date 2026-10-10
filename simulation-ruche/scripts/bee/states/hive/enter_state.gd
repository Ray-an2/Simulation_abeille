class_name EnterState extends HiveState
## Entrée dans la ruche : marche du point d'atterrissage jusqu'au tunnel, le traverse,
## rejoint le pied du cadre sur le plancher, puis saute sur le bas du cadre.

# =============================================================================
# Constantes
# =============================================================================


## Marche vers le pied du cadre : tendance (rad/s)
const FOOT_RADIUS := 0.01

## Écart maximal (m) autour du point du cadre le plus proche de l'entrée, pour que
## les abeilles ne montent pas toutes au même endroit.
const CLIMB_SPREAD := 0.05

## Vitesse (m/s) du saut du plancher vers le cadre.
const CLIMB_SPEED := 0.1

# =============================================================================
# Types
# =============================================================================

## Étapes de l'entrée.
enum Phase {
	TO_PORCH,        ## Marche sur la planche jusqu'au point de dégagement devant le tunnel
	TO_TUNNEL,       ## Ligne droite dans l'axe, jusqu'à l'extrémité extérieure du tunnel
	THROUGH_TUNNEL,  ## Traversée du tunnel jusqu'à son extrémité intérieure
	TO_COMB_FOOT,    ## Marche sur le plancher jusqu'au pied du cadre
	CLIMB,           ## Saut sur le bas du cadre en se retournant
}

# =============================================================================
# État interne
# =============================================================================

## Étape en cours.
var _phase := Phase.TO_TUNNEL

## Point d'arrivée sur le cadre, et point du plancher juste en dessous (pied du cadre).
var _climb_target := Vector3.ZERO
var _comb_foot := Vector3.ZERO

## Point de dégagement devant le tunnel, propre à chaque entrée.
var _porch := Vector3.ZERO

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_phase = Phase.TO_PORCH
	_porch = bee.hive.get_random_porch_point()
	_reset_wander()
	# Sur la planche : l'évitement doit se faire dans le plan horizontal
	# (Bee.change_state vient de remettre le walker sur le cadre)
	bee.walker.reset(CombWalker.Surface.FLOOR)

	# Point d'arrivée sur le cadre : près du bas, côté entrée, un peu au hasard
	var hive := bee.hive
	var edge := hive.get_comb_bottom_point(hive.get_entrance_position())
	_climb_target = hive.get_comb_point_near(edge, CLIMB_SPREAD)
	# Pied du cadre : sous ce point, écarté du cadre comme pour la chute en sortie
	var p := _climb_target + hive.get_comb_normal() * hive.drop_clearance
	_comb_foot = hive.clamp_to_floor(Vector3(p.x, hive.get_floor_height(), p.z))

func update(delta: float) -> BeeState:
	var hive := bee.hive

	match _phase:
		Phase.TO_PORCH:
			# Depuis le point d'atterrissage : on vient se placer devant le tunnel,
			# pour y entrer dans l'axe au lieu d'arriver de biais le long du mur
			_walk_straight(_porch, _wander_speed(delta), delta)
			if bee.is_near(_porch, EXACT_RADIUS):
				_phase = Phase.TO_TUNNEL
		
		Phase.TO_TUNNEL:
			# Ligne droite du point d'atterrissage au tunnel : courte, avec un dénivelé éventuel
			var outer := hive.get_tunnel_outer_end()
			_walk_straight(outer, _wander_speed(delta), delta)
			if bee.is_near(outer, EXACT_RADIUS):
				# Dans le tunnel, au niveau du plancher : le walker prend le relais
				bee.walker.reset(CombWalker.Surface.FLOOR)
				bee.walker.current_speed = _speed_factor   # pas d'arrêt à l'entrée
				_phase = Phase.THROUGH_TUNNEL

		Phase.THROUGH_TUNNEL:
			if _walk_to(hive.get_tunnel_inner_end(), TUNNEL_STEER_RATE, TUNNEL_EXIT_RADIUS,
					delta, TUNNEL_TURN_RATE):
				_phase = Phase.TO_COMB_FOOT

		Phase.TO_COMB_FOOT:
			if _walk_to(_comb_foot, FLOOR_STEER_RATE, FOOT_RADIUS, delta, FLOOR_TURN_RATE):
				bee.play_animation(&"_bee_hover")
				_phase = Phase.CLIMB

		Phase.CLIMB:
			# Saut sur le cadre en se retournant : le dos passe à la normale du cadre,
			# la tête vers le haut du cadre
			var normal := hive.get_comb_normal()
			var facing := (_climb_target - bee.global_position).slide(normal)
			if facing.is_zero_approx():
				facing = Vector3.UP
			bee.hop_towards(_climb_target, CLIMB_SPEED, facing, normal, delta)
			if bee.is_near(_climb_target, EXACT_RADIUS):
				# Toujours UNLOAD, même sans nectar : c'est là que la source est évaluée.
				# Une exploratrice rentrée bredouille en ressort aussitôt vers IDLE.
				return bee.unload

	return null

func exit() -> void:
	# De retour sur le cadre : le walker repart de l'orientation actuelle de l'abeille
	bee.walker.reset(CombWalker.Surface.COMB)
