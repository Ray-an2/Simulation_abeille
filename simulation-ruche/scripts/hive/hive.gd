class_name Hive extends Node3D
## Ruche : gère les deux ressources partagées entre les abeilles.

## Demi-dimensions (largeur, hauteur) de la zone d'attente sur le cadre,
## dans le plan local X/Y de SpawnMarker.
@export var spawn_extent: Vector2 = Vector2(0.2, 0.15)

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

## Point aléatoire sur le cadre, dans le plan de SpawnMarker.
func get_random_spawn_transform() -> Transform3D:
	# orthonormalized : ignore une éventuelle échelle du marqueur
	var b := _spawn.global_basis.orthonormalized()
	var offset := b.x * randf_range(-spawn_extent.x, spawn_extent.x) \
				+ b.z * randf_range(-spawn_extent.y, spawn_extent.y)
	# Rotation autour de la normale du cadre : chaque abeille regarde dans une direction différente
	var oriented := b.rotated(b.y, randf() * TAU)
	return Transform3D(oriented, _spawn.global_position + offset)


# =============================================================================
# Données partagées entre les états
# =============================================================================


# =============================================================================
# États
# =============================================================================

