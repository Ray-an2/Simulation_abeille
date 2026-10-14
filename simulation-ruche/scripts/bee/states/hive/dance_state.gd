class_name DanceState extends HiveState
## Danse frétillante : l'abeille annonce sa source à la ruche pendant une durée
## proportionnelle à sa rentabilité (boucle de recrutement), puis ressort la butiner.
##
## Déroulé : marche jusqu'à la piste de danse (près de l'entrée, voir _pick_floor_start), puis
## alternance de courses frétillantes (ligne droite, corps oscillant) et de boucles
## de retour, une fois à gauche, une fois à droite : la figure en huit.
##
## Codage de l'information, comme chez l'abeille réelle :
##   - direction : l'angle de la course frétillante par rapport à la verticale
##     du cadre est l'angle soleil → source (bee.angle, calculé en UNLOAD) ;
##   - distance : la durée de la course frétillante croît avec la distance
##     de la source (bee.distance, calculée en UNLOAD) ;
##   - rentabilité : plus la source est rentable, plus la boucle de retour est courte,
##     donc plus les courses se succèdent vite.
## Les valeurs par défaut viennent des mesures de Landgraf et al. (2011, 2018) sur des
## danses filmées, et de la dérive entre courses mesurée par Dormagen et al. (2023).
## Les vitesses sont des facteurs de walk_speed : elles ne correspondent aux mesures
## que pour walk_speed = 0,02 m/s (20 mm/s).
##
## La danse n'est déclarée à la ruche (start_dance) qu'une fois sur la piste :
## c'est là que les abeilles en IDLE peuvent la détecter (get_dancers_near).

# =============================================================================
# Constantes
# =============================================================================

## Piste de danse, calculée à partir de l'entrée (pas de marqueur) :
## distance (m) au-dessus du point d'arrivée sur le cadre, pour une source collée
## à la ruche et pour une source à max_source_distance. Les sources lointaines
## sont annoncées plus loin de l'entrée (Boch, 1956). Ordre de grandeur réel :
## la plupart des danses entre 4 et 18 cm de l'entrée (Seeley et Towne, 1992).
const FLOOR_NEAR := 0.04
const FLOOR_FAR := 0.16

## Dispersion (m, écart-type) du point de départ autour de cette position,
## en hauteur comme sur le côté.
const FLOOR_SPREAD := 0.02

## Distance minimale (m) entre le départ d'une danse et une danseuse déjà en place :
## une longueur d'abeille, pour éviter deux corps superposés (la danseuse
## n'utilise pas l'évitement du walker). Ce n'est pas un espacement voulu :
## les danses se regroupent sur la piste.
const MIN_DANCER_GAP := 0.015

## Nombre de tirages pour trouver un départ libre ; ensuite, le dernier est gardé.
const FLOOR_ATTEMPTS := 6

## Distance (m) d'arrivée sur la piste. Doit dépasser le rayon de virage du walker
## (walk_speed × 1,3 / STEER_RATE ≈ 0,9 cm), sinon l'abeille tourne autour.
const ARRIVAL_RADIUS := 0.012

## Vitesse de virage (rad/s) vers la piste de danse.
const STEER_RATE := 3.0

## Temps maximal (s) pour rejoindre la piste. Au-delà (piste encombrée),
## l'abeille danse là où elle se trouve.
const FLOOR_TIMEOUT := 15.0

## Durée (s) de la course frétillante pour une source collée à la ruche et pour
## une source à max_source_distance. Mesure réelle : 0,44 ± 0,16 s pour une source
## à environ 200 m. La relation, à peu près linéaire, est ramenée à la scène.
const WAGGLE_TIME_MIN := 0.4
const WAGGLE_TIME_MAX := 2.0

## Vitesse pendant la course frétillante (× walk_speed). Mesure : 15 ± 5 mm/s.
const WAGGLE_SPEED := 0.75

## Vitesse jusqu'au point de départ de la première course (× walk_speed).
const ALIGN_SPEED := 0.6

## Durée (s) de la boucle de retour pour une rentabilité de 0 et de 1.
## Mesure : 2,13 ± 0,47 s ; elle raccourcit quand la source est plus rentable
## (Seeley et al., 2000). On prend la moyenne ± un écart-type.
const RETURN_TIME_SLOW := 2.6
const RETURN_TIME_FAST := 1.66

