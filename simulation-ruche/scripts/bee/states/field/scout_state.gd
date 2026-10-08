class_name ScoutState extends FieldState

## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

var _direction := Vector3.ZERO
var _target_direction := Vector3.ZERO
var _time_before_turn := 0.0

const TURN_INTERVAL_MIN := 0.8   # secondes entre deux changements de cap
const TURN_INTERVAL_MAX := 2.0
const TURN_SMOOTHNESS := 2.0     # plus petit = virage plus lent
const LOOK_AHEAD := 10.0         # distance du point visé devant l'abeille

## Reset du timer à chaque entrée dans l'état + cap initial
func enter() -> void:
	_direction = bee.global_transform.basis.z.normalized()
	_target_direction = _direction
	_time_before_turn = 0.0
	_remaining=20.0

## Fonction de déplacement et de recherche de fleur(pas encore implémentée)
func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		return bee.return_home

	# TODO : détecter une fleur à portée (→ FORAGE)

	# Nouveau cap de temps en temps seulement
	_time_before_turn -= delta
	if _time_before_turn <= 0.0:
		_target_direction = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.3, 0.3),   # peu de variation verticale : plus naturel
			randf_range(-1.0, 1.0)
		).normalized()
		_time_before_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)

	# Virage progressif (évite les changements de cap brusques)
	_direction = _direction.lerp(_target_direction, TURN_SMOOTHNESS * delta).normalized()

	# On réutilise le vol de Bee : orientation + déplacement à fly_speed
	bee.fly_towards(bee.global_position + _direction * LOOK_AHEAD, delta)
	return null
