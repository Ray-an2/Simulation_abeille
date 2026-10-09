class_name Flower extends Node3D

## Signal de changement d'état
signal state_changed(new_state: State)

## Signal de fin de butinage de la fleur
signal foraging_finished(flower: Flower, amount: float)

## Etat possible de la fleurs
enum State { AVAILABLE, BUSY, EMPTY }

## Type d'espèces disponibles
enum Species { LILY, ROSE_BLUE, ROSE_RED }

## Temps de recharge (seconde réel) par espèce défini
const RECHARGE_TIME := {
	Species.LILY: 720.0,
	Species.ROSE_BLUE: 240.0,
	Species.ROSE_RED: 120.0,
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
	_timer -= delta
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
	_timer = randf_range(4.0, 5.0) # duration = random(4,5)
	_change_state(State.BUSY)
	set_process(true)
	return true
	
## Vérifie l'état de la fleur après le butinage 
func _finish_foraging() -> void:
	resource -= simulation.harvest_amount
	locked = false
	foraging_finished.emit(self, simulation.harvest_amount) # butinage terminé

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
