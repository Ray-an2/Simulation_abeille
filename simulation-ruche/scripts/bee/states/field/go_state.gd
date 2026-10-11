class_name GoState extends FieldState
## Vol vers la source connue (known_flower). En approche finale, l'abeille vérifie
## la fleur sans se poser :
##   - vide → elle l'oublie et explore (SCOUT) ;
##   - réservée par une autre abeille → elle explore autour (SCOUT) en gardant la source,
##     et trouvera une voisine libre dans le même massif ;
##   - libre → elle la réserve, se pose et butine (FORAGE).
## La réservation n'est prise qu'en approche finale : prise dès la ruche,
## elle bloquerait la fleur pendant tout le trajet.

# =============================================================================
# État interne
# =============================================================================

## Fleur visée, gardée ici pour pouvoir la libérer dans exit()
## même si known_flower a été remise à null entre-temps.
var _flower: Flower = null

## Point de pose sur la fleur visée (pistil).
var _target: Vector3

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_flower = bee.known_flower
	if is_instance_valid(_flower):
		_target = _flower.get_landing_position()
	begin_flight()   # décollage de la planche à la sortie de LEAVE

func exit() -> void:
	if is_instance_valid(_flower):
		_flower.release(bee)
	_flower = null

func update(delta: float) -> BeeState:
	var flower := bee.known_flower

	# Aucune source connue
	if not is_instance_valid(flower):
		return bee.scout

	if update_takeoff(_target, delta):
		return null

	if is_on_final_approach():
		# Fleur vide constatée de près : on l'oublie et on explore, toujours en vol
		if flower.is_empty():
			bee.known_flower = null
			bee.known_profitability = 0.0
			return bee.scout
		# Fleur réservée par une autre abeille : on cherche une voisine libre.
		# La source reste connue : SCOUT la remplacera si l'abeille se pose ailleurs.
		if not flower.try_claim(bee):
			return bee.scout

	# Approche, arrêt bref puis pose sur le pistil
	if update_landing(_target, flower.get_landing_normal(), HOVER_TIME_FLOWER, delta):
		return bee.forage
	return null
