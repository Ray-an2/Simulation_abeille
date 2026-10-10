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
# Trajets entre le cadre et la planche d'envol (LEAVE, ENTER)
# =============================================================================

## Marche sur le plancher : tendance vers la cible (rad/s) et virages aléatoires (rad/s).
const FLOOR_STEER_RATE := 3.0
const FLOOR_TURN_RATE := 2.0

## Distance d'arrivée (m) sur le plancher. Doit dépasser le rayon de virage
## (walk_speed × 1,3 / FLOOR_STEER_RATE ≈ 0,9 cm), sinon l'abeille tourne autour.
const FLOOR_ARRIVAL_RADIUS := 0.01

## Traversée du tunnel : guidage serré, presque pas d'errance.
const TUNNEL_STEER_RATE := 8.0
const TUNNEL_TURN_RATE := 0.3
const TUNNEL_EXIT_RADIUS := 0.005

## Distance (m) de fin des déplacements en ligne droite (move_toward atteint la cible exactement).
const EXACT_RADIUS := 0.0005

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

## Marche en ligne droite vers [param target] (planche d'envol, où la hauteur peut différer
## de celle du tunnel), en freinant derrière une voisine située devant.
## Pas de contournement : les abeilles font la queue à l'embouchure du tunnel.
## Le freinage n'est jamais total (AVOID_BRAKE < 1), pour que deux abeilles face à face
## ne se bloquent pas indéfiniment.
func _walk_straight(target: Vector3, speed: float, delta: float) -> void:
	var brake := 1.0
	# Direction de marche dans le plan horizontal, pour savoir qui est « devant »
	var forward := (target - bee.global_position).slide(Vector3.UP)
	if not forward.is_zero_approx():
		var urgency := minf(bee.walker.get_avoidance(forward.normalized()).length(), 1.0)
		brake = 1.0 - CombWalker.AVOID_BRAKE * urgency
	bee.walk_towards(target, delta, Vector3.UP, speed * brake)

## Marche sur le plancher jusqu'à [param target], avec une errance modérée.
## Renvoie true à l'arrivée.
func _walk_on_floor(target: Vector3, delta: float) -> bool:
	return _walk_to(target, FLOOR_STEER_RATE, FLOOR_ARRIVAL_RADIUS, delta, FLOOR_TURN_RATE)

## Traverse le tunnel jusqu'à [param tunnel_end] (extrémité intérieure ou extérieure).
## L'abeille s'aligne sur l'axe et y reste ; le walker continue d'éviter
## et de freiner derrière les autres abeilles. Renvoie true à la sortie.
func _walk_through_tunnel(tunnel_end: Vector3, delta: float) -> bool:
	return _walk_to(tunnel_end, TUNNEL_STEER_RATE, TUNNEL_EXIT_RADIUS, delta, TUNNEL_TURN_RATE)

## Ligne droite jusqu'à [param target] (planche d'envol, embouchure du tunnel).
## Renvoie true à l'arrivée exacte.
func _walk_straight_to(target: Vector3, delta: float) -> bool:
	_walk_straight(target, _wander_speed(delta), delta)
	return bee.is_near(target, EXACT_RADIUS)

# =============================================================================
# File d'attente (variable) 
# =============================================================================
var nectar_stock := 0.0
var _unload_queue: Array[Bee] = []
var _queue_entry: Dictionary = {}       # Bee -> instant d'entrée dans la file
var _measured_wait: Dictionary = {}     # Bee -> attente mesurée à la prise en charge
var _receiver_free_at: Array[float] = []
var _clock := 0.0                       # horloge de la ruche, arrêtée par la pause

# =============================================================================
# File d'attente (fonction) 
# =============================================================================

func _physics_process(delta: float) -> void:
	_clock += delta

## Renvoie true quand une receveuse prend l'abeille en charge, sinon elle reste en file.
func try_unload(bee: Bee) -> bool:
	if not _queue_entry.has(bee):
		_queue_entry[bee] = _clock
		_unload_queue.append(bee)
	# Seule la première de la file peut prendre une receveuse libre
	if _unload_queue[0] != bee:
		return false
	var slot := _find_free_receiver(bee.simulation.receiver_count)
	if slot == -1:
		return false
	_receiver_free_at[slot] = _clock + bee.simulation.unload_duration
	_unload_queue.pop_front()
	_measured_wait[bee] = _clock - _queue_entry[bee]
	return true

func _find_free_receiver(count: int) -> int:
	while _receiver_free_at.size() < count:
		_receiver_free_at.append(0.0)
	for i in count:
		if _receiver_free_at[i] <= _clock:
			return i
	return -1

## Temps d'attente de l'abeille, en cours ou terminé.
func get_wait_time(bee: Bee) -> float:
	if _measured_wait.has(bee):
		return _measured_wait[bee]
	if _queue_entry.has(bee):
		return _clock - _queue_entry[bee]
	return 0.0

## Retire l'abeille de la file et efface ses mesures.
func leave_unload_queue(bee: Bee) -> void:
	_unload_queue.erase(bee)
	_queue_entry.erase(bee)
	_measured_wait.erase(bee)

## Ajoute le nectar au stock de la ruche.
func deposit(amount: float) -> void:
	nectar_stock += amount

## Longueur de la file, pour observer la saturation.
func get_queue_length() -> int:
	return _unload_queue.size()
