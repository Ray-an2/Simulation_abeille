class_name IdleState extends HiveState
## Attente dans la ruche (abeille jaune). État initial.
## L'abeille déambule sur le cadre par petits pas entrecoupés de pauses,
## jusqu'à détecter une danse (→ WATCH) ou partir explorer (→ SCOUT).

# =============================================================================
# Constantes
# =============================================================================

## Durée (s) d'une phase de marche, tirée au hasard dans cet intervalle.
const WALK_MIN := 0.5
const WALK_MAX := 5

## Durée (s) d'une pause, tirée au hasard dans cet intervalle.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 3.0

## Facteur appliqué à walk_speed, tiré au hasard à chaque phase de marche.
const SPEED_FACTOR_MIN := 0.5
const SPEED_FACTOR_MAX := 1.5

## Vitesse de virage maximale (rad/s), dans un sens ou dans l'autre.
const MAX_TURN_RATE := 3.0

## Intervalle (s) entre deux changements de vitesse de virage : plus il est court,
## plus la trajectoire zigzague.
const TURN_CHANGE_MIN := 0.2
const TURN_CHANGE_MAX := 0.8

## Distance (m) du point visé devant l'abeille. Doit rester supérieure au pas
## parcouru en une frame, sinon l'abeille s'arrêterait sur ce point.
const LOOK_AHEAD := 0.01

## Vitesse (1/s) à laquelle le cap se réoriente vers le centre près d'un bord.
const EDGE_STEER := 5.0

# =============================================================================
# État interne
# =============================================================================

## true pendant une phase de marche, false pendant une pause.
var _walking := false

## Temps restant (s) dans la phase en cours (marche ou pause).
var _phase_time := 0.0

## Direction de marche, toujours dans le plan du cadre (unitaire).
var _heading := Vector3.ZERO

## Vitesse de virage actuelle (rad/s) : positive ou négative selon le sens.
var _turn_rate := 0.0

## Temps restant (s) avant de tirer une nouvelle vitesse de virage.
var _turn_change_time := 0.0

## Facteur de vitesse de la phase de marche en cours.
var _speed_factor := 1.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	bee.play_animation(&"_bee_idle")
	# Cap initial : l'avant de l'abeille (+Z), projeté dans le plan du cadre
	var normal := bee.hive.get_comb_normal()
	_heading = bee.global_basis.z.slide(normal).normalized()
	# Commence par une pause de durée aléatoire : évite que toutes les abeilles
	# démarrent en même temps au lancement de la simulation
	_start_pause(randf_range(0.0, PAUSE_MAX))

func update(delta: float) -> BeeState:
	# TODO : détecter une danse à proximité (→ WATCH)

	# p_scout est une probabilité par seconde : × delta pour ne pas dépendre du framerate
	if randf() < bee.simulation.p_scout * delta:
		return bee.scout

	_wander(delta)
	return null

# =============================================================================
# Utilitaires internes
# =============================================================================

## Fait progresser la phase en cours, et bascule entre marche et pause à son terme.
func _wander(delta: float) -> void:
	_phase_time -= delta
	if _phase_time <= 0.0:
		if _walking:
			_start_pause(randf_range(PAUSE_MIN, PAUSE_MAX))
		else:
			_start_walk()
		return

	if _walking:
		_walk_step(delta)

## Avance d'une frame en suivant le cap, qui dérive selon la vitesse de virage.
func _walk_step(delta: float) -> void:
	var normal := bee.hive.get_comb_normal()

	# Nouvelle vitesse de virage de temps en temps : donne une trajectoire sinueuse
	_turn_change_time -= delta
	if _turn_change_time <= 0.0:
		_turn_rate = randf_range(-MAX_TURN_RATE, MAX_TURN_RATE)
		_turn_change_time = randf_range(TURN_CHANGE_MIN, TURN_CHANGE_MAX)

	# Rotation du cap autour de la normale : il reste dans le plan du cadre
	_heading = _heading.rotated(normal, _turn_rate * delta)

	# Près d'un bord, le point visé sort du cadre : on réoriente progressivement
	# le cap vers le centre plutôt que de rester bloqué contre le bord
	var ahead := bee.global_position + _heading * LOOK_AHEAD
	var clamped := bee.hive.clamp_to_comb(ahead)
	if not ahead.is_equal_approx(clamped):
		var to_center := (bee.hive.get_comb_center() - bee.global_position).slide(normal).normalized()
		_heading = _heading.lerp(to_center, EDGE_STEER * delta).normalized()

	bee.walk_towards(clamped, delta, normal, _speed_factor)

## Démarre une phase de marche avec une durée, une vitesse et un virage aléatoires.
func _start_walk() -> void:
	_walking = true
	_phase_time = randf_range(WALK_MIN, WALK_MAX)
	_speed_factor = randf_range(SPEED_FACTOR_MIN, SPEED_FACTOR_MAX)
	_turn_change_time = 0.0   # force un nouveau virage dès la première frame

## Démarre une pause de [param duration] secondes.
func _start_pause(duration: float) -> void:
	_walking = false
	_phase_time = duration
