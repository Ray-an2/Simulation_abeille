class_name Simulation extends Node3D
## Pilotage de la simulation : crée les abeilles et centralise les paramètres.
##
## Tous les paramètres sont exportés : on peut les modifier pendant l'exécution
## via l'onglet Distant de l'arbre de scène, pour régler les boucles de rétroaction.

## Ruche commune à toutes les abeilles. À assigner dans l'inspecteur.
@export var hive: Hive

## Nœud conteneur qui reçoit les abeilles créées (rangement dans l'arbre de scène).
@export var bees_container: Node3D

## Scène instanciée pour chaque abeille (bee.tscn). À assigner dans l'inspecteur.
@export var bee_scene: PackedScene

@export_group("Ruche")

## Nombre de receveuses : abeilles prises en charge en même temps
@export_range(1, 20) var receiver_count := 3

## Durée (s) du transfert du nectar à une receveuse
@export var unload_duration := 3.0

## Attente (s) à partir de laquelle l'envie de danser est réduite au maximum
@export var max_wait_time := 20.0

## Réduction maximale de la rentabilité de danse due à l'attente (0 = aucune, 1 = totale)
@export_range(0.0, 1.0) var wait_penalty := 0.8

@export_group("Temps")

## Nœud Sky3D de la scène
@export var sky: Sky3D

## Durée réelle (secondes) d'une journée simulée de 24 h
@export var day_duration_seconds := 600.0

## Heure de départ de la simulation
@export_range(0.0, 24.0) var start_hour := 8.0

@export_group("Population")

## Nombre d'abeilles créées au lancement.
@export_range(20, 200) var bee_count: int = 100

@export_group("Comportement")

## Probabilité par seconde qu'une abeille en IDLE parte explorer.
## À multiplier par delta dans IdleState, pour ne pas dépendre de la fréquence d'images.
@export var p_scout: float = 0.005

## Rayon (unités) de la zone explorée autour de la ruche en SCOUT.
@export var scout_radius: float = 40.0

## Durée de danse (s) pour une source de rentabilité 1.
## La durée réelle est proportionnelle à la rentabilité (boucle de recrutement).
@export var dance_duration_max: float = 10.0

## Temps (s) qu'une abeille doit suivre une danse pour mémoriser la source.
## Si la danse s'arrête avant, l'abeille retourne en IDLE.
@export var watch_min_duration: float = 2.0

## Durée maximale (s) d'exploration en SCOUT avant de rentrer bredouille.
@export var scout_timeout: float = 90.0

## Rentabilité au-dessus de laquelle l'abeille danse après déchargement.
@export_range(0.0, 1.0) var profitability_high: float = 0.6

## Rentabilité en dessous de laquelle l'abeille abandonne la source (retour en IDLE).
## Entre les deux seuils, elle repart sans danser.
@export_range(0.0, 1.0) var profitability_low: float = 0.2

## Quantité de nectar qu'une abeille peut transporter. FORAGE s'arrête une fois atteinte.
@export var forage_capacity: float = 10.0

## Temps de butinage minimum 
@export var foraging_time_min := 4.0

## Temps de butinage maximum
@export var foraging_time_max := 5.0

@export_group("Déplacement")

## Vitesse de vol à l'extérieur (unités/s). À ajuster à l'échelle du terrain.
@export var fly_speed: float = 7.0

## Accélération (m/s²) au décollage et lors des reprises de vitesse.
## Avec 3 m/s², une abeille atteint 7 m/s en un peu plus de 2 s.
@export var fly_acceleration: float = 3.0

## Décélération (m/s²) à l'approche de la cible. Fixe la distance de freinage,
## v² / (2 × décélération) : environ 6 m depuis 7 m/s avec la valeur par défaut.
@export var fly_deceleration: float = 4.0

## Vitesse minimale (m/s) en fin d'approche : sans plancher, la vitesse tendrait
## vers zéro près de la cible et l'arrivée traînerait.
@export var landing_speed: float = 0.2

## Vitesse de marche sur le rayon (unités/s). À ajuster à l'échelle de la ruche.
@export var walk_speed: float = 0.02

## Vitesse de rotation des abeilles (1/s). Plus la valeur est grande, plus elles
## s'orientent vite vers leur cible. Une valeur très grande revient à un look_at instantané.
@export var turn_speed: float = 6.0

## Vitesse de vol en exploration (m/s) : plus lente que le transit,
## la recherche de fleurs est visuelle.
@export var scout_speed: float = 4.0

## Vitesse angulaire maximale en vol (rad/s). Le rayon de virage vaut
## vitesse / max_flight_turn_rate : 0,75 m à 3 m/s, 1,75 m à 7 m/s.
@export var max_flight_turn_rate: float = 4.0

