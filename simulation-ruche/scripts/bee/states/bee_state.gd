class_name BeeState extends RefCounted
 
var bee: Bee
 
func _init(owner_bee: Bee) -> void:
	bee = owner_bee
 
func enter() -> void:
	pass
 
func exit() -> void:
	pass
 
## Renvoie l'état suivant, ou null pour rester dans l'état courant.
func update(_delta: float) -> BeeState:
	return null
	
## Transition prioritaire, testée par Bee avant update(). Permet à un super-état
## d'imposer une sortie commune à tous ses sous-états (ex. : rentrée à la nuit).
## Renvoie l'état suivant, ou null s'il n'y a rien à imposer.
func interrupt() -> BeeState:
	return null
