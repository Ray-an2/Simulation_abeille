class_name Hive extends Node3D
## Ruche d'observation : géométrie où marchent les abeilles (cadre, plancher, tunnel,
## planche d'envol), présence des abeilles à l'intérieur, danses (boucle positive
## de recrutement) et file de déchargement (boucle négative de saturation).

# =============================================================================
# Constantes
# =============================================================================

## Nombre de tirages avant d'accepter une position qui ne respecte pas l'espacement.
const SPAWN_MAX_ATTEMPTS := 5

## Taille (m) d'une cellule de la grille d'évitement. Doit être supérieure ou égale
## au plus grand rayon passé à get_comb_bees_near() (CombWalker.AVOID_RADIUS) :
## toute voisine à portée est alors forcément dans l'une des 27 cellules autour de l'abeille.
const GRID_CELL := 0.015

## Volume (dB) du bourdonnement quand la ruche est vide : -80 dB est inaudible.
const SILENT_DB := -80.0

## Fréquence de coupure (Hz) du filtre quand la caméra est dans la ruche :
## au-dessus de l'audible, le filtre ne change rien.
const OPEN_CUTOFF_HZ := 20000.0

# =============================================================================
# Paramètres réglables
# =============================================================================

@export_group("Cadre")

## Nœud du modèle contenant la surface où marchent les abeilles (partie cire du cadre).
@export var comb_node_name: StringName = &"Frame-1"

## Marge (m) laissée au bord du cadre pour que les abeilles ne débordent pas.
@export var comb_margin: float = 0.01

## Demi-dimensions (largeur, hauteur) de la zone de déambulation sur le cadre,
## dans le plan local X/Z de SpawnMarker. Recalculées au lancement à partir du modèle
## (_compute_comb_extent) ; la valeur saisie ne sert que si le calcul échoue.
@export var spawn_extent: Vector2 = Vector2(0.2, 0.15)

## Distance minimale (m) entre deux abeilles à l'apparition.
@export var spawn_min_spacing: float = 0.01


@export_group("Zones du cadre")

## Demi-largeur (m) de la zone de déchargement, centrée sur l'aplomb de l'entrée.
## Les receveuses attendent les butineuses près de l'entrée, en bas du rayon.
## Valeur de réglage, à adapter au cadre.
@export var unloading_half_width: float = 0.15

## Hauteur (m) de la zone de déchargement, depuis le bas de la zone de déambulation.
@export var unloading_height: float = 0.1

## Hauteur (m) de la zone de stockage, depuis le haut de la zone de déambulation.
## Le nectar est stocké dans les cellules du haut du rayon, au-dessus du couvain.
@export var storage_height: float = 0.08


@export_group("Plancher et tunnel")

## Demi-écart (m) entre les deux vitres, au niveau du plancher.
@export var floor_half_width: float = 0.02

## Distance (m) entre le cadre et le point où une abeille qui se laisse tomber touche
## le plancher, le long de la normale du cadre. Évite qu'elle traverse la traverse
## du bas du cadre en tombant. À ajuster à la géométrie de la ruche.
@export var drop_clearance: float = 0.01

## Longueur (m) du tunnel d'entrée, centré sur EntranceMarker.
@export var tunnel_length: float = 0.0025

## Demi-largeur (m) du tunnel d'entrée.
@export var tunnel_half_width: float = 0.01

## Marge (m) entre le centre d'une abeille et une paroi : environ sa demi-largeur.
@export var wall_margin: float = 0.004


@export_group("Planche d'envol")

## Distance (m) devant l'embouchure du tunnel, sur la planche, où l'abeille passe avant
## de tourner vers son point de décollage (et par où elle arrive avant d'entrer).
## Environ une longueur d'abeille : elle s'écarte du mur avant de longer la planche.
@export var porch_distance: float = 0.015

## Demi-largeur (m) de la zone de décollage et d'atterrissage, sur l'axe X de LandingMarker.
@export var landing_half_width: float = 0.04

## Profondeur (m) de la zone de décollage et d'atterrissage, de 0 à +Z dans le repère
## de LandingMarker.
@export var landing_depth: float = 0.01

@export_group("Son")

## Volume (dB) du bourdonnement pour une seule abeille dans la ruche.
## Le volume réel monte de 10·log10(N) dB avec N abeilles présentes.
@export var buzz_single_db: float = -30.0

## Vitesse de lissage du volume : évite les sauts quand plusieurs
## abeilles entrent ou sortent en même temps.
@export var buzz_smoothing: float = 2.0

