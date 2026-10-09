class_name GoState extends FieldState

## Position de la fleur visée
var _target: Vector3

func enter() -> void:
	if is_instance_valid(bee.known_flower):
		_target = bee.known_flower.get_landing_position()

func update(delta: float) -> BeeState:
	var flower := bee.known_flower
	
	# Aucun source connue
	if not is_instance_valid(flower): return bee.scout
	
	# Vol vers la fleur
	bee.fly_towards(_target, delta)
	
	# On reste dans GO si on est pas arrivé
	if not bee.is_near(_target, bee.simulation.arrival_radius): return null
	
	# Arrivé et null: on explore
	if flower.is_empty():
		bee.known_flower=null
		bee.known_profitability=0.0
		return bee.scout
	
	# Arrivé et non null : butiner
	return bee.forage
