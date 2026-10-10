class_name Hive extends Node3D
## Ruche : gère les deux ressources partagées entre les abeilles.

# =============================================================================
# Constantes
# =============================================================================

## Nombre de tirages avant d'accepter une position qui ne respecte pas l'espacement.
const SPAWN_MAX_ATTEMPTS := 5

# =============================================================================
# Paramètres réglables
# =============================================================================

@export_group("Apparition")

## Nœud du modèle contenant la surface où marchent les abeilles (partie cire du cadre).
@export var comb_node_name: StringName = &"Frame-1"

## Marge (m) laissée au bord du cadre pour que les abeilles ne débordent pas.
@export var comb_margin: float = 0.01

## Demi-dimensions (largeur, hauteur) de la zone d'attente sur le cadre,
## dans le plan local X/Y de SpawnMarker.
@export var spawn_extent: Vector2 = Vector2(0.2, 0.15)

## Distance minimale (m) entre deux abeilles à l'apparition.
@export var spawn_min_spacing: float = 0.01

@export_group("Sortie")

## Distance (m) entre le cadre et le point où une abeille qui se laisse tomber touche
## le plancher, le long de la normale du cadre. Évite qu'elle traverse la traverse
## du bas du cadre en tombant. À ajuster à la géométrie de la ruche.
@export var drop_clearance: float = 0.01

## Longueur (m) du tunnel d'entrée, centré sur EntranceMarker.
@export var tunnel_length: float = 0.0025

## Demi-écart (m) entre les deux vitres, au niveau du plancher.
@export var floor_half_width: float = 0.02

## Demi-largeur (m) du tunnel d'entrée.
@export var tunnel_half_width: float = 0.01

## Distance (m) devant l'embouchure du tunnel, sur la planche, où l'abeille passe avant
## de tourner vers son point de décollage (et par où elle arrive avant d'entrer).
## Environ une longueur d'abeille : elle s'écarte du mur avant de longer la planche.
@export var porch_distance: float = 0.015

## Marge (m) entre le centre d'une abeille et une paroi : environ sa demi-largeur.
@export var wall_margin: float = 0.004

## Zone de décollage et d'atterrissage sur la planche, dans le repère de LandingMarker :
## ± landing_half_width sur X, de 0 à landing_depth sur +Z.
@export var landing_half_width: float = 0.04
@export var landing_depth: float = 0.01

@export_group("Son")

## Volume (dB) du bourdonnement pour une seule abeille dans la ruche.
## Le volume réel monte de 10·log10(N) dB avec N abeilles présentes.
@export var buzz_single_db: float = -30.0

## Vitesse de lissage du volume : évite les sauts quand plusieurs
## abeilles entrent ou sortent en même temps.
@export var buzz_smoothing: float = 2.0

## Bourdonnement collectif de la colonie.
@onready var _buzz: AudioStreamPlayer3D = %HiveBuzz

# =============================================================================
# Nœuds de la scène
# =============================================================================

## Point où les abeilles se posent en rentrant (fin de RETURN).
@onready var _landing: Marker3D = %LandingMarker
## Entrée de la ruche : passage entre l'extérieur et le cadre.
@onready var _entrance: Marker3D = %EntranceMarker
## Zone de danse sur le cadre.
@onready var _dance: Marker3D = %DanceMarker
## Centre de la zone d'attente sur le cadre (apparition, IDLE).
@onready var _spawn: Marker3D = %SpawnMarker

# =============================================================================
# État interne
# =============================================================================

## Centre de la zone de déambulation, dans le repère local de SpawnMarker (Y = 0).
## Calculé une seule fois dans _ready() par _compute_comb_extent().
var _comb_center_local := Vector3.ZERO

## Positions d'apparition déjà attribuées, dans le plan local X/Z de SpawnMarker,
## pour respecter spawn_min_spacing.
var _used_spawn_positions: Array[Vector2] = []

## Abeilles actuellement dans un état du super-état Ruche.
## Tenue à jour par Bee.change_state() via bee_entered() / bee_left() ;
## sert au volume du bourdonnement et à l'évitement entre abeilles.
var _comb_bees: Array[Bee] = []

## Nombre d'abeilles dans la ruche, déduit de la liste (lecture seule).
## Gardé sous ce nom pour ne pas casser le code qui l'utilise déjà.
var bees_inside: int:
	get:
		return _comb_bees.size()

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	_compute_comb_extent()