## Fréquence de coupure (Hz) quand la caméra est hors de la ruche : le verre et le bois
## laissent passer les graves du bourdonnement et coupent les aigus.
@export var outside_cutoff_hz: float = 800.0

## Atténuation (dB) ajoutée quand la caméra est hors de la ruche, en plus du filtrage.
@export var outside_attenuation_db: float = 6.0

## Vitesse de passage dedans / dehors (1/s). Avec 10, le passage prend environ 0,3 s.
@export var wall_smoothing: float = 10.0

## Marge (m) ajoutée autour de la cire pour délimiter l'intérieur de la ruche :
## doit couvrir les montants du cadre et l'espace entre le bas du cadre et le plancher.
@export var inside_margin: float = 0.03

# =============================================================================
# Nœuds de la scène
# =============================================================================

## Point où les abeilles se posent en rentrant (fin de RETURN). Sa hauteur est celle
## de l'origine d'une abeille posée sur la planche d'envol.
@onready var _landing: Marker3D = %LandingMarker

## Centre du tunnel d'entrée, au niveau du plancher. Sa hauteur est celle
## de l'origine d'une abeille posée sur le plancher (voir get_floor_height).
@onready var _entrance: Marker3D = %EntranceMarker

## Zone de danse sur le cadre.
@onready var _dance: Marker3D = %DanceMarker

## Centre de la zone d'attente sur le cadre (apparition, IDLE).
## Son plan X/Z est la surface du cadre, son axe Y la normale du cadre.
@onready var _spawn: Marker3D = %SpawnMarker

## Bourdonnement collectif de la colonie.
@onready var _buzz: AudioStreamPlayer3D = %HiveBuzz

# =============================================================================
# État interne
# =============================================================================

# --- Cadre ---

## Centre de la zone de déambulation, dans le repère local de SpawnMarker (Y = 0).
## Calculé une seule fois dans _ready() par _compute_comb_extent().
var _comb_center_local := Vector3.ZERO

## Positions d'apparition déjà attribuées, dans le plan local X/Z de SpawnMarker,
## pour respecter spawn_min_spacing.
var _used_spawn_positions: Array[Vector2] = []

# --- Présence et voisinage ---

## Abeilles actuellement dans un état du super-état Ruche.
## Tenue à jour par Bee.change_state() via bee_entered() / bee_left() ;
## sert au volume du bourdonnement et à l'évitement entre abeilles.
var _comb_bees: Array[Bee] = []

## Nombre d'abeilles dans la ruche, déduit de la liste (lecture seule).
## Gardé sous ce nom pour ne pas casser le code qui l'utilise déjà.
var bees_inside: int:
	get:
		return _comb_bees.size()

## Grille d'évitement : cellule (Vector3i) → abeilles qu'elle contient (Array).
var _grid: Dictionary = {}

## Frame physique de la dernière reconstruction de la grille, pour ne la faire
## qu'une fois par frame.
var _grid_frame := -1

# --- Danses ---

## Danses en cours : danseuse → source annoncée.
## Tenue à jour par DanceState : start_dance() à l'arrivée sur la piste,
## stop_dance() à la sortie de l'état (fin normale ou interruption).
var _dances: Dictionary[Bee, Flower] = {}

## Nombre de suiveuses par danseuse. Tenu à jour par WatchState (enter / exit).
var _followers: Dictionary[Bee, int] = {}

## Trémulantes en cours. Tenue à jour par TrembleState (enter / exit).
var _tremblers: Array[Bee] = []

# --- Déchargement ---

## Nectar accumulé par la colonie depuis le début de la simulation.
var nectar_stock: float = 0.0

## Masse de sucre (mg) stockée : l'énergie réellement récoltée par la colonie
var sugar_stock := 0.0

## Nectar (µL) stocké par espèce : Flower.Species → µL, -1 pour une origine inconnue
## (ne devrait pas arriver). Bilan de la récolte, lu par l'interface (StatsPanel) ;
## aucune abeille ne le lit. Dictionnaire non typé, comme get_dances_by_species() :
## les clés sont les valeurs entières de l'enum.
var nectar_by_species: Dictionary = {}

## Sucre (mg) stocké par espèce, mêmes clés : l'énergie rapportée par chaque source.
var sugar_by_species: Dictionary = {}

## Abeilles dans l'état RECEIVE. Tenu à jour par ReceiveState (enter / exit).
var _receivers: Array[Bee] = []

