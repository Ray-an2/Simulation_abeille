class_name Simulation extends Node3D
## Pilotage de la simulation : crée les abeilles et centralise les paramètres.
##
## Tous les paramètres sont exportés : on peut les modifier pendant l'exécution
## via l'onglet Distant de l'arbre de scène, pour régler les boucles de rétroaction.

# ============================================================
# Paramètres réglables
# ============================================================

@export_group("Références")

## Ruche commune à toutes les abeilles. À assigner dans l'inspecteur.
@export var hive: Hive

## Nœud conteneur qui reçoit les abeilles créées (rangement dans l'arbre de scène).
@export var bees_container: Node3D

## Scène instanciée pour chaque abeille (bee.tscn). À assigner dans l'inspecteur.
@export var bee_scene: PackedScene

## Nœud Sky3D de la scène : horloge et position du soleil.
@export var sky: Sky3D

## Terrain3D de la scène, pour connaître la hauteur du sol sous les abeilles.
## Si null, le sol est ignoré.
@export var terrain: Terrain3D


@export_group("Population")

## Nombre d'abeilles créées au lancement.
@export_range(20, 200) var bee_count: int = 100


@export_group("Temps")

## Durée réelle (s) d'une journée simulée de 24 h.
@export var day_duration_seconds := 600.0

## Heure de départ de la simulation.
@export_range(0.0, 24.0) var start_hour := 8.0

## Seuils de lumière individuels : chaque abeille tire au hasard, à sa création,
## une hauteur du soleil (degrés) dans cet intervalle. En dessous, elle cesse de voler.
## Chez A. mellifera, premiers départs et dernières rentrées encadrent le lever
## et le coucher à quelques minutes près : soleil autour de 0°.
## L'étendue de l'intervalle est une estimation (pas de mesure de la dispersion).
@export_range(-6.0, 30.0) var light_threshold_min := -1.0
@export_range(-6.0, 30.0) var light_threshold_max := 5.0

## Descente du soleil (degrés) pendant un trajet typique, appliquée le soir seulement :
## une abeille ne part que si le soleil est au-dessus de son seuil + cette marge.
## Dans la réalité, un trajet de ~20 min correspond à quelques degrés ; ici la
## compression du temps (day_duration_seconds) rend les trajets bien plus longs
## en heures simulées. À régler d'après la durée des trajets affichée dans le HUD.
@export_range(0.0, 45.0) var departure_margin := 10.0


@export_group("Ruche")

## Durée (s) du transfert du nectar d'une butineuse à une receveuse.
@export var unload_duration := 3.0

## Temps de recherche d'une receveuse (s) à partir duquel l'envie de danser est
## réduite au maximum. 20 s : au-delà, les butineuses de Seeley (1992) ne faisaient
## plus de danse frétillante.
@export var max_wait_time := 20.0

## Réduction maximale de la rentabilité de danse due à l'attente (0 = aucune, 1 = totale).
@export_range(0.0, 1.0) var wait_penalty := 0.8


@export_group("Receveuses")

## Probabilité par seconde qu'une abeille en IDLE sans source connue devienne receveuse.
## Avec receiver_idle_timeout, elle fixe la part de receveuses quand aucun nectar
## ne rentre : receveuses / abeilles en attente ≈ p_receive × receiver_idle_timeout
## (loi de Little). 0,0025 × 100 = 0,25, soit environ 20 % des abeilles,
## la proportion de receveuses mesurée par Seeley (1989).
@export var p_receive: float = 0.0025

## Temps (s) sans butineuse à servir au bout duquel une receveuse retourne en IDLE.
## Valeur de réglage, non mesurée.
@export var receiver_idle_timeout: float = 100.0

## Distance (m) à laquelle une butineuse remarque une receveuse libre :
## environ une longueur d'abeille, l'échange se faisant au contact des antennes.
@export var unload_contact_radius: float = 0.015

## Durée (s) du dépôt du nectar en cellule, une fois la receveuse arrivée
## dans la zone de stockage. Valeur de réglage, non mesurée.
@export var store_duration: float = 10.0


@export_group("Exploration")

## Probabilité par seconde qu'une abeille en IDLE parte explorer juste après
## avoir croisé une danse : l'information circule, elle a peu de raisons de chercher.
## À multiplier par delta dans IdleState, pour ne pas dépendre de la fréquence d'images.
@export var p_scout: float = 0.001

