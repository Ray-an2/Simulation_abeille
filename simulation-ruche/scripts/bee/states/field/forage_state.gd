class_name ForageState extends FieldState
## Butinage d'un massif : l'abeille fait harvests_per_flower prélèvement(s) sur une fleur,
## puis vole vers une autre fleur libre de la même espèce, à moins de patch_radius,
## jusqu'à remplir son jabot (→ RETURN).
## S'il ne reste aucune fleur libre de cette espèce à portée, elle rentre avec
## ce qu'elle a récolté (→ RETURN).
##
## Constance florale : une butineuse reste sur une seule espèce pendant un trajet.
## Elle ne revient pas sur une fleur déjà visitée au cours du même trajet
## (équivalent réel : la marque odorante laissée sur la fleur).
## Seule la fleur en cours est réservée : elle est libérée au départ vers la suivante.
##
## known_flower n'est pas modifiée : elle reste la fleur d'arrivée dans le massif,
## celle que l'abeille dansera et vers laquelle GO la renverra.

# =============================================================================
# Types
# =============================================================================

## Étapes du butinage.
enum Phase {
	HARVEST,   ## Posée sur une fleur : prélèvements
	HOP,       ## Vol court vers la fleur suivante du massif
}

# =============================================================================
# État interne
# =============================================================================

## Étape en cours.
var _phase := Phase.HARVEST

## Fleur en cours (butinée, ou visée pendant HOP), réservée par l'abeille.
## Gardée ici pour pouvoir la libérer dans exit() quoi qu'il arrive.
var _flower: Flower = null

## Espèce butinée pendant ce trajet, fixée à l'entrée (constance florale).
var _species: Flower.Species

## Fleurs déjà visitées pendant ce trajet : elles ne sont pas revisitées.
var _visited: Array[Flower] = []

## Nombre de prélèvements faits sur la fleur en cours.
var _harvests_here := 0

## Point de pose sur la fleur visée pendant HOP (pistil).
var _target: Vector3

## true pendant un prélèvement (entre request_foraging() et foraging_finished).
var _foraging: bool = false

## Passe à true à la réception de foraging_finished : le prélèvement est
## comptabilisé à l'image suivante, dans update().
var _harvest_done: bool = false

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_visited.clear()
	_flower = bee.known_flower
	if is_instance_valid(_flower):
		_species = _flower.species
		# Reprend la réservation libérée par SCOUT ou GO dans leur exit().
		# Les deux s'enchaînent dans le même change_state() : aucune autre abeille
		# ne peut prendre la fleur entre-temps.
		_flower.try_claim(bee)
	_start_harvest()

func exit() -> void:
	if is_instance_valid(_flower):
		if _flower.foraging_finished.is_connected(_on_foraging_finished):
			_flower.foraging_finished.disconnect(_on_foraging_finished)
		# La fleur redevient visible pour les autres abeilles
		_flower.release(bee)
	_flower = null
	_visited.clear()

## Un prélèvement en cours verrouille la fleur (BUSY) : on le laisse finir.
## _harvest_done aussi, sinon le nectar du dernier prélèvement serait perdu :
## interrupt() passe avant update(), qui est l'endroit où il est ajouté au jabot.
## Entre deux prélèvements et pendant HOP, la règle du super-état s'applique
## (nuit → RETURN).
func interrupt() -> BeeState:
	if _foraging or _harvest_done:
		return null
	return super()

func update(delta: float) -> BeeState:
	if _phase == Phase.HOP:
		return _update_hop(delta)

	# Fleur disparue : retour à la ruche
	if not is_instance_valid(_flower):
		return bee.return_home

	# Prélèvement terminé : on remplit le jabot
	if _harvest_done:
		_harvest_done = false
		_harvests_here += 1
		# Couleur de la fleur visitée, puis croissance de la pelote
		bee.set_pollen_from(_flower)
		var capacity := bee.simulation.forage_capacity
		bee.nectar += minf(bee.simulation.harvest_amount, capacity - bee.nectar)
		bee.update_pollen()
		# Jabot plein : retour à la ruche
		if bee.nectar >= capacity:
			return bee.return_home
		# Assez prélevé sur cette fleur : on passe à la suivante du massif
		if _harvests_here >= bee.simulation.harvests_per_flower:
			return _hop_to_next_flower()

	# Fleur passée sous le seuil : on passe à la suivante du massif
	if _flower.is_empty():
		return _hop_to_next_flower()

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
# Passage d'une fleur à l'autre
# =============================================================================

## Pose sur une fleur (arrivée de GO, SCOUT ou HOP) : remise à zéro des prélèvements.
func _start_harvest() -> void:
	bee.land()
	bee.play_animation(&"_bee_idle")
	_phase = Phase.HARVEST
	_foraging = false
	_harvest_done = false
	_harvests_here = 0
	if is_instance_valid(_flower):
		_visited.append(_flower)

## Choisit la fleur suivante et décolle vers elle.
## Aucune fleur libre à portée : retour à la ruche avec la récolte en cours.
func _hop_to_next_flower() -> BeeState:
	if not _pick_next_flower():
		return bee.return_home
	_phase = Phase.HOP
	begin_flight()   # décollage de la fleur quittée
	return null

## Vol vers la fleur visée, puis pose et reprise des prélèvements.
func _update_hop(delta: float) -> BeeState:
	# Fleur visée vidée ou disparue en route : on en choisit une autre
	if not is_instance_valid(_flower) or _flower.is_empty():
		if not _pick_next_flower():
			return bee.return_home
		reset_landing()

	if update_takeoff(_target, delta):
		return null

	# Approche lente, arrêt bref puis pose sur le pistil, comme en GO
	if update_landing(_target, _flower.get_landing_normal(), HOVER_TIME_FLOWER,
			delta, bee.simulation.flower_hop_speed, Vector3.ZERO, bee.get_head_offset()):
		_start_harvest()
	return null

## Libère la fleur en cours, puis réserve la fleur libre de la même espèce la plus
## proche, non visitée pendant ce trajet, à moins de patch_radius de l'abeille.
## Renvoie false (et _flower = null) s'il n'y en a aucune.
func _pick_next_flower() -> bool:
	if is_instance_valid(_flower):
		_flower.release(bee)
	_flower = null

	# Comparaison des carrés : évite une racine carrée par fleur
	var best_d2 := bee.simulation.patch_radius ** 2
	for f in bee.simulation.flowers:
		if f.species != _species or _visited.has(f) or not f.is_free_for(bee):
			continue
		var d2 := bee.global_position.distance_squared_to(f.get_landing_position())
		if d2 < best_d2:
			_flower = f
			best_d2 = d2

	if _flower == null:
		return false
	# Réussit toujours : is_free_for() vient d'être vérifié
	_flower.try_claim(bee)
	_target = _flower.get_landing_position()
	return true

# =============================================================================
# Signaux
# =============================================================================

## Fin d'un prélèvement, émise par la fleur. Le nectar est ajouté dans update().
func _on_foraging_finished(_source: Flower) -> void:
	_foraging = false
	_harvest_done = true
