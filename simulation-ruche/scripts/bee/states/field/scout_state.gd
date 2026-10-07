class_name ScoutState extends FieldState

## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		return bee.return_home
	# TODO : détecter une fleur à portée (→ FORAGE)
	return null

