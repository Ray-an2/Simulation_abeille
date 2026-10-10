class_name CombWalker extends RefCounted
## Locomotion sur le cadre, partagée par tous les états Ruche : cap, vitesse courante
## (accélération / freinage), évitement des voisines et des bords.
## Les états fixent une intention (virage, cible, vitesse visée) ; le walker l'exécute.
## Il appartient à l'abeille et non à un état : cap et vitesse sont conservés
## quand l'abeille passe d'un état Ruche à un autre (ex. IDLE → WATCH).

# =============================================================================
# Constantes
# =============================================================================

## Accélération au démarrage (facteur de vitesse gagné par seconde).
## Avec 4, une abeille atteint walk_speed en 0,25 s.
const ACCELERATION := 4.0

## Décélération à l'arrêt (facteur de vitesse perdu par seconde).
## Un peu plus faible que l'accélération : l'abeille ralentit avant de s'arrêter.
const DECELERATION := 3.0

## Distance (m) du point visé devant l'abeille. Doit rester supérieure au pas
## parcouru en une frame, sinon l'abeille s'arrêterait sur ce point.
const LOOK_AHEAD := 0.01

## Vitesse de virage (rad/s) pour revenir vers le centre quand l'abeille atteint un bord.
const EDGE_TURN_RATE := 5.0

## Distance (m) en dessous de laquelle une voisine est évitée.
## Environ une longueur d'abeille : à ajuster à la taille du modèle.
const AVOID_RADIUS := 0.015

## Vitesse de virage (rad/s) pour contourner une voisine, à urgence maximale.
const AVOID_TURN_RATE := 6.0

## Part de la vitesse perdue au contact d'une voisine située devant (0 à 1) :
## l'abeille freine en plus de tourner, comme derrière une abeille plus lente.
const AVOID_BRAKE := 0.7

# =============================================================================
# Types
# =============================================================================

## Surface sur laquelle marche l'abeille.
enum Surface {
	COMB,    ## Cadre : borné au rectangle de déambulation, normale du cadre
	FLOOR,   ## Plancher de la ruche : non borné, verticale du monde
}

# =============================================================================
# Variables
# =============================================================================

## Abeille déplacée par ce walker.
var bee: Bee

## Direction de marche, toujours dans le plan du cadre (unitaire).
var heading := Vector3.ZERO

## Facteur de vitesse réellement appliqué (multiplie walk_speed).
## Tend vers la vitesse visée passée à step(), avec ACCELERATION / DECELERATION.
var current_speed := 0.0

## Sens du dernier virage volontaire (+1 ou -1). Sert à choisir un côté
## quand une voisine est pile devant et qu'aucun côté n'est meilleur.
var _last_turn_sign := 1.0

## Surface parcourue actuellement. Fixée par reset().
var surface := Surface.COMB

# =============================================================================
# Cycle de vie
# =============================================================================

func _init(owner_bee: Bee) -> void:
	bee = owner_bee

## Réinitialise le walker sur [param new_surface] : immobile, cap = avant de l'abeille (+Z)
## projeté sur la surface. Appelé à l'arrivée sur le cadre (apparition, retour)
## et à chaque changement de surface (chute sur le plancher, saut sur le cadre).
func reset(new_surface: Surface = Surface.COMB) -> void:
	surface = new_surface
	current_speed = 0.0
	var normal := get_normal()
	heading = bee.global_basis.z.slide(normal).normalized()
	# Abeille perpendiculaire à la surface : la projection est nulle,
	# on prend son axe latéral comme cap arbitraire
	if heading.is_zero_approx():
		heading = bee.global_basis.x.slide(normal).normalized()

## Normale de la surface parcourue : vecteur haut de l'abeille et axe de ses virages.
func get_normal() -> Vector3:
	return bee.hive.get_comb_normal() if surface == Surface.COMB else Vector3.UP

# =============================================================================
# Intentions (appelées par les états)
# =============================================================================

## Fait tourner le cap de [param angle] radians autour de la normale du cadre.
## Utilisé par IDLE pour ses virages aléatoires.
func turn(angle: float) -> void:
	if angle == 0.0:
		return
	heading = heading.rotated(get_normal(), angle)
	_last_turn_sign = signf(angle)

## Oriente progressivement le cap vers [param point], d'au plus [param rate] rad/s.
## Utilisé pour revenir des bords, et plus tard pour suivre une danseuse (WATCH)
## ou rejoindre une receveuse (UNLOAD).
func steer_towards(point: Vector3, rate: float, delta: float) -> void:
	var normal := get_normal()
	var to_point := (point - bee.global_position).slide(normal)
	# Déjà sur le point : aucune direction à viser
	if to_point.length_squared() < 0.0000000001:
		return
	# Angle signé du cap vers la cible, autour de la normale. Contrairement à un lerp,
	# une rotation fonctionne même quand la cible est pile derrière (angle ±π).
	var angle := heading.signed_angle_to(to_point, normal)
	var max_step := rate * delta
	heading = heading.rotated(normal, clampf(angle, -max_step, max_step))

