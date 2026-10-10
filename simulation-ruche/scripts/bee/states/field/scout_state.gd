class_name ScoutState extends FieldState
## État d'exploration : l'abeille erre autour de la ruche jusqu'à repérer une fleur
## non vide (→ elle vole vers elle puis passe en FORAGE), ou manque de temps (→ RETURN_HOME).

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

# Vol de Lévy : beaucoup de segments courts, quelques très longs (changement de zone)
const LEVY_MU := 2.0               # ≈ 2 : stratégie optimale observée chez l'abeille
const SEGMENT_MIN := 0.5           # longueur minimale, à adapter à l'échelle de la scène
const SEGMENT_MAX := 10.0          # borne haute, pour ne pas sortir de scout_radius
const SEGMENT_TOLERANCE := 0.05    # distance à partir de laquelle un segment est terminé
const SEGMENT_MAX_TRIES := 5       # essais pour trouver un segment qui reste dans scout_radius
const VERTICAL_VARIATION := 0.3    # peu de variation verticale : plus naturel

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
## Temps restant avant d'abandonner et de rentrer.
var _remaining: float

# Errance (vol de Lévy)
var _segment_end := Vector3.ZERO    # point d'arrivée du segment en cours

# Fleur
var _flower: Flower = null
var _target: Vector3    # position d'atterrissage de la fleur visée


# ---------------------------------------------------------------------------
# Cycle de vie de l'état
# ---------------------------------------------------------------------------
## Reset du timer à chaque entrée dans l'état + cap initial.
func enter() -> void:
	#bee.play_animation_then(&"_bee_take_off", &"_bee_hover") #fonction à ajouter dans bee
	bee.play_animation(&"_bee_hover")
	_remaining = bee.simulation.scout_timeout
	_flower = null
	_pick_segment()


func update(delta: float) -> BeeState:
	_update_flower_search()
	
	if _flower != null:
		bee.fly_towards(_target, delta)
		if bee.is_near(_target, bee.simulation.arrival_radius):
			bee.known_flower = _flower
			return bee.forage
	else:
		_remaining -= delta
		if _remaining <= 0.0:
			return bee.return_home
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
# Déplacement : vol de Lévy
# ---------------------------------------------------------------------------
## Vole en ligne droite jusqu'à la fin du segment, puis en tire un nouveau.
## Le lissage des virages est assuré par Bee.fly_towards() (turn_speed).
func _wander(delta: float) -> void:
	bee.fly_towards(_segment_end, delta)
	if bee.is_near(_segment_end, SEGMENT_TOLERANCE):
		_pick_segment()
 
 
## Tire un nouveau cap et une nouvelle longueur. Si le segment sortirait de scout_radius,
## on retente ; après SEGMENT_MAX_TRIES échecs, on repart en direction de la ruche.
func _pick_segment() -> void:
	var origin := bee.global_position
	var hive_pos := bee.hive.global_position
	var max_dist := bee.simulation.scout_radius
 
	for i in SEGMENT_MAX_TRIES:
		var end := origin + _random_direction() * _levy_length()
		if end.distance_to(hive_pos) <= max_dist:
			_segment_end = end
			return
 
	# Aucun segment valide : retour vers la ruche, sur une longueur de Lévy
	var to_hive := (hive_pos - origin).normalized()
	_segment_end = origin + to_hive * minf(_levy_length(), origin.distance_to(hive_pos))
 
 
## Longueur d'un segment, tirée selon une loi de puissance P(l) ∝ l^-µ.
func _levy_length() -> float:
	# Méthode d'inversion : si u suit U(0,1), l_min·(1−u)^(−1/(µ−1)) suit P(l) ∝ l^−µ
	var l := SEGMENT_MIN * pow(1.0 - randf(), -1.0 / (LEVY_MU - 1.0))
	return minf(l, SEGMENT_MAX)
 
func _random_direction() -> Vector3:
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-VERTICAL_VARIATION, VERTICAL_VARIATION),
		randf_range(-1.0, 1.0)
	).normalized()
