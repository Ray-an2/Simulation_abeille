class_name FieldState extends BeeState
## Super-état « Dehors ».
##
## Ajoute aux états de vol (GO, SCOUT, RETURN) ce que Bee.fly_towards() ne fait pas :
##   - au départ d'une surface, une montée verticale avant d'accélérer ;
##   - à l'arrivée, un stationnaire au-dessus de la surface puis une descente lente.
## L'approche elle-même reste confiée à fly_towards() (freinage, évitement, sol).
##
## Utilisation dans un état concret :
##   - enter() appelle begin_flight() ;
##   - update() commence par : if update_takeoff(delta): return null
##   - pour se poser, appeler update_landing() à chaque image jusqu'à ce qu'elle renvoie true.

# =============================================================================
# Constantes
# =============================================================================

## Hauteur (m) de la montée verticale au décollage, avant l'accélération vers l'avant.
const TAKEOFF_HEIGHT := 0.03

## Vitesse (m/s) de la montée verticale.
const TAKEOFF_SPEED := 0.15

## Distance (m) entre la surface et le point de stationnaire.
const HOVER_HEIGHT := 0.02

## Distance (m) au point de stationnaire à laquelle fly_towards() passe la main.
## Pas plus petite : près du sol, _flight_goal() peut relever le point visé
## (ground_clearance) et fly_towards() ne l'atteindrait jamais exactement.
const HOVER_HANDOVER_RADIUS := 0.05

## Vitesse (m/s) pour rejoindre exactement le point de stationnaire.
const HOVER_SPEED := 0.1

## Vitesse (m/s) de la descente finale jusqu'au contact.
const TOUCHDOWN_SPEED := 0.05

## Durée (s) du stationnaire : bref sur la planche, grande surface familière ;
## plus long devant une fleur, petite et souvent inclinée.
const HOVER_TIME_BOARD := 0.3
const HOVER_TIME_FLOWER := 1.0

## Distance (m) d'arrivée des phases lentes. Très petite : hop_towards() utilise
## move_toward, qui atteint exactement sa cible (même raison que l'ancien LANDING_RADIUS).
const EXACT_RADIUS := 0.001

# =============================================================================
# Types
# =============================================================================

## Étapes de l'arrivée sur une surface.
enum Landing {
	APPROACH,   ## Vol normal (fly_towards) jusqu'aux abords du point de stationnaire
	HOVER,      ## Rejoint le point de stationnaire, s'aligne sur la surface et attend
	TOUCHDOWN,  ## Descente lente le long de la normale jusqu'au contact
	DONE,       ## Posée
}

# =============================================================================
# État interne
# =============================================================================

## true pendant la montée verticale du décollage.
var _taking_off := false

## Point visé par la montée verticale.
var _takeoff_point := Vector3.ZERO

## Étape d'arrivée en cours.
var _landing := Landing.APPROACH

## Temps de stationnaire restant (s), décompté une fois le point de stationnaire atteint.
var _hover_left := 0.0

## true quand l'abeille est arrivée sur le point de stationnaire.
var _hover_reached := false

# =============================================================================
# Décollage
# =============================================================================

## À appeler dans enter(). Démarre une montée verticale si l'abeille est posée
## (planche à la sortie de LEAVE, fleur à la sortie de FORAGE). Si elle vole déjà
## (SCOUT → RETURN, GO → SCOUT), le vol continue directement.
func begin_flight() -> void:
	reset_landing()
	_taking_off = bee.is_landed()
	if _taking_off:
		_takeoff_point = bee.global_position + Vector3.UP * TAKEOFF_HEIGHT
		bee.play_animation(&"_bee_hover")

## Fait progresser la montée verticale. Renvoie true tant qu'elle n'est pas terminée :
## l'état concret ne doit alors rien faire d'autre pendant cette image.
## Ensuite, fly_towards() accélère depuis l'arrêt, car land() a remis la vitesse à zéro.
func update_takeoff(delta: float) -> bool:
	if not _taking_off:
		return false
	# Montée sur place : l'abeille garde son cap, ramené à l'horizontale
	bee.hop_towards(_takeoff_point, TAKEOFF_SPEED, _forward_on(Vector3.UP), Vector3.UP, delta)
	if bee.is_near(_takeoff_point, EXACT_RADIUS):
		_taking_off = false
	return _taking_off

# =============================================================================
# Atterrissage
# =============================================================================

## Repart de l'étape APPROACH. À appeler si la cible change en cours d'approche
## (SCOUT : la fleur visée s'est vidée et une autre est choisie).
func reset_landing() -> void:
	_landing = Landing.APPROACH
	_hover_reached = false

## true dès que l'abeille a quitté le vol normal pour le stationnaire.
## Permet à GO de renoncer à une fleur vide sans s'y poser.
func is_hovering() -> bool:
	return _landing != Landing.APPROACH

## Approche, stationnaire puis pose sur [param target], point d'une surface
## de normale [param normal] (unitaire). Renvoie true une fois posée.
## [param max_speed] est transmis à fly_towards() : 0 = fly_speed.
func update_landing(target: Vector3, normal: Vector3, hover_time: float,
		delta: float, max_speed := 0.0) -> bool:
	var hover_point := target + normal * HOVER_HEIGHT

	match _landing:
		Landing.APPROACH:
			# Freinage, évitement et hauteur de vol gérés par fly_towards()
			bee.fly_towards(hover_point, delta, true, max_speed)
			if bee.is_near(hover_point, HOVER_HANDOVER_RADIUS):
				_landing = Landing.HOVER
				_hover_left = hover_time
				_hover_reached = false

		Landing.HOVER:
			# Rejoint le point de stationnaire en pivotant : le haut de l'abeille
			# passe de la verticale à la normale de la surface, le cap est conservé
			bee.hop_towards(hover_point, HOVER_SPEED, _forward_on(normal), normal, delta)
			if not _hover_reached and bee.is_near(hover_point, EXACT_RADIUS):
				_hover_reached = true
			# Le temps de stationnaire ne compte qu'une fois sur place
			if _hover_reached:
				_hover_left -= delta
				if _hover_left <= 0.0:
					_landing = Landing.TOUCHDOWN
					bee.play_animation(&"_bee_landing")

		Landing.TOUCHDOWN:
			# Descente lente le long de la normale jusqu'au contact exact
			bee.hop_towards(target, TOUCHDOWN_SPEED, _forward_on(normal), normal, delta)
			if bee.is_near(target, EXACT_RADIUS):
				_landing = Landing.DONE

	return _landing == Landing.DONE

# =============================================================================
# Utilitaires internes
# =============================================================================

## Avant de l'abeille (+Z, convention du modèle glTF) projeté dans le plan
## perpendiculaire à [param normal]. Sert de direction de regard pendant
## les phases lentes : l'abeille ne tourne que pour s'aligner sur la surface.
func _forward_on(normal: Vector3) -> Vector3:
	var forward := bee.global_basis.z.slide(normal)
	# Abeille pointée le long de la normale : on prend son haut projeté comme cap
	if forward.is_zero_approx():
		forward = bee.global_basis.y.slide(normal)
	return forward
