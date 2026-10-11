extends Node3D
class_name BeeCamera
## Caméra qui suit une abeille, en 3ème personne (orbite à la souris)
## ou en 1ère personne (vue depuis la tête). Touche V pour basculer.
##
## Arborescence attendue :
##   BeeCamera (Node3D, ce script)
##   └── SpringArm3D
##       └── Camera3D
##
## Le nœud peut être placé n'importe où dans la scène : il passe en
## top_level pour ne pas hériter des transformations de son parent.

## Abeille actuellement suivie (null = rien à suivre).
@export var target: Node3D

## Sensibilité de la souris (radians par pixel déplacé).
@export var mouse_sensitivity := 0.003

@export_group("Third person")
## Distance caméra <-> abeille, en mètres. Une ouvrière mesure ~1,2-1,5 cm :
## si la scène est à l'échelle réelle, quelques centimètres suffisent.
@export var distance := 0.08
@export var distance_min := 0.02
@export var distance_max := 0.5
## Vitesse à laquelle le pivot rattrape l'abeille (plus grand = plus rigide).
@export var follow_smoothing := 12.0

@export_group("First person")
## Position de l'œil dans le repère local de l'abeille (avant = -Z).
## À ajuster selon le modèle : ici ~6 mm devant le centre, 2 mm au-dessus.
@export var head_offset := Vector3(0.0, 0.002, -0.006)
## Couche de rendu réservée à l'abeille suivie, masquée en 1ère personne.
## Aucun autre objet de la scène ne doit l'utiliser.
@export_range(1, 20) var hidden_layer := 20

@export_group("View limits")
## Limites de l'inclinaison verticale (communes aux deux modes).
@export_range(-89.0, 0.0) var pitch_min_deg := -80.0
@export_range(0.0, 89.0) var pitch_max_deg := 60.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var first_person := false

# Angles de vue pilotés par la souris (en radians).
# En 3ème personne : absolus (repère du monde).
# En 1ère personne : relatifs à l'orientation de l'abeille.
var yaw := 0.0
var pitch := deg_to_rad(-20.0)

# Angles de la 3ème personne, mis de côté pendant la 1ère personne
# pour retrouver la même vue au retour.
var _saved_yaw := 0.0
var _saved_pitch := deg_to_rad(-20.0)

# Couches de rendu d'origine des maillages de la cible, pour les restaurer.
var _original_layers := {}


func _ready() -> void:
	# Indépendant du parent : seule la cible nous intéresse.
	top_level = true

	# À petite échelle, le plan de découpage proche par défaut (0,05 m)
	# couperait l'abeille entière : on le rapproche.
	camera.near = 0.002

	# La caméra ne dessine jamais la couche réservée : il suffit d'y
	# déplacer les maillages de l'abeille pour la rendre invisible.
	camera.set_cull_mask_value(hidden_layer, false)

	# Une petite sphère plutôt qu'un rayon évite que la caméra frôle
	# une paroi au point de voir à travers.
	var shape := SphereShape3D.new()
	shape.radius = 0.005
	spring_arm.shape = shape
	spring_arm.spring_length = distance

	if target:
		follow(target)


## Change l'abeille suivie et active cette caméra.
func follow(bee: Node3D) -> void:
	# On rend à l'ancienne cible son apparence et ses collisions normales.
	if is_instance_valid(target):
		_hide_target(false)
		if target is CollisionObject3D:
			spring_arm.remove_excluded_object(target.get_rid())

	target = bee

	# Le SpringArm ne doit pas entrer en collision avec l'abeille elle-même.
	if target is CollisionObject3D:
		spring_arm.add_excluded_object(target.get_rid())
	if first_person:
		_hide_target(true)

	# Téléportation immédiate pour éviter un long travelling depuis l'ancienne cible.
	global_position = target.global_position
	camera.make_current()


## Bascule entre 1ère et 3ème personne.
func toggle_view() -> void:
	first_person = not first_person

	if first_person:
		# On mémorise la vue orbitale et on regarde droit devant l'abeille.
		_saved_yaw = yaw
		_saved_pitch = pitch
		yaw = 0.0
		pitch = 0.0
		spring_arm.spring_length = 0.0 # caméra exactement sur le pivot (l'œil)
	else:
		yaw = _saved_yaw
		pitch = _saved_pitch

	if is_instance_valid(target):
		_hide_target(first_person)


func _unhandled_input(event: InputEvent) -> void:
	# Rotation de la vue : seulement quand la souris est capturée,
	# pour pouvoir encore cliquer sur l'interface sinon.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# Clic = on prend la main sur la souris.
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(distance * 0.9, distance_min)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(distance * 1.1, distance_max)

	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		toggle_view()

	elif event.is_action_pressed("ui_cancel"):
		# Échap = on rend la souris.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	# L'abeille a pu mourir / être libérée : on ne suit plus rien.
	if not is_instance_valid(target):
		return

	if first_person:
		_update_first_person()
	else:
		_update_third_person(delta)


func _update_third_person(delta: float) -> void:
	# Suivi amorti de la position. La forme 1 - exp(-k*dt) rend le lissage
	# indépendant du nombre d'images par seconde.
	var t := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(target.global_position, t)

	# Orientation du pivot : ordre d'Euler YXZ par défaut, donc
	# x = inclinaison, y = rotation horizontale.
	rotation = Vector3(pitch, yaw, 0.0)

	# Le bras s'étend selon +Z local ; la caméra au bout regarde selon -Z,
	# donc vers l'abeille. Le zoom est lissé lui aussi.
	spring_arm.spring_length = lerpf(spring_arm.spring_length, distance, t)


func _update_first_person() -> void:
	# Pas de lissage ici : un retard placerait l'œil dans le corps de l'abeille.
	var bee_transform := target.global_transform.orthonormalized()

	# L'œil est positionné dans le repère de l'abeille...
	global_position = bee_transform * head_offset

	# ...et la souris tourne la tête par rapport au corps : la vue suit
	# donc les virages de l'abeille.
	global_basis = bee_transform.basis * Basis.from_euler(Vector3(pitch, yaw, 0.0))


## Cache ou réaffiche tous les maillages de la cible en jouant sur leurs
## couches de rendu (l'abeille reste visible pour les autres caméras
## éventuelles qui n'excluent pas cette couche).
func _hide_target(should_hide: bool) -> void:
	var meshes := target.find_children("*", "VisualInstance3D", true, false)
	if target is VisualInstance3D:
		meshes.append(target)

	for m: VisualInstance3D in meshes:
		if should_hide:
			_original_layers[m] = m.layers
			m.layers = 1 << (hidden_layer - 1)
		elif _original_layers.has(m):
			m.layers = _original_layers[m]

	if not should_hide:
		_original_layers.clear()
