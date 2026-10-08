class_name ReturnState extends FieldState

func update(delta: float) -> BeeState:
	var landing := bee.hive.get_landing_position()
	bee.fly_towards(landing, delta)
	if bee.is_near(landing, 0):
		bee.play_animation(&"_bee_land")
		return bee.idle
	return null