## Receveuses libres (en route vers la zone de déchargement ou en attente).
## Une butineuse qui en croise une la retire de la liste (claim_receiver_near).
var _free_receivers: Array[Bee] = []

## Butineuses en train de chercher une receveuse (interface uniquement).
var _searching: Array[Bee] = []


# =============================================================================
# Son
# =============================================================================

## Volume (dB) lissé selon le nombre d'abeilles, avant l'atténuation des parois.
## Séparé de _buzz.volume_db : le passage dedans / dehors a son propre lissage, plus rapide.
var _buzz_base_db := 0.0

## Position de la caméra, de 0 (dans la ruche) à 1 (dehors), lissée.
## Part de 1 : au lancement, la caméra est dans une vue fixe, hors de la ruche.
var _outside := 1.0

## Filtre passe-bas du bus de HiveBuzz, null si le bus n'est pas utilisable.
var _lowpass: AudioEffectLowPassFilter

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	_compute_comb_extent()
	# Point de départ du lissage : le volume réglé dans l'inspecteur (-80 conseillé)
	_buzz_base_db = _buzz.volume_db
	_lowpass = _setup_lowpass()

func _process(delta: float) -> void:
	# Parois d'abord : _update_buzz_volume() utilise _outside
	_update_walls(delta)
	_update_buzz_volume(delta)

# =============================================================================
# Points de passage
# =============================================================================

## Centre du tunnel d'entrée, au niveau du plancher de la ruche.
## Point de passage entre l'intérieur et la planche d'envol (LEAVE, ENTER).
func get_entrance_position() -> Vector3:
	return _entrance.global_position

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

## Point de référence de la planche d'envol (centre du bord, côté tunnel).
## LandingMarker est placé à la hauteur de l'origine d'une abeille posée sur la planche.
## Pour un point de décollage ou d'atterrissage, préférer get_random_landing_position().
func get_landing_position() -> Vector3:
	return _landing.global_position

## Point tiré au hasard dans la zone de décollage / atterrissage de la planche,
## pour que les abeilles ne partent et n'arrivent pas toutes au même endroit.
## Zone prise dans le repère de LandingMarker, à la hauteur du marqueur (Y local = 0).
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
# Plancher
# =============================================================================

## Hauteur (Y global) de l'origine d'une abeille posée sur le plancher de la ruche.
## Donnée par EntranceMarker, placé à cette hauteur à l'entrée.
func get_floor_height() -> float:
	return _entrance.global_position.y

## Point du plancher sous [param comb_point], écarté du cadre de drop_clearance
## pour ne pas traverser la traverse du bas. Sert à la chute en sortie (LEAVE)
## comme au point de départ du saut en entrée (ENTER).
func get_floor_point_below(comb_point: Vector3) -> Vector3:
	var p := comb_point + get_comb_normal() * drop_clearance
	return clamp_to_floor(Vector3(p.x, get_floor_height(), p.z))

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

## Vrai si [param point] est dans la ruche : entre les deux vitres et dans l'emprise
## de la cire, agrandie de inside_margin pour couvrir les montants et le plancher.
## Même hypothèse que clamp_to_floor() : vitres centrées sur EntranceMarker.
func is_inside(point: Vector3) -> bool:
	# Écart au milieu des vitres, le long de la normale du cadre
	var lateral := (point - _entrance.global_position).dot(get_comb_normal())
	if absf(lateral) > floor_half_width:
		return false
	# Position dans le plan du cadre, par rapport au centre de la zone de déambulation
	var local := get_spawn_transform().affine_inverse() * point - _comb_center_local
	# spawn_extent est déjà réduit de comb_margin : on la rajoute pour retrouver la cire entière
	var half := spawn_extent + Vector2.ONE * (comb_margin + inside_margin)
	return absf(local.x) <= half.x and absf(local.z) <= half.y

# =============================================================================
# Zone du cadre (déambulation en IDLE)
# =============================================================================

## Repère du cadre, en coordonnées globales : origine au centre de la zone d'attente,
## plan X/Z = surface où marchent les abeilles, axe Y = normale du cadre.
## orthonormalized() retire une éventuelle échelle du marqueur pour ne garder que la rotation.
func get_spawn_transform() -> Transform3D:
	return Transform3D(_spawn.global_basis.orthonormalized(), _spawn.global_position)

## Normale du cadre : sert de vecteur « haut » aux abeilles qui marchent dessus.
func get_comb_normal() -> Vector3:
	return _spawn.global_basis.orthonormalized().y

