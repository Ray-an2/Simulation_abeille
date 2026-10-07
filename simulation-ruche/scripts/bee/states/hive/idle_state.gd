class_name IdleState extends HiveState

func update(delta: float) -> BeeState:
	# TODO : détecter une danse à proximité (→ WATCH)
	# p_scout est une probabilité par seconde : × delta pour ne pas dépendre du framerate
	if randf() < bee.simulation.p_scout * delta:
		return bee.scout
	return null
