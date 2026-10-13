class_name ReceiveState extends HiveState
## Receveuse de nectar (« food storer », Seeley 1989). Attend les butineuses dans la
## zone de déchargement, en bas du cadre côté entrée, reçoit leur nectar, le monte
## jusqu'aux cellules de stockage en haut du cadre, puis redescend en attendre une autre.
##
## Entrée : depuis IDLE, par engagement spontané (Simulation.p_receive). Réservé aux
## abeilles sans source connue : les butineuses ne deviennent pas receveuses
## (Seeley, Kühnholz et Weidenmüller 1996 : aucune vieille abeille parmi les recrues).
## Sortie : IDLE, quand aucune butineuse ne l'a sollicitée pendant receiver_idle_timeout.
##
## Régulation sans vue d'ensemble : une receveuse souvent sollicitée reste dans l'état,
## une receveuse désœuvrée retourne en IDLE. Le nombre de receveuses suit donc l'afflux
## de nectar, alors que chacune ne perçoit que ses propres contacts.
##
## Ventilation : une receveuse non sollicitée peut monter ventiler au-dessus des
## réserves (Phase.TO_FAN puis Phase.FAN). Les receveuses appartiennent à la classe
## d'âge « intermédiaire » (environ 11 à 20 jours, Seeley 1982), qui assure aussi la
## ventilation : il s'agit d'un changement de tâche entre deux sollicitations, pas
## d'un rôle exclusif. Sur le rayon, la ventilation renouvelle l'air et évapore l'eau
## du nectar en cours de mûrissement. Pas de condition sur Hive.nectar_stock : ce
## compteur part de zéro au lancement, alors qu'une vraie colonie a déjà des réserves
## (miel et nectar non mûr des jours précédents).
## Partie ventiler, la receveuse n'est plus disponible pour les butineuses : elle se
## retire du registre des receveuses libres jusqu'à son retour dans la zone de
## déchargement. Ventiler a donc un coût pour la boucle de saturation.
##
## Non modélisé : la ventilation à l'entrée de la ruche (thermorégulation), la plus
## visible en réalité (Peters et al. 2019). Elle demanderait un trajet jusqu'au tunnel
## et une température de la ruche pour la déclencher.
##
## Simplification : la receveuse ne cherche pas les butineuses, ce sont elles qui la
## trouvent en la croisant (UnloadState). En réalité, les deux vont à la rencontre
## l'une de l'autre dans la zone de déchargement.

# =============================================================================
# Constantes
# =============================================================================

## Distance (m) d'arrivée à un point visé. Doit dépasser le rayon de virage
## du walker (walk_speed × 1,3 / STEER_RATE ≈ 0,9 cm), sinon l'abeille tourne autour.
const ARRIVAL_RADIUS := 0.012

## Vitesse de virage (rad/s) vers le point visé.
const STEER_RATE := 3.0

## Virages aléatoires (rad/s) pendant l'attente : déambulation sur place.
const WAIT_TURN_RATE := 2.0

## Facteur de vitesse pendant l'attente (multiplie walk_speed) : les receveuses
## se déplacent lentement dans la zone de déchargement. Valeur de réglage.
const WAIT_SPEED := 0.4

## Garde-fou : un transfert dure au plus unload_duration × ce facteur, plus le temps
## de mise en place. Au-delà, la butineuse est considérée comme partie et la receveuse
## se libère.
const TRANSFER_TIMEOUT_FACTOR := 2.0

## Temps maximal (s) laissé à la butineuse pour se placer tête contre tête.
## Doit dépasser UnloadState.APPROACH_TIMEOUT.
const MAX_APPROACH_TIME := 3.0

## Probabilité par seconde qu'une receveuse en attente parte ventiler.
## 0,01 : 100 s d'attente en moyenne, du même ordre que receiver_idle_timeout.
## Une valeur plus forte viderait la zone de déchargement (la receveuse s'absente
## le temps du trajet aller-retour et de la ventilation) et renforcerait fortement
## la boucle de saturation. Valeur de réglage, non mesurée.
const FAN_START_RATE := 0.01

## Durée (s) d'une séquence de ventilation, tirée entre ces deux bornes.
## Une ventileuse reste sur place de plusieurs dizaines de secondes à plusieurs
## minutes ; bornes raccourcies pour que l'alternance reste visible.
## Valeurs de réglage, non mesurées.
const FAN_DURATION_MIN := 15.0
const FAN_DURATION_MAX := 60.0

# =============================================================================
# Types
# =============================================================================

## Étapes du travail de receveuse.
enum Phase {
	TO_AREA,   ## Marche vers la zone de déchargement (libre : peut être sollicitée)
	WAIT,      ## Attente dans la zone de déchargement (libre)
	TO_FAN,    ## Monte vers les réserves pour ventiler (indisponible)
	FAN,       ## Ventile au-dessus des réserves (indisponible)
	TRANSFER,  ## Se tourne vers la butineuse et reçoit son nectar (occupée)
	TO_STORE,  ## Monte vers les cellules de stockage (occupée)
	STORE,     ## Dépose le nectar dans une cellule (occupée)
}