## Vitesse visée pendant la boucle (× walk_speed). Mesure : 20 ± 4 mm/s.
## Avec la durée ci-dessus, elle fixe la longueur de la boucle (≈ 4 cm),
## donc sa largeur : c'est ce qui donne de l'ampleur à la figure.
const RETURN_SPEED := 1.0

## Bornes de la demi-largeur (m) de la boucle. Si la boucle est bornée,
## c'est la vitesse qui s'ajuste : la durée de retour reste exacte.
const LOOP_MIN_HALF_WIDTH := 0.006
const LOOP_MAX_HALF_WIDTH := 0.02

## Dérive (m) du point de départ d'une course à la suivante : moyenne et écart-type
## le long de la course, écart-type sur le côté (Dormagen et al., 2023 :
## 0,81 ± 7,3 mm vers l'avant). La danse se déplace peu à peu sur le cadre
## au lieu de rester sur place.
const DRIFT_FORWARD_MEAN := 0.0008
const DRIFT_FORWARD_SD := 0.0073
const DRIFT_SIDE_SD := 0.0082

## Fréquence (Hz) et amplitude (rad) du frétillement (rotation du corps autour
## de la normale du cadre). Mesure : 12,7 Hz, environ 14° crête à crête, soit ±7°.
## La fréquence doit rester sous la moitié de la fréquence physique : à 30 Hz
## de physique, la baisser.
const WIGGLE_FREQUENCY := 13.0
const WIGGLE_AMPLITUDE := 0.12

# =============================================================================
# Types
# =============================================================================

## Étapes de la danse.
enum Phase {
	TO_FLOOR,   ## Marche jusqu'à la piste, avec le walker (évitement, bords)
	TO_START,   ## Ligne droite jusqu'au point de départ de la première course
	WAGGLE,     ## Course frétillante : direction et durée encodent la source
	LOOP,       ## Boucle de retour vers le départ de la course suivante, côté alterné
}

# =============================================================================
# État interne
# =============================================================================

## Temps de danse restant (s). Ne décompte que sur la piste.
var _remaining := 0.0

## Étape en cours.
var _phase := Phase.TO_FLOOR

## Temps passé à rejoindre la piste (s).
var _floor_time := 0.0

## Normale du cadre, lue à l'entrée (le cadre ne bouge pas pendant la danse).
var _normal := Vector3.ZERO

## Direction de la course frétillante, dans le plan du cadre (unitaire).
var _dir := Vector3.ZERO

## Perpendiculaire à _dir dans le plan du cadre, à gauche de la course (unitaire).
var _side := Vector3.ZERO

## Longueur (m) d'une course frétillante, fixée par la distance de la source.
var _run_length := 0.0

## Extrémités de la course en cours.
var _run_start := Vector3.ZERO
var _run_end := Vector3.ZERO

## Durée (s) de chaque boucle de retour pour cette danse, tirée de la rentabilité.
var _return_time := 2.0

## Boucle en cours : demi-ellipse de _run_end jusqu'au départ de la course suivante.
## _loop_axis va du départ vers la fin de course ; _loop_lateral est à sa gauche.
var _loop_middle := Vector3.ZERO
var _loop_axis := Vector3.ZERO
var _loop_lateral := Vector3.ZERO
var _loop_a := 0.0          # demi-axe le long de la corde (m)
var _loop_b := 0.0          # demi-axe sur le côté (m)
var _loop_speed := 0.0      # vitesse sur la boucle (m/s)
var _next_start := Vector3.ZERO

## Côté de la prochaine boucle : +1 à gauche de la course, -1 à droite.
var _loop_sign := 1.0

## Avancement de la boucle : 0 en fin de course, PI au départ de la course suivante.
var _loop_phi := 0.0

## Temps écoulé dans la course en cours (s), pour la phase du frétillement.
var _wiggle_time := 0.0

## Rotation de frétillement actuellement appliquée au corps (rad).
var _wiggle_yaw := 0.0

## Signaux d'arrêt reçus pendant cette danse (interface).
var _stop_signals := 0

# =============================================================================
# Méthodes de l'état
# =============================================================================

