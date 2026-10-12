class_name Flower extends Node3D
## Source de nectar. Chaque fleur a son propre automate à trois états :
##   - AVAILABLE : peut être butinée ;
##   - BUSY : une abeille la butine (request_foraging() a réussi) ;
##   - EMPTY : stock sous le seuil, fermée jusqu'à ce que la sécrétion
##     l'ait fait remonter à reopen_level.
## Le stock baisse de harvest_amount à chaque butinage (boucle d'épuisement)
## et remonte en continu par sécrétion, dans tous les états.
##
## Modèle de sécrétion (Búrquez & Corbet, 1991) : le débit apparent est la
## sécrétion brute moins une réabsorption proportionnelle au stock présent,
## dR/dt = s - a·R. Le stock tend donc exponentiellement vers un plafond
## (max_resource = s/a), avec la constante de temps 1/a :
##   - une fleur vidée sécrète vite, une fleur presque pleine presque plus ;
##   - une fleur jamais butinée reste pleine, sans « déborder ».
## La sécrétion ralentit la nuit (night_secretion_factor dans Simulation).
##
## Une abeille réserve la fleur dès qu'elle décide d'y aller (try_claim()),
## et non au moment où elle s'y pose : les autres la voient occupée et en
## cherchent une autre, au lieu de s'agglutiner sur le même pistil.
## Équivalent réel : la marque odorante que l'abeille laisse sur la fleur visitée.

# =============================================================================
# Signaux
# =============================================================================

## Émis à chaque changement d'état (AVAILABLE, BUSY, EMPTY).
signal state_changed(new_state: State)

## Émis à la fin d'un butinage, une fois le nectar prélevé.
## Écouté par ForageState pour remplir le jabot de l'abeille.
signal foraging_finished(flower: Flower)

# =============================================================================
# Types
# =============================================================================

## États possibles de la fleur.
enum State { AVAILABLE, BUSY, EMPTY }

## Espèces disponibles, déduites du nom de la scène instanciée.
enum Species { LILY, ROSE_BLUE, ROSE_RED }

# =============================================================================
# Constantes
# =============================================================================

## Constante de temps de la sécrétion (heures simulées) par espèce : en une
## constante de temps, la fleur regagne 63 % du nectar qui lui manque, en trois
## 95 %. Convertie en temps réel par Simulation.hours_from() : elle suit donc
## la durée de la journée simulée. Valeurs de réglage, reprises des anciens
## temps de recharge : l'ordre des espèces est conservé.
const SECRETION_TAU := {
	Species.LILY: 2.0,
	Species.ROSE_BLUE: 4.0,
	Species.ROSE_RED: 6.0,
}

## Écart (unités) au stock maximal en dessous duquel la fleur est considérée
## pleine. Nécessaire : une exponentielle n'atteint jamais exactement son plafond,
## et le _process ne se couperait jamais.
const FULL_EPSILON := 0.05

## Libellés de l'espèce affichés dans l'interface (infobulles, tableau de bord).
const SPECIES_LABELS := {
	Species.LILY: "Lys",
	Species.ROSE_BLUE: "Rose bleue",
	Species.ROSE_RED: "Rose rouge",
}

## Libellés de l'état affichés dans l'interface (infobulles, tableau de bord).
const STATE_LABELS := {
	State.AVAILABLE: "Disponible",
	State.BUSY: "Occupée",
	State.EMPTY: "Fermée, en sécrétion",
}

# =============================================================================
# Paramètres
# =============================================================================

## Matériau des pelotes de pollen récoltées sur cette espèce.
## Réglé une fois dans la scène de l'espèce (lys.tscn, roseb.tscn, roser.tscn),
## et non sur chacune des trente instances.
@export var pollen_material: StandardMaterial3D

# =============================================================================
# État
# =============================================================================

## Espèce de la fleur, fixée dans _ready().
var species: Species

## Constante de temps de sécrétion (heures simulées) de cette fleur, tirée de SECRETION_TAU.
var secretion_tau: float

## Référence vers la simulation, injectée par setup(). Donne les paramètres
## de stock (max_resource, threshold, reopen_level, harvest_amount,
## night_secretion_factor) et l'horloge simulée.
var simulation: Simulation