func step(target_speed: float, delta: float, steer_from_edges: bool = true) -> void:
	var rate := ACCELERATION if target_speed > current_speed else DECELERATION
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	if current_speed <= 0.0:
		# Arrêt complet : walk_towards() n'est pas appelée, on repasse nous-mêmes à _bee_idle
		bee.play_walk(0.0)
		return

	var normal := get_normal()
	var brake := _avoid_neighbours(normal, delta)
	var target: Vector3
	if surface == Surface.COMB:
		# Bords traités après l'évitement : une voisine ne peut pas pousser l'abeille hors du cadre
		target = _keep_inside(delta, steer_from_edges)
	else:
		# Plancher et tunnel : bornés par les vitres et les parois du tunnel
		target = _keep_between_walls(delta, steer_from_edges)
	# walk_towards() règle aussi la cadence des pattes, freinage compris
	bee.walk_towards(target, delta, normal, current_speed * brake)

## Renvoie true si l'abeille est complètement arrêtée.
func is_stopped() -> bool:
	return current_speed <= 0.0

## Direction pour s'éloigner des voisines trop proches, dans le plan du cadre.
## Sa longueur mesure l'urgence : 0 sans voisine, environ 1 au contact d'une voisine,
## davantage si plusieurs sont collées. Renvoie Vector3.ZERO si personne n'est à portée.
## Si [param forward] est fourni, seules les voisines situées devant comptent,
## d'autant plus qu'elles sont dans l'axe : l'abeille ne réagit pas à celles
## qui l'approchent par l'arrière.
func get_avoidance(forward: Vector3 = Vector3.ZERO) -> Vector3:
	var normal := get_normal()
	var away := Vector3.ZERO
	for other in bee.hive.get_comb_bees_near(bee.global_position, AVOID_RADIUS, bee):
		# Vecteur voisine → abeille, ramené dans le plan du cadre
		var diff := (bee.global_position - other.global_position).slide(normal)
		var d := diff.length()
		# Deux abeilles exactement superposées : direction de fuite arbitraire (sur le côté)
		if d < 0.000001:
			diff = bee.global_basis.x.slide(normal)
			d = 0.000001
		var dir_away := diff / d

		# Poids linéaire : 0 au bord du rayon, 1 au contact
		var weight := 1.0 - d / AVOID_RADIUS

		if forward != Vector3.ZERO:
			# Cosinus entre le cap et la direction de la voisine :
			# 1 droit devant, 0 sur le côté, négatif derrière
			var facing := forward.dot(-dir_away)
			if facing <= 0.0:
				continue   # voisine derrière ou sur le côté : ignorée
			weight *= facing

		away += dir_away * weight
	return away

# =============================================================================
# Utilitaires internes
# =============================================================================

## Fait tourner le cap pour contourner les voisines situées devant.
## Renvoie le facteur de freinage à appliquer (1 = aucune voisine, plus petit si proche).
func _avoid_neighbours(normal: Vector3, delta: float) -> float:
	var away := get_avoidance(heading)
	if away == Vector3.ZERO:
		return 1.0
	var urgency := minf(away.length(), 1.0)

	# Composante latérale de la fuite : indique de quel côté contourner la voisine.
	# On fait TOURNER le cap au lieu d'interpoler : quand la voisine est pile dans l'axe,
	# la fuite est opposée au cap et un lerp ne le ferait pas tourner.
	var side := away.slide(heading)
	# Une rotation positive autour de la normale amène le cap vers normal × cap
	var turn_sign := signf(side.dot(normal.cross(heading)))

	# Voisine (presque) pile dans l'axe : aucun côté n'est meilleur,
	# on garde le sens du dernier virage
	if side.length() < 0.1 * away.length():
		turn_sign = _last_turn_sign

	heading = heading.rotated(normal, turn_sign * AVOID_TURN_RATE * urgency * delta)

	# Plus la voisine est proche, plus l'abeille freine
	return 1.0 - AVOID_BRAKE * urgency

## Renvoie le point visé devant l'abeille, borné au cadre. Si ce point sortait du cadre
## et que [param steer_from_edges] est vrai, le cap est réorienté progressivement vers le centre.
func _keep_inside(delta: float, steer_from_edges: bool) -> Vector3:
	var ahead := bee.global_position + heading * LOOK_AHEAD
	var clamped := bee.hive.clamp_to_comb(ahead)
	if steer_from_edges and not ahead.is_equal_approx(clamped):
		steer_towards(bee.hive.get_comb_center(), EDGE_TURN_RATE, delta)
	return clamped

## Renvoie le point visé devant l'abeille, ramené entre les parois (vitres, tunnel).
## Si ce point traversait une paroi et que [param steer_from_edges] est vrai,
## le cap est réorienté vers le point ramené : l'abeille longe la paroi au lieu de s'y coller.
func _keep_between_walls(delta: float, steer_from_edges: bool) -> Vector3:
	var ahead := bee.global_position + heading * LOOK_AHEAD
	var clamped := bee.hive.clamp_to_floor(ahead)
	if steer_from_edges and not ahead.is_equal_approx(clamped):
		steer_towards(clamped, EDGE_TURN_RATE, delta)
	return clamped
