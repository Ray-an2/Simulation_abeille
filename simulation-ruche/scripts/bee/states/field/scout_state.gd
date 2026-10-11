class_name ScoutState extends FieldState
## État d'exploration : l'abeille s'éloigne de la ruche en marche de Lévy corrélée,
## jusqu'à repérer une fleur libre (→ elle la réserve, vole vers elle puis passe en FORAGE),
## ou manquer de temps (→ RETURN).
## Une fleur est libre si elle n'est ni vide ni réservée par une autre abeille :
## les exploratrices se répartissent sur les fleurs au lieu de s'agglutiner.

# =============================================================================
# Constantes : marche de Lévy
# =============================================================================

## Exposant de la loi de puissance des longueurs de segment, P(l) ∝ l^-µ.
## ≈ 2 : optimum théorique pour des cibles rares (beaucoup de segments courts,
## quelques très longs pour changer de zone).
const LEVY_MU := 2.0

## Longueur minimale (m) d'un segment.
const SEGMENT_MIN := 1.5

## Borne haute (m) d'un segment, pour ne pas sortir de scout_radius d'un seul trait.
const SEGMENT_MAX := 20.0

## Nombre d'essais pour trouver un segment valide (dans la zone, sans obstacle)
## avant de se replier vers la ruche.
const SEGMENT_MAX_TRIES := 5

## Écart-type (rad) du changement de cap entre deux segments. Marche corrélée :
## l'abeille garde globalement sa direction (0,4 rad ≈ 23°) au lieu d'en tirer
## une au hasard à chaque segment, ce qui la ferait piétiner autour de la ruche.
const TURN_SIGMA := 0.4

# =============================================================================
# Constantes : zone d'exploration
# =============================================================================

## Demi-angle (rad) du cône de départ, centré sur la direction opposée à la ruche.
const DEPARTURE_SPREAD := PI / 2.0

## Fraction de scout_radius à partir de laquelle le cap est infléchi vers la ruche :
## retour progressif plutôt que rebond sur le bord de la zone.
const BORDER_START := 0.7

## Distance (m) à laquelle on enchaîne sur le segment suivant. En vol continu,
## l'abeille ne s'arrête pas sur le point : elle bascule un peu avant.
const WAYPOINT_RADIUS := 0.3

## Distance (m) à laquelle s'arrête le segment de repli vers la ruche :
## son centre est dans la forme de collision, l'abeille ne pourrait pas l'atteindre.
const HIVE_KEEP_OUT := 1.0

# =============================================================================
# État interne
# =============================================================================

## Temps restant (s) avant d'abandonner et de rentrer. Ne décompte que
## pendant l'errance : une abeille qui a repéré une fleur va jusqu'au bout.
var _remaining: float

## Cap horizontal courant (unitaire), conservé d'un segment à l'autre.
var _heading := Vector3.FORWARD

## Point d'arrivée du segment en cours.
var _segment_end := Vector3.ZERO

## Fleur repérée et réservée, vers laquelle l'abeille vole. null tant qu'elle erre.
var _flower: Flower = null

## Point de pose sur la fleur visée (pistil).
var _target: Vector3

# =============================================================================
# Méthodes de l'état
# =============================================================================

## Remet le chrono à zéro, tire le cap de départ et le premier segment,
## puis décolle si l'abeille est posée (sortie de LEAVE).
func enter() -> void:
	bee.play_animation(&"_bee_hover")
	_remaining = bee.simulation.scout_timeout
	_flower = null
	_heading = _departure_heading()
	_pick_segment()
	begin_flight()

## Libère la fleur visée en quittant l'état. En cas d'arrivée, FORAGE
## la réserve de nouveau dans son enter(), dans le même change_state().
func exit() -> void:
	if _flower != null:
		_flower.release(bee)
	_flower = null

func update(delta: float) -> BeeState:
	if update_takeoff(_segment_end, delta):
		return null

	_update_flower_search()

	if _flower != null:
		# Approche, stationnaire puis pose, à vitesse de recherche
		if update_landing(_target, _flower.get_landing_normal(), HOVER_TIME_FLOWER,
				delta, bee.simulation.scout_speed, Vector3.ZERO, bee.get_head_offset()):
			# Source déjà connue : l'abeille vient de GO (fleur réservée) et se rabat
			# sur une voisine. Elle reste recrutée par la même danseuse.
			# Sinon, c'est une vraie découverte en exploration.
			var dancer := bee.recruited_by if is_instance_valid(bee.known_flower) else null
			bee.learn_source(_flower, dancer)
			return bee.forage
	else:
		_remaining -= delta
		if _remaining <= 0.0:
			return bee.return_home
		_wander(delta)
	return null

# =============================================================================
# Recherche de fleur
# =============================================================================