## Durée de danse : dance_duration_max pour une rentabilité de 1.
## UNLOAD a déjà réduit known_profitability selon l'attente à la file (saturation).
func enter() -> void:
	var profitability := clampf(bee.known_profitability, 0.0, 1.0)
	_remaining = bee.simulation.dance_duration_max * bee.known_profitability
	_return_time = lerpf(RETURN_TIME_SLOW, RETURN_TIME_FAST, profitability)
	_phase = Phase.TO_FLOOR
	_floor_time = 0.0
	_wiggle_yaw = 0.0
	_stop_signals = 0
	# Première boucle d'un côté ou de l'autre : les danseuses ne sont pas synchrones
	_loop_sign = 1.0 if randf() < 0.5 else -1.0
	_reset_wander()

	_normal = bee.hive.get_comb_normal()
	_build_figure(_pick_floor_start())

func exit() -> void:
	bee.hive.stop_dance(bee)
	_stop_wiggle()
	# La danse déplace l'abeille sans le walker : on le recale sur son orientation
	# actuelle pour que LEAVE reparte dans la bonne direction, depuis l'arrêt
	bee.walker.reset()

func update(delta: float) -> BeeState:
	# Garde-fou : source disparue, rien à annoncer
	if not is_instance_valid(bee.known_flower):
		return bee.idle

	match _phase:
		Phase.TO_FLOOR:
			_floor_time += delta
			if _walk_to(_run_start, STEER_RATE, ARRIVAL_RADIUS, delta):
				_phase = Phase.TO_START
			elif _floor_time > FLOOR_TIMEOUT:
				# Piste inaccessible : la figure part de la position de l'abeille
				_build_figure(bee.hive.clamp_to_comb(bee.global_position))
				_phase = Phase.TO_START

		Phase.TO_START:
			# Dernier centimètre en ligne droite : la course doit partir du point exact
			bee.walk_towards(_run_start, delta, _normal, ALIGN_SPEED)
			if bee.is_near(_run_start, EXACT_RADIUS):
				# Sur la piste : la danse devient visible des abeilles en attente
				bee.hive.start_dance(bee, bee.known_flower)
				# Angle recalculé : le soleil a pu tourner pendant la marche vers la piste
				_begin_run(_run_start)

		Phase.WAGGLE:
			_remaining -= delta
			# move_toward : l'abeille reste exactement sur la droite de la course
			bee.walk_towards(_run_end, delta, _normal, WAGGLE_SPEED)
			_update_wiggle(delta)
			if bee.is_near(_run_end, EXACT_RADIUS):
				_stop_wiggle()
				# Une course n'est jamais interrompue : la fin est testée après
				if _remaining <= 0.0:
					return go_out_if_day(bee.go)
				_start_loop()

		Phase.LOOP:
			_remaining -= delta
			# Temps écoulé pendant la boucle : l'abeille quitte la piste sans la finir
			if _remaining <= 0.0:
				return go_out_if_day(bee.go)
			# hop_towards et non walk_towards : le point visé n'est qu'à une fraction
			# de mm devant l'abeille, et _move_towards() ne l'oriente plus en dessous
			# de 1 mm. Elle reculerait sans tourner. On impose donc la tangente.
			var target := _next_loop_point(delta)
			# false : la danseuse marche, elle ne saute pas (pas de bourdonnement)
			bee.hop_towards(target, _loop_speed, _loop_tangent(), _normal, delta, false)
			# hop_towards() ne règle pas les pattes : cadence calée sur la vitesse réelle
			bee.play_walk(_loop_speed / bee.simulation.walk_speed)
			if _loop_phi >= PI and bee.is_near(_next_start, EXACT_RADIUS):
				# Course suivante, et boucle suivante de l'autre côté : le huit.
				# La direction suit le soleil d'une course à l'autre.
				_loop_sign = -_loop_sign
				_begin_run(_next_start)

	return null
	
# =============================================================================
# Signal d'arrêt et lecture (appelé par TrembleState et par l'interface)
# =============================================================================

## Signal d'arrêt donné par une trémulante (Kirchner 1993 ; Nieh 1993) :
## le temps de danse restant diminue de stop_signal_strength.
## La course en cours n'est pas interrompue : la fin de danse est testée
## en fin de course ou pendant la boucle, comme d'habitude.
func receive_stop_signal() -> void:
	_remaining *= 1.0 - bee.simulation.stop_signal_strength
	_stop_signals += 1

## Temps de danse restant (s), signaux d'arrêt compris.
func get_remaining() -> float:
	return maxf(_remaining, 0.0)

## Signaux d'arrêt reçus depuis le début de la danse.
func get_stop_signals() -> int:
	return _stop_signals

# =============================================================================
# Géométrie de la figure
# =============================================================================

