class_name CameraSwitcher extends Node3D
## Gère les vues de la simulation et l'abeille suivie.
##
## 1, 2, 3… : changer de vue (dans l'ordre de pcams).
## Tab / Maj+Tab : aller sur l'abeille épinglée, sinon l'abeille suivante / précédente,
## et passer en vue abeille.
## C (en vue abeille) : basculer entre 1ère et 3ème personne.
## Clic droit maintenu (en 3ème personne) : tourner autour de l'abeille.
## V : activer / désactiver le filtre « vision d'abeille ».
## F11 : basculer en plein écran.

# =============================================================================
# Paramètres réglables
# =============================================================================

## Vues disponibles, dans l'ordre des touches. La première est la vue de départ.
@export var pcams: Array[PhantomCamera3D]

## Durée (s) de la transition entre deux vues fixes.
@export var transition_duration: float = 0.5

@export_group("Vue abeille")

## PCam placé sur l'abeille suivie. Doit aussi figurer dans pcams
## pour être sélectionnable avec les touches chiffrées.
@export var bee_view: PhantomCamera3D

## Conteneur des abeilles créées par Simulation (Simulation/Bees).
@export var bees_container: Node3D

## Filtre plein écran affiché en vue abeille (CanvasLayer contenant le ColorRect).
@export var bee_vision: CanvasLayer

## Surcouche des marqueurs : si une abeille y est épinglée, la vue abeille la suit,
## et elle affiche les données de l'abeille suivie en vue abeille.
@export var bee_overlay: BeeOverlay

@export_group("Vue abeille 3ème personne")

## PCam en suivi 3ème personne (Follow Mode : Third Person) sur l'abeille suivie.
## Ne pas l'ajouter à pcams : on y accède depuis la vue abeille avec third_person_key.
@export var bee_view_third_person: PhantomCamera3D

## Touche qui bascule entre 1ère et 3ème personne en vue abeille.
## Lue par position physique, comme les autres touches de ce script.
@export var third_person_key: Key = KEY_C

## Sensibilité de la souris (degrés par pixel) pour tourner autour de l'abeille.
@export var mouse_sensitivity := 0.15

## Limites d'inclinaison verticale (degrés) de la vue 3ème personne.
@export var pitch_min := -80.0
@export var pitch_max := 60.0

## Inclinaison (degrés) au passage en 3ème personne : légèrement au-dessus de l'abeille.
@export var third_person_start_pitch := -20.0

## Distance (m) minimale et maximale entre la caméra et l'abeille en 3ème personne.
@export var zoom_min := 0.02
@export var zoom_max := 0.5

## Facteur appliqué à la distance à chaque cran de molette.
## Multiplicatif : le zoom paraît aussi rapide de près que de loin.
@export var zoom_step := 1.1

# =============================================================================
# État interne
# =============================================================================

## Indice de l'abeille suivie dans bees_container.
var _bee_index := 0

## Vue actuellement active (indice dans pcams).
var _current_view := 0

## Filtre activé par l'utilisateur (touche V). Il ne s'affiche qu'en vue abeille.
var _bee_vision_enabled := true

## Vue abeille en 3ème personne plutôt qu'en 1ère (touche third_person_key).
## Le mode est conservé : Tab ou la touche chiffrée y ramènent directement.
var _third_person := false

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	_select_view(0)
	# Différé : Cameras est avant Simulation dans l'arbre, son _ready() s'exécute
	# donc avant que Simulation ait créé les abeilles
	_select_bee.call_deferred(0)

# =============================================================================
# Entrées
# =============================================================================