func _process(delta: float) -> void:
	_update_buzz_volume(delta)

# =============================================================================
# Points de passage
# =============================================================================

## Repère du cadre, en coordonnées globales : origine au centre de la zone d'attente,
## plan X/Z = surface où marchent les abeilles, axe Y = normale du cadre.
## orthonormalized() retire une éventuelle échelle du marqueur pour ne garder que la rotation.
func get_spawn_transform() -> Transform3D:
	return Transform3D(_spawn.global_basis.orthonormalized(), _spawn.global_position)

## Centre du tunnel d'entrée, au niveau du plancher de la ruche.
## Point de passage entre l'intérieur et la planche d'envol (LEAVE, ENTER).
func get_entrance_position() -> Vector3:
	return _entrance.global_position
	
## Hauteur (Y global) du centre d'une abeille posée sur le plancher de la ruche.
## Donnée par EntranceMarker, placé au niveau du plancher à l'entrée.
func get_floor_height() -> float:
	return _entrance.global_position.y

## Axe du tunnel d'entrée, horizontal, orienté de l'intérieur vers la planche d'envol.
## Suppose que le tunnel est dans l'axe EntranceMarker → LandingMarker (vu de dessus).
func get_tunnel_axis() -> Vector3:
	return (_landing.global_position - _entrance.global_position).slide(Vector3.UP).normalized()

## Extrémité intérieure du tunnel (côté cadre), au niveau du plancher.
func get_tunnel_inner_end() -> Vector3:
	return _entrance.global_position - get_tunnel_axis() * tunnel_length * 0.5

## Extrémité extérieure du tunnel (côté planche), au niveau du plancher.
func get_tunnel_outer_end() -> Vector3:
	return _entrance.global_position + get_tunnel_axis() * tunnel_length * 0.5

## Point de dégagement devant l'embouchure du tunnel, à porch_distance dans son axe,
## décalé au hasard sur la largeur utile du tunnel.
func get_random_porch_point() -> Vector3:
	var axis := get_tunnel_axis()
	var side := Vector3.UP.cross(axis).normalized()
	var half_width := tunnel_half_width - wall_margin
	return get_tunnel_outer_end() + axis * porch_distance + side * randf_range(-half_width, half_width)
	
## Ramène [param point] entre les parois : entre les deux vitres à l'intérieur de la ruche,
## entre les parois du tunnel dans le tunnel. Seule la position latérale est bornée ;
## la hauteur et l'avancée ne changent pas. Au-delà du tunnel (planche d'envol),
## le point est renvoyé tel quel.
## Suppose le tunnel centré entre les vitres, sur EntranceMarker.
func clamp_to_floor(point: Vector3) -> Vector3:
	var axis := get_tunnel_axis()
	var rel := point - _entrance.global_position
	# Position le long du tunnel : négative à l'intérieur, positive vers la planche
	var along := rel.dot(axis)
	var half_length := tunnel_length * 0.5

	# Dehors, sur la planche : pas de parois
	if along > half_length:
		return point

	# Direction latérale et demi-largeur utile selon la zone
	var side: Vector3
	var half_width: float
	if along >= -half_length:
		# Dans le tunnel : perpendiculaire à son axe, à l'horizontale
		side = Vector3.UP.cross(axis).normalized()
		half_width = tunnel_half_width - wall_margin
	else:
		# Dans la ruche : d'une vitre à l'autre, le long de la normale du cadre
		side = get_comb_normal()
		half_width = floor_half_width - wall_margin

	var lateral := rel.dot(side)
	return point - side * (lateral - clampf(lateral, -half_width, half_width))

## Point de référence de la planche d'envol (centre du bord, côté tunnel).
## Pour un point de décollage ou d'atterrissage, préférer get_random_landing_position().
func get_landing_position() -> Vector3:
	return _landing.global_position

## Point tiré au hasard dans la zone de décollage / atterrissage de la planche,
## pour que les abeilles ne partent et n'arrivent pas toutes au même endroit.
func get_random_landing_position() -> Vector3:
	return _landing.global_transform * Vector3(
		randf_range(-landing_half_width, landing_half_width),
		0.0,
		randf_range(0.0, landing_depth)
	)