## État courant de l'automate. Lu par le HUD.
var state: State = State.AVAILABLE

## Stock de nectar restant. Lu par le HUD et par get_profitability().
var resource: float

## true pendant un butinage. Doublon de State.BUSY, conservé par sécurité
## contre deux request_foraging() dans la même image.
var locked: bool = false

## Abeille qui a réservé la fleur : celle qui vole vers elle ou la butine.
## null si personne. Empêche plusieurs abeilles de viser la même fleur.
var _claimant: Bee = null

## Temps restant (s réelles) du butinage en cours, en BUSY.
var _timer: float = 0.0

## Point de pose de l'abeille, sur le pistil. Son axe Y sort de la corolle.
@onready var _pistil_marker: Marker3D = $PistilMarker

# =============================================================================
# Cycle de vie
# =============================================================================

## Inscrit la fleur dans le groupe lu par Simulation, détecte son espèce
## et coupe le _process tant que la fleur est pleine et non butinée.
func _ready() -> void:
	# Groupe lu par Simulation._ready() pour construire la liste des fleurs.
	# Fait ici plutôt que dans les scènes : lys, roseb et roser en héritent toutes.
	add_to_group(&"flowers")
	species = _detect_species()
	secretion_tau = SECRETION_TAU[species]
	set_process(false)

## Appelée par Simulation au lancement : injecte la simulation et remplit le stock.
func setup(sim: Simulation) -> void:
	simulation = sim
	resource = simulation.max_resource

## Actif tant que la fleur n'est pas pleine, ou pendant un butinage :
## sécrétion, fin du butinage, réouverture d'une fleur vide.
func _process(delta: float) -> void:
	# Sécrétion : dans tous les états, y compris pendant un butinage
	_secrete(simulation.hours_from(delta))

	match state:
		State.BUSY:
			# Le butinage dure quelques secondes réelles
			_timer -= delta
			if _timer <= 0.0:
				_finish_foraging()
		State.EMPTY:
			# Réouverture avec une marge au-dessus du seuil : sans elle, la fleur
			# rouvrirait juste au-dessus et se refermerait au prélèvement suivant
			if resource >= simulation.reopen_level:
				_change_state(State.AVAILABLE)

	# Fleur pleine et libre : plus rien à calculer. request_foraging()
	# réactive le _process au prochain butinage.
	if state == State.AVAILABLE and resource >= simulation.max_resource:
		set_process(false)

# =============================================================================
# Réservation (appelée par les états de l'abeille)
# =============================================================================

## true si [param bee] peut viser la fleur : ni vide, ni réservée par une autre abeille.
func is_free_for(bee: Bee) -> bool:
	return state != State.EMPTY and (_claimant == null or _claimant == bee)

## Réserve la fleur pour [param bee]. Renvoie false si elle est vide ou déjà
## réservée par une autre. Sans effet si [param bee] la détient déjà : on peut
## donc l'appeler à chaque image sans risque.
func try_claim(bee: Bee) -> bool:
	if not is_free_for(bee):
		return false
	_claimant = bee
	return true

## Libère la réservation, uniquement si elle appartient à [param bee] :
## une abeille ne peut pas libérer la fleur d'une autre.
func release(bee: Bee) -> void:
	if _claimant == bee:
		_claimant = null

# =============================================================================
# Butinage (appelé par ForageState)
# =============================================================================

## Démarre un butinage si la fleur est disponible : elle passe en BUSY pour une
## durée tirée entre foraging_time_min et foraging_time_max, puis émet
## foraging_finished. Renvoie false si elle est occupée ou vide.
func request_foraging() -> bool:
	if state != State.AVAILABLE or locked:
		return false
	locked = true
	_timer = randf_range(simulation.foraging_time_min, simulation.foraging_time_max)
	_change_state(State.BUSY)
	set_process(true)
	return true

## true si la fleur est fermée (stock passé sous le seuil, pas encore remonté).
func is_empty() -> bool:
	return state == State.EMPTY

# =============================================================================
# Requêtes
# =============================================================================

## Position où l'abeille se pose : le pistil.
func get_landing_position() -> Vector3:
	return _pistil_marker.global_position

