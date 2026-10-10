class_name Flower extends Node3D

## Matériau des pelotes de pollen récoltées sur cette espèce.
## Réglé une fois dans la scène de l'espèce (lys.tscn, roseb.tscn, roser.tscn),
## et non sur chacune des trente instances.
@export var pollen_material: StandardMaterial3D

## Signal de changement d'état
signal state_changed(new_state: State)

## Signal de fin de butinage de la fleur
signal foraging_finished(flower: Flower)

## Etat possible de la fleurs
enum State { AVAILABLE, BUSY, EMPTY }

## Type d'espèces disponibles
enum Species { LILY, ROSE_BLUE, ROSE_RED }

## Temps de recharge (heure simulées) par espèce défini
const RECHARGE_TIME := {
	Species.LILY: 2.0,
	Species.ROSE_BLUE: 4.0,
	Species.ROSE_RED: 6.0,
}

## Type de l'espèce 
var species : Species

## Temps de recharge (secondes) par espèces
var recharge_time: float

@onready var _pistil_marker: Marker3D = $PistilMarker

## Référence vers la simuation
var simulation: Simulation

# variable
var state: State = State.AVAILABLE
var resource: float
var locked: bool = false
var _timer: float = 0.0

## L'initialisation de la fleur
func _ready() -> void:
	species = _detect_species()
	recharge_time = RECHARGE_TIME[species]
	set_process(false)

## Appel Simulation au lancement
func setup(sim: Simulation) -> void:
	simulation = sim
	resource = simulation.max_resource

func _process(delta: float) -> void:
	_timer -= simulation.hours_from(delta)
	if _timer > 0.0:
		return
	match state:
		State.BUSY:
			_finish_foraging()
		State.EMPTY:
			_finish_recharge()

## Demande si c'est possible de butiner
func request_foraging() -> bool:
	if state != State.AVAILABLE or locked:
		return false
	locked = true
	_timer = randf_range(4.0, 5.0) / 60.0 # duration = random(4,5) secondes réel
	_change_state(State.BUSY)
	set_process(true)
	return true
	
## Vérifie l'état de la fleur après le butinage 
func _finish_foraging() -> void:
	resource -= simulation.harvest_amount
	locked = false
	foraging_finished.emit(self) # butinage terminé

	if resource > simulation.threshold:
		_change_state(State.AVAILABLE) # changement d'état
		set_process(false)
	else:
		_timer = recharge_time
		_change_state(State.EMPTY)

 
## Rend la fleur disponible avec ces ressources pleines 
func _finish_recharge() -> void:
	resource = simulation.max_resource
	_change_state(State.AVAILABLE)
	set_process(false)
 

## Change l'état de la fleur avec son nouvelle état en paramètre
func _change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)

func is_empty() -> bool:
	return state == State.EMPTY

## Retourne la position où l'abeille se pose
func get_landing_position() -> Vector3:
	return _pistil_marker.global_position

## Rentabilité entre 0 et 1 selon le stock restant
func get_profitability() -> float:
	if state == State.EMPTY: return 0.0
	var range_size := maxf(simulation.max_resource - simulation.threshold, 0.001)
	return clampf((resource - simulation.threshold) / range_size, 0.0, 0.1) 

## Détection de l'espece de fleurs
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