## Centre de la zone de danse sur le cadre, où les danseuses se regroupent (DANCE)
## et où les abeilles en attente viennent les suivre (WATCH).
func get_dance_position() -> Vector3:
	return _dance.global_position
	
# =============================================================================
# Zone du cadre (déambulation en IDLE)
# =============================================================================

## Calcule [member spawn_extent] et [member _comb_center_local] à partir de la géométrie
## du cadre, exprimée dans le repère de SpawnMarker (plan X/Z, normale Y).
## Garde la valeur exportée de spawn_extent si le nœud ou ses meshes sont introuvables.
func _compute_comb_extent() -> void:
	# Recherche récursive par nom dans le modèle importé
	var root := find_child(comb_node_name, true, false)
	if root == null:
		push_warning("Hive : nœud '%s' introuvable, spawn_extent manuel conservé" % comb_node_name)
		return

	# find_children ne renvoie que les descendants : on ajoute le nœud lui-même s'il est un mesh
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	if meshes.is_empty():
		push_warning("Hive : aucun MeshInstance3D sous '%s'" % comb_node_name)
		return

	# Passage du repère global au repère local de SpawnMarker.
	# Calculer l'AABB dans ce repère (et non en global) évite qu'elle soit gonflée
	# quand la ruche est tournée dans la scène.
	var to_marker := _spawn.global_transform.affine_inverse()

	# Fusion des boîtes englobantes de tous les meshes (ex. plusieurs surfaces de cire)
	var box := AABB()
	var first := true
	for m: MeshInstance3D in meshes:
		# get_aabb() est dans le repère du mesh : mesh → global → SpawnMarker
		var b: AABB = (to_marker * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false

	# Centre de la zone dans le plan du cadre. Y forcé à 0 : les abeilles restent
	# à la hauteur de SpawnMarker, posé sur la face où elles marchent.
	_comb_center_local = Vector3(box.get_center().x, 0.0, box.get_center().z)

	# Demi-dimensions sur X (largeur) et Z (hauteur du cadre), réduites de la marge
	# pour que les abeilles n'atteignent pas le bord
	spawn_extent = Vector2(box.size.x, box.size.z) * 0.5 - Vector2.ONE * comb_margin
	
## Normale du cadre : sert de vecteur « haut » aux abeilles qui marchent dessus.
func get_comb_normal() -> Vector3:
	return _spawn.global_basis.orthonormalized().y
	
## Centre de la zone de déambulation, en coordonnées globales.
## Sert de point de repli aux abeilles qui arrivent au bord du cadre.
func get_comb_center() -> Vector3:
	return _spawn.global_transform * _comb_center_local

## Point du cadre à au plus [param radius] de [param from], borné au rectangle
## et ramené dans le plan de SpawnMarker.
func get_comb_point_near(from: Vector3, radius: float) -> Vector3:
	var b := _spawn.global_basis.orthonormalized()
	# Décalage aléatoire dans le plan du cadre (axes X et Z du marqueur)
	var offset := b.x * randf_range(-radius, radius) + b.z * randf_range(-radius, radius)
	return clamp_to_comb(from + offset)

## Point du bord inférieur de la zone de déambulation le plus proche de [param pos].
## Sert de cible aux abeilles qui descendent le cadre pour sortir.
func get_comb_bottom_point(pos: Vector3) -> Vector3:
	var local := _spawn.global_transform.affine_inverse() * clamp_to_comb(pos)
	# Bas du cadre = côté -Z de SpawnMarker
	local.z = _comb_center_local.z - spawn_extent.y
	return _spawn.global_transform * local

## Distance (m) entre [param pos] et le bord inférieur de la zone de déambulation,
## mesurée dans le plan du cadre (0 = sur le bord, positive au-dessus).
## Suppose que l'axe Z de SpawnMarker monte le long du cadre (bas = côté -Z).
func get_comb_bottom_distance(pos: Vector3) -> float:
	var local := _spawn.global_transform.affine_inverse() * pos
	return local.z - (_comb_center_local.z - spawn_extent.y)
	
## Ramène [param point] dans le rectangle du cadre et dans son plan.
## Renvoie le point inchangé s'il y est déjà.
func clamp_to_comb(point: Vector3) -> Vector3:
	var local := _spawn.global_transform.affine_inverse() * point
	local.x = clampf(local.x, _comb_center_local.x - spawn_extent.x, _comb_center_local.x + spawn_extent.x)
	local.z = clampf(local.z, _comb_center_local.z - spawn_extent.y, _comb_center_local.z + spawn_extent.y)
	local.y = 0.0   # collé à la surface du cadre (hauteur de SpawnMarker)
	return _spawn.global_transform * local
	
# =============================================================================
# Apparition des abeilles
# =============================================================================

## Point aléatoire sur le cadre, à au moins spawn_min_spacing des abeilles déjà placées,
## avec une orientation aléatoire autour de la normale du cadre.
func get_random_spawn_transform() -> Transform3D:
	# orthonormalized : ignore une éventuelle échelle du marqueur
	var b := _spawn.global_basis.orthonormalized()
	var p := _pick_spawn_position()
	# Retour en 3D : X et Z du plan local, Y = 0 pour rester à la surface du cadre
	var pos := _spawn.global_transform * Vector3(p.x, 0.0, p.y)
	# Rotation autour de la normale du cadre : chaque abeille regarde dans une direction différente
	var oriented := b.rotated(b.y, randf() * TAU)
	return Transform3D(oriented, pos)

## Tire une position libre dans le rectangle du cadre (repère local de SpawnMarker).
## Si aucune n'est trouvée après SPAWN_MAX_ATTEMPTS (zone saturée), garde le dernier
## tirage plutôt que de bloquer.
func _pick_spawn_position() -> Vector2:
	var p := Vector2.ZERO
	for attempt in SPAWN_MAX_ATTEMPTS:
		p = Vector2(
			_comb_center_local.x + randf_range(-spawn_extent.x, spawn_extent.x),
			_comb_center_local.z + randf_range(-spawn_extent.y, spawn_extent.y)
		)
		if _is_spawn_position_free(p):
			break
	_used_spawn_positions.append(p)
	return p

## Renvoie true si [param p] est à au moins spawn_min_spacing de toutes les positions déjà prises.
func _is_spawn_position_free(p: Vector2) -> bool:
	# Comparaison des carrés : évite une racine carrée par abeille déjà placée
	var min_sq := spawn_min_spacing * spawn_min_spacing
	for used in _used_spawn_positions:
		if p.distance_squared_to(used) < min_sq:
			return false
	return true

## Vide la liste des positions occupées (à appeler si on relance la simulation).
func clear_spawn_positions() -> void:
	_used_spawn_positions.clear()
	
# =============================================================================
# Abeilles sur le cadre (évitement)
# =============================================================================

## Abeilles de la ruche à moins de [param radius] de [param pos], sans [param exclude].
## Parcours complet de la liste : suffisant pour 200 abeilles, à remplacer par une
## grille spatiale si le profileur montre que ça coûte trop cher.
func get_comb_bees_near(pos: Vector3, radius: float, exclude: Bee = null) -> Array[Bee]:
	var result: Array[Bee] = []
	# Comparaison des carrés : évite une racine carrée par abeille
	var r2 := radius * radius
	for other in _comb_bees:
		if other != exclude and other.global_position.distance_squared_to(pos) < r2:
			result.append(other)
	return result
	
# =============================================================================
# Danses (boucle positive : recrutement)
# =============================================================================

# =============================================================================
# Présence des abeilles (appelé par Bee)
# =============================================================================

## Déclare [param bee] présente dans la ruche (passage Dehors → Ruche ou apparition).
func bee_entered(bee: Bee) -> void:
	# Garde-fou : une abeille ne doit pas être comptée deux fois
	if not _comb_bees.has(bee):
		_comb_bees.append(bee)


## Retire [param bee] de la ruche (départ en vol ou suppression).
func bee_left(bee: Bee) -> void:
	_comb_bees.erase(bee)
	
# =============================================================================
# Son
# =============================================================================

## Ajuste le volume du bourdonnement collectif au nombre d'abeilles présentes.
func _update_buzz_volume(delta: float) -> void:
	# Ruche vide : silence (-80 dB est inaudible)
	var target := -80.0
	if bees_inside > 0:
		# Sommation de sources indépendantes : +10·log10(N) dB
		target = buzz_single_db + linear_to_db(sqrt(float(bees_inside)))
	# Lissage exponentiel, indépendant du framerate
	# volume(N) = volume d’une abeille + 10·log₁₀(N)
	_buzz.volume_db = lerpf(_buzz.volume_db, target, 1.0 - exp(-buzz_smoothing * delta))
