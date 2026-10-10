class_name ReturnState extends FieldState
## Retour vers la ruche : vol jusqu'à un point de la planche d'envol, puis entrée à pied (ENTER).

## Distance (m) d'arrivée sur la planche. Très petite : move_toward garantit que l'abeille
## atteint exactement sa cible, et ENTER doit commencer posée, pas en l'air.
## (arrival_radius de Simulation, 5 cm, est pensé pour le vol vers les fleurs.)
const LANDING_RADIUS := 0.001

## Point d'atterrissage tiré au hasard sur la planche, propre à chaque retour.
var _landing_spot := Vector3.ZERO

func enter() -> void:
	_landing_spot = bee.hive.get_random_landing_position()

func update(delta: float) -> BeeState:
	bee.fly_towards(_landing_spot, delta)
	if bee.is_near(_landing_spot, LANDING_RADIUS):
		bee.play_animation(&"_bee_landing")
		return bee.enter_hive
	return null
