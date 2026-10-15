class_name UnloadState extends HiveState
## Déchargement du nectar à une receveuse, puis évaluation de la source visitée.
## Déroulé : marche vers la zone de déchargement (bas du cadre, côté entrée) ->
## recherche d'une receveuse libre au contact -> mise en place tête contre tête ->
## transfert (trophallaxie) -> évaluation de la source.
## Sorties : DANCE (source au-dessus du seuil de danse), GO (source gardée sans danse),
##           TREMBLE (bonne source, mais receveuse très longue à trouver),
##           IDLE (source abandonnée sous profitability_low).
##
## Pas de file d'attente : la butineuse ne trouve une receveuse qu'en la croisant.
## Son temps de recherche, qu'elle mesure elle-même, est d'autant plus long que les
## receveuses libres sont rares : il reflète le rapport entre la récolte et la capacité
## de traitement de la colonie (Seeley et Tovey 1994).
##
## Seuil de danse variable (Seeley) : la butineuse ne connaît pas les réserves de la
## colonie, mais elle perçoit le temps qu'elle met à trouver une receveuse.
##   - recherche courte : la colonie traite tout ce qui rentre, elle peut recruter :
##     seuil bas (dance_threshold_min), une source moyenne suffit ;
##   - recherche longue : la colonie est débordée : seuil haut
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
##
## Bilan par espèce : l'espèce du nectar (bee.crop_species) passe à la receveuse avec
## le nectar, pour le bilan des réserves de la ruche (Hive.deposit). Donnée
## d'observation : elle n'intervient pas dans l'évaluation de la source.

# =============================================================================
# Constantes
# =============================================================================

## Distance (m) d'arrivée à un point de la zone de déchargement. Doit dépasser le rayon
## de virage du walker (walk_speed × 1,3 / STEER_RATE ≈ 0,9 cm), sinon l'abeille tourne autour.
const ARRIVAL_RADIUS := 0.012

## Vitesse de virage (rad/s) vers le point visé.
const STEER_RATE := 3.0

## Virages aléatoires (rad/s) pendant la recherche : plus francs que la marche dirigée,
## la butineuse sonde les abeilles autour d'elle.
const SEARCH_TURN_RATE := 2.5

## La recherche d'une receveuse au contact ne se fait que toutes les N frames physiques.
const CONTACT_CHECK_STEP := 2

## Vitesse (facteur de walk_speed) du dernier pas vers la receveuse.
const APPROACH_SPEED := 0.5

## Distance (m) d'arrivée au point de rencontre (marche en ligne droite, move_toward).
const MEET_RADIUS := 0.001

## Écart (m) entre les deux têtes pendant le transfert : la receveuse tend sa langue
## vers la gouttelette que la butineuse tient entre ses mandibules.
const TROPHALLAXIS_GAP := 0.001

## Durée maximale (s) de la mise en place : passé ce délai, le transfert commence
## même si l'alignement n'est pas parfait (voisine qui gêne, bord du cadre).
## Doit rester inférieure à ReceiveState.MAX_APPROACH_TIME.
const APPROACH_TIMEOUT := 2.0

# =============================================================================
# Types
# =============================================================================

## Étapes du déchargement.
enum Phase {
	TO_AREA,   ## Marche vers la zone de déchargement (une receveuse croisée en route convient)
	SEARCH,    ## Déambulation dans la zone jusqu'à croiser une receveuse libre
	APPROACH,  ## Se place tête contre tête avec la receveuse trouvée
	TRANSFER,  ## Transfert du nectar à la receveuse (trophallaxie)
}

# =============================================================================
# État interne
# =============================================================================

## Point visé dans la zone de déchargement, renouvelé à chaque arrivée.
var _target: Vector3

## Étape en cours.
var _phase := Phase.TO_AREA

## Temps restant (s) du transfert à la receveuse.
var _transfer_left := 0.0

## Temps (s) passé à chercher une receveuse, de l'entrée dans l'état au contact.
var _search_time := 0.0

## Receveuse trouvée, null avant le contact.
var _receiver: Bee = null

## Temps (s) passé à se mettre en place face à la receveuse.
var _approach_time := 0.0

## Décalage propre à chaque abeille : les tests de contact sont étalés sur les frames.
var _check_offset := 0

