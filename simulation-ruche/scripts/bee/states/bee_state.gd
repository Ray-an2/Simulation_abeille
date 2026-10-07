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