## Centre de la zone de déambulation, en coordonnées globales.
## Sert de point de repli aux abeilles qui arrivent au bord du cadre.
func get_comb_center() -> Vector3:
	return _spawn.global_transform * _comb_center_local

## Point tiré au hasard dans la zone de déambulation du cadre.
## Contrairement à get_random_spawn_transform(), ne réserve pas la position.
func get_random_comb_point() -> Vector3:
	return _spawn.global_transform * Vector3(
		_comb_center_local.x + randf_range(-spawn_extent.x, spawn_extent.x),
		0.0,   # à la surface du cadre
		_comb_center_local.z + randf_range(-spawn_extent.y, spawn_extent.y)
	)

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

## Vide la liste des positions occupées (à appeler si on relance la simulation).
func clear_spawn_positions() -> void:
	_used_spawn_positions.clear()

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
# Voisinage (évitement)
# =============================================================================

## Abeilles de la ruche à moins de [param radius] de [param pos], sans [param exclude].
## Ne parcourt que les 27 cellules voisines au lieu de toute la colonie.
func get_comb_bees_near(pos: Vector3, radius: float, exclude: Bee = null) -> Array[Bee]:
	assert(radius <= GRID_CELL, "Hive : rayon de recherche supérieur à GRID_CELL")
	_update_grid()
	var result: Array[Bee] = []
	var r2 := radius * radius
	var center := _cell_of(pos)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var cell = _grid.get(center + Vector3i(x, y, z))
				if cell == null:
					continue
				for other: Bee in cell:
					if other != exclude and other.global_position.distance_squared_to(pos) < r2:
						result.append(other)
	return result

## Cellule de la grille contenant [param pos].
func _cell_of(pos: Vector3) -> Vector3i:
	return Vector3i((pos / GRID_CELL).floor())

## Reconstruit la grille au premier appel de la frame physique.
## Les abeilles déjà déplacées pendant cette frame sont rangées avec leur nouvelle
## position : décalage de quelques dixièmes de mm, sans effet visible sur l'évitement.
func _update_grid() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _grid_frame:
		return
	_grid_frame = frame
	_grid.clear()
	for b in _comb_bees:
		var key := _cell_of(b.global_position)
		if _grid.has(key):
			_grid[key].append(b)
		else:
			_grid[key] = [b]

# =============================================================================
# Danses (boucle positive : recrutement)
# =============================================================================

## Déclare que [param bee] danse pour [param flower].
func start_dance(bee: Bee, flower: Flower) -> void:
	_dances[bee] = flower

## Retire la danse de [param bee]. Sans effet si elle ne dansait pas.
func stop_dance(bee: Bee) -> void:
	_dances.erase(bee)
	_followers.erase(bee)

## true tant que [param bee] danse. Sert à WATCH : une danse finie avant
## watch_min_duration renvoie la suiveuse en IDLE.
func is_dancing(bee: Bee) -> bool:
	return _dances.has(bee)

## Source annoncée par [param bee], ou null si elle ne danse pas.
## WATCH la copie dans known_flower de la suiveuse.
func get_dance_flower(bee: Bee) -> Flower:
	return _dances.get(bee, null)

## Nombre de danses en cours (statistiques, interface).
func get_dance_count() -> int:
	return _dances.size()

## Une suiveuse de plus pour [param dancer].
func add_follower(dancer: Bee) -> void:
	_followers[dancer] = _followers.get(dancer, 0) + 1

## Une suiveuse de moins pour [param dancer]. Sans effet si la danse est finie
## (stop_dance a déjà vidé le compteur).
func remove_follower(dancer: Bee) -> void:
	if not _followers.has(dancer):
		return
	_followers[dancer] -= 1
	if _followers[dancer] <= 0:
		_followers.erase(dancer)

## Nombre de suiveuses de [param dancer].
func get_follower_count(dancer: Bee) -> int:
	return _followers.get(dancer, 0)

## Danseuses à moins de [param radius] de [param pos].
## Peu de danseuses à la fois : un simple parcours suffit, sans grille.
func get_dancers_near(pos: Vector3, radius: float) -> Array[Bee]:
	var result: Array[Bee] = []
	for dancer: Bee in _dances:
		# Abeille supprimée en pleine danse : exit() n'a pas été appelée
		if is_instance_valid(dancer) and dancer.is_near(pos, radius):
			result.append(dancer)
	return result


