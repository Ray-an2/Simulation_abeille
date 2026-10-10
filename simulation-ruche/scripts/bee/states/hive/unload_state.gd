class_name UnloadState extends HiveState
## Déchargement du nectar sur le rayon, puis évaluation de la source visitée.
## Sorties :  1 (rentable) -> DANCE    0 (moyenne) -> GO    -1 (mauvaise ou vide) -> IDLE

## Point du rayon où l'abeille va décharger (tiré au hasard à l'entrée)
var _target: Vector3


func enter() -> void:
	# Point au hasard sur le cadre (position monde)
	_target = bee.hive.get_random_spawn_transform().origin


func update(delta: float) -> BeeState:
	# Marcher jusqu'au point de déchargement
	bee.walk_towards(_target, delta, bee.hive.get_comb_normal())
	if not bee.is_near(_target, bee.simulation.arrival_radius):
		return null

	# Décharger le nectar dans la ruche
	if bee.nectar > 0.0:
		bee.hive.deposit(bee.nectar)
		bee.nectar = 0.0

	# Évaluer la source et choisir l'état suivant
	var verdict := _evaluate_source()
	if verdict == 1:
		return bee.dance
	if verdict == 0:
		return bee.go

	# Source mauvaise ou vide : l'abeille l'oublie
	bee.known_flower = null
	bee.known_profitability = 0.0
	return bee.idle


## Calcule la rentabilité de la source (0 à 1) et renvoie 1, 0 ou -1.
func _evaluate_source() -> int:
	var sim := bee.simulation
	var flower := bee.known_flower

	# Le trajet est terminé : on lit le chrono puis on le remet à zéro
	var trip := bee.trip_time
	bee.trip_time = 0.0

	# Aucune source connue, ou source épuisée
	if not is_instance_valid(flower) or flower.is_empty():
		bee.known_profitability = 0.0
		return -1

	# Distance à plat et angle de danse (utilisés par DANCE)
	bee.distance = sim.get_flat_distance(bee.hive.global_position, flower.global_position)
	bee.angle = sim.get_dance_angle(flower.global_position, bee.hive.global_position)

	# Trois scores entre 0 (mauvais) et 1 (excellent)
	var stock_score := flower.get_profitability()
	var distance_score := 1.0 - clampf(bee.distance / sim.max_source_distance, 0.0, 1.0)
	var time_score := 1.0 - clampf(trip / sim.max_trip_time, 0.0, 1.0)

	# Moyenne pondérée (poids réglables dans simulation.gd)
	var total_weight := maxf(sim.weight_stock + sim.weight_distance + sim.weight_time, 0.001)
	bee.known_profitability = (
		sim.weight_stock * stock_score
		+ sim.weight_distance * distance_score
		+ sim.weight_time * time_score
	) / total_weight

	# Seuils : au-dessus de high on danse, en dessous de low on abandonne
	if bee.known_profitability >= sim.profitability_high:
		return 1
	if bee.known_profitability < sim.profitability_low:
		return -1
	return 0
