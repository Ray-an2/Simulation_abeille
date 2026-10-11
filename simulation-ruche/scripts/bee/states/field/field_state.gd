class_name FieldState extends BeeState
## Super-état « Dehors ».
##
## Complète Bee.fly_towards() pour les deux moments où l'abeille ne vole pas comme en croisière :
##   - le décollage : départ selon la verticale, trajectoire qui s'incline progressivement
##     vers la direction de vol, vitesse qui croît sans rupture jusqu'au relais par fly_towards() ;
##   - l'approche finale : vitesse proportionnelle à la distance restante (taux d'expansion
##     de l'image constant, comme chez la vraie abeille), trajectoire qui s'incurve pour
##     arriver selon la normale de la surface, bref arrêt juste avant le contact.
##
## Utilisation dans un état concret :
##   - enter() appelle begin_flight() ;
##   - update() commence par : if update_takeoff(cible, delta): return null
##   - pour se poser, appeler update_landing() à chaque image jusqu'à ce qu'elle renvoie true.

# =============================================================================
# Constantes : décollage
# =============================================================================

## Distance (m) parcourue pendant le décollage, avant le relais par fly_towards().
const TAKEOFF_DISTANCE := 0.06

## Vitesse (m/s) au premier instant : l'abeille pousse sur ses pattes en battant
## déjà des ailes, elle ne part pas d'une vitesse nulle.
const TAKEOFF_START_SPEED := 0.1

## Pente de fin de décollage : composante verticale de la direction finale, pour 1 à
## l'horizontale (0,5 ≈ 27°). L'abeille est encore en montée au relais, comme fly_towards()
## qui la fait ensuite grimper jusqu'à cruise_height : pas de palier entre les deux.
const TAKEOFF_CLIMB := 0.5

# =============================================================================
# Constantes : atterrissage
# =============================================================================

## Constante de temps (s) de l'approche finale : vitesse = distance / LANDING_TAU.
## Plus elle est grande, plus l'approche commence tôt et plus elle est douce.
const LANDING_TAU := 0.4

## Distance (m) à laquelle l'approche finale commence au plus tard. Normalement elle
## commence avant, dès que distance / LANDING_TAU rejoint la vitesse de vol : la vitesse
## est alors la même des deux côtés du relais, il n'y a pas d'à-coup.
const FINAL_MIN_DISTANCE := 0.3

## Courbure de l'approche : le point visé est décalé le long de la normale de
## distance × APPROACH_CURVE. 0 = ligne droite ; plus grand = arrivée plus perpendiculaire.
const APPROACH_CURVE := 0.5

## Vitesse plancher (m/s) : sans elle, la loi distance / tau n'atteindrait jamais
## la surface (convergence asymptotique). Sert aussi à la mise en contact.
const TOUCHDOWN_SPEED := 0.05

## Distance (m) à la surface du bref arrêt avant contact.
const HOVER_HEIGHT := 0.008

## Durée (s) du bref arrêt avant contact. Nulle sur la planche : sur une surface
## horizontale, l'abeille ralentit jusqu'au contact sans s'arrêter. Plus longue devant
## une fleur, petite et souvent inclinée, qu'elle inspecte avant de s'y poser.
## Une durée nulle saute l'étape HOVER.
const HOVER_TIME_BOARD := 0.0
const HOVER_TIME_FLOWER := 0.3

## Avance du point visé quand une direction d'arrivée est imposée : il est placé
## en amont de la cible, à distance × APPROACH_LEAD. Il se rapproche de la cible
## avec l'abeille, ce qui l'amène progressivement dans l'axe d'arrivée.
## Avec APPROACH_CURVE, √(0,5² + 0,6²) < 1 : le point visé reste plus près de la cible
## que l'abeille, la distance diminue donc toujours.
const APPROACH_LEAD := 0.6

## Cosinus du demi-angle du cône d'arrivée (0,5 = 60°). L'approche finale, qui n'évite
## pas les obstacles, ne commence que si l'abeille est dans ce cône : jamais derrière la ruche.
const APPROACH_CONE_COS := 0.5

## Distance (m) d'arrivée exacte : hop_towards() utilise move_toward, qui atteint
## exactement sa cible (même raison que l'ancien LANDING_RADIUS de ReturnState).
const EXACT_RADIUS := 0.001

# =============================================================================
# Types
# =============================================================================

## Étapes de l'arrivée sur une surface.
enum Landing {
	APPROACH,   ## Vol normal (fly_towards), freinage compris
	FINAL,      ## Vitesse proportionnelle à la distance, trajectoire incurvée vers la normale
	HOVER,      ## Bref arrêt juste au-dessus de la surface
	TOUCHDOWN,  ## Mise en contact
	DONE,       ## Posée
}

# =============================================================================
# État interne
# =============================================================================

## true pendant le décollage.
var _taking_off := false

