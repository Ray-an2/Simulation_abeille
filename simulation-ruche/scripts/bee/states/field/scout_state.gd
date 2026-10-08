class_name ScoutState extends FieldState
## État d'exploration : l'abeille erre autour de la ruche jusqu'à repérer une fleur
## non vide (→ elle vole vers elle puis passe en FORAGE), ou manque de temps (→ RETURN_HOME).

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
const SCOUT_DURATION := 20.0       # secondes avant d'abandonner et de rentrer

# Errance (quand aucune fleur n'est à portée)
const TURN_INTERVAL_MIN := 0.8     # secondes entre deux changements de cap
const TURN_INTERVAL_MAX := 2.0
const TURN_SMOOTHNESS := 2.0       # plus petit = virage plus lent
const LOOK_AHEAD := 10.0           # distance du point visé devant l'abeille
const VERTICAL_VARIATION := 0.3    # peu de variation verticale : plus naturel

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

# Errance
var _direction := Vector3.ZERO
var _target_direction := Vector3.ZERO
var _time_before_turn := 0.0

# Fleur
var _flower: Flower = null
var _target: Vector3    # position d'atterrissage de la fleur visée


# ---------------------------------------------------------------------------
# Cycle de vie de l'état
# ---------------------------------------------------------------------------
## Reset du timer à chaque entrée dans l'état + cap initial.
func enter() -> void:
	#bee.play_animation(&"_bee_take_off")
	bee.play_animation(&"_bee_hover")
	_remaining = SCOUT_DURATION
	_flower = null
	_direction = bee.global_transform.basis.z.normalized()
	_target_direction = _direction
	_time_before_turn = 0.0


func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		return bee.return_home

	_update_flower_search()

	if _flower != null:
		bee.fly_towards(_target, delta)
		if bee.is_near(_target, bee.simulation.arrival_radius):
			bee.known_flower = _flower
			return bee.forage
	else:
		_wander(delta)

	return null


# ---------------------------------------------------------------------------
# Recherche de fleur
# ---------------------------------------------------------------------------
## Abandonne la fleur visée si elle est vide, et en cherche une nouvelle si besoin.
func _update_flower_search() -> void:
	if _flower != null and _flower.is_empty():
		_flower = null

	if _flower == null:
		_flower = _find_flower()
		if _flower != null:
			_target = _flower.get_landing_position()


## Fleur non vide la plus proche dans le rayon de perception, ou null.
func _find_flower() -> Flower:
	var best: Flower = null
	var best_d2 := bee.simulation.perception_radius ** 2
	for f in bee.simulation.flowers:
		if f.is_empty():
			continue
		var d2 := bee.global_position.distance_squared_to(f.get_landing_position())
		if d2 < best_d2:
			best = f
			best_d2 = d2
	return best


# ---------------------------------------------------------------------------
# Déplacement : errance
# ---------------------------------------------------------------------------
## Vol libre avec virages progressifs, utilisé tant qu'aucune fleur n'est repérée.
func _wander(delta: float) -> void:
	# Nouveau cap de temps en temps seulement
	_time_before_turn -= delta
	if _time_before_turn <= 0.0:
		_target_direction = _random_direction()
		_time_before_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)

	# Trop loin de la ruche : on revient vers elle
	var to_hive := bee.hive.global_position - bee.global_position
	if to_hive.length() > bee.simulation.scout_radius:
		_target_direction = to_hive.normalized()

	# Virage progressif (évite les changements de cap brusques)
	_direction = _direction.lerp(_target_direction, TURN_SMOOTHNESS * delta).normalized()

	# On réutilise le vol de Bee : orientation + déplacement à fly_speed
	bee.fly_towards(bee.global_position + _direction * LOOK_AHEAD, delta)


func _random_direction() -> Vector3:
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-VERTICAL_VARIATION, VERTICAL_VARIATION),
		randf_range(-1.0, 1.0)
	).normalized()
