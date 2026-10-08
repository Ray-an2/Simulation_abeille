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

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	_compute_comb_extent()

# =============================================================================
# Points de passage
# =============================================================================

func get_landing_position() -> Vector3:
	return _landing.global_position

func get_entrance_position() -> Vector3:
	return _entrance.global_position

func get_dance_position() -> Vector3:
	return _dance.global_position

func get_spawn_transform() -> Transform3D:
	return Transform3D(_spawn.global_basis.orthonormalized(), _spawn.global_position)
	
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
	
## Point du cadre à au plus [param radius] de [param from], borné au rectangle
## et ramené dans le plan de SpawnMarker.
func get_comb_point_near(from: Vector3, radius: float) -> Vector3:
	var local := _spawn.global_transform.affine_inverse() * from
	local.x += randf_range(-radius, radius)
	local.z += randf_range(-radius, radius)
	local.x = clampf(local.x, _comb_center_local.x - spawn_extent.x, _comb_center_local.x + spawn_extent.x)
	local.z = clampf(local.z, _comb_center_local.z - spawn_extent.y, _comb_center_local.z + spawn_extent.y)
	local.y = 0.0   # collé à la surface du cadre
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
# Danses (boucle positive : recrutement)
# =============================================================================