## Point de départ de la danse sur la piste : au-dessus du point où les abeilles
## arrivent sur le cadre depuis l'entrée, d'autant plus haut que la source est loin,
## avec une dispersion aléatoire. Évite seulement de partir sur une autre danseuse.
func _pick_floor_start() -> Vector3:
	var hive := bee.hive
	# Verticale et horizontale dans le plan du cadre
	var up := Vector3.UP.slide(_normal).normalized()
	var across := _normal.cross(up).normalized()
	# Point du bas du cadre le plus proche de l'entrée : là où ENTER pose les abeilles
	var foot := hive.get_comb_bottom_point(hive.get_entrance_position())

	var ratio := clampf(bee.distance / maxf(bee.simulation.max_source_distance, 0.001), 0.0, 1.0)
	var center := foot + up * lerpf(FLOOR_NEAR, FLOOR_FAR, ratio)

	var point := center
	for attempt in FLOOR_ATTEMPTS:
		# randfn : loi normale, la plupart des départs restent près du centre
		point = hive.clamp_to_comb(center + up * randfn(0.0, FLOOR_SPREAD)
				+ across * randfn(0.0, FLOOR_SPREAD))
		if hive.get_dancers_near(point, MIN_DANCER_GAP).is_empty():
			break
	return point

## Calcule la direction et la longueur des courses, et la première course,
## qui part de [param start].
func _build_figure(start: Vector3) -> void:
	var sim := bee.simulation

		# Direction provisoire, pour placer la première course sur la piste ;
	# elle sera recalculée au départ de la course (_begin_run)
	_update_direction()

	# Durée de la course : interpolée entre les deux bornes selon la distance,
	# puis convertie en longueur à la vitesse de la course
	var ratio := clampf(bee.distance / maxf(sim.max_source_distance, 0.001), 0.0, 1.0)
	var waggle_time := lerpf(WAGGLE_TIME_MIN, WAGGLE_TIME_MAX, ratio)
	_run_length = waggle_time * sim.walk_speed * WAGGLE_SPEED

	_run_start = bee.hive.clamp_to_comb(start)
	_run_end = bee.hive.clamp_to_comb(_run_start + _dir * _run_length)

## Prépare la boucle de retour : tire le départ de la course suivante (dérive),
## puis dimensionne la demi-ellipse pour qu'elle dure _return_time.
func _start_loop() -> void:
	var hive := bee.hive

	# Dérive : la course suivante ne repart pas exactement du même point.
	# randfn tire selon une loi normale (moyenne, écart-type).
	var drift := _dir * randfn(DRIFT_FORWARD_MEAN, DRIFT_FORWARD_SD) \
			+ _side * randfn(0.0, DRIFT_SIDE_SD)
	_next_start = hive.clamp_to_comb(_run_start + drift)

	# Corde de la boucle : de la fin de course au départ suivant
	var chord := _run_end - _next_start
	_loop_middle = (_run_end + _next_start) * 0.5
	_loop_a = chord.length() * 0.5
	# Corde quasi nulle (dérive qui ramène sur la fin de course) : axe de la course
	_loop_axis = chord.normalized() if _loop_a > 0.0001 else _dir
	_loop_lateral = _normal.cross(_loop_axis).normalized()

	# Largeur : celle qui donne une boucle de longueur vitesse mesurée × durée voulue
	var wanted_length := bee.simulation.walk_speed * RETURN_SPEED * _return_time
	_loop_b = clampf(_solve_half_width(_loop_a, wanted_length),
			LOOP_MIN_HALF_WIDTH, LOOP_MAX_HALF_WIDTH)
	# Vitesse recalculée sur la longueur réelle : la durée de retour reste exacte,
	# même quand la largeur a été bornée
	_loop_speed = _half_ellipse_length(_loop_a, _loop_b) / _return_time

	_loop_phi = 0.0
	_phase = Phase.LOOP

## Fait avancer la boucle de retour et renvoie le point visé sur la demi-ellipse.
func _next_loop_point(delta: float) -> Vector3:
	# Longueur de la tangente |dP/dphi| : convertit la vitesse de marche
	# en vitesse angulaire, pour une vitesse à peu près constante sur l'ellipse
	var s := sin(_loop_phi)
	var c := cos(_loop_phi)
	var tangent := sqrt(_loop_a * _loop_a * s * s + _loop_b * _loop_b * c * c)
	_loop_phi = minf(_loop_phi + _loop_speed * delta / maxf(tangent, 0.0001), PI)

	# phi = 0 : fin de course ; phi = PI : départ de la course suivante
	var point := _loop_middle + _loop_axis * (_loop_a * cos(_loop_phi)) \
			+ _loop_lateral * (_loop_sign * _loop_b * sin(_loop_phi))
	return bee.hive.clamp_to_comb(point)

