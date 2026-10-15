class_name StatsCollector extends Node
## Observateur de la simulation : relève à intervalle régulier l'état global
## (fleurs, abeilles, réserves de la ruche) pour le panneau de statistiques (F1).
##
## Ce n'est pas un agent : il voit tout, mais aucune abeille ne lit ses données.
## Les abeilles restent non omniscientes ; seul l'observateur humain a la vue d'ensemble.
##
## Il calcule aussi, une fois au lancement, une prévision par espèce avec les
## mêmes formules que les abeilles (Bee.trip_efficiency) : c'est la référence
## à laquelle comparer la composition réelle des réserves.
##
## Créé par StatsPanel : rien à ajouter dans la scène.

# =============================================================================
# Paramètres
# =============================================================================

## Intervalle (heures simulées) entre deux relevés des courbes.
## 0,25 h = 15 s réelles avec une journée de 24 min.
@export var sample_interval_hours := 0.25

## Nombre maximal de relevés conservés (les plus anciens sont supprimés).
## 400 relevés de 0,25 h couvrent plus de quatre jours simulés.
@export var max_samples := 400

## Fenêtre (heures simulées) de la composition « récente » des réserves.
## Écarte le démarrage, où la composition dépend surtout de l'ordre dans lequel
## les éclaireuses ont découvert les sources.
@export var window_hours := 1.0

# =============================================================================
# État
# =============================================================================

## Simulation observée, injectée par StatsPanel.
var simulation: Simulation

## Espèces présentes dans la scène, dans l'ordre de l'enum Flower.Species.
var species_list: Array[int] = []

## Prévision par espèce (Flower.Species → Dictionary), voir _compute_predictions().
var predictions: Dictionary = {}

## Relevés successifs, du plus ancien au plus récent. Chaque relevé contient :
## hour (heures simulées depuis le lancement), foragers (espèce → abeilles qui
## connaissent une fleur de cette espèce), sugar (espèce → sucre stocké, mg),
## outside (abeilles dehors), dances (danses frétillantes), receivers (receveuses).
var samples: Array[Dictionary] = []

## Heure simulée du prochain relevé.
var _next_sample_hour := 0.0

## true une fois les fleurs et les abeilles en place et la prévision calculée.
var _initialized := false

# =============================================================================
# Cycle de vie
# =============================================================================

func _process(_delta: float) -> void:
	if simulation == null:
		return
	if not _initialized:
		_try_initialize()
		return
	if simulation.sim_hours >= _next_sample_hour:
		_take_sample()
		_next_sample_hour = simulation.sim_hours + sample_interval_hours


## true quand les données sont disponibles (lu par StatsPanel).
func is_ready() -> bool:
	return _initialized


## Attend que Simulation ait collecté les fleurs et créé les abeilles :
## elle le fait dans son _ready(), éventuellement après un await sur la ruche.
func _try_initialize() -> void:
	if simulation.flowers.is_empty() or simulation.bees_container.get_child_count() == 0:
		return
	for flower in simulation.flowers:
		if not species_list.has(flower.species):
			species_list.append(flower.species)
	species_list.sort()
	_compute_predictions()
	_initialized = true
	_take_sample()
	_next_sample_hour = simulation.sim_hours + sample_interval_hours

# =============================================================================
# Prévision
# =============================================================================

## Pour chaque espèce, ce que les abeilles devraient en penser, calculé avec
## leurs propres formules sur un trajet « idéal » :
##   - distance : moyenne des distances à plat ruche → fleurs de l'espèce ;
##   - jabot plein (forage_capacity), rempli sur des fleurs pleines, une visite
##     par fleur (harvest_amount par prélèvement) ;
##   - durée de prélèvement moyenne, allongée par la viscosité du nectar ;
##   - vols entre fleurs ignorés (même biais pour toutes les espèces).
## C'est une borne optimiste sans concurrence ni épuisement : elle classe
## l'attrait de chaque source pour une abeille seule.
##
## Le débit maximal de sécrétion du massif dit au contraire combien de sucre
## l'espèce peut fournir à la colonie : stock vide, la sécrétion vaut
## max_resource / tau par fleur et par heure simulée (modèle de Flower._secrete).
## Une source attrayante mais à faible débit doit saturer vite (boucle d'épuisement).
func _compute_predictions() -> void:
	var sim := simulation
	var hive_pos := sim.hive.global_position
	# trip_efficiency ne dépend que des paramètres de la simulation :
	# n'importe quelle abeille peut faire le calcul, on prend la première
	var any_bee := sim.bees_container.get_child(0) as Bee

	for sp in species_list:
		var count := 0
		var distance_sum := 0.0
		var reference: Flower = null
		for flower in sim.flowers:
			if flower.species != sp:
				continue
			count += 1
			distance_sum += sim.get_flat_distance(hive_pos, flower.global_position)
			reference = flower
		var distance := distance_sum / maxi(count, 1)

		# Trajet idéal : jabot plein, prélèvements de durée moyenne
		var c := reference.sugar_concentration
		var capacity: float = sim.forage_capacity
		var harvests := ceili(capacity / maxf(sim.harvest_amount, 0.001))
		var harvest_time: float = 0.5 * (sim.foraging_time_min + sim.foraging_time_max) \
				* reference.get_viscosity_factor()
		var sugar := Flower.sugar_in(capacity, c)
		var load := Flower.nectar_mass(capacity, c)
		var efficiency: float = 0.0
		if any_bee != null:
			efficiency = any_bee.trip_efficiency(sugar, load, distance, harvests * harvest_time)

		# Débit maximal du massif (µL par heure simulée), converti en sucre
		var max_volume_rate: float = count * sim.max_resource / maxf(reference.secretion_tau, 0.001)

		predictions[sp] = {
			"flowers": count,
			"distance": distance,
			"concentration": c,
			"tau": reference.secretion_tau,
			"efficiency": efficiency,
			"profitability": _to_profitability(efficiency),
			"max_sugar_rate": Flower.sugar_in(max_volume_rate, c),
		}

	# Rang prévu : 1 = source la plus rentable par trajet
	var ranked: Array[int] = species_list.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return predictions[a]["profitability"] > predictions[b]["profitability"])
	for i in ranked.size():
		predictions[ranked[i]]["rank"] = i + 1