## Raccourcis clavier : 1, 2, 3… changent de vue, Tab / Maj+Tab changent d'abeille suivie,
## C bascule 1ère / 3ème personne, V bascule le filtre, F11 le plein écran.
## Clic droit maintenu en 3ème personne : rotation autour de l'abeille.
## _unhandled_input reçoit les touches que l'interface n'a pas déjà consommées.
func _unhandled_input(event: InputEvent) -> void:
	# Clic droit maintenu en 3ème personne : on tourne autour de l'abeille.
	# Le clic gauche reste réservé à l'épinglage (BeeOverlay).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_orbiting(event.pressed and _is_third_person_active())
		return
	# Molette en 3ème personne : rapprocher / éloigner la caméra
	if event is InputEventMouseButton and event.pressed and _is_third_person_active():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.0 / zoom_step)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_step)
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit(event.relative)
		return

	# echo : ignore la répétition quand la touche reste enfoncée
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# F11 : bascule entre fenêtré et plein écran
	if event.physical_keycode == KEY_F11:
		_toggle_fullscreen()
		return
	if event.physical_keycode == KEY_TAB:
		_cycle_bee(event.shift_pressed)
		return
	if event.physical_keycode == KEY_V:
		_bee_vision_enabled = not _bee_vision_enabled
		_update_bee_vision()
		return
	if event.physical_keycode == third_person_key:
		_toggle_third_person()
		return
	# physical_keycode : position de la touche, indépendante de la disposition (AZERTY)
	var index: int = event.physical_keycode - KEY_1
	# Passage en vue abeille par sa touche : on suit l'abeille épinglée s'il y en a une
	if index >= 0 and index < pcams.size() and pcams[index] == bee_view:
		_follow_pinned_bee()
	_select_view(index)

# =============================================================================
# Vues
# =============================================================================

## Donne la priorité la plus haute à la vue [param index], 0 aux autres.
## En vue abeille, la PCam activée dépend du mode 1ère / 3ème personne.
## [param instant] : pas de transition, la caméra saute directement sur la vue.
func _select_view(index: int, instant := false) -> void:
	if index < 0 or index >= pcams.size():
		return
	var target := pcams[index]
	if target == bee_view and _third_person and bee_view_third_person != null:
		target = bee_view_third_person
	# Le tween utilisé est celui de la PCam d'arrivée : on le règle avant de l'activer
	target.tween_duration = 0.0 if instant else transition_duration
	for pcam in pcams:
		pcam.priority = 0
	if bee_view_third_person != null:
		bee_view_third_person.priority = 0
	target.priority = 10
	_current_view = index
	# Hors de la 3ème personne, la souris ne doit pas rester capturée
	if target != bee_view_third_person:
		_set_orbiting(false)
	# Entrée ou sortie de la vue abeille : filtre et panneau de données suivent
	_update_bee_vision()
	_update_overlay()

# =============================================================================
# Vue abeille : 1ère / 3ème personne
# =============================================================================

## Vrai si la vue active est la vue abeille en 3ème personne.
func _is_third_person_active() -> bool:
	return _third_person and pcams[_current_view] == bee_view


## Bascule 1ère / 3ème personne. Sans effet hors de la vue abeille.
func _toggle_third_person() -> void:
	if bee_view_third_person == null or pcams[_current_view] != bee_view:
		return
	_third_person = not _third_person
	if _third_person:
		# On démarre derrière l'abeille, dans l'axe de son regard. On se fie au
		# CameraAnchor plutôt qu'au corps : il regarde par construction vers l'avant,
		# quel que soit le sens du modèle dans bee.tscn.
		var bee := bees_container.get_child(_bee_index)
		var anchor: Marker3D = bee.get_node("CameraAnchor")
		var forward := -anchor.global_basis.z
		# Une rotation de yaw autour de Y envoie -Z sur (-sin yaw, 0, -cos yaw)
		var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
		bee_view_third_person.set_third_person_rotation_degrees(
			Vector3(third_person_start_pitch, yaw, 0.0))
	# Transition animée : la caméra recule depuis l'œil, ou y revient
	_select_view(_current_view)


