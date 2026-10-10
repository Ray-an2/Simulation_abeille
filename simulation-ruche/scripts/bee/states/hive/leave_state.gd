class_name LeaveState extends HiveState
## Sortie de la ruche : descend le cadre vers un point du bord inférieur proche de l'entrée,
## se laisse tomber sur le plancher en se retournant, rejoint le tunnel, le traverse,
## puis marche jusqu'à un point de la planche d'envol et décolle vers l'état prévu.
## Usage depuis un autre état : return bee.leave_hive.then(bee.scout)

# =============================================================================
# Constantes
# =============================================================================

## Écart maximal (m), le long du bas du cadre, autour du point le plus proche de l'entrée.
## Les abeilles tombent à des endroits différents et convergent ensuite vers le tunnel.
const DESCENT_SPREAD := 0.05

## Vitesse de virage (rad/s) vers le but sur le cadre : plus faible que les virages
## aléatoires, à court terme l'abeille zigzague, en moyenne elle descend.
const DESCENT_STEER_RATE := 1.5

## Distance (m) au bord inférieur du cadre en dessous de laquelle l'abeille se laisse tomber.
const BOTTOM_TOLERANCE := 0.003

## Vitesse (m/s) de la chute vers le plancher : nettement plus rapide que la marche.
const DROP_SPEED := 0.15

## Distance (m) entre le point d'approche et l'entrée du tunnel, dans l'axe du tunnel.
## Laisse à l'abeille la place de s'aligner avant d'entrer.
const APPROACH_DISTANCE := 0.02

## Marche vers le point d'approche : tendance (rad/s), virages aléatoires (rad/s)
## et distance d'arrivée (m), supérieure au rayon de virage.
const APPROACH_RADIUS := 0.01

# =============================================================================
# Types
# =============================================================================

## Étapes de la sortie.
enum Phase {
	DESCEND,         ## Descente du cadre vers le but sur le bord inférieur
	DROP,            ## Chute sur le plancher en se retournant
	TO_TUNNEL,       ## Marche sur le plancher jusqu'au point d'approche du tunnel
	THROUGH_TUNNEL,  ## Traversée du tunnel jusqu'à son extrémité extérieure
	TO_PORCH,        ## Ligne droite dans l'axe du tunnel, pour s'écarter du mur
	TO_TAKEOFF,      ## Marche sur la planche jusqu'au point de décollage
}

# =============================================================================
# État interne
# =============================================================================

## État dans lequel entrer après le décollage (SCOUT ou GO).
var _next: BeeState

## Étape en cours.
var _phase := Phase.DESCEND

## But sur le bord inférieur du cadre, propre à chaque sortie.
var _descent_goal := Vector3.ZERO

## Point du plancher visé pendant la chute.
var _drop_target := Vector3.ZERO

## Point de décollage sur la planche, propre à chaque sortie.
var _takeoff := Vector3.ZERO

## Point de dégagement devant le tunnel, propre à chaque sortie.
var _porch := Vector3.ZERO

# =============================================================================
# Méthodes de l'état
# =============================================================================

## Fixe l'état suivant et renvoie l'état lui-même, pour pouvoir écrire
## « return bee.leave_hive.then(bee.go) » dans les autres états.
func then(next: BeeState) -> LeaveState:
	_next = next
	return self

func enter() -> void:
	assert(_next != null, "LeaveState : état suivant non défini, utiliser then()")
	_phase = Phase.DESCEND
	_reset_wander()

	# But de descente : point du bas du cadre proche de l'entrée, décalé au hasard
	var hive := bee.hive
	var near_entrance := hive.get_comb_point_near(hive.clamp_to_comb(hive.get_entrance_position()), DESCENT_SPREAD)
	_descent_goal = hive.get_comb_bottom_point(near_entrance)

func update(delta: float) -> BeeState:
	var hive := bee.hive

	match _phase:
		Phase.DESCEND:
			# Sans retour vers le centre : il contrarierait la descente vers le bord
			_walk_to(_descent_goal, DESCENT_STEER_RATE, 0.0, delta, WANDER_TURN_RATE, false)
			# Bord du bas atteint, n'importe où : l'abeille se laisse tomber
			if hive.get_comb_bottom_distance(bee.global_position) < BOTTOM_TOLERANCE:
				_start_drop()

		Phase.DROP:
			# Chute en se retournant : le dos passe de la normale du cadre à la verticale,
			# la tête vers le tunnel
			var facing := (hive.get_tunnel_inner_end() - bee.global_position).slide(Vector3.UP)
			if facing.is_zero_approx():
				facing = hive.get_comb_normal()
			bee.hop_towards(_drop_target, DROP_SPEED, facing, Vector3.UP, delta)
			if bee.is_near(_drop_target, EXACT_RADIUS):
				bee.play_animation(&"_bee_idle")
				# Désormais sur le plancher : le walker repart de l'orientation actuelle
				bee.walker.reset(CombWalker.Surface.FLOOR)
				_phase = Phase.TO_TUNNEL

		Phase.TO_TUNNEL:
			# Point d'approche dans l'axe du tunnel, un peu avant son entrée
			var approach := hive.get_tunnel_inner_end() - hive.get_tunnel_axis() * APPROACH_DISTANCE
			if _walk_on_floor(approach, delta):
				_phase = Phase.THROUGH_TUNNEL

		Phase.THROUGH_TUNNEL:
			if _walk_through_tunnel(hive.get_tunnel_outer_end(), delta):
				_porch = hive.get_random_porch_point()
				_phase = Phase.TO_PORCH

		Phase.TO_PORCH:
			# Tout droit hors du tunnel : l'abeille s'écarte du mur avant de tourner
			if _walk_straight_to(_porch, delta):
				_takeoff = hive.get_random_landing_position()
				_phase = Phase.TO_TAKEOFF

		Phase.TO_TAKEOFF:
			# Décollage. Le passage à un état Dehors démarre le bourdonnement
			# individuel (Bee.change_state).
			if _walk_straight_to(_takeoff, delta):
				return _next

	return null

# =============================================================================
# Utilitaires internes
# =============================================================================

## Démarre la chute : point du plancher sous l'abeille, écarté du cadre
## de drop_clearance pour ne pas traverser la traverse du bas.
func _start_drop() -> void:
	_phase = Phase.DROP
	# Ailes en mouvement pendant la chute
	bee.play_animation(&"_bee_hover")
	var p := bee.global_position + bee.hive.get_comb_normal() * bee.hive.drop_clearance
	_drop_target = bee.hive.get_floor_point_below(bee.global_position)