# =============================================================================
# Déchargement et receveuses (boucle négative : saturation)
# =============================================================================
# La ruche ne gère ni file d'attente ni attribution : elle tient seulement le registre
# des receveuses, comme celui des danses. Une butineuse ne trouve une receveuse qu'en
# la croisant, et mesure elle-même son temps de recherche (UnloadState). Ce temps
# s'allonge quand les receveuses libres se raréfient (Seeley et Tovey 1994).

## Ajoute [param amount] µL de nectar contenant [param sugar] mg de sucre au stock
## de la ruche. Appelé par la receveuse quand elle dépose sa charge en cellule,
## ou par la butineuse si la receveuse a disparu (UnloadState._hand_over).
## [param species] : espèce d'origine du nectar (Flower.Species), -1 si inconnue.
## Elle ne sert qu'au bilan par espèce.
func deposit(amount: float, sugar: float = 0.0, species: int = -1) -> void:
	nectar_stock += amount
	sugar_stock += sugar
	# Bilan par espèce : le total reste dans nectar_stock et sugar_stock
	nectar_by_species[species] = nectar_by_species.get(species, 0.0) + amount
	sugar_by_species[species] = sugar_by_species.get(species, 0.0) + sugar

## Point tiré au hasard dans la zone de déchargement : bas du cadre, à l'aplomb de l'entrée.
func get_unloading_point() -> Vector3:
	var to_local := _spawn.global_transform.affine_inverse()
	var local := to_local * clamp_to_comb(get_entrance_position())
	local.x += randf_range(-unloading_half_width, unloading_half_width)
	# Bas du cadre = côté -Z de SpawnMarker (voir get_comb_bottom_point)
	local.z = _comb_center_local.z - spawn_extent.y + randf() * unloading_height
	return clamp_to_comb(_spawn.global_transform * local)

## Point tiré au hasard dans la zone de stockage : bande du haut du cadre.
func get_storage_point() -> Vector3:
	var local := Vector3(
		_comb_center_local.x + randf_range(-spawn_extent.x, spawn_extent.x),
		0.0,   # à la surface du cadre
		_comb_center_local.z + spawn_extent.y - randf() * storage_height)
	return clamp_to_comb(_spawn.global_transform * local)

## Inscrit [param bee] parmi les receveuses (entrée dans RECEIVE).
func register_receiver(bee: Bee) -> void:
	if not _receivers.has(bee):
		_receivers.append(bee)

## Retire [param bee] des receveuses (sortie de RECEIVE, ou abeille supprimée).
func unregister_receiver(bee: Bee) -> void:
	_receivers.erase(bee)
	_free_receivers.erase(bee)

## Marque [param bee] comme libre ou occupée. Sans effet si elle n'est pas receveuse.
func set_receiver_free(bee: Bee, free: bool) -> void:
	if not free:
		_free_receivers.erase(bee)
	elif _receivers.has(bee) and not _free_receivers.has(bee):
		_free_receivers.append(bee)

## Receveuse libre la plus proche de [param forager], à moins de [param radius],
## ou null. La receveuse renvoyée n'est plus libre : deux butineuses ne peuvent
## pas la prendre en même temps. Perception locale : seule une receveuse au contact
## compte, la butineuse ne sait rien des autres.
## Peu de receveuses libres à la fois : un simple parcours suffit, sans grille.
func claim_receiver_near(forager: Bee, radius: float) -> Bee:
	var best: Bee = null
	var best_d2 := radius * radius
	# Boucle non typée : une abeille supprimée peut rester dans la liste
	for r in _free_receivers:
		if not is_instance_valid(r) or r == forager:
			continue
		var d2: float = r.global_position.distance_squared_to(forager.global_position)
		if d2 <= best_d2:
			best = r
			best_d2 = d2
	if best != null:
		_free_receivers.erase(best)
	return best

## Une butineuse commence à chercher une receveuse.
func start_search(bee: Bee) -> void:
	if not _searching.has(bee):
		_searching.append(bee)

## La butineuse a trouvé une receveuse, ou a quitté UNLOAD.
func stop_search(bee: Bee) -> void:
	_searching.erase(bee)

## Nombre de receveuses (interface).
func get_receiver_count() -> int:
	return _receivers.size()

## Nombre de receveuses libres (interface).
func get_free_receiver_count() -> int:
	return _free_receivers.size()

## Nombre de butineuses qui cherchent une receveuse (interface).
func get_searching_count() -> int:
	return _searching.size()