## Probabilité par seconde de partir explorer pour une abeille qui n'a croisé
## aucune danse depuis scout_patience secondes de jour.
## Rapport p_scout_max / p_scout ≈ 6 : transposé de l'écart de proportion
## d'éclaireuses parmi les butineuses observé par Seeley (1983), d'environ 5 %
## quand les sources abondent à environ 35 % quand elles manquent.
## Transposition approximative : une proportion n'est pas un taux.
@export var p_scout_max: float = 0.006

## Temps (s) passé de jour en IDLE sans croiser de danse au bout duquel
## l'envie d'explorer atteint p_scout_max. Valeur de réglage, non mesurée.
@export var scout_patience: float = 300.0

## Rayon (unités) de la zone explorée autour de la ruche en SCOUT.
@export var scout_radius: float = 70.0

## Durée maximale (s) d'exploration en SCOUT avant de rentrer bredouille.
@export var scout_timeout: float = 90.0

## Angle apparent minimal (degrés) sous lequel une abeille repère une fleur.
## 5° : détection par le contraste (canal vert des photorécepteurs),
## 15° : détection par la couleur seule (Giurfa et al. 1996).
## Portée qui en découle : diamètre / (2 tan(angle / 2)), soit ≈ 11,4 × diamètre à 5°.
@export_range(1.0, 30.0) var detection_angle_deg: float = 5.0

@export_group("Butinage")

## Quantité de nectar qu'une abeille peut transporter. FORAGE s'arrête une fois atteinte.
@export var forage_capacity: float = 30.0

## Durée minimale (s) de butinage sur une fleur.
@export var foraging_time_min := 4.0

## Durée maximale (s) de butinage sur une fleur.
@export var foraging_time_max := 5.0

## Probabilité par seconde qu'une abeille en IDLE qui connaît une source
## y retourne d'elle-même (reprise du matin après la nuit).
@export var p_reactivate: float = 0.02

## Nombre de prélèvements sur une même fleur avant de passer à la suivante.
## 1 : une fleur ne contient que quelques microlitres de nectar.
@export_range(1, 10) var harvests_per_flower: int = 1

## Distance (m) maximale entre deux fleurs butinées pendant un même trajet :
## taille d'un massif. Valeur de réglage, à adapter à l'espacement des fleurs.
@export var patch_radius: float = 5.0

## Vitesse maximale (m/s) du vol d'une fleur à l'autre.
## Valeur de réglage, non mesurée : vol lent de prospection.
@export var flower_hop_speed: float = 1.5

@export_group("Danse")

## Durée de danse (s) pour une source de rentabilité 1.
## La durée réelle est proportionnelle à la rentabilité (boucle de recrutement).
@export var dance_duration_max: float = 60.0

## Temps (s) qu'une abeille doit suivre une danse pour mémoriser la source.
## Si la danse s'arrête avant, l'abeille retourne en IDLE.
@export var watch_min_duration: float = 12.0

## Seuil de danse quand la ruche est saturée (attente d'une receveuse ≥ max_wait_time).
## Le seuil réel descend jusqu'à dance_threshold_min quand l'abeille est déchargée
## sans attendre : la colonie qui récolte peu recrute même pour une source moyenne.
@export_range(0.0, 1.0) var profitability_high: float = 0.6

## Seuil de danse quand une receveuse prend l'abeille en charge sans attente.
## 0,35 : une efficacité énergétique d'environ 3 suffit pour danser.
@export_range(0.0, 1.0) var dance_threshold_min: float = 0.35

## Écart maximal (±) du seuil de danse d'une abeille à l'autre.
## Valeur de réglage : Seeley décrit cette variabilité sans en donner une mesure simple.
@export_range(0.0, 0.3) var dance_threshold_spread: float = 0.05

## Rentabilité en dessous de laquelle l'abeille abandonne la source (retour en IDLE).
## Entre les deux seuils, elle repart sans danser.
@export_range(0.0, 1.0) var profitability_low: float = 0.2

## Distance (m) à laquelle une abeille en IDLE remarque une danseuse.
## Mesure : 90 % des suiveuses sont attirées à moins de 27 mm (cellules ouvertes).
@export var follow_radius: float = 0.027

## Probabilité par seconde qu'une abeille en IDLE se mette à suivre
## une danseuse à portée. Valeur de réglage, non mesurée.
@export var p_follow: float = 0.5

## Nombre maximal de suiveuses par danseuse. Les suiveuses se tiennent à moins
## d'une longueur d'abeille de la danseuse : peu de places autour d'elle.
## Valeur estimée, non mesurée.
@export_range(1, 12) var max_followers: int = 6


