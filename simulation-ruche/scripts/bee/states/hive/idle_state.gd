class_name IdleState extends HiveState
## Attente dans la ruche (abeille jaune). État initial.
## L'abeille déambule sur le cadre par petits pas entrecoupés de pauses,
## jusqu'à détecter une danse (→ WATCH) ou partir explorer (→ SCOUT).

# =============================================================================
# Constantes
# =============================================================================

## Durée (s) d'une phase de marche, tirée au hasard dans cet intervalle.
const WALK_MIN := 0.5
const WALK_MAX := 5.0

## Durée (s) d'une pause, tirée au hasard dans cet intervalle.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 3.0

## Facteur appliqué à walk_speed, tiré au hasard à chaque phase de marche.
const SPEED_FACTOR_MIN := 0.5
const SPEED_FACTOR_MAX := 1.5

## Intervalle (s) entre deux changements de vitesse pendant une phase de marche.
const SPEED_CHANGE_MIN := 0.3
const SPEED_CHANGE_MAX := 1.0

## Accélération au démarrage (facteur de vitesse gagné par seconde).
## Avec 4, une abeille atteint walk_speed en 0,25 s.
const ACCELERATION := 4.0

## Décélération à l'arrêt (facteur de vitesse perdu par seconde).
## Un peu plus faible que l'accélération : l'abeille ralentit avant de s'arrêter.
const DECELERATION := 3.0

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

## Vitesse de virage (rad/s) pour contourner une voisine, à urgence maximale.
const AVOID_TURN_RATE := 6.0

## Part de la vitesse perdue au contact d'une voisine située devant (0 à 1) :
## l'abeille freine en plus de tourner, comme derrière une abeille plus lente.
const AVOID_BRAKE := 0.7

## Urgence au-delà de laquelle une abeille en pause se remet à marcher pour s'écarter.
## 0.8 correspond à une voisine à moins de 20 % de AVOID_RADIUS : quasi superposée.
## Plus bas, l'abeille à l'arrêt semble fuir celle qui approche.
const PUSH_THRESHOLD := 0.8

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

## Facteur de vitesse réellement appliqué, qui rejoint progressivement
## _speed_factor en marche et 0 en pause.
var _current_speed := 0.0

## Temps restant (s) avant de tirer une nouvelle vitesse visée pendant la marche.
var _speed_change_time := 0.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	bee.play_animation(&"_bee_idle")
	# L'abeille arrive immobile sur le cadre
	_current_speed = 0.0
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

## Fait progresser la phase en cours, bascule entre marche et pause à son terme,
## et fait évoluer la vitesse courante vers la vitesse de la phase.
## Une abeille en pause bousculée par une voisine repart pour s'écarter.
func _wander(delta: float) -> void:
	if not _walking:
		var away := get_avoidance(bee.hive.get_comb_normal())
		if away.length() > PUSH_THRESHOLD:
			# Repart directement dans la direction de fuite
			_heading = away.normalized()
			_start_walk()

	_phase_time -= delta
	if _phase_time <= 0.0:
		if _walking:
			_start_pause(randf_range(PAUSE_MIN, PAUSE_MAX))
		else:
			_start_walk()

	# Vitesse visée : celle de la phase de marche, ou 0 en pause.
	# Accélération et décélération distinctes selon qu'on accélère ou qu'on freine.
	var target_speed := _speed_factor if _walking else 0.0
	var rate := ACCELERATION if target_speed > _current_speed else DECELERATION
	_current_speed = move_toward(_current_speed, target_speed, rate * delta)

	# On avance tant qu'il reste de la vitesse : en début de pause, l'abeille
	# finit de freiner au lieu de s'arrêter net
	if _current_speed > 0.0:
		_walk_step(delta)

## Avance d'une frame en suivant le cap, qui dérive selon la vitesse de virage,
## s'écarte des voisines et revient vers le centre près des bords.
func _walk_step(delta: float) -> void:
	var normal := bee.hive.get_comb_normal()
	
	# Nouvelle vitesse visée de temps en temps : l'abeille accélère ou ralentit
	# en cours de marche. La transition est lissée par ACCELERATION / DECELERATION
	# dans _wander(), qui fait tendre _current_speed vers _speed_factor.
	_speed_change_time -= delta
	if _speed_change_time <= 0.0:
		_speed_factor = randf_range(SPEED_FACTOR_MIN, SPEED_FACTOR_MAX)
		_speed_change_time = randf_range(SPEED_CHANGE_MIN, SPEED_CHANGE_MAX)

	# Nouvelle vitesse de virage de temps en temps : donne une trajectoire sinueuse
	_turn_change_time -= delta
	if _turn_change_time <= 0.0:
		_turn_rate = randf_range(-MAX_TURN_RATE, MAX_TURN_RATE)
		_turn_change_time = randf_range(TURN_CHANGE_MIN, TURN_CHANGE_MAX)

	# Rotation du cap autour de la normale : il reste dans le plan du cadre
	_heading = _heading.rotated(normal, _turn_rate * delta)

	# Évitement des voisines situées devant. On fait TOURNER le cap au lieu
	# d'interpoler vers la direction de fuite : quand la voisine est pile dans l'axe,
	# la fuite est opposée au cap, et un lerp ne ferait que raccourcir le vecteur
	# sans le faire tourner.
	var away := get_avoidance(normal, _heading)
	var brake := 1.0
	if away != Vector3.ZERO:
		var urgency := minf(away.length(), 1.0)

		# Composante latérale de la fuite : indique de quel côté contourner la voisine
		var side := away.slide(_heading)
		# Une rotation positive autour de la normale amène le cap vers normal × cap
		var turn_sign := signf(side.dot(normal.cross(_heading)))

		# Voisine (presque) pile dans l'axe : aucun côté n'est meilleur,
		# on garde le sens du virage en cours (à gauche par défaut)
		if side.length() < 0.1 * away.length():
			turn_sign = signf(_turn_rate) if _turn_rate != 0.0 else 1.0

		_heading = _heading.rotated(normal, turn_sign * AVOID_TURN_RATE * urgency * delta)

		# Plus la voisine est proche, plus l'abeille freine
		brake = 1.0 - AVOID_BRAKE * urgency

	# Près d'un bord, le point visé sort du cadre : on réoriente progressivement
	# le cap vers le centre. Appliqué après l'évitement pour qu'une voisine
	# ne puisse pas pousser l'abeille hors du cadre.
	var ahead := bee.global_position + _heading * LOOK_AHEAD
	var clamped := bee.hive.clamp_to_comb(ahead)
	if not ahead.is_equal_approx(clamped):
		var to_center := (bee.hive.get_comb_center() - bee.global_position).slide(normal).normalized()
		_heading = _heading.lerp(to_center, EDGE_STEER * delta).normalized()

	# Vitesse courante, réduite si une voisine est juste devant
	bee.walk_towards(clamped, delta, normal, _current_speed * brake)

## Démarre une phase de marche avec une durée, une vitesse et un virage aléatoires.
func _start_walk() -> void:
	_walking = true
	_phase_time = randf_range(WALK_MIN, WALK_MAX)
	_speed_factor = randf_range(SPEED_FACTOR_MIN, SPEED_FACTOR_MAX)
	_speed_change_time = randf_range(SPEED_CHANGE_MIN, SPEED_CHANGE_MAX)
	_turn_change_time = 0.0   # force un nouveau virage dès la première frame

## Démarre une pause de [param duration] secondes.
func _start_pause(duration: float) -> void:
	_walking = false
	_phase_time = duration