## Libellés pour l'interface.
const PHASE_LABELS := {
	Phase.TO_AREA: "Rejoint la zone de déchargement",
	Phase.WAIT: "Attend une butineuse",
	Phase.TO_FAN: "Monte ventiler au-dessus des réserves",
	Phase.FAN: "Ventile au-dessus des réserves",
	Phase.TRANSFER: "Reçoit du nectar",
	Phase.TO_STORE: "Monte stocker le nectar",
	Phase.STORE: "Dépose le nectar en cellule",
}

# =============================================================================
# État interne
# =============================================================================

## Étape en cours.
var _phase := Phase.TO_AREA

## Point visé : dans la zone de déchargement ou dans la zone de stockage
## (dépôt du nectar ou ventilation).
var _target := Vector3.ZERO

## Temps (s) passé libre depuis le dernier transfert (ou depuis l'entrée dans l'état).
var _idle_time := 0.0

## Butineuse en cours de transfert, null hors de TRANSFER.
var _forager: Bee = null

## Temps (s) écoulé depuis le début du transfert (garde-fou).
var _transfer_time := 0.0

## Temps restant (s) du dépôt en cellule.
var _store_left := 0.0

## Temps restant (s) de la séquence de ventilation en cours.
var _fan_left := 0.0

## Nectar (µL) et sucre (mg) reçus, portés jusqu'à la cellule.
## Gardés ici et non dans bee.nectar : bee.nectar pilote les pelotes de pollen
## et le compteur de nectar livré du tracker, propres aux butineuses.
var _load_nectar := 0.0
var _load_sugar := 0.0

## Nombre de chargements stockés depuis l'entrée dans l'état (interface).
var _loads_stored := 0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_reset_wander()
	_forager = null
	_load_nectar = 0.0
	_load_sugar = 0.0
	_loads_stored = 0
	_idle_time = 0.0
	_fan_left = 0.0
	bee.hive.register_receiver(bee)
	_go_to_area()

func exit() -> void:
	bee.hive.unregister_receiver(bee)
	# Interrompue avec du nectar (ne devrait pas arriver) : déposé sur place, pas perdu
	if _load_nectar > 0.0:
		bee.hive.deposit(_load_nectar, _load_sugar)
		_load_nectar = 0.0
		_load_sugar = 0.0
	_forager = null

