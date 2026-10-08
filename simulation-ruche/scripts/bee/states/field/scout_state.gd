class_name ScoutState extends FieldState

## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		return bee.return_home
	# TODO : détecter une fleur à portée (→ FORAGE)
	else :
		var direction := Vector3.ZERO
		direction = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		bee.look_at(direction)
		bee.position += direction * bee.simulation.fly_speed * delta
	return null