@export_group("Recrutement")

## Écart-type (m) de l'erreur de la danse sur le point estimé, sur chaque axe horizontal.
## Erreur isotrope en mètres, indépendante de la distance : l'erreur de distance est du
## même ordre que l'erreur de direction, et la dispersion absolue des recrues varie peu
## avec la distance (Towne et Gould 1988). 4,4 m donne un écart moyen de 5,5 m
## (σ·√(π/2)), celui mesuré au radar par Riley et al. (2005).
@export var dance_error_sigma: float = 4.4

## Rayon (m) de la zone de recherche autour du point estimé.
## Valeur de réglage : environ 3σ, pour que la source soit presque toujours dedans.
@export var recruit_search_radius: float = 12.0

## Durée maximale (s) de recherche avant de rentrer bredouille.
## Valeur de réglage, non mesurée.
@export var recruit_search_timeout: float = 60.0


@export_group("Déplacement")

@export_subgroup("Vol")

## Vitesse de vol à l'extérieur (unités/s). À ajuster à l'échelle du terrain.
@export var fly_speed: float = 7.0

## Vitesse de vol en exploration (m/s) : plus lente que le transit,
## la recherche de fleurs est visuelle.
@export var scout_speed: float = 4.0

## Accélération (m/s²) au décollage et lors des reprises de vitesse.
## Avec 3 m/s², une abeille atteint 7 m/s en un peu plus de 2 s.
@export var fly_acceleration: float = 3.0

## Décélération (m/s²) à l'approche de la cible. Fixe la distance de freinage,
## v² / (2 × décélération) : environ 6 m depuis 7 m/s avec la valeur par défaut.
@export var fly_deceleration: float = 4.0

## Vitesse minimale (m/s) en fin d'approche : sans plancher, la vitesse tendrait
## vers zéro près de la cible et l'arrivée traînerait.
@export var landing_speed: float = 0.2

@export_subgroup("Virages")

## Vitesse de rotation des abeilles (1/s). Plus la valeur est grande, plus elles
## s'orientent vite vers leur cible. Une valeur très grande revient à un look_at instantané.
@export var turn_speed: float = 6.0

## Vitesse angulaire maximale en vol (rad/s). Le rayon de virage vaut
## vitesse / max_flight_turn_rate : 0,75 m à 3 m/s, 1,75 m à 7 m/s.
@export var max_flight_turn_rate: float = 4.0

## Fraction de la vitesse conservée quand la cible est pile derrière l'abeille.
## Elle ralentit le temps de virer au lieu de décrire un grand arc.
@export_range(0.1, 1.0) var turning_speed_factor: float = 0.3

@export_subgroup("Marche")

## Vitesse de marche sur le rayon (unités/s). À ajuster à l'échelle de la ruche.
@export var walk_speed: float = 0.02

@export_subgroup("Arrivée")

## Distance (m) à la cible en dessous de laquelle le mouvement bascule
## progressivement de « droit devant » à « droit sur la cible », pour garantir l'arrivée.
@export var homing_distance: float = 0.5

## Distance (unités) en dessous de laquelle l'abeille est considérée arrivée.
@export var arrival_radius: float = 0.05


@export_group("Obstacles")

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


@export_group("Décollage / atterrissage")

## Montée (m) selon la normale avant de partir.
@export var takeoff_height: float = 0.02

## Constante de temps (s) de l'approche : vitesse d'approche = distance / tau.
@export var landing_tau: float = 1.0

## Hauteur (m) du vol stationnaire avant la pose.
@export var hover_distance: float = 0.015

## Durée (s) du vol stationnaire au-dessus de la planche d'envol.
@export var hover_time_board: float = 0.3

## Vitesse (m/s) de la descente finale, et vitesse plancher de l'approche.
@export var touchdown_speed: float = 0.01


@export_group("Fleur")

## Quantité maximale de nectar (µL) dans une fleur.
@export var max_resource := 100.0

## Seuil de la fleur.
@export var threshold := 20.0

## Quantité de nectar (µL) prélevée sur une fleur pleine ; proportionnelle au stock sinon.
@export var harvest_amount := 5.0

## Stock auquel une fleur fermée (EMPTY) rouvre. Supérieur au seuil : la fleur
## rouvre avec quelques prélèvements d'avance au lieu de clignoter entre
## AVAILABLE et EMPTY. Valeur de réglage.
@export var reopen_level := 40.0

