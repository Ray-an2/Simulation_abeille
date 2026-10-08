class_name ReturnState extends FieldState

func update(delta: float) -> BeeState:
	var landing := bee.hive.get_landing_position()
	bee.fly_towards(landing, delta)
	if bee.is_near(landing, 0.00005):
		return bee.idle
	return null