## Capture la souris pendant la rotation (curseur masqué, mouvement illimité),
## la libère ensuite pour pouvoir de nouveau survoler et épingler.
func _set_orbiting(enabled: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


## Tourne la vue 3ème personne autour de l'abeille selon le déplacement de la souris.
func _orbit(motion: Vector2) -> void:
	var rot := bee_view_third_person.get_third_person_rotation_degrees()
	rot.y -= motion.x * mouse_sensitivity
	rot.x = clampf(rot.x - motion.y * mouse_sensitivity, pitch_min, pitch_max)
	bee_view_third_person.set_third_person_rotation_degrees(rot)
	
## Multiplie la longueur du bras de la vue 3ème personne par [param factor],
## dans les limites zoom_min / zoom_max.
func _zoom(factor: float) -> void:
	var length := bee_view_third_person.get_spring_length() * factor
	bee_view_third_person.set_spring_length(clampf(length, zoom_min, zoom_max))

# =============================================================================
# Abeille suivie
# =============================================================================

## Accroche [member bee_view] au repère CameraAnchor de l'abeille [param index],
## et fait suivre la même abeille à [member bee_view_third_person].
func _select_bee(index: int) -> void:
	var bees := bees_container.get_children()
	if bees.is_empty():
		return
	_bee_index = wrapi(index, 0, bees.size())
	var anchor: Marker3D = bees[_bee_index].get_node("CameraAnchor")
	# false : on se place dans le repère du marqueur, puis on se cale exactement dessus.
	# Position et orientation de l'œil sont réglées dans bee.tscn, pas ici.
	bee_view.reparent(anchor, false)
	bee_view.transform = Transform3D.IDENTITY
	# La 3ème personne suit la même abeille que la 1ère
	if bee_view_third_person != null:
		bee_view_third_person.follow_target = bees[_bee_index]
	# Changement d'abeille : le panneau de données passe sur la nouvelle
	_update_overlay()


## Accroche [member bee_view] à l'abeille épinglée dans la surcouche, s'il y en a une.
## Sans abeille épinglée, la vue abeille reste sur l'abeille suivie jusque-là.
func _follow_pinned_bee() -> void:
	if bee_overlay == null:
		return
	var bee := bee_overlay.get_pinned_bee()
	if bee == null:
		return
	# _select_bee travaille sur un indice : on retrouve celui de l'abeille épinglée
	var index := bees_container.get_children().find(bee)
	if index != -1:
		_select_bee(index)


## Tab / Maj+Tab. Va d'abord sur l'abeille épinglée si la caméra n'y est pas encore,
## sinon passe à l'abeille suivante (ou précédente si [param backward]).
## L'épingle suit alors l'abeille, sinon le Tab suivant reviendrait sur l'ancienne.
## Le mode 1ère / 3ème personne est conservé.
func _cycle_bee(backward: bool) -> void:
	var pinned: Bee = bee_overlay.get_pinned_bee() if bee_overlay != null else null
	var bees := bees_container.get_children()
	if bees.is_empty():
		return
	var followed: Node = bees[_bee_index] if _bee_index < bees.size() else null
	# Caméra déjà sur l'abeille épinglée : en vue abeille, et c'est elle qui est suivie
	var on_pinned := pcams[_current_view] == bee_view and followed == pinned

	if pinned != null and not on_pinned:
		_follow_pinned_bee()
	else:
		_select_bee(_bee_index + (-1 if backward else 1))
		if pinned != null:
			bee_overlay.set_pinned_bee(bees_container.get_child(_bee_index) as Bee)
	# Saut sec vers l'abeille, même si on venait d'une vue fixe
	_select_view(pcams.find(bee_view), true)

# =============================================================================
# Affichages liés à la vue abeille
# =============================================================================

## Affiche le filtre seulement en vue abeille 1ère personne, et seulement s'il est activé :
## il simule ce que voient les yeux de l'abeille, ce qui n'a pas de sens vu de l'extérieur.
func _update_bee_vision() -> void:
	if bee_vision == null:
		return
	bee_vision.visible = _bee_vision_enabled and pcams[_current_view] == bee_view \
			and not _third_person


## Indique à la surcouche l'abeille suivie, ou null hors de la vue abeille,
## pour qu'elle affiche (ou retire) le panneau de données.
## Vaut pour la 1ère comme pour la 3ème personne.
func _update_overlay() -> void:
	if bee_overlay == null:
		return
	var bees := bees_container.get_children()
	var in_bee_view := pcams[_current_view] == bee_view
	bee_overlay.followed_bee = bees[_bee_index] as Bee \
			if in_bee_view and _bee_index < bees.size() else null

# =============================================================================
# Fenêtre
# =============================================================================

## Passe en plein écran, ou revient en fenêtré si on y est déjà.
func _toggle_fullscreen() -> void:
	# Jeu affiché dans l'onglet Jeu de l'éditeur : seul le mode fenêtré est autorisé
	if Engine.is_embedded_in_editor():
		push_warning("Plein écran indisponible : désactiver « Intégrer le jeu » dans l'onglet Jeu")
		return
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if fullscreen
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	)
