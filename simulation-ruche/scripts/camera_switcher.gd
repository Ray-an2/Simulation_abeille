class_name CameraSwitcher extends Node3D
## Gère les vues de la simulation et l'abeille suivie.
##
## 1, 2, 3… : changer de vue (dans l'ordre de pcams).
## Tab / Maj+Tab : aller sur l'abeille épinglée, sinon l'abeille suivante / précédente,
## et passer en vue abeille.
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

# =============================================================================
# État interne
# =============================================================================

## Indice de l'abeille suivie dans bees_container.
var _bee_index := 0

## Vue actuellement active (indice dans pcams).
var _current_view := 0

## Filtre activé par l'utilisateur (touche V). Il ne s'affiche qu'en vue abeille.
var _bee_vision_enabled := true

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
## V bascule le filtre, F11 le plein écran.
## _unhandled_input reçoit les touches que l'interface n'a pas déjà consommées.
func _unhandled_input(event: InputEvent) -> void:
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
## [param instant] : pas de transition, la caméra saute directement sur la vue.
func _select_view(index: int, instant := false) -> void:
	if index < 0 or index >= pcams.size():
		return
	# Le tween utilisé est celui de la PCam d'arrivée : on le règle avant de l'activer
	pcams[index].tween_duration = 0.0 if instant else transition_duration
	for i in pcams.size():
		pcams[i].priority = 10 if i == index else 0
	_current_view = index
	# Entrée ou sortie de la vue abeille : filtre et panneau de données suivent
	_update_bee_vision()
	_update_overlay()

# =============================================================================
# Abeille suivie
# =============================================================================

## Accroche [member bee_view] au repère CameraAnchor de l'abeille [param index].
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

## Affiche le filtre seulement en vue abeille, et seulement s'il est activé.
func _update_bee_vision() -> void:
	if bee_vision == null:
		return
	bee_vision.visible = _bee_vision_enabled and pcams[_current_view] == bee_view


## Indique à la surcouche l'abeille suivie, ou null hors de la vue abeille,
## pour qu'elle affiche (ou retire) le panneau de données.
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
