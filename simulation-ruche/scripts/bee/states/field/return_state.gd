class_name ReturnState extends FieldState
## Retour vers la ruche : décollage si l'abeille est posée (sortie de FORAGE),
## vol jusqu'à un point de la planche d'envol, stationnaire, pose,
## puis entrée à pied (ENTER).
##
## LANDING_RADIUS n'existe plus : son rôle (arriver exactement sur la planche,
## pour que ENTER commence posée et non en l'air) est assuré par l'étape TOUCHDOWN
## de FieldState, qui finit avec hop_towards() et EXACT_RADIUS (0,001 m).

## Point d'atterrissage tiré au hasard sur la planche, propre à chaque retour.
var _landing_spot := Vector3.ZERO

func enter() -> void:
	_landing_spot = bee.hive.get_random_landing_position()
	begin_flight()

func update(delta: float) -> BeeState:
	if update_takeoff(delta):
		return null
	# Planche d'envol supposée horizontale : normale = verticale du monde.
	# Si elle est inclinée, utiliser l'axe Y de LandingMarker (getter à ajouter dans Hive).
	if update_landing(_landing_spot, Vector3.UP, HOVER_TIME_BOARD, delta):
		return bee.enter_hive
	return null
