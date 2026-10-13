class_name UnloadState extends HiveState
## Déchargement du nectar sur le rayon, puis évaluation de la source visitée.
## Déroulé : marche jusqu'à un point du rayon -> file d'attente de la ruche ->
## transfert à une receveuse -> dépôt du nectar -> évaluation de la source.
## Sorties : DANCE (source au-dessus du seuil de danse), GO (source gardée sans danse),
##           IDLE (source abandonnée sous profitability_low).
##
## Seuil de danse variable (Seeley) : la butineuse ne connaît pas les réserves de la
## colonie, mais elle perçoit le temps qu'elle met à trouver une receveuse.
##   - attente courte : peu de nectar rentre, la colonie a besoin de recruter :
##     seuil bas (dance_threshold_min), une source moyenne suffit ;
##   - attente longue : la colonie est bien approvisionnée : seuil haut
##     (profitability_high), seules les meilleures sources sont annoncées.
## Chaque abeille ajoute son propre écart (Bee.dance_threshold_offset) : la réponse
## de la colonie est graduelle, et non tout ou rien.
##
## Rentabilité : efficacité énergétique du trajet, (gain - coût) / coût, mesure
## utilisée par Seeley pour relier la qualité d'une source à l'intensité de la danse
## (calcul dans Bee.trip_efficiency()).
##   - gain : énergie du sucre rapporté (volume × concentration, goûté en FORAGE) ;
##   - coût : vol aller à vide, retour chargé (distance perçue par le flux optique),
##     et temps passé dans le massif.
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

	# Sucre et masse du chargement : relevés avant le vidage du jabot,
	# ils servent à l'évaluation
	var sugar := bee.sugar
	var load := bee.load_mass

	# Décharger le nectar dans la ruche
	if bee.nectar > 0.0:
		bee.hive.deposit(bee.nectar, sugar)
		bee.nectar = 0.0
		# Nectar déchargé : les pelotes disparaissent
		bee.update_pollen()
	bee.sugar = 0.0
	bee.load_mass = 0.0

	# Évaluer la source et choisir l'état suivant
	var verdict := _evaluate_source(sugar, load)
	if verdict == -1:
		# Source mauvaise ou vide : l'abeille l'oublie
		bee.forget_source()
		return bee.idle

	if verdict == 1:
		var sim := bee.simulation
		var wait_ratio := clampf(_waited / sim.max_wait_time, 0.0, 1.0)
		# Seuil de danse : bas si une receveuse l'a prise en charge tout de suite,
		# haut si elle a attendu longtemps, plus son écart individuel
		var threshold := lerpf(sim.dance_threshold_min, sim.profitability_high, wait_ratio) \
				+ bee.dance_threshold_offset
		# Saturation de la ruche : l'attente réduit aussi la durée de la danse
		var dance_quality := bee.known_profitability * (1.0 - sim.wait_penalty * wait_ratio)
		if dance_quality >= threshold:
			bee.known_profitability = dance_quality   # DANCE : durée proportionnelle
			return bee.dance

	# Source gardée sans danse (sous le seuil du moment, ou rien de nouveau appris) :
	# sortie à pied jusqu'à la planche, puis vol vers la source
	return go_out_if_day(bee.go)


## Calcule la rentabilité de la source (0 à 1) à partir de [param sugar], masse
## de sucre (mg) rapportée, et de [param load], masse du nectar (mg) transporté
## au retour. Renvoie :
##    1 : source évaluée et gardée, la danse dépend du seuil du moment ;
##    0 : rien de nouveau appris pendant ce trajet, source gardée sans danse ;
##   -1 : source inconnue ou trop peu rentable, à abandonner.
func _evaluate_source(sugar: float, load: float) -> int:
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
	bee.known_efficiency = bee.trip_efficiency(sugar, load, bee.distance, forage_time)
	bee.known_profitability = _efficiency_to_profitability(bee.known_efficiency)

	# Sous le seuil bas, l'abeille abandonne la source. Au-dessus, la danse est
	# décidée dans update() selon l'attente à la ruche (seuil variable).
	if bee.known_profitability < sim.profitability_low:
		return -1
	return 1


## Ramène une efficacité énergétique entre 0 et 1, sur une échelle logarithmique :
## 0 quand le trajet n'a rien rapporté de net (efficacité nulle ou négative),
## 1 à efficiency_max et au-dessus.
## log(1 + e) : nul en 0, puis compare les sources par rapports plutôt que par
## différences (choix de modélisation). Avec efficiency_max = 60 :
## 0,2 (abandon) vers e ≈ 1,3 ; 0,6 (danse) vers e ≈ 11.
func _efficiency_to_profitability(efficiency: float) -> float:
	if efficiency <= 0.0:
		return 0.0
	var e_max := maxf(bee.simulation.efficiency_max, 0.001)
	return clampf(log(1.0 + efficiency) / log(1.0 + e_max), 0.0, 1.0)
