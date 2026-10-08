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

@export_group("Population")

## Nombre d'abeilles créées au lancement.
@export_range(20, 200) var bee_count: int = 10

@export_group("Comportement")

## Probabilité par seconde qu'une abeille en IDLE parte explorer.
## À multiplier par delta dans IdleState, pour ne pas dépendre de la fréquence d'images.
@export var p_scout: float = 0.01

## Rayon (unités) de la zone explorée autour de la ruche en SCOUT.
@export var scout_radius: float = 10.0

## Durée de danse (s) pour une source de rentabilité 1.
## La durée réelle est proportionnelle à la rentabilité (boucle de recrutement).
@export var dance_duration_max: float = 10.0

## Temps (s) qu'une abeille doit suivre une danse pour mémoriser la source.
## Si la danse s'arrête avant, l'abeille retourne en IDLE.
@export var watch_min_duration: float = 2.0

## Durée maximale (s) d'exploration en SCOUT avant de rentrer bredouille.
@export var scout_timeout: float = 20.0

## Rentabilité au-dessus de laquelle l'abeille danse après déchargement.
@export_range(0.0, 1.0) var profitability_high: float = 0.6

## Rentabilité en dessous de laquelle l'abeille abandonne la source (retour en IDLE).
## Entre les deux seuils, elle repart sans danser.
@export_range(0.0, 1.0) var profitability_low: float = 0.2

## Quantité de nectar qu'une abeille peut transporter. FORAGE s'arrête une fois atteinte.
@export var forage_capacity: float = 1.0

@export_group("Déplacement")

## Vitesse de vol à l'extérieur (unités/s). À ajuster à l'échelle du terrain.
@export var fly_speed: float = 0.05

## Vitesse de marche sur le rayon (unités/s). À ajuster à l'échelle de la ruche.
@export var walk_speed: float = 0.02

## Vitesse de rotation des abeilles (1/s). Plus la valeur est grande, plus elles
## s'orientent vite vers leur cible. Une valeur très grande revient à un look_at instantané.
@export var turn_speed: float = 6.0

## Distance (unités) à laquelle une abeille en SCOUT repère une fleur.
@export var perception_radius: float = 3.0

## Distance (unités) en dessous de laquelle l'abeille est considérée arrivée.
@export var arrival_radius: float = 0.05

## Toutes les fleurs de la scène, collectées au lancement.
var flowers: Array[Flower] = []

## Crée [member bee_count] abeilles et leur injecte la ruche et la simulation.
func _ready() -> void:
	flowers.assign(get_tree().get_nodes_in_group(&"flowers"))
	for i in bee_count:
		var bee: Bee = bee_scene.instantiate()
		bee.name = "Bee_%03d" % (i + 1)   # Bee_001, Bee_002...
		bee.hive = hive
		bee.simulation = self
		bees_container.add_child(bee)
		bee.global_transform = hive.get_random_spawn_transform()	# Position d'apparition
