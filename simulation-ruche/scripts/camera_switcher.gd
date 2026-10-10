class_name CameraSwitcher extends Node3D
## Change de vue avec les touches 1, 2, 3…, et d'abeille suivie avec Tab / Maj+Tab.

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

## Indice de l'abeille suivie dans bees_container.
var _bee_index := 0

## Vue actuellement active (indice dans pcams).
var _current_view := 0

## Filtre activé par l'utilisateur (touche V). Il ne s'affiche qu'en vue abeille.
var _bee_vision_enabled := true

func _ready() -> void:
	_select_view(0)
	# Différé : Cameras est avant Simulation dans l'arbre, son _ready() s'exécute
	# donc avant que Simulation ait créé les abeilles
	_select_bee.call_deferred(0)

## Raccourcis clavier : 1, 2, 3… changent de vue, Tab / Maj+Tab changent d'abeille suivie,
## F11 bascule en plein écran. _unhandled_input reçoit les touches que l'interface n'a pas déjà consommées.
func _unhandled_input(event: InputEvent) -> void:
	# echo : ignore la répétition quand la touche reste enfoncée
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# F11 : bascule entre fenêtré et plein écran
	if event.physical_keycode == KEY_F11:
		_toggle_fullscreen()
		return
	if event.physical_keycode == KEY_TAB:
		_select_bee(_bee_index + (-1 if event.shift_pressed else 1))
		# Saut sec vers l'abeille, même si on venait d'une vue fixe
		_select_view(pcams.find(bee_view), true)
		return
	
	if event.physical_keycode == KEY_V:
		_bee_vision_enabled = not _bee_vision_enabled
		_update_bee_vision()
		return
	# physical_keycode : position de la touche, indépendante de la disposition (AZERTY)
	_select_view(event.physical_keycode - KEY_1)

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
	_update_bee_vision()

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

## Affiche le filtre seulement en vue abeille, et seulement s'il est activé.
func _update_bee_vision() -> void:
	if bee_vision == null:
		return
	bee_vision.visible = _bee_vision_enabled and pcams[_current_view] == bee_view
	
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