## Vitesse (m/s) et distance parcourue (m) pendant le décollage.
var _takeoff_speed := 0.0
var _takeoff_traveled := 0.0

## Étape d'arrivée en cours.
var _landing := Landing.APPROACH

## Distance à la cible au début de l'approche finale : sert à doser l'alignement sur la surface.
var _final_start_dist := 1.0

## Temps d'arrêt restant (s) avant le contact.
var _hover_left := 0.0

# =============================================================================
# Décollage
# =============================================================================

## À appeler dans enter(). Démarre un décollage si l'abeille est posée
## (planche à la sortie de LEAVE, fleur à la sortie de FORAGE). Si elle vole déjà
## (SCOUT → RETURN, GO → SCOUT), le vol continue directement.
func begin_flight() -> void:
	reset_landing()
	_taking_off = bee.is_landed()
	if _taking_off:
		_takeoff_speed = TAKEOFF_START_SPEED
		_takeoff_traveled = 0.0
		# Animation de décollage, puis battement d'ailes en boucle quand elle est finie
		bee.play_animation(&"_bee_takeoff")
		bee.queue_animation(&"_bee_hover")
	else:
		# Déjà en vol, éventuellement interrompue en pleine approche (pattes sorties)
		bee.play_animation(&"_bee_hover")

## Fait progresser le décollage vers [param toward] (cible de l'état : fleur, planche,
## fin de segment). Renvoie true tant qu'il n'est pas terminé : l'état concret ne doit
## alors rien faire d'autre pendant cette image.
func update_takeoff(toward: Vector3, delta: float) -> bool:
	if not _taking_off:
		return false
	var sim := bee.simulation

	# Cap horizontal vers la cible ; cible pile au-dessus : cap actuel
	var heading := (toward - bee.global_position).slide(Vector3.UP)
	if heading.is_zero_approx():
		heading = _forward_on(Vector3.UP)
	heading = heading.normalized()

	# Direction de fin de décollage : vers la cible, encore en montée
	var end_dir := (heading + Vector3.UP * TAKEOFF_CLIMB).normalized()

	# Direction du mouvement : verticale au départ, end_dir à la fin.
	# smoothstep : l'inclinaison commence et finit en douceur.
	var t := smoothstep(0.0, 1.0, _takeoff_traveled / TAKEOFF_DISTANCE)
	var dir := Vector3.UP.lerp(end_dir, t).normalized()

	# Vitesse croissante, même accélération que fly_towards()
	_takeoff_speed = move_toward(_takeoff_speed, sim.fly_speed, sim.fly_acceleration * delta)

	# Le corps s'oriente d'emblée vers end_dir (nez relevé, face à la cible) :
	# au relais, l'avant de l'abeille est déjà dans l'axe du mouvement, et
	# fly_towards(), qui avance selon l'axe du corps, continue sans cassure
	bee.hop_towards(bee.global_position + dir, _takeoff_speed, end_dir, Vector3.UP, delta)
	_takeoff_traveled += _takeoff_speed * delta

	if _takeoff_traveled >= TAKEOFF_DISTANCE:
		_taking_off = false
		# fly_towards() repart de la vitesse atteinte au lieu de zéro
		bee.set_flight_speed(_takeoff_speed)
	return _taking_off

# =============================================================================
# Atterrissage
# =============================================================================

## Repart de l'étape APPROACH. À appeler si la cible change en cours d'approche
## (SCOUT : la fleur visée s'est vidée et une autre est choisie).
func reset_landing() -> void:
	_landing = Landing.APPROACH

## true dès que l'approche finale a commencé. Permet à GO de renoncer à une fleur
## vide en la voyant de près, sans s'y poser.
func is_on_final_approach() -> bool:
	return _landing != Landing.APPROACH