## Normale de la corolle au point de pose : axe Y de PistilMarker, qui doit sortir de la fleur.
## Sert au stationnaire et à la pose (FieldState.update_landing()).
## Normalisée : une instance mise à l'échelle ne doit pas fausser la hauteur de stationnaire.
func get_landing_normal() -> Vector3:
	return _pistil_marker.global_basis.y.normalized()

## Rentabilité entre 0 et 1 selon le stock restant : 0 au seuil, 1 stock plein.
func get_profitability() -> float:
	if state == State.EMPTY:
		return 0.0
	var range_size := maxf(simulation.max_resource - simulation.threshold, 0.001)
	return clampf((resource - simulation.threshold) / range_size, 0.0, 1.0)

# =============================================================================
# Lecture seule (appelé par l'interface : BeeOverlay)
# =============================================================================

## Abeille qui a réservé la fleur (en vol vers elle ou en train de la butiner), ou null.
func get_claimant() -> Bee:
	return _claimant if is_instance_valid(_claimant) else null

## Débit de sécrétion courant (1/heure simulée) : 1/tau le jour,
## réduit par night_secretion_factor la nuit.
func get_secretion_rate() -> float:
	var factor := 1.0 if simulation.is_daytime() else simulation.night_secretion_factor
	return factor / maxf(secretion_tau, 0.001)

## Heures simulées avant que le stock atteigne reopen_level, au débit actuel
## et sans prélèvement. Inversion de l'exponentielle de _secrete() :
## t = ln((max - R) / (max - reopen)) / débit.
## 0 si le niveau est déjà atteint, INF s'il ne peut pas l'être
## (sécrétion nocturne nulle, ou reopen_level au niveau du plafond).
## Estimation : le débit change au passage jour / nuit.
func get_reopen_remaining() -> float:
	var max_res := simulation.max_resource
	if resource >= simulation.reopen_level:
		return 0.0
	var rate := get_secretion_rate()
	var gap_target := max_res - simulation.reopen_level
	if rate <= 0.0 or gap_target <= 0.0:
		return INF
	return log((max_res - resource) / gap_target) / rate

## Nom de l'espèce en français (Lys, Rose bleue, Rose rouge).
func get_species_label() -> String:
	return SPECIES_LABELS.get(species, "?")

## Nom de l'état en français (Disponible, Occupée, Fermée, en sécrétion).
func get_state_label() -> String:
	return STATE_LABELS.get(state, "?")

# =============================================================================
# Utilitaires internes
# =============================================================================

## Fait remonter le stock pendant [param hours] heures simulées.
## Solution exacte de dR/dt = débit × (max - R) sur le pas de temps, et non un pas
## d'Euler : le résultat ne dépend pas de la fréquence d'images et ne dépasse
## jamais le plafond, même avec une journée simulée très accélérée.
func _secrete(hours: float) -> void:
	var max_res := simulation.max_resource
	resource = max_res - (max_res - resource) * exp(-get_secretion_rate() * hours)
	if max_res - resource < FULL_EPSILON:
		resource = max_res

## Fin du butinage : prélève le nectar, prévient l'abeille, puis repasse en
## AVAILABLE si le stock reste au-dessus du seuil, sinon en EMPTY.
## Le _process reste actif : la fleur n'est plus pleine, la sécrétion continue.
func _finish_foraging() -> void:
	resource = maxf(resource - simulation.harvest_amount, 0.0)
	locked = false
	foraging_finished.emit(self)

	if resource > simulation.threshold:
		_change_state(State.AVAILABLE)
	else:
		_change_state(State.EMPTY)

## Change l'état de la fleur et émet state_changed.
func _change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)

## Espèce déduite du nom de la scène instanciée (lys, roseb, roser) :
## évite un réglage manuel sur chacune des trente instances.
func _detect_species() -> Species:
	var scene_name := scene_file_path.get_file().get_basename().to_lower()
	match scene_name:
		"lys":
			return Species.LILY
		"roseb":
			return Species.ROSE_BLUE
		"roser":
			return Species.ROSE_RED
	push_warning("Flower: espèce inconnue pour la scène '%s', Lys par défaut." % scene_name)
	return Species.LILY