# =============================================================================
# Danses trémulantes (boucle négative : saturation)
# =============================================================================

## Déclare que [param bee] fait une danse trémulante.
func start_tremble(bee: Bee) -> void:
	if not _tremblers.has(bee):
		_tremblers.append(bee)

## Retire la trémulante [param bee]. Sans effet si elle ne tremblait pas.
func stop_tremble(bee: Bee) -> void:
	_tremblers.erase(bee)

## Trémulantes à moins de [param radius] de [param pos].
## Peu de trémulantes à la fois : un simple parcours suffit, sans grille.
func get_tremblers_near(pos: Vector3, radius: float) -> Array[Bee]:
	var result: Array[Bee] = []
	# Boucle non typée : une abeille supprimée peut rester dans la liste
	for t in _tremblers:
		if is_instance_valid(t) and t.is_near(pos, radius):
			result.append(t)
	return result

## Nombre de danses trémulantes en cours (interface).
func get_tremble_count() -> int:
	return _tremblers.size()


# =============================================================================
# Son
# =============================================================================

## Ajuste le volume du bourdonnement collectif au nombre d'abeilles présentes,
## puis retire l'atténuation des parois si la caméra est dehors.
func _update_buzz_volume(delta: float) -> void:
	var target := SILENT_DB
	if bees_inside > 0:
		# Sommation de sources indépendantes : volume(N) = volume d'une abeille + 10·log10(N).
		# linear_to_db(√N) = 20·log10(√N) = 10·log10(N)
		target = buzz_single_db + linear_to_db(sqrt(float(bees_inside)))
	# Lissage exponentiel, indépendant du framerate
	_buzz_base_db = lerpf(_buzz_base_db, target, 1.0 - exp(-buzz_smoothing * delta))
	_buzz.volume_db = _buzz_base_db - outside_attenuation_db * _outside

## Suit la position de la caméra active (celle qui sert d'auditeur) et règle le filtre
## des parois : son net dans la ruche, assourdi dehors.
func _update_walls(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var target := 0.0 if cam != null and is_inside(cam.global_position) else 1.0
	_outside = lerpf(_outside, target, 1.0 - exp(-wall_smoothing * delta))
	if _lowpass != null:
		# Interpolation en fréquence logarithmique : l'oreille perçoit des octaves, pas des Hz.
		# Une interpolation linéaire resterait presque tout le passage au-dessus de 10 kHz.
		_lowpass.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF_HZ), log(outside_cutoff_hz), _outside))

## Renvoie le filtre passe-bas du bus de HiveBuzz, en l'ajoutant s'il n'existe pas.
## Le filtre agit sur tout le bus : HiveBuzz doit être seul dessus (bus Ruche),
## sinon les abeilles en vol seraient assourdies aussi.
func _setup_lowpass() -> AudioEffectLowPassFilter:
	var bus := AudioServer.get_bus_index(_buzz.bus)
	# -1 : bus introuvable ; 0 : Master, partagé par tous les sons
	if bus <= 0:
		push_warning("Hive : HiveBuzz doit avoir son propre bus pour l'effet des parois (bus actuel : %s)" % _buzz.bus)
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var effect := AudioServer.get_bus_effect(bus, i) as AudioEffectLowPassFilter
		if effect != null:
			return effect
	# Pas de filtre dans la configuration des bus : on en ajoute un pour la durée de l'exécution
	var lowpass := AudioEffectLowPassFilter.new()
	AudioServer.add_bus_effect(bus, lowpass)
	return lowpass
	
## Bus du bourdonnement collectif, avec le filtre des parois.
## Les abeilles l'empruntent pour les sauts entre le cadre et le plancher (Bee._update_buzz).
func get_buzz_bus() -> StringName:
	return _buzz.bus

## Nombre total de suiveuses, toutes danses confondues.
func get_follower_total() -> int:
	var total := 0
	for dancer in _followers:
		total += _followers[dancer]
	return total
	
# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## Danses en cours par espèce annoncée (Flower.Species → nombre de danseuses).
## Dictionnaire non typé : les clés sont les valeurs entières de l'enum.
func get_dances_by_species() -> Dictionary:
	var counts := {}
	for dancer: Bee in _dances:
		var flower := _dances[dancer]
		# Danseuse ou fleur supprimée en pleine danse : exit() n'a pas été appelée
		if not is_instance_valid(dancer) or not is_instance_valid(flower):
			continue
		counts[flower.species] = counts.get(flower.species, 0) + 1
	return counts