## Direction de marche sur la boucle (dérivée de la demi-ellipse) : sert
## à orienter l'abeille. En sortie de course, elle tourne vers le côté de la boucle,
## puis revient progressivement vers le départ.
func _loop_tangent() -> Vector3:
	var tangent := -_loop_axis * (_loop_a * sin(_loop_phi)) \
			+ _loop_lateral * (_loop_sign * _loop_b * cos(_loop_phi))
	# Ne peut pas être nul (_loop_b > 0), mais on garde un repli
	return tangent if not tangent.is_zero_approx() else _dir

## Longueur d'une demi-ellipse de demi-axes [param a] et [param b]
## (formule approchée de Ramanujan, divisée par deux).
func _half_ellipse_length(a: float, b: float) -> float:
	return 0.5 * PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))

## Demi-largeur b telle que la demi-ellipse de demi-axe [param a] mesure
## [param length]. Résolu par dichotomie : la longueur croît avec b.
func _solve_half_width(a: float, length: float) -> float:
	var lo := 0.0
	var hi := maxf(length, 0.0001)
	for i in 30:
		var mid := 0.5 * (lo + hi)
		if _half_ellipse_length(a, mid) < length:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)

## Verticale du cadre : la gravité projetée dans son plan. Sur un cadre vertical,
## elle remplace le soleil comme référence, comme pour l'abeille réelle.
func _comb_up() -> Vector3:
	var up := Vector3.UP.slide(_normal)
	if up.is_zero_approx():
		# Cadre posé à plat (ne devrait pas arriver) : axe arbitraire dans le plan
		up = Vector3.FORWARD.slide(_normal)
	return up.normalized()

## Recalcule l'angle soleil → source à l'instant présent, puis la direction
## de la course. Appelée au début de chaque course : le soleil tourne pendant
## la danse (environ 15° par heure simulée, soit 1 h toutes les 25 s avec une
## journée de 600 s), et la danseuse réelle corrige son angle d'une course
## à l'autre (von Frisch). bee.angle est mis à jour pour que le HUD reste juste.
func _update_direction() -> void:
	bee.angle = bee.simulation.get_dance_angle(
			bee.known_flower.global_position, bee.hive.global_position)
	# Angle positif = source à gauche du soleil vu de dessus. Une rotation positive
	# autour de la normale amène la verticale vers la gauche pour qui regarde
	# le cadre : même sens que sur le terrain.
	_dir = _comb_up().rotated(_normal, bee.angle)
	# Rotation de +90° autour de la normale : côté gauche de la course
	_side = _normal.cross(_dir).normalized()

## Démarre une course frétillante depuis [param start], dans la direction
## du soleil à cet instant.
func _begin_run(start: Vector3) -> void:
	
	_update_direction()
	_run_start = start
	_run_end = bee.hive.clamp_to_comb(_run_start + _dir * _run_length)
	_start_waggle()

# =============================================================================
# Frétillement
# =============================================================================

## Démarre une course frétillante depuis _run_start.
func _start_waggle() -> void:
	_phase = Phase.WAGGLE
	_wiggle_time = 0.0
	_wiggle_yaw = 0.0

## Fait osciller le corps autour de la normale du cadre. Seul l'écart avec l'image
## précédente est appliqué : walk_towards() ayant déjà orienté l'abeille vers
## _run_end, l'oscillation reste centrée sur la direction de la course.
func _update_wiggle(delta: float) -> void:
	_wiggle_time += delta
	var yaw := WIGGLE_AMPLITUDE * sin(TAU * WIGGLE_FREQUENCY * _wiggle_time)
	_rotate_body(yaw - _wiggle_yaw)
	_wiggle_yaw = yaw

## Annule la rotation de frétillement en cours (fin de course, sortie de l'état).
func _stop_wiggle() -> void:
	if _wiggle_yaw != 0.0:
		_rotate_body(-_wiggle_yaw)
	_wiggle_yaw = 0.0

## Tourne l'abeille de [param angle] radians autour de la normale du cadre,
## sans la déplacer.
func _rotate_body(angle: float) -> void:
	bee.global_basis = Basis(_normal, angle) * bee.global_basis
