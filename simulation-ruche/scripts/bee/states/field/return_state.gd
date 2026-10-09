class_name ReturnState extends FieldState
## Retour vers la ruche : vol jusqu'à la planche d'envol, puis entrée à pied (ENTER).

func update(delta: float) -> BeeState:
	var landing := bee.hive.get_landing_position()
	bee.fly_towards(landing, delta)
	if bee.is_near(landing, bee.simulation.arrival_radius):
		return bee.enter_hive
	return null
