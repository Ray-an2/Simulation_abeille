class_name HiveState extends BeeState
## Super-état « Ruche » : états où l'abeille marche dans la ruche (cadre, plancher, tunnel).
## La locomotion commune (cap, vitesse, évitement) est dans CombWalker, via bee.walker.
## Ce super-état sert à Bee.change_state() pour détecter les passages Ruche ↔ Dehors,
## et regroupe les utilitaires d'errance des états qui se déplacent vers un but
## (LEAVE, ENTER) : virages aléatoires et variations de vitesse.

# =============================================================================
# Constantes
# =============================================================================

## Vitesse de virage aléatoire maximale (rad/s) par défaut.
const WANDER_TURN_RATE := 1.5

## Intervalle (s) entre deux tirages de vitesse de virage.
const TURN_CHANGE_MIN := 0.2
const TURN_CHANGE_MAX := 0.8

## Facteur de vitesse (multiplie walk_speed), retiré au hasard régulièrement.
const SPEED_FACTOR_MIN := 0.7
const SPEED_FACTOR_MAX := 1.3

## Intervalle (s) entre deux tirages de vitesse.
const SPEED_CHANGE_MIN := 0.5
const SPEED_CHANGE_MAX := 1.5

# =============================================================================
# État interne de l'errance
# =============================================================================

## Vitesse de virage aléatoire actuelle (rad/s) et temps avant le prochain tirage (s).
var _turn_rate := 0.0
var _turn_change_time := 0.0

## Facteur de vitesse visé actuellement et temps avant le prochain tirage (s).
var _speed_factor := 1.0
var _speed_change_time := 0.0

# =============================================================================
# Utilitaires pour les états
# =============================================================================

## Force un nouveau tirage de virage et de vitesse dès la prochaine frame.
## À appeler dans enter() des états qui utilisent l'errance.
func _reset_wander() -> void:
	_turn_change_time = 0.0
	_speed_change_time = 0.0

## Fait tourner le cap du walker selon une vitesse de virage aléatoire,
## retirée de temps en temps, d'au plus [param max_rate] rad/s.
func _wander_turn(delta: float, max_rate: float = WANDER_TURN_RATE) -> void:
	_turn_change_time -= delta
	if _turn_change_time <= 0.0:
		_turn_rate = randf_range(-max_rate, max_rate)
		_turn_change_time = randf_range(TURN_CHANGE_MIN, TURN_CHANGE_MAX)
	bee.walker.turn(_turn_rate * delta)

## Renvoie le facteur de vitesse visé, retiré au hasard de temps en temps.
## Le walker le rejoint progressivement (accélération / décélération).
func _wander_speed(delta: float) -> float:
	_speed_change_time -= delta
	if _speed_change_time <= 0.0:
		_speed_factor = randf_range(SPEED_FACTOR_MIN, SPEED_FACTOR_MAX)
		_speed_change_time = randf_range(SPEED_CHANGE_MIN, SPEED_CHANGE_MAX)
	return _speed_factor

## Marche vers [param target] avec le walker, en combinant une tendance vers la cible
## ([param steer_rate] rad/s) et des virages aléatoires (au plus [param max_turn] rad/s).
## Renvoie true quand l'abeille est à moins de [param radius] de la cible.
## [param radius] doit dépasser le rayon de virage (walk_speed × vitesse / steer_rate),
## sinon l'abeille tourne autour de la cible sans l'atteindre.
func _walk_to(target: Vector3, steer_rate: float, radius: float, delta: float,
		max_turn: float = WANDER_TURN_RATE, steer_from_edges: bool = true) -> bool:
	_wander_turn(delta, max_turn)
	bee.walker.steer_towards(target, steer_rate, delta)
	bee.walker.step(_wander_speed(delta), delta, steer_from_edges)
	return bee.is_near(target, radius)