## Même conversion que UnloadState._efficiency_to_profitability (échelle logarithmique,
## 1 à efficiency_max). Dupliquée car la méthode de l'état est privée :
## à garder identique si l'une des deux change.
func _to_profitability(efficiency: float) -> float:
	if efficiency <= 0.0:
		return 0.0
	var e_max := maxf(simulation.efficiency_max, 0.001)
	return clampf(log(1.0 + efficiency) / log(1.0 + e_max), 0.0, 1.0)

# =============================================================================
# Relevés (courbes)
# =============================================================================

## Ajoute un relevé à l'historique. 200 abeilles parcourues toutes les 15 s réelles :
## coût négligeable, inutile de passer par les signaux des états.
func _take_sample() -> void:
	var hive := simulation.hive
	var foragers := {}
	var outside := 0
	for node in simulation.bees_container.get_children():
		var bee := node as Bee
		if bee == null or bee.current_state == null:
			continue
		if bee.current_state is FieldState:
			outside += 1
		if is_instance_valid(bee.known_flower):
			var sp: int = bee.known_flower.species
			foragers[sp] = foragers.get(sp, 0) + 1

	samples.append({
		"hour": simulation.sim_hours,
		"foragers": foragers,
		# Copie : le dictionnaire de la ruche continue d'évoluer
		"sugar": hive.sugar_by_species.duplicate(),
		"outside": outside,
		"dances": hive.get_dance_count(),
		"receivers": hive.get_receiver_count(),
	})
	if samples.size() > max_samples:
		samples.pop_front()

# =============================================================================
# Lecture instantanée (appelé par StatsPanel à chaque rafraîchissement)
# =============================================================================

## État actuel des fleurs et des abeilles, regroupé pour l'affichage :
##   flowers : espèce → {count, available, busy, empty, resource (somme des stocks)} ;
##   states : nom de classe de l'état → nombre d'abeilles ;
##   foragers : espèce → abeilles qui connaissent une fleur de cette espèce ;
##   recruits : espèce → recrues qui suivent un vecteur de danse sans avoir trouvé la fleur ;
##   dances : espèce → danses frétillantes en cours ;
##   total, outside, with_source : compteurs globaux.
func live() -> Dictionary:
	var flowers := {}
	for flower in simulation.flowers:
		var sp: int = flower.species
		if not flowers.has(sp):
			flowers[sp] = {"count": 0, "available": 0, "busy": 0, "empty": 0, "resource": 0.0}
		var entry: Dictionary = flowers[sp]
		entry["count"] += 1
		entry["resource"] += flower.resource
		match flower.state:
			Flower.State.AVAILABLE:
				entry["available"] += 1
			Flower.State.BUSY:
				entry["busy"] += 1
			Flower.State.EMPTY:
				entry["empty"] += 1

	var states := {}
	var foragers := {}
	var recruits := {}
	var total := 0
	var outside := 0
	var with_source := 0
	for node in simulation.bees_container.get_children():
		var bee := node as Bee
		if bee == null or bee.current_state == null:
			continue
		total += 1
		var state_name: StringName = bee.current_state.get_script().get_global_name()
		states[state_name] = states.get(state_name, 0) + 1
		if bee.current_state is FieldState:
			outside += 1
		if is_instance_valid(bee.known_flower):
			with_source += 1
			var sp: int = bee.known_flower.species
			foragers[sp] = foragers.get(sp, 0) + 1
		elif bee.has_dance_vector():
			# Recrue : elle ne connaît que l'espèce et le point dansé
			recruits[bee.dance_species] = recruits.get(bee.dance_species, 0) + 1

	return {
		"flowers": flowers,
		"states": states,
		"foragers": foragers,
		"recruits": recruits,
		"dances": simulation.hive.get_dances_by_species(),
		"total": total,
		"outside": outside,
		"with_source": with_source,
	}


## Sucre (mg) stocké par espèce pendant les window_hours dernières heures simulées :
## différence entre les réserves actuelles et le plus ancien relevé de la fenêtre.
## Tant que la simulation n'a pas tourné window_hours, renvoie le cumul depuis le début.
func recent_sugar() -> Dictionary:
	var now: Dictionary = simulation.hive.sugar_by_species
	var start_hour := simulation.sim_hours - window_hours
	var base := {}
	for sample in samples:
		if sample["hour"] >= start_hour:
			base = sample["sugar"]
			break
	var result := {}
	for sp in now:
		result[sp] = now[sp] - base.get(sp, 0.0)
	return result
