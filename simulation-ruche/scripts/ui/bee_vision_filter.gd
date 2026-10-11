class_name BeeVisionFilter extends ColorRect
## Règle le filtre « vision d'abeille » d'après la caméra active : la mosaïque
## et le flou découlent des angles mesurés sur l'œil d'ouvrière, et non d'un
## nombre de cellules choisi à la main.

## Angle (°) entre deux ommatidies voisines, zone frontale (≈ 1,5 à 2°).
@export_range(0.5, 5.0) var interommatidial_angle := 1.8

## Niveau de mipmap lu pour chaque cellule. Réglé à l'œil : Godot floute ses
## mipmaps d'écran par un gaussien cumulé, on ne peut pas le déduire de l'angle
## de collecte d'une ommatidie.
@export_range(0.0, 6.0) var blur_lod := 2.5

## Niveaux supplémentaires pour lire la couleur sur une zone large (~15°).
## Réglé à l'œil pour la même raison.
@export_range(0.0, 4.0) var color_lod_offset := 1.5

var _material: ShaderMaterial


func _ready() -> void:
	_material = material as ShaderMaterial
	if _material == null:
		push_warning("BeeVisionFilter : le ColorRect n'a pas de ShaderMaterial")


func _process(_delta: float) -> void:
	if _material == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen := get_viewport_rect().size
	var aspect := screen.x / screen.y

	# Champ horizontal de la caméra. Par défaut (KEEP_HEIGHT), Camera3D.fov est vertical
	var fov_h := deg_to_rad(cam.fov)
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		fov_h = 2.0 * atan(tan(fov_h * 0.5) * aspect)

	# Une cellule de la mosaïque = une ommatidie
	_material.set_shader_parameter("cells_across", rad_to_deg(fov_h) / interommatidial_angle)
	_material.set_shader_parameter("blur_lod", blur_lod)
	_material.set_shader_parameter("color_lod_offset", color_lod_offset)