## Abandonne la fleur visée si elle est vide, et en cherche une nouvelle si besoin.
func _update_flower_search() -> void:
	if _flower != null and _flower.is_empty():
		_flower.release(bee)
		_flower = null
		reset_landing()

	if _flower == null:
		_flower = _find_flower()
		if _flower != null:
			# Réussit toujours : _find_flower() n'a retenu qu'une fleur libre
			_flower.try_claim(bee)
			_target = _flower.get_landing_position()

## Fleur libre (ni vide, ni réservée par une autre) la plus proche
## dans le rayon de perception, ou null.
func _find_flower() -> Flower:
	var best: Flower = null
	# Comparaison des carrés : évite une racine carrée par fleur
	var best_d2 := bee.simulation.perception_radius ** 2
	for f in bee.simulation.flowers:
		if not f.is_free_for(bee):
			continue
		var d2 := bee.global_position.distance_squared_to(f.get_landing_position())
		if d2 < best_d2:
			best = f
			best_d2 = d2
	return best

# =============================================================================
# Déplacement : marche de Lévy corrélée
# =============================================================================

## Vol continu jusqu'à la fin du segment (sans freinage), puis segment suivant.
func _wander(delta: float) -> void:
	# arrive = false : point de passage, l'abeille garde sa vitesse
	bee.fly_towards(_segment_end, delta, false, bee.simulation.scout_speed)
	if bee.is_near(_segment_end, WAYPOINT_RADIUS):
		_pick_segment()

## Cap de départ : à l'opposé de la ruche, avec un écart aléatoire,
## pour que les exploratrices se répartissent autour de la colonie.
func _departure_heading() -> Vector3:
	var away := bee.global_position - bee.hive.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		# Abeille pile au-dessus du centre de la ruche : cap quelconque
		return Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	return away.normalized().rotated(Vector3.UP, randf_range(-DEPARTURE_SPREAD, DEPARTURE_SPREAD))

## Tire un nouveau segment dans le prolongement du cap courant. S'il sort de
## scout_radius ou traverse un obstacle, on retente avec un autre écart de cap ;
## après SEGMENT_MAX_TRIES échecs, on repart en direction de la ruche.
func _pick_segment() -> void:
	var origin := bee.global_position
	var hive_pos := bee.hive.global_position
	var max_dist := bee.simulation.scout_radius

	for i in SEGMENT_MAX_TRIES:
		_turn_heading(origin, hive_pos, max_dist)
		var end := origin + _heading * _levy_length()
		# Altitude de croisière au-dessus du sol (altitude actuelle si pas de terrain)
		var ground := bee.get_ground_height(end)
		end.y = origin.y if ground == -INF else ground + bee.simulation.cruise_height
		if end.distance_to(hive_pos) <= max_dist and bee.is_path_clear(origin, end):
			_segment_end = end
			return

	# Aucun segment valide : retour vers la ruche, en s'arrêtant avant elle.
	# Le cap suit, pour que les segments suivants repartent de cette direction.
	var to_hive := hive_pos - origin
	to_hive.y = 0.0
	if not to_hive.is_zero_approx():
		_heading = to_hive.normalized()
	var length := minf(_levy_length(), maxf(origin.distance_to(hive_pos) - HIVE_KEEP_OUT, 0.0))
	_segment_end = origin + (hive_pos - origin).normalized() * length

## Fait dévier le cap d'un petit angle aléatoire, puis l'infléchit vers la ruche
## d'autant plus que l'abeille approche du bord de la zone d'exploration.
func _turn_heading(origin: Vector3, hive_pos: Vector3, max_dist: float) -> void:
	# Écart gaussien autour du cap actuel : la plupart des virages sont faibles
	_heading = _heading.rotated(Vector3.UP, randfn(0.0, TURN_SIGMA))

	var to_hive := hive_pos - origin
	to_hive.y = 0.0
	# 0 en deçà de BORDER_START × rayon, 1 au bord de la zone
	var pull := smoothstep(BORDER_START * max_dist, max_dist, to_hive.length())
	if pull > 0.0:
		# Rotation plutôt que lerp : fonctionne aussi quand la ruche est pile derrière
		var angle := _heading.signed_angle_to(to_hive, Vector3.UP)
		_heading = _heading.rotated(Vector3.UP, angle * pull)

## Longueur d'un segment, tirée selon une loi de puissance P(l) ∝ l^-µ.
func _levy_length() -> float:
	# Méthode d'inversion : si u suit U(0,1), l_min·(1−u)^(−1/(µ−1)) suit P(l) ∝ l^−µ
	var l := SEGMENT_MIN * pow(1.0 - randf(), -1.0 / (LEVY_MU - 1.0))
	return minf(l, SEGMENT_MAX)
