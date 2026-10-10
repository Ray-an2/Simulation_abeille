class_name UnloadState extends HiveState
## Déchargement du nectar sur le rayon, puis évaluation de la source visitée.
## Déroulé : marche jusqu'à un point du rayon -> file d'attente de la ruche ->
## transfert à une receveuse -> dépôt du nectar -> évaluation de la source.
## Sorties :  1 (rentable) -> DANCE    0 (moyenne) -> GO    -1 (mauvaise ou vide) -> IDLE

## Distance (m) d'arrivée au point de déchargement. Doit dépasser le rayon de virage
## du walker (walk_speed × 1,3 / STEER_RATE ≈ 0,9 cm), sinon l'abeille tourne autour.
const ARRIVAL_RADIUS := 0.012

## Vitesse de virage (rad/s) vers le point de déchargement.
const STEER_RATE := 3.0

## Étapes du déchargement
enum Phase { WALKING, QUEUE, TRANSFER }

## Point du rayon où l'abeille va décharger (tiré au hasard à l'entrée)
var _target: Vector3

## Étape en cours
var _phase := Phase.WALKING

## Temps restant (s) du transfert à la receveuse
var _transfer_left := 0.0

## Temps (s) passé dans la file d'attente, lu quand une receveuse la prend en charge
var _waited := 0.0

func enter() -> void:
	# Nouveaux tirages de virage et de vitesse dès la première frame
	_reset_wander()
	_target = bee.hive.get_random_comb_point()
	_phase = Phase.WALKING
	_waited = 0.0

func exit() -> void:
	# Quitte la file si l'état est interrompu avant la fin du déchargement
	bee.hive.leave_unload_queue(bee)

func update(delta: float) -> BeeState:
	match _phase:
		# 1. Marche avec le walker : accélération, évitement des voisines, bords du cadre
		Phase.WALKING:
			if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.QUEUE
				bee.play_animation(&"_bee_idle")
			return null

		# 2. File d'attente : l'abeille reste en place tant qu'aucune receveuse n'est libre
		Phase.QUEUE:
			if bee.hive.try_unload(bee):
				_waited = bee.hive.get_wait_time(bee)
				_transfer_left = bee.simulation.unload_duration
				_phase = Phase.TRANSFER
			return null

		# 3. Transfert du nectar à la receveuse
		Phase.TRANSFER:
			_transfer_left -= delta
			if _transfer_left > 0.0:
				return null

	# 4. Décharger le nectar dans la ruche
	if bee.nectar > 0.0:
		bee.hive.deposit(bee.nectar)
		bee.nectar = 0.0
		# Nectar déchargé : les pelotes disparaissent
		bee.update_pollen()

	# 5. Évaluer la source et choisir l'état suivant
	var verdict := _evaluate_source()
	if verdict == 1:
		# Saturation de la ruche : plus l'attente a été longue, moins l'abeille
		# a envie de danser (durée de danse réduite, voire pas de danse du tout)
		var sim := bee.simulation
		var wait_ratio := clampf(_waited / sim.max_wait_time, 0.0, 1.0)
		var dance_quality := bee.known_profitability * (1.0 - sim.wait_penalty * wait_ratio)
		if dance_quality >= sim.profitability_high:
			bee.known_profitability = dance_quality   # DANCE : durée proportionnelle
			return bee.dance
		return bee.go   # trop de monde à la ruche : elle repart sans danser
	if verdict == 0:
		return bee.go

	# Source mauvaise ou vide : l'abeille l'oublie
	bee.known_flower = null
	bee.known_profitability = 0.0
	return bee.idle


## Calcule la rentabilité de la source (0 à 1) et renvoie 1, 0 ou -1.
func _evaluate_source() -> int:
	var sim := bee.simulation
	var flower := bee.known_flower

	# Le trajet est terminé : on lit le chrono puis on le remet à zéro
	var trip := bee.trip_time
	bee.trip_time = 0.0

	# Aucune source connue, ou source épuisée
	if not is_instance_valid(flower) or flower.is_empty():
		bee.known_profitability = 0.0
		return -1

	# Distance à plat et angle de danse (utilisés par DANCE)
	bee.distance = sim.get_flat_distance(bee.hive.global_position, flower.global_position)
	bee.angle = sim.get_dance_angle(flower.global_position, bee.hive.global_position)

	# Trois scores entre 0 (mauvais) et 1 (excellent)
	var stock_score := flower.get_profitability()
	var distance_score := 1.0 - clampf(bee.distance / sim.max_source_distance, 0.0, 1.0)
	var time_score := 1.0 - clampf(trip / sim.max_trip_time, 0.0, 1.0)

	# Moyenne pondérée (poids réglables dans simulation.gd)
	var total_weight := maxf(sim.weight_stock + sim.weight_distance + sim.weight_time, 0.001)
	bee.known_profitability = (
		sim.weight_stock * stock_score
		+ sim.weight_distance * distance_score
		+ sim.weight_time * time_score
	) / total_weight

	# Seuils : au-dessus de high on danse, en dessous de low on abandonne
	if bee.known_profitability >= sim.profitability_high:
		return 1
	if bee.known_profitability < sim.profitability_low:
		return -1
	return 0
