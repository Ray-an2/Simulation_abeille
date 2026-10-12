class_name IdleState extends HiveState
## Attente dans la ruche (abeille jaune). État initial.
## L'abeille alterne phases de marche sinueuse et pauses sur le cadre,
## jusqu'à détecter une danse (→ WATCH) ou partir explorer (→ SCOUT).
## Le déplacement lui-même (accélération, évitement, bords) est délégué à bee.walker.

# =============================================================================
# Constantes
# =============================================================================

## Durée (s) d'une phase de marche, tirée au hasard dans cet intervalle.
const WALK_MIN := 0.5
const WALK_MAX := 5.0

## Durée (s) d'une pause, tirée au hasard dans cet intervalle.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 3.0

## Vitesse de virage maximale (rad/s), dans un sens ou dans l'autre.
const MAX_TURN_RATE := 3.0

## Urgence au-delà de laquelle une abeille en pause se remet à marcher pour s'écarter.
## 0.8 correspond à une voisine à moins de 20 % de AVOID_RADIUS : quasi superposée.
const PUSH_THRESHOLD := 0.8

## Une abeille en pause ne vérifie la bousculade que toutes les N frames physiques.
const PUSH_CHECK_STEP := 4

## La recherche de danseuse ne se fait que toutes les N frames physiques.
const DANCE_CHECK_STEP := 4

# =============================================================================
# État interne
# =============================================================================

## true pendant une phase de marche, false pendant une pause.
var _walking := false

## Temps restant (s) dans la phase en cours (marche ou pause).
var _phase_time := 0.0

## Décalage propre à chaque abeille : les tests sont étalés sur les N frames
## au lieu de tomber tous sur la même.
var _push_offset := 0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	# Commence par une pause de durée aléatoire : évite que toutes les abeilles
	# démarrent en même temps au lancement de la simulation
	_start_pause(randf_range(0.0, PAUSE_MAX))
	_push_offset = randi() % PUSH_CHECK_STEP

func update(delta: float) -> BeeState:
		# Danse à portée : l'abeille peut se mettre à la suivre (→ WATCH)
	var dancer := _find_dancer(delta)
	if dancer != null:
		return bee.watch.follow(dancer)
	
	# Pas de sortie si la lumière est insuffisante pour cette abeille
	if bee.can_leave():
		# Au matin, une abeille qui connaît une source y retourne sans attendre
		# de danse. p_reactivate est une probabilité par seconde.
		if is_instance_valid(bee.known_flower) \
				and randf() < bee.simulation.p_reactivate * delta:
			return bee.leave_hive.then(bee.go)
		# p_scout est une probabilité par seconde : × delta pour ne pas dépendre du framerate.
		# L'abeille sort d'abord à pied, puis explore une fois dehors.
		if randf() < bee.simulation.p_scout * delta:
			return bee.leave_hive.then(bee.scout)

	# p_scout est une probabilité par seconde : × delta pour ne pas dépendre du framerate.
	# L'abeille sort d'abord à pied, puis explore une fois dehors.
	if randf() < bee.simulation.p_scout * delta:
		return bee.leave_hive.then(bee.scout)

	_update_phase(delta)

	# Errance pendant la marche : virages plus francs qu'en LEAVE / ENTER (MAX_TURN_RATE)
	var speed := 0.0
	if _walking:
		_wander_turn(delta, MAX_TURN_RATE)
		speed = _wander_speed(delta)

	# Appelé aussi en pause (vitesse visée 0) : l'abeille finit de freiner
	bee.walker.step(speed, delta)
	return null

# =============================================================================
# Utilitaires internes
# =============================================================================

## Fait progresser la phase en cours et bascule entre marche et pause à son terme.
## Une abeille en pause bousculée par une voisine repart pour s'écarter.
func _update_phase(delta: float) -> void:
		# En pause, test de bousculade une frame sur PUSH_CHECK_STEP seulement
	if not _walking and (Engine.get_physics_frames() + _push_offset) % PUSH_CHECK_STEP == 0:
		# Sans cap fourni : en pause, l'abeille réagit aux voisines de tous les côtés
		var away := bee.walker.get_avoidance()
		if away.length() > PUSH_THRESHOLD:
			# Repart directement dans la direction de fuite
			bee.walker.heading = away.normalized()
			_start_walk()
			return

	_phase_time -= delta
	if _phase_time <= 0.0:
		if _walking:
			_start_pause(randf_range(PAUSE_MIN, PAUSE_MAX))
		else:
			_start_walk()

## Démarre une phase de marche d'une durée aléatoire.
func _start_walk() -> void:
	_walking = true
	_phase_time = randf_range(WALK_MIN, WALK_MAX)
	# Nouveau virage et nouvelle vitesse dès la première frame de marche
	_reset_wander()

## Démarre une pause de [param duration] secondes.
func _start_pause(duration: float) -> void:
	_walking = false
	_phase_time = duration

## Renvoie la danseuse la plus proche à portée si l'abeille décide de la suivre,
## sinon null. Testé une frame sur DANCE_CHECK_STEP, avec le même décalage
## que la bousculade : les abeilles ne cherchent pas toutes sur la même frame.
func _find_dancer(delta: float) -> Bee:
	if (Engine.get_physics_frames() + _push_offset) % DANCE_CHECK_STEP != 0:
		return null
	var sim := bee.simulation
	# Probabilité par seconde, ramenée aux DANCE_CHECK_STEP frames écoulées.
	# Tirée avant la recherche : la plupart du temps, on évite la requête.
	if randf() >= sim.p_follow * delta * DANCE_CHECK_STEP:
		return null
	# La danse la plus proche : les suiveuses réelles suivent plutôt la plus proche
	var nearest: Bee = null
	var best := INF
	for dancer in bee.hive.get_dancers_near(bee.global_position, sim.follow_radius):
		# Danseuse déjà entourée : plus de place autour d'elle
		if bee.hive.get_follower_count(dancer) >= sim.max_followers:
			continue
		var d2 := dancer.global_position.distance_squared_to(bee.global_position)
		if d2 < best:
			best = d2
			nearest = dancer
	return nearest
