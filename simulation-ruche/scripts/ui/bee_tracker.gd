class_name BeeTracker extends Node
## Tient pour chaque abeille un historique : temps passé dans l'état, dernières
## transitions, compteurs de vie, vitesse mesurée et origine de la source connue.
##
## Les transitions arrivent par le signal Bee.state_changed, au moment exact où
## elles ont lieu. Le reste (nectar, source, position) est observé à chaque image
## physique, en comparant avec l'image précédente.

# =============================================================================
# Constantes
# =============================================================================

## Nombre de transitions gardées par abeille.
const LOG_SIZE := 6

## Lissage de la vitesse mesurée (1/s) : évite les sauts d'une image à l'autre.
const SPEED_SMOOTHING := 5.0

# =============================================================================
# Types
# =============================================================================

## Historique d'une abeille.
class Record:
	## Nom de classe de l'état courant (IdleState…) et instant d'entrée (horloge du tracker).
	var state_name: StringName = &""
	var state_since := 0.0

	## Dernières transitions, la plus récente en premier : {"time", "from", "to"}.
	var transitions: Array[Dictionary] = []

	## Retours à la ruche, dont ceux sans nectar.
	var trips := 0
	var empty_trips := 0

	## Nectar total déposé dans la ruche.
	var nectar_delivered := 0.0

	## Danses commencées.
	var dances := 0

	## Comment la source actuelle a été connue : &"scout", &"dance", ou &"" sans source.
	var source_origin: StringName = &""

	## Vitesse mesurée (m/s), lissée.
	var speed := 0.0

	# Valeurs de l'image précédente, pour détecter les changements
	var last_nectar := 0.0
	var last_flower: Flower = null
	var last_position := Vector3.ZERO

# =============================================================================
# Paramètres réglables
# =============================================================================

## Conteneur des abeilles créées par Simulation (Simulation/Bees).
@export var bees_container: Node3D

# =============================================================================
# État interne
# =============================================================================

## Horloge du tracker (s). Comme elle avance dans _physics_process, elle s'arrête
## avec la pause du jeu, en même temps que les abeilles.
var clock := 0.0

## Bee → Record. Non typé : les classes internes ne sont pas acceptées partout
## comme type de valeur d'un dictionnaire typé.
var _records: Dictionary = {}

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	if bees_container == null:
		push_warning("BeeTracker : bees_container non assigné, aucune abeille ne sera suivie")


func _physics_process(delta: float) -> void:
	clock += delta
	if bees_container == null:
		return
	for node in bees_container.get_children():
		var bee := node as Bee
		if bee == null or bee.current_state == null:
			continue
		var rec: Record = _records.get(bee)
		if rec == null:
			_records[bee] = _create_record(bee)
			# Transitions reçues au moment exact où elles ont lieu
			bee.state_changed.connect(_on_state_changed)
		else:
			_observe(bee, rec, delta)

# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## Historique de [param bee], ou null si elle n'a pas encore été observée.
func get_record(bee: Bee) -> Record:
	return _records.get(bee)


## Nom de classe de l'état courant de [param bee] (IdleState, ScoutState…),
## tiré du class_name du script de l'état.
static func state_of(bee: Bee) -> StringName:
	return _name_of(bee.current_state)


## Nom de classe de [param state], ou &"" pour null (premier appel de change_state).
static func _name_of(state: BeeState) -> StringName:
	return state.get_script().get_global_name() if state != null else &""

# =============================================================================
# Observation
# =============================================================================

## Premier passage : on part de l'état actuel, sans transition ni compteur.
func _create_record(bee: Bee) -> Record:
	var rec := Record.new()
	rec.state_name = state_of(bee)
	rec.state_since = clock
	rec.last_nectar = bee.nectar
	rec.last_flower = bee.known_flower if is_instance_valid(bee.known_flower) else null
	rec.last_position = bee.global_position
	return rec


## Une transition de [param bee] : journal, temps dans l'état, danses, voyages.
func _on_state_changed(bee: Bee, from: BeeState, to: BeeState) -> void:
	var rec: Record = _records.get(bee)
	if rec == null:
		return
	var from_name := _name_of(from)
	var to_name := _name_of(to)
	rec.transitions.push_front({"time": clock, "from": from_name, "to": to_name})
	if rec.transitions.size() > LOG_SIZE:
		rec.transitions.pop_back()
	rec.state_name = to_name
	rec.state_since = clock
	if to is DanceState:
		rec.dances += 1
	# Dehors → Ruche : un voyage de plus. Le nectar n'est pas encore déchargé.
	if from is FieldState and to is HiveState:
		rec.trips += 1
		if bee.nectar <= 0.0:
			rec.empty_trips += 1


## Compare l'abeille à l'image précédente : nectar livré, nouvelle source, vitesse.
func _observe(bee: Bee, rec: Record, delta: float) -> void:
	# --- Déchargement : seul UNLOAD fait baisser la charge ---
	if bee.nectar < rec.last_nectar:
		rec.nectar_delivered += rec.last_nectar - bee.nectar
	rec.last_nectar = bee.nectar

	# --- Nouvelle source : apprise en suivant une danse, sinon trouvée en exploration ---
	var flower: Flower = bee.known_flower if is_instance_valid(bee.known_flower) else null
	if flower != rec.last_flower:
		if flower == null:
			rec.source_origin = &""
		elif _left_watch(rec):
			rec.source_origin = &"dance"
		else:
			rec.source_origin = &"scout"
		rec.last_flower = flower

	# --- Vitesse : distance parcourue depuis l'image précédente ---
	if delta > 0.0:
		var instant := bee.global_position.distance_to(rec.last_position) / delta
		rec.speed = lerpf(rec.speed, instant, 1.0 - exp(-SPEED_SMOOTHING * delta))
	rec.last_position = bee.global_position


## true si l'abeille est en WATCH ou vient d'en sortir : une source apparue à ce
## moment-là a été apprise en suivant une danse. Provisoire : remplacé par
## Bee.recruited_by avec l'amélioration « chaîne de recrutement ».
func _left_watch(rec: Record) -> bool:
	if rec.state_name == &"WatchState":
		return true
	return not rec.transitions.is_empty() and rec.transitions[0].from == &"WatchState"