func update(delta: float) -> BeeState:
	match _phase:
		Phase.TO_AREA:
			_idle_time += delta
			if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.WAIT
				_target = bee.hive.get_unloading_point()

		Phase.WAIT:
			_idle_time += delta
			# Désœuvrée trop longtemps : la colonie a plus de receveuses que de nectar
			# à traiter, elle retourne à l'attente générale
			if _idle_time >= bee.simulation.receiver_idle_timeout:
				return bee.idle
			# Tirage par seconde, multiplié par delta : indépendant de la fréquence d'images
			if randf() < FAN_START_RATE * delta:
				_start_fanning()
			else:
				_wander_in_area(delta)

		Phase.TO_FAN:
			_idle_time += delta
			if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.FAN

		Phase.FAN:
			_idle_time += delta
			# Même règle qu'en WAIT : ventiler ne compte pas comme une sollicitation.
			# Désœuvrée trop longtemps, elle rejoint l'attente générale depuis le haut du cadre
			if _idle_time >= bee.simulation.receiver_idle_timeout:
				return bee.idle
			_update_fanning(delta)

		Phase.TRANSFER:
			# Sur place : c'est la butineuse qui vient se placer en face, décompte
			# la durée du transfert et appelle take_load() à la fin
			_transfer_time += delta
			var limit := bee.simulation.unload_duration * TRANSFER_TIMEOUT_FACTOR \
					+ MAX_APPROACH_TIME
			if not is_instance_valid(_forager) or _transfer_time > limit:
				_forager = null
				bee.walker.reset()
				_go_to_area()
			else:
				# Pivote pour faire face à la butineuse : échange tête contre tête
				_turn_to_face(_forager.global_position, FACE_TURN_RATE, delta)

		Phase.TO_STORE:
			if _walk_to(_target, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.STORE
				_store_left = bee.simulation.store_duration
				bee.play_animation(&"_bee_idle")

		Phase.STORE:
			_store_left -= delta
			if _store_left <= 0.0:
				# Le nectar n'entre dans les réserves qu'une fois en cellule
				bee.hive.deposit(_load_nectar, _load_sugar)
				_load_nectar = 0.0
				_load_sugar = 0.0
				_loads_stored += 1
				_idle_time = 0.0
				# Repart de l'arrêt, dans la direction où elle se trouve
				bee.walker.reset()
				_go_to_area()
	return null

# =============================================================================
# Échanges avec la butineuse (appelé par UnloadState)
# =============================================================================

## Début du transfert avec [param forager], qui vient de la trouver libre
## (Hive.claim_receiver_near l'a déjà retirée des receveuses libres).
## La receveuse s'arrête et se tourne vers elle pendant qu'elle se met en place.
func start_transfer(forager: Bee) -> void:
	_forager = forager
	_transfer_time = 0.0
	_idle_time = 0.0
	_phase = Phase.TRANSFER
	bee.play_animation(&"_bee_idle")

## Fin du transfert : la receveuse prend [param nectar] µL contenant [param sugar] mg
## de sucre et part les stocker. Renvoie false si elle n'est pas en transfert avec
## [param forager] (garde-fou déclenché entre-temps) : la butineuse dépose alors
## elle-même le nectar pour qu'il ne soit pas perdu.
func take_load(forager: Bee, nectar: float, sugar: float) -> bool:
	if _phase != Phase.TRANSFER or forager != _forager:
		return false
	_load_nectar += nectar
	_load_sugar += sugar
	_forager = null
	_phase = Phase.TO_STORE
	_target = bee.hive.get_storage_point()
	_reset_wander()
	bee.walker.reset()
	return true

## Transfert interrompu par la butineuse (changement d'état imprévu) :
## la receveuse redevient libre.
func cancel_transfer(forager: Bee) -> void:
	if _phase != Phase.TRANSFER or forager != _forager:
		return
	_forager = null
	bee.walker.reset()
	_go_to_area()

# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## true si la receveuse peut être sollicitée par une butineuse.
## Une receveuse partie ventiler ne l'est pas (voir _start_fanning).
func is_free() -> bool:
	return _phase == Phase.TO_AREA or _phase == Phase.WAIT

## Temps (s) passé libre depuis le dernier transfert.
func get_idle_time() -> float:
	return _idle_time

## Nectar (µL) porté vers les cellules : non nul entre take_load() et le dépôt.
## Distinct de bee.nectar, réservé aux butineuses (voir _load_nectar).
func get_load_nectar() -> float:
	return _load_nectar

## Chargements stockés depuis l'entrée dans l'état.
func get_loads_stored() -> int:
	return _loads_stored

## Libellé de l'étape en cours.
func get_phase_label() -> String:
	return PHASE_LABELS.get(_phase, "?")

# =============================================================================
# Utilitaires internes
# =============================================================================

## Retourne vers la zone de déchargement, disponible pour les butineuses.
func _go_to_area() -> void:
	_phase = Phase.TO_AREA
	_target = bee.hive.get_unloading_point()
	bee.hive.set_receiver_free(bee, true)

## Déambulation lente dans la zone de déchargement : un nouveau point est tiré
## à chaque arrivée, ce qui garde la receveuse dans la zone sans la figer.
func _wander_in_area(delta: float) -> void:
	_wander_turn(delta, WAIT_TURN_RATE)
	bee.walker.steer_towards(_target, STEER_RATE, delta)
	bee.walker.step(WAIT_SPEED * _wander_speed(delta), delta)
	if bee.is_near(_target, ARRIVAL_RADIUS):
		_target = bee.hive.get_unloading_point()

## Départ vers la zone de stockage pour une séquence de ventilation.
## La receveuse quitte le registre des receveuses libres : loin de la zone de
## déchargement, aucune butineuse ne la croiserait de toute façon, et le compteur
## de receveuses libres de l'interface resterait faux.
## L'animation n'est lancée qu'une fois l'abeille arrêtée (voir _update_fanning).
func _start_fanning() -> void:
	_phase = Phase.TO_FAN
	_target = bee.hive.get_storage_point()
	_fan_left = randf_range(FAN_DURATION_MIN, FAN_DURATION_MAX)
	bee.hive.set_receiver_free(bee, false)

## Ventilation sur place : l'abeille finit de freiner, puis bat des ailes
## sans bouger jusqu'à la fin de la séquence.
func _update_fanning(delta: float) -> void:
	# Freinage : step() continue d'avancer en ralentissant, puis passe en _bee_idle
	# à l'arrêt complet. On ne l'appelle plus ensuite, sinon il imposerait
	# _bee_idle à chaque frame et écraserait _bee_fan.
	if not bee.walker.is_stopped():
		bee.walker.step(0.0, delta)
		return

	# play_animation() ne relance pas une animation déjà en cours :
	# l'appel à chaque frame est sans effet une fois _bee_fan démarrée
	bee.play_animation(&"_bee_fan")

	_fan_left -= delta
	if _fan_left <= 0.0:
		# Redescend vers la zone de déchargement, de nouveau disponible.
		# Nouveaux tirages de virage et de vitesse, départ de l'arrêt
		_reset_wander()
		bee.walker.reset()
		_go_to_area()