## Approche puis pose sur [param target], point d'une surface de normale
## [param normal] (unitaire). Renvoie true une fois posée.
## [param max_speed] est transmis à fly_towards() : 0 = fly_speed.
## [param approach_dir] : direction (horizontale, unitaire) dans laquelle l'abeille doit
## se déplacer en se posant, et donc regarder une fois posée. Planche d'envol : vers
## l'entrée. Vector3.ZERO (fleurs) : arrivée libre, face à la direction de vol.
func update_landing(target: Vector3, normal: Vector3, hover_time: float,
		delta: float, max_speed := 0.0, approach_dir := Vector3.ZERO) -> bool:
	var dist := bee.global_position.distance_to(target)
	# Décalage en amont de la cible, le long de l'axe d'arrivée (nul sans direction imposée)
	var lead := -approach_dir * (dist * APPROACH_LEAD)

	match _landing:
		Landing.APPROACH:
			# Relais quand la loi distance / tau rejoint la vitesse actuelle : même vitesse
			# des deux côtés, donc pas d'à-coup. FINAL_MIN_DISTANCE garantit le relais
			# même si fly_towards() a déjà beaucoup ralenti.
			if dist <= maxf(bee.get_flight_speed() * LANDING_TAU, FINAL_MIN_DISTANCE) \
					and _in_approach_cone(target, dist, approach_dir):
				_landing = Landing.FINAL
				_final_start_dist = maxf(dist, 0.001)
				# Pattes sorties pendant toute l'approche finale : animation visible.
				# Non bouclée, elle reste sur sa dernière pose jusqu'au contact.
				bee.play_animation(&"_bee_landing")
			else:
				# Vol normal vers un point en amont de la cible : l'abeille rejoint l'axe
				# d'arrivée, en contournant la ruche si besoin (évitement de fly_towards)
				bee.fly_towards(target + lead, delta, true, max_speed)

		Landing.FINAL:
			# Vitesse proportionnelle à la distance, jamais en hausse, avec un plancher
			var speed := maxf(minf(bee.get_flight_speed(), dist / LANDING_TAU), TOUCHDOWN_SPEED)

			# Point visé décalé le long de la normale et en amont dans l'axe d'arrivée,
			# d'autant moins que l'abeille est proche : la trajectoire s'incurve,
			# finit perpendiculaire à la surface et, si imposé, dans l'axe d'arrivée
			var aim := target + normal * (dist * APPROACH_CURVE) + lead

			# Le haut de l'abeille passe progressivement de la verticale à la normale
			var k := 1.0 - clampf(dist / _final_start_dist, 0.0, 1.0)
			var up := Vector3.UP.slerp(normal, k)

			# Regard dans le sens du mouvement, ramené dans le plan perpendiculaire à up
			var facing := (aim - bee.global_position).slide(up)
			if facing.is_zero_approx():
				facing = _forward_on(up)

			bee.hop_towards(aim, speed, facing, up, delta)
			# Vitesse mémorisée : si l'état change en pleine approche (GO → SCOUT),
			# fly_towards() repart de là et is_landed() reste faux
			bee.set_flight_speed(speed)

			if bee.global_position.distance_to(target) <= HOVER_HEIGHT:
				_hover_left = hover_time
				# Sans arrêt prévu, on enchaîne directement sur la mise en contact :
				# FINAL est déjà à TOUCHDOWN_SPEED à cette distance, la vitesse ne change pas
				_landing = Landing.HOVER if hover_time > 0.0 else Landing.TOUCHDOWN

		Landing.HOVER:
			# Bref arrêt juste au-dessus de la surface, en finissant de s'aligner dessus
			bee.hop_towards(bee.global_position, 0.0, _landing_facing(normal, approach_dir), normal, delta)
			_hover_left -= delta
			if _hover_left <= 0.0:
				_landing = Landing.TOUCHDOWN

		Landing.TOUCHDOWN:
			# Derniers millimètres jusqu'au contact exact
			bee.hop_towards(target, TOUCHDOWN_SPEED, _landing_facing(normal, approach_dir), normal, delta)
			if bee.is_near(target, EXACT_RADIUS):
				_landing = Landing.DONE

	return _landing == Landing.DONE

# =============================================================================
# Utilitaires internes
# =============================================================================

## Avant de l'abeille (+Z, convention du modèle glTF) projeté dans le plan
## perpendiculaire à [param normal]. Sert de direction de regard quand
## l'abeille ne se déplace pas dans un sens qui aurait un sens pour l'orientation.
func _forward_on(normal: Vector3) -> Vector3:
	var forward := bee.global_basis.z.slide(normal)
	# Abeille pointée le long de la normale : on prend son haut projeté comme cap
	if forward.is_zero_approx():
		forward = bee.global_basis.y.slide(normal)
	return forward

## Regard de l'abeille dans les derniers millimètres : direction d'arrivée imposée,
## projetée sur la surface, ou à défaut son cap actuel.
func _landing_facing(normal: Vector3, approach_dir: Vector3) -> Vector3:
	if approach_dir != Vector3.ZERO:
		var facing := approach_dir.slide(normal)
		if not facing.is_zero_approx():
			return facing
	return _forward_on(normal)

## true si l'abeille arrive dans le cône d'arrivée, ou si aucune direction n'est imposée.
## Compare la direction abeille → cible à approach_dir, à plat (seul le cap compte,
## pas la hauteur d'arrivée).
func _in_approach_cone(target: Vector3, dist: float, approach_dir: Vector3) -> bool:
	if approach_dir == Vector3.ZERO or dist < EXACT_RADIUS:
		return true
	var to_target := (target - bee.global_position).slide(Vector3.UP)
	if to_target.is_zero_approx():
		return true   # pile au-dessus de la cible : rien à traverser
	return to_target.normalized().dot(approach_dir) >= APPROACH_CONE_COS