## Fraction de la vitesse conservée quand la cible est pile derrière l'abeille.
## Elle ralentit le temps de virer au lieu de décrire un grand arc.
@export_range(0.1, 1.0) var turning_speed_factor: float = 0.3

## Distance (m) à la cible en dessous de laquelle le mouvement bascule
## progressivement de « droit devant » à « droit sur la cible », pour garantir l'arrivée.
@export var homing_distance: float = 0.5

## Distance (unités) à laquelle une abeille en SCOUT repère une fleur.
@export var perception_radius: float = 3.0

## Distance (unités) en dessous de laquelle l'abeille est considérée arrivée.
@export var arrival_radius: float = 0.05

## Toutes les fleurs de la scène, collectées au lancement.
var flowers: Array[Flower] = []

@export_group("Obstacles")

## Terrain3D de la scène, pour connaître la hauteur du sol sous les abeilles.
## Si null, le sol est ignoré.
@export var terrain: Terrain3D

## Hauteur de vol (m) au-dessus du sol, loin de la cible.
@export var cruise_height: float = 1.0

## Distance horizontale (m) à la cible en dessous de laquelle l'abeille amorce sa descente.
## La hauteur exigée passe linéairement de cruise_height à ground_clearance.
@export var descent_distance: float = 2.0

## Hauteur minimale (m) du centre de l'abeille au-dessus du sol, même posée.
@export var ground_clearance: float = 0.02

## Portée (m) du rayon de détection des obstacles devant l'abeille.
@export var obstacle_look_ahead: float = 0.5

## Distance (m) gardée entre l'abeille et un obstacle pendant le contournement.
@export var obstacle_clearance: float = 0.1

## Calques de collision considérés comme obstacles (ruche, arbres).
## Le terrain n'y est pas : il est géré par sa hauteur, plus rapide qu'un rayon.
@export_flags_3d_physics var obstacle_mask: int = 1 << 2   # calque 3

@export_group("Fleur")

## Ressources maximum dans une fleur
@export var max_resource := 100.0

## Seuil de la fleur
@export var threshold := 20.0

## Quantite de nectar récolter de l'abeille
@export var harvest_amount := 5.0

@export_group("Qualité de source")

## Distance à plat (unités) à partir de laquelle la source est jugée trop loin (score 0)
@export var max_source_distance := 25.0

## Durée de trajet (s) à partir de laquelle le score de temps tombe à 0
@export var max_trip_time := 120.0

## Poids de chaque critère dans la rentabilité
@export_range(0.0, 1.0) var weight_stock := 0.4
@export_range(0.0, 1.0) var weight_distance := 0.3
@export_range(0.0, 1.0) var weight_time := 0.3

## Retourne l'heure
func hours_from(delta: float) -> float:
	return delta * 24.0 / day_duration_seconds

## Retourne true s'il y fait jour, sinon false
func is_daytime() -> bool:
	return sky.is_day()

## total heures écoulées
var sim_hours := 0.0

## Crée [member bee_count] abeilles et leur injecte la ruche et la simulation.
func _ready() -> void:
	# Horloge unique
	sky.game_time_enabled = false
	sky.current_time = start_hour
	# La ruche doit avoir calculé la zone du cadre avant qu'on y place les abeilles
	if not hive.is_node_ready():
		await hive.ready
	flowers.assign(get_tree().get_nodes_in_group(&"flowers"))
	for flower in flowers:
		flower.setup(self)
	for i in bee_count:
		var bee: Bee = bee_scene.instantiate()
		bee.name = "Bee_%03d" % (i + 1)   # Bee_001, Bee_002...
		bee.hive = hive
		bee.simulation = self
		# Position fixée AVANT add_child : add_child déclenche _ready() puis IdleState.enter(),
		# qui a besoin de la vraie position pour choisir son premier pas.
		# global_transform n'est pas utilisable hors de l'arbre : on passe par le repère
		# local du conteneur.
		bee.transform = bees_container.global_transform.affine_inverse() * hive.get_random_spawn_transform()
		bees_container.add_child(bee)	# Position d'apparition

func _process(delta: float) -> void:
	var dh := hours_from(delta)
	sim_hours += dh
	sky.current_time += dh # Recalcule le soleil à chaque changement

## Distance horizontale entre 2 positions
func get_flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()

## Angle entre la direction du soleil et celle de la source
func get_dance_angle(source_pos: Vector3, hive_pos: Vector3) -> float:
	var to_source := source_pos - hive_pos
	var to_sun: Vector3 = sky.sun.global_transform.basis.z   # direction vers le soleil
	to_source.y = 0.0
	to_sun.y = 0.0
	if to_source.length() < 0.001 or to_sun.length() < 0.001:
		return 0.0
	return to_sun.signed_angle_to(to_source, Vector3.UP)
