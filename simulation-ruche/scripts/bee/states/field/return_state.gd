class_name ReturnState extends FieldState
## Retour vers la ruche : vol jusqu'à la planche d'envol, puis entrée à pied (ENTER).

## Distance (m) d'arrivée sur la planche. Très petite : move_toward garantit que l'abeille
## atteint exactement sa cible, et ENTER doit commencer posée, pas en l'air.
## (arrival_radius de Simulation, 5 cm, est pensé pour le vol vers les fleurs.)
const LANDING_RADIUS := 0.001

func update(delta: float) -> BeeState:
	var landing := bee.hive.get_landing_position()
	bee.fly_towards(landing, delta)
	if bee.is_near(landing, LANDING_RADIUS):
		return bee.enter_hive
	return null