## Point où la butineuse se place face à la receveuse, fixé au contact.
var _meet_point := Vector3.ZERO

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	# Nouveaux tirages de virage et de vitesse dès la première frame
	_reset_wander()
	_target = bee.hive.get_unloading_point()
	_phase = Phase.TO_AREA
	_search_time = 0.0
	_receiver = null
	_check_offset = randi() % CONTACT_CHECK_STEP
	# Comptée parmi les butineuses en recherche (interface uniquement)
	bee.hive.start_search(bee)

func exit() -> void:
	bee.hive.stop_search(bee)
	# Interrompue pendant la mise en place ou le transfert : la receveuse redevient libre
	if (_phase == Phase.APPROACH or _phase == Phase.TRANSFER) and _is_receiving(_receiver):
		_receiver.receive.cancel_transfer(bee)
	_receiver = null
	# La mise en place déplace l'abeille sans le walker : on le recale sur son
	# orientation actuelle, comme en sortie de DANCE
	bee.walker.reset()

func update(delta: float) -> BeeState:
	match _phase:
		# Marche puis recherche : une receveuse libre au contact interrompt les deux
		Phase.TO_AREA, Phase.SEARCH:
			_search_time += delta
			if _try_contact():
				return null
			if _phase == Phase.TO_AREA:
				if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
					_phase = Phase.SEARCH
					_target = bee.hive.get_unloading_point()
			# Recherche : nouveau point de la zone à chaque arrivée
			elif _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta, SEARCH_TURN_RATE):
				_target = bee.hive.get_unloading_point()
			return null

		# Mise en place tête contre tête avec la receveuse
		Phase.APPROACH:
			_update_approach(delta)
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

	# Le nectar passe à la receveuse, qui le stockera en cellule.
	# Son espèce l'accompagne, pour le bilan des réserves par espèce
	if bee.nectar > 0.0:
		_hand_over(bee.nectar, sugar, bee.crop_species)
		bee.nectar = 0.0
		# Nectar déchargé : les pelotes disparaissent
		bee.update_pollen()
	bee.sugar = 0.0
	bee.load_mass = 0.0
	# Jabot vide : plus d'espèce associée
	bee.crop_species = -1
	# Transfert terminé : exit() ne doit pas annuler quoi que ce soit
	_receiver = null

	# Évaluer la source et choisir l'état suivant
	var verdict := _evaluate_source(sugar, load)
	if verdict == -1:
		# Source mauvaise ou vide : l'abeille l'oublie
		bee.forget_source()
		return bee.idle

	if verdict == 1:
		var sim := bee.simulation
		# Recherche très longue, pour une source qu'elle aurait annoncée sans
		# saturation : la colonie manque de receveuses, elle fait la danse trémulante.
		# Seeley (1992) : recherche > 50 s → trémulante, < 20 s → frétillante.
		if _search_time >= sim.tremble_wait_threshold and bee.known_profitability \
				>= sim.dance_threshold_min + bee.dance_threshold_offset:
			return bee.tremble
		var wait_ratio := clampf(_search_time / sim.max_wait_time, 0.0, 1.0)
		# Seuil de danse : bas si une receveuse a été trouvée tout de suite,
		# haut si la recherche a été longue, plus l'écart individuel
		var threshold := lerpf(sim.dance_threshold_min, sim.profitability_high, wait_ratio) \
				+ bee.dance_threshold_offset
		# Saturation de la ruche : la recherche réduit aussi la durée de la danse
		var dance_quality := bee.known_profitability * (1.0 - sim.wait_penalty * wait_ratio)
		if dance_quality >= threshold:
			bee.known_profitability = dance_quality   # DANCE : durée proportionnelle
			return bee.dance

	# Source gardée sans danse (sous le seuil du moment, ou rien de nouveau appris) :
	# sortie à pied jusqu'à la planche, puis vol vers la source
	return go_out_if_day(bee.go)

# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## Temps (s) passé à chercher une receveuse : en cours pendant la recherche,
## figé au contact.
func get_search_time() -> float:
	return _search_time

## true dès qu'une receveuse est trouvée : mise en place, puis transfert.
func is_transferring() -> bool:
	return _phase == Phase.APPROACH or _phase == Phase.TRANSFER

# =============================================================================
# Receveuse
# =============================================================================

