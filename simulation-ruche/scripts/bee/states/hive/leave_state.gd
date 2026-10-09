class_name LeaveState extends HiveState
## Sortie de la ruche : descend le cadre en dérivant vers le côté de l'entrée,
## se laisse tomber sur le plancher en se retournant, marche jusqu'à l'entrée
## puis jusqu'à la planche d'envol, et décolle vers l'état prévu (SCOUT ou GO).
## Usage depuis un autre état : return bee.leave_hive.then(bee.scout)

# =============================================================================
# Constantes
# =============================================================================

## Vitesse de virage (rad/s) vers le bas du cadre, côté entrée. Plus faible que les
## virages aléatoires : à court terme l'abeille zigzague, en moyenne elle descend.
const DESCENT_STEER_RATE := 1.5

## Vitesse de virage (rad/s) vers l'entrée sur le plancher : trajet plus direct.
const FLOOR_STEER_RATE := 5.0

## Vitesse de virage aléatoire maximale (rad/s) et intervalle (s) entre deux tirages.
const MAX_TURN_RATE := 1.5
const TURN_CHANGE_MIN := 0.2
const TURN_CHANGE_MAX := 0.8

## Distance (m) au bord inférieur du cadre en dessous de laquelle l'abeille se laisse tomber.
const BOTTOM_TOLERANCE := 0.003

## Vitesse (m/s) de la chute vers le plancher : nettement plus rapide que la marche.
const DROP_SPEED := 0.15

## Distance (m) à l'entrée en dessous de laquelle l'abeille se dirige vers la planche.
## Supérieure au rayon de virage (walk_speed / FLOOR_STEER_RATE), sinon elle tournerait autour.
const ENTRANCE_RADIUS := 0.008

## Distance (m) de fin des déplacements en ligne droite (move_toward atteint la cible exactement).
const EXACT_RADIUS := 0.0005

# =============================================================================
# Types
# =============================================================================

## Étapes de la sortie.
enum Phase {
	DESCEND,       ## Descente du cadre, avec une tendance vers le côté de l'entrée
	DROP,          ## Chute sur le plancher en se retournant
	TO_ENTRANCE,   ## Marche sur le plancher jusqu'à l'entrée
	TO_LANDING,    ## Marche de l'entrée jusqu'à la planche d'envol
}

# =============================================================================
# État interne
# =============================================================================

## État dans lequel entrer après le décollage (SCOUT ou GO).
var _next: BeeState

## Étape en cours.
var _phase := Phase.DESCEND

## Point du plancher visé pendant la chute.
var _drop_target := Vector3.ZERO

## Vitesse de virage aléatoire actuelle (rad/s) et temps avant le prochain tirage (s).
var _turn_rate := 0.0
var _turn_change_time := 0.0

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
	bee.play_animation(&"_bee_idle")
	_phase = Phase.DESCEND
	_turn_change_time = 0.0   # premier virage aléatoire dès la première frame

func update(delta: float) -> BeeState:
	var entrance := bee.hive.get_entrance_position()

	match _phase:
		Phase.DESCEND:
			# Tendance vers le point du cadre le plus proche de l'entrée (bas du cadre,
			# côté entrée), combinée aux virages aléatoires : trajectoire sinueuse
			var goal := bee.hive.clamp_to_comb(entrance)
			_random_turn(delta)
			bee.walker.steer_towards(goal, DESCENT_STEER_RATE, delta)
			# Sans retour vers le centre : il contrarierait la descente vers le bord
			bee.walker.step(1.0, delta, false)
			# Bord du bas atteint, n'importe où : l'abeille se laisse tomber
			if bee.hive.get_comb_bottom_distance(bee.global_position) < BOTTOM_TOLERANCE:
				_start_drop()

		Phase.DROP:
			# Chute en se retournant : le dos passe de la normale du cadre à la verticale,
			# la tête vers l'entrée
			var facing := (entrance - bee.global_position).slide(Vector3.UP)
			if facing.is_zero_approx():
				facing = bee.hive.get_comb_normal()
			bee.hop_towards(_drop_target, DROP_SPEED, facing, Vector3.UP, delta)
			if bee.is_near(_drop_target, EXACT_RADIUS):
				bee.play_animation(&"_bee_idle")
				# Désormais sur le plancher : le walker repart de l'orientation actuelle
				bee.walker.reset(CombWalker.Surface.FLOOR)
				_phase = Phase.TO_ENTRANCE

		Phase.TO_ENTRANCE:
			# Plancher plat, à la hauteur de l'entrée : le walker gère virages,
			# accélération et évitement des autres abeilles
			_random_turn(delta)
			bee.walker.steer_towards(entrance, FLOOR_STEER_RATE, delta)
			bee.walker.step(1.0, delta)
			if bee.is_near(entrance, ENTRANCE_RADIUS):
				_phase = Phase.TO_LANDING

		Phase.TO_LANDING:
			# Ligne droite jusqu'à la planche : courte, et la planche peut être
			# à une autre hauteur que le plancher (le walker reste à hauteur constante)
			var landing := bee.hive.get_landing_position()
			bee.walk_towards(landing, delta, Vector3.UP, maxf(bee.walker.current_speed, 0.5))
			if bee.is_near(landing, EXACT_RADIUS):
				# Décollage. Le passage à un état Dehors démarre le bourdonnement
				# individuel (Bee.change_state).
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
	_drop_target = Vector3(p.x, bee.hive.get_floor_height(), p.z)

## Virages aléatoires : nouvelle vitesse de virage de temps en temps.
func _random_turn(delta: float) -> void:
	_turn_change_time -= delta
	if _turn_change_time <= 0.0:
		_turn_rate = randf_range(-MAX_TURN_RATE, MAX_TURN_RATE)
		_turn_change_time = randf_range(TURN_CHANGE_MIN, TURN_CHANGE_MAX)
	bee.walker.turn(_turn_rate * delta)
