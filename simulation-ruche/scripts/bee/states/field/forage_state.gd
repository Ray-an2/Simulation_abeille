class_name ForageState extends FieldState
## Butinage : l'abeille est posée sur la fleur et enchaîne les prélèvements
## jusqu'à remplir son jabot (→ RETURN), ou jusqu'à ce que la fleur se vide (→ RETURN).
## La fleur reste réservée pendant tout l'état : les autres abeilles l'évitent.

# =============================================================================
# État interne
# =============================================================================

## Fleur butinée, reprise de bee.known_flower à l'entrée.
## Gardée ici pour pouvoir la libérer dans exit() quoi qu'il arrive.
var _flower: Flower = null

## true pendant un prélèvement (entre request_foraging() et foraging_finished).
var _foraging: bool = false

## Passe à true à la réception de foraging_finished : le prélèvement est
## comptabilisé à l'image suivante, dans update().
var _harvest_done: bool = false

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	bee.land()   # posée : le départ vers la ruche repartira d'un décollage
	bee.play_animation(&"_bee_idle")
	_flower = bee.known_flower
	# Reprend la réservation libérée par SCOUT ou GO dans leur exit().
	# Les deux s'enchaînent dans le même change_state() : aucune autre abeille
	# ne peut prendre la fleur entre-temps.
	if is_instance_valid(_flower):
		_flower.try_claim(bee)
	_foraging = false
	_harvest_done = false

func exit() -> void:
	if is_instance_valid(_flower):
		if _flower.foraging_finished.is_connected(_on_foraging_finished):
			_flower.foraging_finished.disconnect(_on_foraging_finished)
		# La fleur redevient visible pour les autres abeilles
		_flower.release(bee)
	_flower = null
	
## Un prélèvement en cours verrouille la fleur (BUSY) : on le laisse finir.
## _harvest_done aussi, sinon le nectar du dernier prélèvement serait perdu :
## interrupt() passe avant update(), qui est l'endroit où il est ajouté au jabot.
## Entre deux prélèvements, la règle du super-état s'applique (nuit → RETURN).
func interrupt() -> BeeState:
	if _foraging or _harvest_done:
		return null
	return super()

func update(_delta: float) -> BeeState:
	# Fleur disparue : retour à la ruche
	if not is_instance_valid(_flower):
		return bee.return_home

	# Prélèvement terminé : on remplit le jabot
	if _harvest_done:
		_harvest_done = false
		# Couleur de la fleur visitée, puis croissance de la pelote
		bee.set_pollen_from(_flower)
		var capacity := bee.simulation.forage_capacity
		bee.nectar += minf(bee.simulation.harvest_amount, capacity - bee.nectar)
		bee.update_pollen()
		# Jabot plein : retour à la ruche. La fleur garde du stock
		# pour les autres butineuses et pour un prochain trajet.
		if bee.nectar >= capacity:
			return bee.return_home

	# Fleur passée sous le seuil : retour avec ce qui a été récolté
	if _flower.is_empty():
		return bee.return_home

	# Prélèvement en cours : on attend foraging_finished
	if _foraging:
		return null

	# Nouveau prélèvement. Grâce à la réservation, request_foraging() ne devrait
	# plus échouer ; en cas de refus, l'abeille reste en vol stationnaire et
	# retente à l'image suivante.
	if _flower.request_foraging():
		_foraging = true
		bee.play_animation(&"_bee_forage")
		_flower.foraging_finished.connect(_on_foraging_finished, CONNECT_ONE_SHOT)
	else:
		bee.play_animation(&"_bee_hover")
	return null

# =============================================================================
# Signaux
# =============================================================================

## Fin d'un prélèvement, émise par la fleur. Le nectar est ajouté dans update().
func _on_foraging_finished(_source: Flower) -> void:
	_foraging = false
	_harvest_done = true
