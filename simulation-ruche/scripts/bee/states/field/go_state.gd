class_name GoState extends FieldState
## Vol vers la source connue. Si la fleur est vide, l'abeille le constate pendant
## le stationnaire et repart explorer sans se poser ; sinon elle se pose et butine.

## Position de la fleur visée
var _target: Vector3

func enter() -> void:
	if is_instance_valid(bee.known_flower):
		_target = bee.known_flower.get_landing_position()
	begin_flight()   # décollage de la planche à la sortie de LEAVE

func update(delta: float) -> BeeState:
	var flower := bee.known_flower

	# Aucune source connue
	if not is_instance_valid(flower):
		return bee.scout

	if update_takeoff(delta):
		return null

	# Fleur vide constatée au stationnaire : on l'oublie et on explore, toujours en vol
	if is_hovering() and flower.is_empty():
		bee.known_flower = null
		bee.known_profitability = 0.0
		return bee.scout

	# Approche, stationnaire puis pose sur le pistil
	if update_landing(_target, flower.get_landing_normal(), HOVER_TIME_FLOWER, delta):
		return bee.forage
	return null
