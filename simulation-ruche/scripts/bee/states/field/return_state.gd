class_name ReturnState extends FieldState
## Retour vers la ruche : décollage si l'abeille est posée (sortie de FORAGE),
## vol jusqu'à un point de la planche d'envol, approche finale face à l'entrée, pose,
## puis entrée à pied (ENTER).
##
## LANDING_RADIUS n'existe plus : son rôle (arriver exactement sur la planche,
## pour que ENTER commence posée et non en l'air) est assuré par l'étape TOUCHDOWN
## de FieldState, qui finit avec hop_towards() et EXACT_RADIUS (0,001 m).

## Point d'atterrissage tiré au hasard sur la planche, propre à chaque retour.
var _landing_spot := Vector3.ZERO

## Direction d'arrivée : vers l'entrée, à plat. Calculée une fois par retour.
var _approach_dir := Vector3.ZERO

func enter() -> void:
	_landing_spot = bee.hive.get_random_landing_position()
	# L'axe du tunnel pointe de l'intérieur vers la planche : on arrive en sens inverse,
	# face à l'entrée. get_tunnel_axis() est déjà horizontal et unitaire.
	_approach_dir = -bee.hive.get_tunnel_axis()
	begin_flight()

func update(delta: float) -> BeeState:
	if update_takeoff(_landing_spot, delta):
		return null
	# Planche d'envol supposée horizontale : normale = verticale du monde.
	# Si elle est inclinée, utiliser l'axe Y de LandingMarker (getter à ajouter dans Hive).
	if update_landing(_landing_spot, Vector3.UP, HOVER_TIME_BOARD, delta, 0.0, _approach_dir):
		return bee.enter_hive
	return null
