class_name IdleState extends HiveState
## Attente dans la ruche (abeille jaune). État initial.
## L'abeille alterne phases de marche sinueuse et pauses sur le cadre,
## jusqu'à détecter une danse (→ WATCH), partir explorer (→ SCOUT)
## ou devenir receveuse (→ RECEIVE), plus souvent au contact d'une danse trémulante.
## Le déplacement lui-même (accélération, évitement, bords) est délégué à bee.walker.
##
## Envie d'explorer : elle croît avec le temps passé de jour sans croiser de danse.
## Une abeille qui trouve des danses les suit ; une abeille qui n'en trouve pas
## finit par chercher elle-même (Seeley 1983 ; Biesmeijer et Seeley 2005).
## L'information est locale : l'abeille ne connaît que les danses à sa portée.

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

## Temps (s) passé de jour dans cet état sans croiser de danse à portée.
## Remis à zéro à l'entrée dans l'état et à chaque danse rencontrée.
var _time_without_dance := 0.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	# Commence par une pause de durée aléatoire : évite que toutes les abeilles
	# démarrent en même temps au lancement de la simulation
	_start_pause(randf_range(0.0, PAUSE_MAX))
	_push_offset = randi() % PUSH_CHECK_STEP
	# De retour sur le cadre (trajet, réception, suivi de danse interrompu),
	# l'abeille cherche d'abord des danses avant d'avoir envie d'explorer
	_time_without_dance = 0.0

func update(delta: float) -> BeeState:
	# Lumière suffisante pour sortir : testée une seule fois par frame
	var day := bee.can_leave()

	# Danse à portée : l'abeille peut se mettre à la suivre (→ WATCH)
	var dancer := _check_dances(delta, day)
	if dancer != null:
		return bee.watch.follow(dancer)

	# Engagement comme receveuse, réservé aux abeilles qui ne butinent pas :
	# ni source connue, ni vecteur de danse. Probabilité par seconde, comme p_scout :
	# p_receive en temps normal, tremble_recruit_rate au contact d'une trémulante
	# (Seeley et al. 1996 : la danse trémulante fait monter la part de receveuses).
	# Testé une frame sur DANCE_CHECK_STEP, comme les danses : la probabilité
	# est multipliée d'autant pour garder le même taux par seconde.
	if not is_instance_valid(bee.known_flower) and not bee.has_dance_vector() \
			and (Engine.get_physics_frames() + _push_offset) % DANCE_CHECK_STEP == 0:
		var sim := bee.simulation
		# Aucune trémulante dans la ruche : inutile de chercher
		var trembler: Bee = null
		if bee.hive.get_tremble_count() > 0:
			trembler = _find_trembler()
		var rate := sim.p_receive
		if trembler != null:
			rate = maxf(sim.tremble_recruit_rate, sim.p_receive)
		if randf() < rate * delta * DANCE_CHECK_STEP:
			# Crédit pour l'interface seulement : la trémulante n'en tient pas compte
			if trembler != null:
				trembler.tremble.credit_recruit()
			return bee.receive

	# Pas de sortie si la lumière est insuffisante pour cette abeille
	if day:
		# Au matin, une abeille qui connaît une source y retourne sans attendre
		# de danse. p_reactivate est une probabilité par seconde.
		if is_instance_valid(bee.known_flower) \
				and randf() < bee.simulation.p_reactivate * delta:
			return bee.leave_hive.then(bee.go)

		# Taux d'exploration par seconde : × delta pour ne pas dépendre du framerate.
		# Il croît avec le temps passé sans croiser de danse (voir get_scout_rate).
		# L'abeille sort d'abord à pied, puis explore une fois dehors.
		if randf() < get_scout_rate() * delta:
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
# Lecture (interface)
# =============================================================================

## Probabilité par seconde de partir explorer, au moment présent.
## p_scout juste après une danse rencontrée, p_scout_max après scout_patience
## secondes de jour sans en croiser, interpolation linéaire entre les deux.
func get_scout_rate() -> float:
	var sim := bee.simulation
	var t := clampf(_time_without_dance / maxf(sim.scout_patience, 0.001), 0.0, 1.0)
	return lerpf(sim.p_scout, sim.p_scout_max, t)

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

## Met à jour le temps sans danse et renvoie la danseuse la plus proche
## si l'abeille décide de la suivre, sinon null.
## [param day] : true si la lumière permet de sortir. La nuit, personne ne danse :
## le temps sans danse ne compte pas, sinon toutes les abeilles partiraient
## explorer en même temps au lever du jour.
## Testé une frame sur DANCE_CHECK_STEP, avec le même décalage que la bousculade :
## les abeilles ne cherchent pas toutes sur la même frame.
func _check_dances(delta: float, day: bool) -> Bee:
	if day:
		_time_without_dance += delta
	if (Engine.get_physics_frames() + _push_offset) % DANCE_CHECK_STEP != 0:
		return null
	var sim := bee.simulation
	# La requête est faite à chaque test (et plus seulement après le tirage
	# de p_follow) : il faut savoir si une danse est à portée pour remettre
	# le compteur à zéro. Peu de danses à la fois : le coût reste faible.
	var nearby := bee.hive.get_dancers_near(bee.global_position, sim.follow_radius)
	if nearby.is_empty():
		return null
	# Une danse à portée : de l'information circule, l'envie d'explorer retombe,
	# même si l'abeille ne la suit pas (danseuse déjà entourée, tirage raté)
	_time_without_dance = 0.0
	# Probabilité par seconde, ramenée aux DANCE_CHECK_STEP frames écoulées
	if randf() >= sim.p_follow * delta * DANCE_CHECK_STEP:
		return null
	# La danse la plus proche : les suiveuses réelles suivent plutôt la plus proche
	var nearest: Bee = null
	var best := INF
	for dancer in nearby:
		# Danseuse déjà entourée : plus de place autour d'elle
		if bee.hive.get_follower_count(dancer) >= sim.max_followers:
			continue
		var d2 := dancer.global_position.distance_squared_to(bee.global_position)
		if d2 < best:
			best = d2
			nearest = dancer
	return nearest

## Trémulante au contact, ou null. Perception locale : seule une trémulante
## à moins de tremble_contact_radius compte.
## Peu de trémulantes à la fois : la requête reste peu coûteuse.
func _find_trembler() -> Bee:
	var nearby := bee.hive.get_tremblers_near(bee.global_position,
			bee.simulation.tremble_contact_radius)
	return null if nearby.is_empty() else nearby[0]
