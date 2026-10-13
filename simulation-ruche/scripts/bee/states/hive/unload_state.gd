class_name UnloadState extends HiveState
## Déchargement du nectar sur le rayon, puis évaluation de la source visitée.
## Déroulé : marche jusqu'à un point du rayon -> file d'attente de la ruche ->
## transfert à une receveuse -> dépôt du nectar -> évaluation de la source.
## Sorties :  1 (rentable) -> DANCE    0 (moyenne) -> GO    -1 (mauvaise ou vide) -> IDLE
##
## Rentabilité : efficacité énergétique du trajet, (gain - coût) / coût, mesure
## utilisée par Seeley pour relier la qualité d'une source à l'intensité de la danse.
##   - gain : énergie du sucre rapporté (volume × concentration, goûté en FORAGE) ;
##   - coût : vol aller-retour (distance perçue par le flux optique) et temps
##     passé dans le massif.
## L'abeille n'utilise que ce qu'elle a mesuré elle-même : jamais le stock d'une fleur.
## L'épuisement d'une source lui parvient par un jabot moins rempli et un butinage
## plus long ; la distance, la concentration et la viscosité par le gain et le coût.

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
		# Marche avec le walker : accélération, évitement des voisines, bords du cadre
		Phase.WALKING:
			if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.QUEUE
				bee.play_animation(&"_bee_idle")
			return null

		# File d'attente : l'abeille reste en place tant qu'aucune receveuse n'est libre
		Phase.QUEUE:
			if bee.hive.try_unload(bee):
				_waited = bee.hive.get_wait_time(bee)
				_transfer_left = bee.simulation.unload_duration
				_phase = Phase.TRANSFER
			return null

		# Transfert du nectar à la receveuse
		Phase.TRANSFER:
			_transfer_left -= delta
			if _transfer_left > 0.0:
				return null

	# Sucre rapporté : relevé avant le vidage du jabot, il sert à l'évaluation
	var sugar := bee.sugar

	# Décharger le nectar dans la ruche
	if bee.nectar > 0.0:
		bee.hive.deposit(bee.nectar, sugar)
		bee.nectar = 0.0
		# Nectar déchargé : les pelotes disparaissent
		bee.update_pollen()
	bee.sugar = 0.0

	# Évaluer la source et choisir l'état suivant
	var verdict := _evaluate_source(sugar)
	if verdict == 1:
		# Saturation de la ruche : plus l'attente a été longue, moins l'abeille
		# a envie de danser (durée de danse réduite, voire pas de danse du tout)
		var sim := bee.simulation
		var wait_ratio := clampf(_waited / sim.max_wait_time, 0.0, 1.0)
		var dance_quality := bee.known_profitability * (1.0 - sim.wait_penalty * wait_ratio)
		if dance_quality >= sim.profitability_high:
			bee.known_profitability = dance_quality   # DANCE : durée proportionnelle
			return bee.dance
		# Trop de monde à la ruche : elle repart sans danser.
		# Sortie à pied jusqu'à la planche, puis vol vers la source.
		return go_out_if_day(bee.go)
	if verdict == 0:
		# Source moyenne : elle y retourne sans danser, en passant par la planche
		return go_out_if_day(bee.go)

	# Source mauvaise ou vide : l'abeille l'oublie
	bee.forget_source()
	return bee.idle


## Calcule la rentabilité de la source (0 à 1) à partir de [param sugar], masse
## de sucre (mg) rapportée, et renvoie 1, 0 ou -1.
func _evaluate_source(sugar: float) -> int:
	var sim := bee.simulation
	var flower := bee.known_flower

	# Mesures du trajet, relevées avant leur remise à zéro.
	# forage_time n'est remis à zéro qu'à l'entrée de FORAGE : on le fait aussi ici,
	# sinon un trajet sans butinage hériterait de la valeur du trajet précédent.
	var forage_time := bee.forage_time
	var cut_short := bee.trip_cut_short
	bee.trip_time = 0.0
	bee.forage_time = 0.0
	bee.trip_cut_short = false

	# Aucune source connue
	if not is_instance_valid(flower):
		bee.known_profitability = 0.0
		bee.known_efficiency = 0.0
		return -1

	# Distance à plat et angle de danse (utilisés par DANCE et par le coût du vol)
	bee.distance = sim.get_flat_distance(bee.hive.global_position, flower.global_position)
	bee.angle = sim.get_dance_angle(flower.global_position, bee.hive.global_position)

	# Pas de butinage pendant ce trajet (nuit tombée en GO, source réservée puis
	# exploration bredouille), ou butinage écourté par la nuit : l'abeille n'a rien
	# appris de nouveau sur la source. Elle garde son jugement et y retournera.
	if forage_time <= 0.0 or cut_short:
		return 0

	# Efficacité énergétique du trajet
	bee.known_efficiency = _energetic_efficiency(sugar, bee.distance, forage_time)
	bee.known_profitability = _efficiency_to_profitability(bee.known_efficiency)

	# Seuils : au-dessus de high on danse, en dessous de low on abandonne
	if bee.known_profitability >= sim.profitability_high:
		return 1
	if bee.known_profitability < sim.profitability_low:
		return -1
	return 0


## Efficacité énergétique (gain - coût) / coût d'un trajet : [param sugar] mg
## de sucre rapportés d'une source à [param distance] m (à l'échelle de la scène),
## après [param forage_time] s passées dans le massif.
## Négative si le trajet a coûté plus qu'il n'a rapporté (jabot vide).
func _energetic_efficiency(sugar: float, distance: float, forage_time: float) -> float:
	var sim := bee.simulation
	var gain := sugar * sim.sugar_energy
	# Vol aller-retour, distance ramenée à l'échelle réelle du terrain de butinage
	var flight_cost := 2.0 * distance * sim.distance_scale * sim.flight_cost_per_m
	var forage_cost := forage_time * sim.forage_power
	var cost := maxf(flight_cost + forage_cost, 0.001)
	return (gain - cost) / cost


## Ramène une efficacité énergétique entre 0 et 1, sur une échelle logarithmique :
## 0 à efficiency_min et en dessous, 1 à efficiency_max et au-dessus.
## Le logarithme compare les sources par rapports et non par différences :
## passer de 5 à 10 compte autant que passer de 25 à 50 (choix de modélisation).
func _efficiency_to_profitability(efficiency: float) -> float:
	var sim := bee.simulation
	var e_min := maxf(sim.efficiency_min, 0.001)
	var e_max := maxf(sim.efficiency_max, e_min * 1.001)
	if efficiency <= e_min:
		return 0.0
	return clampf(log(efficiency / e_min) / log(e_max / e_min), 0.0, 1.0)
