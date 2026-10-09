class_name PathFollower extends RefCounted
## Marche guidée le long d'un Path3D, dans un sens ou dans l'autre (sortie / entrée de la ruche).
## L'abeille vise un point un peu en avant sur la courbe, décalé sur le côté (voie propre
## à chaque abeille), et ralentit derrière une abeille qui va dans le même sens.
## Ce n'est pas un rail : pas de file indienne parfaite, mais des bouchons possibles à l'entrée.

# =============================================================================
# Constantes
# =============================================================================

## Distance (m) le long de la courbe entre le point de référence et le point visé.
const LOOK_AHEAD := 0.01

## Accélération et décélération (facteur de vitesse par seconde), comme sur le cadre.
const ACCELERATION := 4.0
const DECELERATION := 3.0

## Facteur de vitesse de l'abeille sur le chemin, tiré au hasard au départ :
## toutes les abeilles n'avancent pas au même rythme.
const SPEED_FACTOR_MIN := 0.8
const SPEED_FACTOR_MAX := 1.3

## Distance (m) en dessous de laquelle une abeille devant ralentit celle qui suit.
const QUEUE_RADIUS := 0.015

## Cône devant l'abeille dans lequel une voisine la fait ralentir (cosinus de son demi-angle).
## 0.8 correspond à environ 37° de part et d'autre du cap.
const QUEUE_CONE := 0.8

## Distance (m) au dernier point en dessous de laquelle le trajet est terminé.
const END_RADIUS := 0.003

# =============================================================================
# Variables
# =============================================================================

## Abeille guidée.
var bee: Bee

## Chemin suivi, sa longueur, et le sens de parcours (true = du début vers la fin).
var _path: Path3D
var _length := 0.0
var _forward := true

## Position du point de référence le long de la courbe (m depuis le début).
var _offset := 0.0

## Décalage latéral (m) de la voie de l'abeille par rapport à la courbe.
var _lateral := 0.0

## Facteur de vitesse visé et facteur réellement appliqué (multiplient walk_speed).
var _speed_factor := 1.0
var _current_speed := 0.0

# =============================================================================
# Cycle de vie
# =============================================================================

func _init(owner_bee: Bee) -> void:
	bee = owner_bee

## Commence à suivre [param path], du début vers la fin si [param forward] est vrai,
## en sens inverse sinon. Le départ se fait au point de la courbe le plus proche de l'abeille.
func start(path: Path3D, forward: bool) -> void:
	_path = path
	_forward = forward
	_length = path.curve.get_baked_length()

	# Point de départ : le plus proche de l'abeille, qui n'est jamais pile sur la courbe
	var local := path.global_transform.affine_inverse() * bee.global_position
	_offset = path.curve.get_closest_offset(local)

	# Voie : un côté pour la sortie, l'autre pour l'entrée, pour que les abeilles
	# qui se croisent ne se bloquent pas. Jamais pile au centre (0.2 × largeur minimum).
	var w := bee.hive.lane_half_width
	var lane := randf_range(0.2 * w, w)
	_lateral = lane if forward else -lane

	_speed_factor = randf_range(SPEED_FACTOR_MIN, SPEED_FACTOR_MAX)
	# Continuité avec la marche sur le cadre : pas d'arrêt au début du chemin
	_current_speed = bee.walker.current_speed

# =============================================================================
# Méthodes publiques
# =============================================================================

## Avance d'une frame le long du chemin.
func step(delta: float) -> void:
	# Vitesse visée, réduite si une abeille allant dans le même sens est juste devant
	var target_speed := _speed_factor * _queue_factor()
	var rate := ACCELERATION if target_speed > _current_speed else DECELERATION
	_current_speed = move_toward(_current_speed, target_speed, rate * delta)

	# Le point de référence avance sur la courbe à la vitesse de l'abeille :
	# si elle est bloquée, il l'attend
	var dist := bee.simulation.walk_speed * _current_speed * delta
	_offset = clampf(_offset + (dist if _forward else -dist), 0.0, _length)

	# Point visé un peu en avant : l'abeille suit la courbe sans y être collée
	var aim := clampf(_offset + (LOOK_AHEAD if _forward else -LOOK_AHEAD), 0.0, _length)
	var aim_point := _point_at(aim)
	bee.walk_towards(aim_point, delta, _surface_up(aim_point), _current_speed)

## Renvoie true quand l'abeille est arrivée au bout du chemin (dans son sens de parcours).
func is_finished() -> bool:
	var end := _length if _forward else 0.0
	return is_equal_approx(_offset, end) and bee.is_near(_point_at(end), END_RADIUS)

# =============================================================================
# Utilitaires internes
# =============================================================================

## Point global de la voie de l'abeille, à [param offset] mètres du début de la courbe.
func _point_at(offset: float) -> Vector3:
	var curve := _path.curve
	var p := _path.global_transform * curve.sample_baked(offset, true)

	# Tangente approchée par deux échantillons voisins, dans le sens de la courbe
	# (toujours le même, quel que soit le sens de parcours : les voies restent de part
	# et d'autre de la courbe)
	var before := curve.sample_baked(maxf(offset - 0.001, 0.0), true)
	var after := curve.sample_baked(minf(offset + 0.001, _length), true)
	var tangent := _path.global_basis * (after - before)

	# Côté de la voie : horizontal et perpendiculaire à la courbe.
	# Nul si la courbe est verticale (pas de décalage possible), ce qui reste correct.
	var side := Vector3.UP.cross(tangent).normalized()
	return p + side * _lateral

## Facteur de ralentissement dû aux abeilles devant : 1 si la voie est libre,
## proche de 0 au contact d'une abeille allant dans le même sens.
func _queue_factor() -> float:
	# Avant du modèle sur +Z (convention glTF) ; normalisé au cas où l'abeille est mise à l'échelle
	var forward := bee.global_basis.z.normalized()
	var factor := 1.0
	for other in bee.hive.get_comb_bees_near(bee.global_position, QUEUE_RADIUS, bee):
		# Abeilles venant en sens inverse : elles sont sur l'autre voie, on les ignore
		if other.global_basis.z.normalized().dot(forward) <= 0.0:
			continue
		var to_other := other.global_position - bee.global_position
		var d := to_other.length()
		if d < 0.000001:
			continue
		# Seulement celles qui sont devant, dans le cône
		if forward.dot(to_other / d) < QUEUE_CONE:
			continue
		# Plus elle est proche, plus on ralentit : on la suit à distance
		factor = minf(factor, d / QUEUE_RADIUS)
	return factor

## Vecteur haut de l'abeille selon la pente du chemin vers [param aim_point] :
## normale du cadre quand le chemin est vertical (descente du cadre),
## verticale du monde quand il est horizontal (plancher, planche d'envol),
## mélange des deux entre les deux (passage de l'arête).
## Évite que _face() reçoive une direction parallèle au vecteur haut.
func _surface_up(aim_point: Vector3) -> Vector3:
	var dir := aim_point - bee.global_position
	if dir.length_squared() < 0.0000000001:
		return Vector3.UP
	# 1 si le chemin est vertical, 0 s'il est horizontal
	var steepness := absf(dir.normalized().dot(Vector3.UP))
	return Vector3.UP.lerp(bee.hive.get_comb_normal(), steepness).normalized()
