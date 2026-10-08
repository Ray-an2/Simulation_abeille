class_name ScoutState extends FieldState

## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

var _direction := Vector3.ZERO
var _target_direction := Vector3.ZERO
var _time_before_turn := 0.0

const TURN_INTERVAL_MIN := 0.8   # secondes
const TURN_INTERVAL_MAX := 2.0
const TURN_SMOOTHNESS := 2.0     # plus petit = virage plus lent

## Reset du timer à chaque entrée dans l'état
func enter() -> void:
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
			randf_range(-1, 1),
			randf_range(-0.3, 0.3),   # peu de variation verticale, plus naturel
			randf_range(-1, 1)
		).normalized()
		_time_before_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)

	# Virage progressif vers le cap cible
	_direction = _direction.lerp(_target_direction, TURN_SMOOTHNESS * delta).normalized()

	# Orienter l'abeille vers l'avant
	if _direction.length() > 0.01:
		bee.look_at(bee.global_position + _direction, Vector3.UP)

	bee.position += _direction * bee.simulation.fly_speed * delta
	return bee.scout
