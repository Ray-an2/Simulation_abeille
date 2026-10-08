class_name Hive extends Node3D
## Ruche : gère les deux ressources partagées entre les abeilles.

## Demi-dimensions (largeur, hauteur) de la zone d'attente sur le cadre,
## dans le plan local X/Y de SpawnMarker.
@export var spawn_extent: Vector2 = Vector2(0.2, 0.15)

## Décalage latéral maximal (m) de part et d'autre de SpawnMarker, sur son axe X local.
@export var spawn_half_width: float = 0.04

## Distance minimale (m) entre deux abeilles à l'apparition.
@export var spawn_min_spacing: float = 0.01

## Nombre de tirages avant d'accepter une position qui ne respecte pas l'espacement.
const SPAWN_MAX_ATTEMPTS := 5

## Décalages latéraux déjà attribués, pour respecter spawn_min_spacing.
var _used_spawn_offsets: Array[float] = []

## Point où les abeilles se posent en rentrant (fin de RETURN).
@onready var _landing: Marker3D = %LandingMarker
## Entrée de la ruche : passage entre l'extérieur et le cadre.
@onready var _entrance: Marker3D = %EntranceMarker
## Zone de danse sur le cadre.
@onready var _dance: Marker3D = %DanceMarker
## Centre de la zone d'attente sur le cadre (apparition, IDLE).
@onready var _spawn: Marker3D = %SpawnMarker

func get_landing_position() -> Vector3:
	return _landing.global_position

func get_entrance_position() -> Vector3:
	return _entrance.global_position

func get_dance_position() -> Vector3:
	return _dance.global_position
	
func get_spawn_transform() -> Transform3D:
	return Transform3D(_spawn.global_basis.orthonormalized(), _spawn.global_position)

## Point aléatoire jusqu'à spawn_half_width à gauche ou à droite de SpawnMarker,
## à au moins spawn_min_spacing des abeilles déjà placées.
func get_random_spawn_transform() -> Transform3D:
	# orthonormalized : ignore une éventuelle échelle du marqueur
	var b := _spawn.global_basis.orthonormalized()
	var x := _pick_spawn_offset()
	# Rotation autour de la normale du cadre : chaque abeille regarde dans une direction différente
	var oriented := b.rotated(b.y, randf() * TAU)
	return Transform3D(oriented, _spawn.global_position + b.x * x)

## Tire un décalage latéral libre. Si aucun n'est trouvé après SPAWN_MAX_ATTEMPTS
## (zone saturée), garde le dernier tirage plutôt que de bloquer.
func _pick_spawn_offset() -> float:
	var x := 0.0
	for attempt in SPAWN_MAX_ATTEMPTS:
		x = randf_range(-spawn_half_width, spawn_half_width)
		if _is_spawn_offset_free(x):
			break
	_used_spawn_offsets.append(x)
	return x

func _is_spawn_offset_free(x: float) -> bool:
	for used in _used_spawn_offsets:
		if absf(x - used) < spawn_min_spacing:
			return false
	return true

## Vide la liste des positions occupées (à appeler si on relance la simulation).
func clear_spawn_offsets() -> void:
	_used_spawn_offsets.clear()


# =============================================================================
# Données partagées entre les états
# =============================================================================


# =============================================================================
# États
# =============================================================================