## Fraction du débit de sécrétion conservée la nuit (0 = arrêt, 1 = comme le jour).
## La sécrétion nocturne est nettement plus faible chez la plupart des espèces,
## sans être nulle. Valeur de réglage, non mesurée.
@export_range(0.0, 1.0) var night_secretion_factor := 0.2


@export_group("Rentabilité")

## Distance à plat (m) de la source la plus lointaine envisagée.
## Ne sert plus qu'à l'affichage : échelle de la boussole de danse (BeeHud).
@export var max_source_distance := 25.0

## Concentration (fraction massique) qui maximise le débit de sucre d'un insecte
## qui lape le nectar : environ 52 % (Kim, Gilet & Bush, PNAS 2011). Au-delà,
## le nectar est plus riche mais trop visqueux pour être bu vite.
@export_range(0.1, 0.9) var optimal_concentration := 0.52

## Concentration pour laquelle la durée d'un prélèvement vaut foraging_time_min..max.
## Plus concentré : prélèvement plus long ; plus dilué : plus court.
@export_range(0.1, 0.9) var reference_concentration := 0.40

## Énergie (J) d'un milligramme de sucre (saccharose : environ 16,5 kJ/g).
@export var sugar_energy := 16.5

## Facteur d'échelle entre les distances de la scène et celles du terrain réel.
## Une butineuse va couramment à 1 ou 2 km de la ruche : à l'échelle de la scène,
## le coût du vol serait négligeable et la distance ne compterait plus.
## 30 : le bord de la zone explorée (scout_radius = 70 m) vaut environ 2 km.
@export var distance_scale := 30.0

## Coût énergétique du vol (J/m). Ordre de grandeur : environ 45 mW pour une
## ouvrière de 0,1 g (soit environ 10 mg de sucre par heure de vol) à 6-7 m/s.
@export var flight_cost_per_m := 0.0065

## Masse (mg) d'une ouvrière à jabot vide : environ 80 à 100 mg.
## Le coût du vol est multiplié par (1 + charge / bee_body_mass).
@export var bee_body_mass := 90.0

## Part du surcoût théorique de la charge réellement payée en vol.
## 1 : puissance proportionnelle à la masse totale (hypothèse des modèles
## d'optimisation, dont Schmid-Hempel, Kacelnik & Houston 1985).
## 0,15 : mesures de Feuerbacher et al. (2003), environ 6 % de plus en vol
## stationnaire pour une charge de nectar de 40 % de la masse corporelle.
## Le sujet reste débattu : à présenter comme un paramètre de l'étude.
@export_range(0.0, 1.0) var load_cost_factor := 0.15

## Puissance (W) dépensée dans le massif à jabot vide : surtout des vols courts
## d'une fleur à l'autre, pris égaux au vol de croisière. Valeur de réglage.
@export var forage_power := 0.045

## Départ anticipé : l'abeille rentre avant d'avoir rempli son jabot si une fleur
## de plus ferait baisser l'efficacité de son trajet (Schmid-Hempel, Kacelnik
## & Houston, 1985). Désactivable pour comparer les deux comportements.
@export var efficient_stop := true

## Efficacité énergétique (gain - coût) / coût à partir de laquelle la rentabilité vaut 1.
@export var efficiency_max := 60.0


# ============================================================
# État de la simulation
# ============================================================

## Toutes les fleurs de la scène, collectées au lancement.
var flowers: Array[Flower] = []

## Nombre total d'heures simulées écoulées depuis le lancement.
var sim_hours := 0.0

## true quand le soleil descend (après-midi et soir), false quand il monte.
## Mis à jour dans _physics_process ; sert à n'appliquer departure_margin que le soir.
var sun_setting := false

## Hauteur du soleil relevée à la dernière mise à jour de sun_setting.
var _last_elevation := 0.0


# ============================================================
# Cycle de vie
# ============================================================

## Crée [member bee_count] abeilles et leur injecte la ruche et la simulation.
func _ready() -> void:
	# Horloge unique
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
		bee.name = _bee_name(i + 1)   # 1re, 2e, 3e… 100e
		bee.hive = hive
		bee.simulation = self
		# Position fixée AVANT add_child : add_child déclenche _ready() puis IdleState.enter(),
		# qui a besoin de la vraie position pour choisir son premier pas.
		# global_transform n'est pas utilisable hors de l'arbre : on passe par le repère
		# local du conteneur.
		bee.transform = bees_container.global_transform.affine_inverse() * hive.get_random_spawn_transform()
		bees_container.add_child(bee)	# Position d'apparition
		# Une partie de la colonie est déjà receveuse au lancement, dans la proportion
		# d'équilibre : on évite le régime transitoire où toutes partent d'IDLE
		if randf() < _initial_receiver_share():
			bee.change_state(bee.receive)
			bee.receive.start_at_launch()

