class_name CameraSwitcher extends Node3D
## Change de vue avec les touches 1, 2, 3… en donnant la priorité au PCam choisi.

## Vues disponibles, dans l'ordre des touches. La première est la vue de départ.
@export var pcams: Array[PhantomCamera3D]

func _ready() -> void:
	_select_view(0)

func _unhandled_input(event: InputEvent) -> void:
	# echo : ignore la répétition quand la touche reste enfoncée
	if event is InputEventKey and event.pressed and not event.echo:
		# physical_keycode : position de la touche, indépendante de la disposition.
		# En AZERTY, la touche « 1 » sans Maj produit « & », keycode ne marcherait pas.
		_select_view(event.physical_keycode - KEY_1)

## Donne la priorité la plus haute à la vue [param index], 0 aux autres.
func _select_view(index: int) -> void:
	if index < 0 or index >= pcams.size():
		return
	for i in pcams.size():
		pcams[i].priority = 10 if i == index else 0
