class_name GoState extends FieldState
## Vol vers une source, dans deux cas :
##
## 1. Source connue (known_flower) : l'abeille y retourne. En approche finale,
##    elle vérifie la fleur sans se poser :
##      - vide → elle l'oublie et explore (SCOUT) ;
##      - réservée par une autre abeille → elle explore autour (SCOUT) en gardant
##        la source, et trouvera une voisine libre dans le même massif ;
##      - libre → elle la réserve, se pose et butine (FORAGE).
##    La réservation n'est prise qu'en approche finale : prise dès la ruche,
##    elle bloquerait la fleur pendant tout le trajet.
##
## 2. Recrue (vecteur de danse appris en WATCH, pas de fleur connue) :
##    l'abeille ne connaît que le point estimé (dance_target, déjà entaché de
##    l'erreur de la danse) et l'espèce annoncée (odeur). Elle vole jusqu'au point,
##    puis le cherche autour en errant dans recruit_search_radius.
##      - fleur de la bonne espèce repérée → elle l'adopte comme source
##        (la danseuse est alors créditée) et poursuit comme dans le cas 1 ;
##      - recruit_search_timeout écoulé → retour bredouille (RETURN).
##    La détection commence dès l'entrée dans la zone, pendant le transit.
##
## Le vecteur ne vaut que pour un trajet : exit() l'efface dans tous les cas.

# =============================================================================
# Constantes
# =============================================================================

## Distance à plat (m) à laquelle un point est considéré comme atteint.
## En vol continu (arrive = false), l'abeille enchaîne sans s'arrêter dessus.
const WAYPOINT_RADIUS := 0.5

## La recherche de fleurs n'est faite qu'une frame physique sur SEARCH_CHECK_STEP :
## find_visible_flower() parcourt toutes les fleurs de la scène.
const SEARCH_CHECK_STEP := 5

# =============================================================================
# État interne
# =============================================================================

## Fleur visée, gardée ici pour pouvoir la libérer dans exit()
## même si known_flower a été remise à null entre-temps.
var _flower: Flower = null

## Point visé : pistil de la fleur, ou point dansé pour une recrue.
## Sert aussi de direction de décollage.
var _target: Vector3

## true quand la recrue est arrivée au point dansé et cherche autour.
var _searching := false

## Temps de recherche restant (s). Ne décompte qu'une fois la recherche commencée.
var _search_left := 0.0

## Point de passage en cours pendant la recherche.
var _waypoint := Vector3.ZERO

## Décalage tiré à l'entrée : les recrues ne cherchent pas toutes à la même frame.
var _check_offset := 0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_flower = bee.known_flower
	_searching = false
	_search_left = 0.0
	_check_offset = randi() % SEARCH_CHECK_STEP
	if is_instance_valid(_flower):
		_target = _flower.get_landing_position()
	elif bee.has_dance_vector():
		_target = bee.dance_target
	begin_flight()   # décollage de la planche à la sortie de LEAVE

func exit() -> void:
	if is_instance_valid(_flower):
		_flower.release(bee)
	_flower = null
	_searching = false
	# Vecteur valable pour un seul trajet, réussi ou non (nuit, timeout, fleur trouvée)
	bee.forget_dance_vector()

func update(delta: float) -> BeeState:
	if is_instance_valid(bee.known_flower):
		return _update_known_source(delta)
	if bee.has_dance_vector():
		return _update_recruit(delta)
	# Ni source ni vecteur : exploration
	return bee.scout

# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## true si la recrue cherche autour du point dansé (point atteint, fleur pas encore trouvée).
func is_searching() -> bool:
	return _searching

## Temps de recherche restant (s) ; 0 hors recherche.
func get_search_left() -> float:
	return maxf(_search_left, 0.0) if _searching else 0.0

# =============================================================================
# Cas 1 : source connue
# =============================================================================

func _update_known_source(delta: float) -> BeeState:
	var flower := bee.known_flower

	if update_takeoff(_target, delta):
		return null

	if is_on_final_approach():
		# Fleur vide constatée de près : on l'oublie et on explore, toujours en vol
		if flower.is_empty():
			bee.forget_source()
			return bee.scout
		# Fleur réservée par une autre abeille : on cherche une voisine libre.
		# La source reste connue : SCOUT la remplacera si l'abeille se pose ailleurs.
		if not flower.try_claim(bee):
			return bee.scout

	# Approche par la face ouverte, arrêt bref puis pose sur le pistil
	if update_flower_landing(flower, delta):
		return bee.forage

	return null

# =============================================================================
# Cas 2 : recrue
# =============================================================================

func _update_recruit(delta: float) -> BeeState:
	if update_takeoff(_target, delta):
		return null

	var sim := bee.simulation
	var flat := sim.get_flat_distance(bee.global_position, bee.dance_target)

	# Détection limitée à la zone indiquée par la danse : la recrue ne s'arrête pas
	# sur une fleur de la bonne espèce croisée à mi-chemin
	if flat <= sim.recruit_search_radius and _is_check_frame():
		var found := sim.find_visible_flower(bee, bee.dance_species)
		if found != null:
			_adopt(found)
			return null

	# Transit vers le point dansé, sans freiner : la recherche enchaîne
	if not _searching:
		bee.fly_towards(bee.dance_target, delta, false)
		if flat <= WAYPOINT_RADIUS:
			_start_search()
		return null

	# Recherche autour du point dansé
	_search_left -= delta
	if _search_left <= 0.0:
		# Bredouille : exit() efface le vecteur, UNLOAD verra un jabot vide
		return bee.return_home

	if sim.get_flat_distance(bee.global_position, _waypoint) <= WAYPOINT_RADIUS:
		_waypoint = _random_search_point()
	# Vol plus lent, comme en exploration : la recherche est visuelle
	bee.fly_towards(_waypoint, delta, false, sim.scout_speed)
	return null

## Démarre la recherche locale, au premier passage sur le point dansé.
func _start_search() -> void:
	_searching = true
	_search_left = bee.simulation.recruit_search_timeout
	_waypoint = _random_search_point()

## Adopte [param flower] comme source : la danseuse est créditée du recrutement,
## le vecteur n'a plus d'utilité. La suite du vol passe par _update_known_source().
func _adopt(flower: Flower) -> void:
	bee.learn_source(flower, bee.dance_teacher)
	bee.forget_dance_vector()
	_flower = flower
	_target = flower.get_landing_position()
	_searching = false
	_search_left = 0.0
	# Nouvelle cible : l'approche repart de zéro
	reset_landing()

## Point tiré uniformément dans le disque de rayon recruit_search_radius
## centré sur le point dansé (racine carrée : pas de surdensité au centre).
func _random_search_point() -> Vector3:
	var r := bee.simulation.recruit_search_radius * sqrt(randf())
	var a := randf() * TAU
	return bee.dance_target + Vector3(cos(a), 0.0, sin(a)) * r

## true une frame physique sur SEARCH_CHECK_STEP, décalée pour chaque abeille.
func _is_check_frame() -> bool:
	return (Engine.get_physics_frames() + _check_offset) % SEARCH_CHECK_STEP == 0
