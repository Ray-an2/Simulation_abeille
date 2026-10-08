class_name CameraSwitcher extends Node3D
## Change de vue avec les touches 1, 2, 3…, et d'abeille suivie avec Tab / Maj+Tab.

## Vues disponibles, dans l'ordre des touches. La première est la vue de départ.
@export var pcams: Array[PhantomCamera3D]

@export_group("Vue abeille")

## PCam placé sur l'abeille suivie. Doit aussi figurer dans pcams
## pour être sélectionnable avec les touches chiffrées.
@export var bee_view: PhantomCamera3D

## Conteneur des abeilles créées par Simulation (Simulation/Bees).
@export var bees_container: Node3D

## Indice de l'abeille suivie dans bees_container.
var _bee_index := 0

func _ready() -> void:
	_select_view(0)
	# Différé : Cameras est avant Simulation dans l'arbre, son _ready() s'exécute
	# donc avant que Simulation ait créé les abeilles
	_select_bee.call_deferred(0)

func _unhandled_input(event: InputEvent) -> void:
	# echo : ignore la répétition quand la touche reste enfoncée
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_TAB:
		# Maj+Tab : abeille précédente
		_select_bee(_bee_index + (-1 if event.shift_pressed else 1))
		# Changer d'abeille bascule aussi sur la vue abeille
		_select_view(pcams.find(bee_view))
		return
	# physical_keycode : position de la touche, indépendante de la disposition (AZERTY)
	_select_view(event.physical_keycode - KEY_1)

## Donne la priorité la plus haute à la vue [param index], 0 aux autres.
func _select_view(index: int) -> void:
	if index < 0 or index >= pcams.size():
		return
	for i in pcams.size():
		pcams[i].priority = 10 if i == index else 0

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
