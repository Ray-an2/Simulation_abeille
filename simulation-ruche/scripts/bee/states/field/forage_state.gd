class_name ForageState extends FieldState

## Fleur butinée récupérer dans bee.know_flower 
var _flower: Flower = null

## Boolean qui est true tant que l'abeille tient la fleur
var _foraging : bool

## Boolean qui est false tant que l'abeille n'a pas terminé de butinée
var _harvest_done : bool

func enter() -> void:
	bee.land()   # posée : le départ vers la ruche repartira d'un décollage
	bee.play_animation(&"_bee_idle")
	_flower = bee.known_flower
	_foraging = false
	_harvest_done = false

func exit() -> void:
	if is_instance_valid(_flower) and _flower.foraging_finished.is_connected(_on_foraging_finished):
		_flower.foraging_finished.disconnect(_on_foraging_finished)
	_flower = null

func update(_delta: float) -> BeeState:
	# Fleur non present -> Etat RETURN
	if not is_instance_valid(_flower): return bee.return_home
	# Butinage terminé
	if _harvest_done:
		_harvest_done = false
		var capacity := bee.simulation.forage_capacity
		bee.nectar += minf(bee.simulation.harvest_amount, capacity - bee.nectar)
		# Abeille pleine -> Etat RETURN
		if bee.nectar >= capacity: return bee.return_home
 
	# Fleur vide -> Etat RETURN
	if _flower.is_empty(): return bee.return_home
 
	# Butinage en cours : on attend la fin
	if _foraging: return null
 
	# Sinon on tente de prendre la fleur (échoue si une autre abeille y butine)
	if _flower.request_foraging():
		_foraging = true
		_flower.foraging_finished.connect(_on_foraging_finished, CONNECT_ONE_SHOT)
	return null

## Signal de fin de butinage par la fleur saisi
func _on_foraging_finished(_source: Flower) -> void:
	_foraging = false
	_harvest_done = true