## Nom d'une abeille, en clin d'œil aux Fourmis de Bernard Werber (« 103 683e »).
## Ouvrières, donc féminin : 1re, puis 2e, 3e…
func _bee_name(n: int) -> String:
	return "1re" if n == 1 else "%de" % n

## Part des abeilles déjà receveuses au lancement : proportion d'équilibre
## donnée par la loi de Little avec p_receive et receiver_idle_timeout.
## Avec les valeurs par défaut : 0,25 / 1,25 = 20 %, la proportion de Seeley (1989).
## Calculée et non saisie : elle reste cohérente si l'un des deux paramètres change.
func _initial_receiver_share() -> float:
	var x := p_receive * receiver_idle_timeout
	return x / (1.0 + x)

## Fait avancer l'horloge simulée et le soleil.
func _process(delta: float) -> void:
	var dh := hours_from(delta)
	sim_hours += dh
	sky.current_time += dh # Recalcule le soleil à chaque changement

## Suit le sens de déplacement du soleil. Sky3D ne met pas forcément à jour
## la lumière à chaque image : on ne compare que des valeurs différentes.
func _physics_process(_delta: float) -> void:
	var elevation := get_sun_elevation()
	if not is_equal_approx(elevation, _last_elevation):
		sun_setting = elevation < _last_elevation
		_last_elevation = elevation


# ============================================================
# Temps
# ============================================================

## Convertit une durée réelle [param delta] (s) en heures simulées.
func hours_from(delta: float) -> float:
	return delta * 24.0 / day_duration_seconds


## Retourne true s'il fait jour, sinon false.
func is_daytime() -> bool:
	return sky.is_day()
	
## Hauteur du soleil au-dessus de l'horizon (degrés), négative la nuit.
## basis.z du DirectionalLight pointe vers le soleil (voir get_dance_angle).
func get_sun_elevation() -> float:
	var to_sun: Vector3 = sky.sun.global_transform.basis.z.normalized()
	return rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))


# ============================================================
# Géométrie
# ============================================================

## Distance horizontale entre 2 positions.
func get_flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## Angle entre la direction du soleil et celle de la source.
func get_dance_angle(source_pos: Vector3, hive_pos: Vector3) -> float:
	var to_source := source_pos - hive_pos
	var to_sun: Vector3 = sky.sun.global_transform.basis.z   # direction vers le soleil
	to_source.y = 0.0
	to_sun.y = 0.0
	if to_source.length() < 0.001 or to_sun.length() < 0.001:
		return 0.0
	return to_sun.signed_angle_to(to_source, Vector3.UP)
	
## Inverse de get_dance_angle() : direction horizontale (unitaire) qui fait
## l'angle [param angle] avec la direction du soleil à cet instant.
## Vector3.ZERO si le soleil est au zénith : il ne donne alors plus de direction,
## comme pour l'abeille réelle (jamais le cas à la latitude de Brest).
func get_direction_from_dance_angle(angle: float) -> Vector3:
	var to_sun: Vector3 = sky.sun.global_transform.basis.z   # direction vers le soleil
	to_sun.y = 0.0
	if to_sun.length() < 0.001:
		return Vector3.ZERO
	return to_sun.normalized().rotated(Vector3.UP, angle)


## Fleur libre (ni vide, ni réservée par une autre) la plus proche que [param bee]
## peut voir, ou null. [param species] : -1 pour toutes les espèces, sinon seulement
## celle-ci (recrue qui cherche l'odeur annoncée). Portée de chaque fleur
## proportionnelle au diamètre de sa corolle (règle de l'angle apparent).
func find_visible_flower(bee: Bee, species: int = -1) -> Flower:
	var best: Flower = null
	var best_d2 := INF
	# Facteur commun à toutes les fleurs : portée = diamètre × factor
	var factor := 0.5 / tan(deg_to_rad(detection_angle_deg) * 0.5)
	for f in flowers:
		if species >= 0 and f.species != species:
			continue
		if not f.is_free_for(bee):
			continue
		var reach := f.corolla_diameter * factor
		# Comparaison des carrés : évite une racine carrée par fleur
		var d2 := bee.global_position.distance_squared_to(f.get_landing_position())
		if d2 < reach * reach and d2 < best_d2:
			best = f
			best_d2 = d2
	return best