## Cherche une receveuse libre au contact. Testé une frame sur CONTACT_CHECK_STEP.
## Renvoie true si une receveuse est trouvée : la mise en place commence.
func _try_contact() -> bool:
	if (Engine.get_physics_frames() + _check_offset) % CONTACT_CHECK_STEP != 0:
		return false
	var receiver := bee.hive.claim_receiver_near(bee, bee.simulation.unload_contact_radius)
	if receiver == null:
		return false
	_receiver = receiver
	# La receveuse s'arrête et se tourne vers la butineuse
	_receiver.receive.start_transfer(bee)
	bee.hive.stop_search(bee)
	_meet_point = _compute_meet_point()
	_approach_time = 0.0
	_phase = Phase.APPROACH
	return true

## Point où se tient la butineuse pour être tête contre tête avec la receveuse :
## sur la droite qui les relie, à deux distances centre-tête (plus TROPHALLAXIS_GAP)
## du centre de la receveuse. La butineuse y arrive en marchant vers la receveuse,
## donc déjà tournée vers elle.
func _compute_meet_point() -> Vector3:
	var normal := bee.hive.get_comb_normal()
	var away := (bee.global_position - _receiver.global_position).slide(normal)
	if away.is_zero_approx():
		# Pile au même endroit (ne devrait pas arriver) : la butineuse recule
		away = -bee.global_basis.z.slide(normal)
	var spacing := bee.get_head_offset() + _receiver.get_head_offset() + TROPHALLAXIS_GAP
	return bee.hive.clamp_to_comb(_receiver.global_position + away.normalized() * spacing)

## Rejoint le point de rencontre en ligne droite, puis finit de se tourner vers
## la receveuse. Le transfert commence une fois face à face, ou au bout de
## APPROACH_TIMEOUT si la place est prise.
func _update_approach(delta: float) -> void:
	# Receveuse disparue (garde-fou) : la recherche reprend
	if not _is_receiving(_receiver):
		_receiver = null
		bee.walker.reset()
		bee.hive.start_search(bee)
		_phase = Phase.SEARCH
		return

	_approach_time += delta
	var in_place := bee.is_near(_meet_point, MEET_RADIUS)
	var facing := false
	if in_place:
		facing = _turn_to_face(_receiver.global_position, FACE_TURN_RATE, delta) <= FACE_TOLERANCE
	else:
		bee.walk_towards(_meet_point, delta, bee.hive.get_comb_normal(), APPROACH_SPEED)

	if (in_place and facing) or _approach_time > APPROACH_TIMEOUT:
		_transfer_left = bee.simulation.unload_duration
		_phase = Phase.TRANSFER
		bee.play_animation(&"_bee_idle")

## Remet [param nectar] µL contenant [param sugar] mg de sucre, issus de l'espèce
## [param species] (Flower.Species, -1 si inconnue), à la receveuse.
## Si elle n'est plus là (garde-fou), le nectar est déposé directement pour ne pas
## fausser le bilan de la colonie, avec son espèce pour ne pas fausser non plus
## le bilan par espèce.
func _hand_over(nectar: float, sugar: float, species: int) -> void:
	if _is_receiving(_receiver) and _receiver.receive.take_load(bee, nectar, sugar, species):
		return
	bee.hive.deposit(nectar, sugar, species)

## true si [param receiver] existe encore et est toujours dans l'état RECEIVE.
func _is_receiving(receiver: Bee) -> bool:
	return is_instance_valid(receiver) and receiver.current_state == receiver.receive

# =============================================================================
# Évaluation de la source
# =============================================================================

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
	# décidée dans update() selon la durée de la recherche (seuil variable).
	if bee.known_profitability < sim.profitability_low:
		return -1
	return 1


## Ramène une efficacité énergétique entre 0 et 1, sur une échelle logarithmique :
## 0 quand le trajet n'a rien rapporté de net (efficacité nulle ou négative),
## 1 à efficiency_max et au-dessus.
## log(1 + e) : nul en 0, puis compare les sources par rapports plutôt que par
## différences (choix de modélisation). Avec efficiency_max = 60 :
## 0,2 (abandon) vers e ≈ 1,3 ; 0,6 (danse) vers e ≈ 11.
## StatsCollector._to_profitability en est une copie (prévision du panneau F1) :
## à modifier en même temps.
func _efficiency_to_profitability(efficiency: float) -> float:
	if efficiency <= 0.0:
		return 0.0
	var e_max := maxf(bee.simulation.efficiency_max, 0.001)
	return clampf(log(1.0 + efficiency) / log(1.0 + e_max), 0.0, 1.0)
