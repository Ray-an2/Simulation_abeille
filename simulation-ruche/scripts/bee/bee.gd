class_name Bee extends Node3D
## Agent abeille ouvrière, piloté par une machine à états hiérarchique.

## Émis par change_state() après l'entrée dans le nouvel état.
## [param from] vaut null au premier appel (état initial).
signal state_changed(bee: Bee, from: BeeState, to: BeeState)

# =============================================================================
# Constantes
# =============================================================================

# --- Marche : conversion de la vitesse de l'animation ---

## Vitesse d'avance du corps dans _bee_walk à speed_scale = 1, en unités du squelette par seconde :
## chaque pied recule de 220 unités pendant les 0,25 s d'appui.
const WALK_ANIM_SPEED := 880.0

## Échelle racine appliquée à l'import du glTF (option « Root Scale »). Avec
## « Apply Root Scale » activé, elle est intégrée au squelette et aux animations,
## et n'apparaît donc pas dans l'échelle du nœud Model : il faut la reporter ici.
const IMPORT_ROOT_SCALE := 0.01

## Échelle entre le squelette et le modèle (nœud RootNode du glTF).
const SKELETON_SCALE := 0.0008

## En dessous de ce facteur de vitesse, l'abeille est considérée à l'arrêt :
## évite d'alterner walk et idle pendant les phases d'accélération et de freinage.
const WALK_MIN_FACTOR := 0.05

# --- Vol : inclinaison dans les virages ---

## Inclinaison (rad) par rad/s de vitesse de lacet. Avec 0,15, un virage à
## 4 rad/s (max_flight_turn_rate) donne environ 34° d'inclinaison.
const BANK_GAIN := 0.15

## Inclinaison maximale (rad), environ 35°.
const MAX_BANK := 0.6

## Vitesse de lissage de l'inclinaison (1/s) : l'abeille s'incline et se redresse
## progressivement, même si le lacet démarre d'un coup.
const BANK_SMOOTHING := 8.0

## Part de l'inclinaison du corps transmise à la caméra embarquée (0 = vue stable,
## 1 = vue solidaire du corps). La tête compense une partie du roulis.
const CAMERA_BANK_FACTOR := 0.5

# --- Animation : fréquence de mise à jour ---

## Distance (m) caméra–abeille en dessous de laquelle l'animation est mise à jour
## à chaque frame (vue abeille, gros plan sur le cadre).
const ANIM_NEAR := 0.5

## Au-delà de ANIM_NEAR : une mise à jour de l'animation toutes les N frames.
const ANIM_FAR_STEP := 4

# --- Son : bourdonnement individuel ---

## Animations où l'abeille bat des ailes. Avec la vitesse de vol, elles décident
## du bourdonnement individuel (voir _update_buzz()).
const WING_ANIMS: Array[StringName] = [&"_bee_takeoff", &"_bee_hover", &"_bee_landing"]

## Volume considéré comme silencieux : en dessous, on arrête le player.
const BUZZ_OFF_DB := -60.0

## Vitesse du fondu (1/s). Avec 12, l'extinction prend environ 0,3 s.
const BUZZ_FADE_SPEED := 12.0

# --- Pelotes de pollen (indicateur visuel de charge) ---

## Durée (s) de l'animation de croissance des pelotes après chaque visite.
const POLLEN_GROW_TIME := 0.8

## Taille des pelotes pour une charge minimale (fraction de leur taille maximale).
const POLLEN_MIN_SCALE := 0.3

# =============================================================================
# Références injectées par Simulation
# =============================================================================

## Ruche de rattachement : point de retour, file de déchargement, liste des danses.
var hive: Hive

## Nœud de pilotage : fournit tous les paramètres réglables (vitesses, seuils, durées).
var simulation: Simulation

# =============================================================================
# Nœuds de la scène
# =============================================================================

## Modèle 3D : seul lui est incliné, pour ne pas perturber _face() ni la caméra.
@onready var _model: Node3D = $Model

## Marqueur de la caméra embarquée, enfant de Bee.
@onready var _camera_anchor: Marker3D = $CameraAnchor

## Repère des pièces buccales : c'est ce point qui doit arriver sur le pistil.
@onready var _head: Marker3D = %HeadMarker

## Lecteur d'animations du modèle glTF (hover, idle, take_off_and_land).
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer

## Bourdonnement individuel, audible uniquement en vol.
@onready var _buzz: AudioStreamPlayer3D = $Buzz

## Pelotes de pollen, enfants des BoneAttachment3D des pattes arrière.
## On agit sur elles et non sur les attachements, dont la transformation
## est imposée par l'os à chaque frame.
@onready var _pollen: Array[MeshInstance3D] = [
	$BonePollenLeft/PollenBall,
	$BonePollenRight/PollenBall,
]

# =============================================================================
# États
# =============================================================================

## État actif. Son [method BeeState.update] est appelé à chaque frame physique.
var current_state: BeeState

# --- Ruche ---

## Attente dans la ruche. État initial.
var idle: IdleState

## Sortie à pied jusqu'à la planche d'envol, puis décollage (voir LeaveState.then()).
var leave_hive: LeaveState

## Entrée à pied de la planche d'envol jusqu'au cadre.
var enter_hive: EnterState

## Suit une danseuse pour mémoriser la source annoncée (recrutement).
var watch: WatchState

## Danse frétillante : annonce la source à la ruche (recrutement).
var dance: DanceState

## Décharge le nectar dans la ruche
var unload: UnloadState

# --- Dehors ---

## Exploration à la recherche d'une fleur, avec timeout.
var scout: ScoutState

## Vol en direction d'une source connue
var go: GoState

## Butine une source
var forage: ForageState

## État de retour à la ruche
var return_home: ReturnState

# =============================================================================
# Données partagées entre les états
# =============================================================================

## Locomotion sur le cadre (cap, vitesse, évitement), partagée par les états Ruche.
## Conservée d'un état à l'autre, réinitialisée à chaque arrivée dans la ruche.
var walker: CombWalker

## Quantité de nectar transportée. Remplie en FORAGE, vidée en UNLOAD.
var nectar: float = 0.0

## Source mémorisée : apprise en WATCH, ou trouvée en SCOUT. Cible de l'état GO.
## [code]null[/code] si l'abeille ne connaît aucune source.
var known_flower: Flower = null

## Rentabilité de [member known_flower] (entre 0 et 1), évaluée en UNLOAD.
## Détermine la transition suivante (DANCE, GO ou IDLE) et la durée de la danse.
var known_profitability: float = 0.0

## Danseuse dont l'abeille a appris sa source en WATCH ; null si elle l'a trouvée
## elle-même en exploration, ou si elle ne connaît aucune source.
var recruited_by: Bee = null

## Durée du trajet en cours hors de la ruche
var trip_time: float = 0.0

## Temps (s) passé à butiner pendant ce trajet (prélèvements et vols entre fleurs).
## Compté par FORAGE, lu par UNLOAD pour le score de temps de la source.
var forage_time: float = 0.0

## Distance à plat ruche -> source
var distance: float = 0.0

## Angle (rad) entre la direction du soleil et celle de la source, vu de la ruche.
## Calculé en UNLOAD, encodé par DANCE dans l'orientation de la phase frétillante.
var angle: float = 0.0

## Normale de la surface sur laquelle l'abeille est posée ; Vector3.ZERO quand elle vole.
var surface_normal: Vector3 = Vector3.ZERO

# =============================================================================
# État interne
# =============================================================================

# --- Vol ---

## Vitesse de vol actuelle (m/s). Repart de 0 à chaque décollage et rejoint
## fly_speed avec fly_acceleration ; diminue à l'approche de la cible.
var _flight_speed := 0.0

## Inclinaison actuelle (rad) et avant horizontal à l'image précédente (mesure du lacet).
var _bank := 0.0
var _prev_forward := Vector3.ZERO

## Sens de contournement préféré (+1 ou -1), tiré à la création : face à un obstacle
## pile dans l'axe, les abeilles se répartissent des deux côtés au lieu de partir toutes à gauche.
var _avoid_side := 1.0

# --- Orientation d'origine (bee.tscn) ---

## Orientation d'origine du modèle dans bee.tscn, à laquelle on ajoute l'inclinaison.
var _model_base_basis: Basis

## Orientation d'origine du marqueur dans bee.tscn.
var _camera_anchor_base_basis: Basis

# --- Animation ---

## Vitesse d'avance (m/s) du corps dans _bee_walk à speed_scale = 1, en unités du monde.
## Calculée une fois dans _ready() : l'échelle du modèle ne change pas pendant la simulation.
var _walk_anim_world_speed := 0.0

## Temps accumulé depuis la dernière mise à jour de l'animation.
var _anim_accum := 0.0

## Décalage propre à chaque abeille : elles ne sont pas toutes mises à jour à la même frame.
var _anim_offset := 0

# --- Son ---

## Volume (dB) du bourdonnement en vol : celui réglé sur le nœud Buzz dans bee.tscn.
## Relevé dans _ready(), avant que le fondu ne le modifie.
var _buzz_on_db := 0.0

# --- Pelotes de pollen ---

## Tween en cours sur les pelotes, pour l'interrompre si la charge change de nouveau.
var _pollen_tween: Tween

## Échelle de chaque pelote réglée dans bee.tscn : c'est sa taille maximale.
## update_pollen() en applique une fraction. Sans elle, le tween écraserait
## l'échelle de l'éditeur (×1000, pour compenser celle du squelette)
## et les pelotes deviendraient invisibles.
var _pollen_full_scale: Array[Vector3] = []

# =============================================================================
# Cycle de vie
# =============================================================================

## Crée les états et la locomotion sur le cadre, relève les réglages de bee.tscn,
## puis active l'état initial IDLE.
func _ready() -> void:
	assert(hive != null and simulation != null,
		"Bee '%s' : hive=%s, simulation=%s — doivent être assignés avant add_child()"
		% [name, hive, simulation])

	# Locomotion sur le cadre, partagée par les états Ruche.
	# Créée en premier : un état pourrait s'en servir dès sa construction.
	walker = CombWalker.new(self)

	idle = IdleState.new(self)
	leave_hive = LeaveState.new(self)
	enter_hive = EnterState.new(self)
	scout = ScoutState.new(self)
	return_home = ReturnState.new(self)
	unload = UnloadState.new(self)
	go = GoState.new(self)
	forage = ForageState.new(self)
	dance = DanceState.new(self)
	watch = WatchState.new(self)

	_model_base_basis = _model.transform.basis
	_camera_anchor_base_basis = _camera_anchor.transform.basis

	# Volume de référence réglé dans l'inspecteur, avant toute modification par le fondu
	_buzz_on_db = _buzz.volume_db

	# Hauteur légèrement différente par abeille : évite l'effet « 200 clones »
	_buzz.pitch_scale = randf_range(0.9, 1.1)

	# Conversion de la vitesse de l'animation : unités du squelette → modèle → monde.
	# IMPORT_ROOT_SCALE : échelle appliquée à l'import, absente du nœud Model.
	var model_scale := ($Model as Node3D).global_basis.get_scale().x
	_walk_anim_world_speed = WALK_ANIM_SPEED * SKELETON_SCALE * IMPORT_ROOT_SCALE * model_scale

	# Fondu de 0,25 s entre deux animations : masque l'écart de pose des pattes
	# et des ailes entre takeoff, hover et landing. Réglé ici plutôt que dans
	# l'inspecteur, car l'AnimationPlayer fait partie du modèle importé.
	_anim.playback_default_blend_time = 0.25

	# L'animation n'avance plus toute seule : _process() l'avance, plus ou moins souvent
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_offset = randi() % ANIM_FAR_STEP

	_avoid_side = 1.0 if randf() < 0.5 else -1.0

	# Taille maximale des pelotes : celle réglée dans bee.tscn
	for p in _pollen:
		_pollen_full_scale.append(p.scale)

	# Abeille vide au départ : pelotes masquées
	update_pollen()

	change_state(idle)

## Avance l'animation à chaque frame près de la caméra, toutes les ANIM_FAR_STEP frames
## au-delà. Le temps accumulé est rattrapé d'un coup : la vitesse reste juste,
## seule la fluidité baisse, ce qui ne se voit pas de loin.
func _process(delta: float) -> void:
	_anim_accum += delta
	var step := 1
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) > ANIM_NEAR * ANIM_NEAR:
		step = ANIM_FAR_STEP
	if (Engine.get_process_frames() + _anim_offset) % step != 0:
		return
	_anim.advance(_anim_accum)
	_anim_accum = 0.0

## Exécute l'état courant et applique la transition qu'il renvoie, le cas échéant.
## Les transitions imposées par le super-état (interrupt) passent avant celles de l'état.
func _physics_process(delta: float) -> void:
	if current_state == null:
		return
	# Chronomètre du trajet : temps passé dehors, remis à zéro par UNLOAD
	# après évaluation de la source
	if current_state is FieldState:
		trip_time += delta
	var next: BeeState = current_state.interrupt()
	if next == null:
		next = current_state.update(delta)
	if next != null:
		change_state(next)

	_update_buzz(delta)

## Retire l'abeille de la ruche si elle est supprimée alors qu'elle y est.
func _exit_tree() -> void:
	if current_state is HiveState:
		hive.bee_left(self)

# =============================================================================
# Transitions
# =============================================================================

## Quitte l'état courant ([method BeeState.exit]) puis entre dans [param next]
## ([method BeeState.enter]). Seul point de passage de toutes les transitions.
## Prévient aussi la ruche quand l'abeille passe de Ruche à Dehors ou l'inverse.
func change_state(next: BeeState) -> void:
	var previous := current_state

	# Super-état avant / après : seul un passage Ruche ↔ Dehors nous intéresse
	var was_inside := current_state is HiveState   # false au premier appel (null)
	var is_inside := next is HiveState

	surface_normal = hive.get_comb_normal()

	if current_state != null:
		current_state.exit()
	current_state = next

	# Fait avant enter() pour que l'état puisse déjà interroger ses voisines
	if is_inside != was_inside:
		_on_location_changed(is_inside)

	current_state.enter()
	state_changed.emit(self, previous, next)

## Prévient la ruche et réinitialise la marche. Le bourdonnement individuel
## ne dépend pas d'ici : _update_buzz() le règle à chaque image.
func _on_location_changed(inside: bool) -> void:
	# Passage Ruche ↔ Dehors : toujours posée sur la planche d'envol
	land()
	if inside:
		hive.bee_entered(self)
		# Arrivée sur le cadre : l'abeille repart immobile, dans la direction où elle regarde
		walker.reset()
	else:
		hive.bee_left(self)

# =============================================================================
# Vol (appelé par les états)
# =============================================================================

## [param arrive] : true pour s'arrêter sur la cible (fleur, planche d'envol),
## false pour un point de passage (errance en SCOUT) : pas de freinage,
## l'abeille garde sa vitesse et enchaîne sur le point suivant.
## [param max_speed] : vitesse de croisière visée ; 0 = fly_speed.
func fly_towards(target: Vector3, delta: float, arrive := true, max_speed := 0.0) -> void:
	var goal := _flight_goal(target)
	var to_goal := goal - global_position
	var dist := global_position.distance_to(target)
	var cruise := max_speed if max_speed > 0.0 else simulation.fly_speed

	# --- Vitesse voulue ---
	var wanted := cruise
	if arrive:
		# Plafond de freinage : vitesse maximale qui permet encore de s'arrêter sur la cible
		var brake_limit := sqrt(2.0 * simulation.fly_deceleration * dist)
		wanted = clampf(brake_limit, simulation.landing_speed, cruise)

	# Plafond de virage : vitesse maximale qui permet encore d'atteindre la cible.
	# Rayon de virage r = v / ω_max ; pour un point à distance d vu sous l'angle θ,
	# il faut r ≤ d / (2 sin θ), soit v ≤ ω_max · d / (2 sin θ).
	# Sans ce plafond, une cible à l'intérieur du cercle de virage est inaccessible
	# et l'abeille tourne autour indéfiniment.
	var turn_limit := INF
	var forward := global_basis.z.normalized()   # avant du modèle sur +Z (glTF)
	if not to_goal.is_zero_approx():
		var cos_bearing := forward.dot(to_goal.normalized())
		# Cible derrière ou sur le côté : on ralentit pour virer serré.
		# Alignement ramené de [-1, 1] à [0, 1] : 1 droit devant, 0 pile derrière.
		wanted *= lerpf(simulation.turning_speed_factor, 1.0, (cos_bearing + 1.0) * 0.5)
		var sin_bearing := sqrt(maxf(1.0 - cos_bearing * cos_bearing, 0.0))
		if sin_bearing > 0.01:
			turn_limit = simulation.max_flight_turn_rate * to_goal.length() / (2.0 * sin_bearing)
	wanted = minf(wanted, turn_limit)

	# La vitesse courante rejoint la vitesse voulue sans à-coup...
	var rate := simulation.fly_acceleration if wanted > _flight_speed else simulation.fly_deceleration
	_flight_speed = move_toward(_flight_speed, wanted, rate * delta)
	# ...sauf pour virer : freinage immédiat. Avec la seule décélération (4 m/s²),
	# l'abeille mettrait un demi-seconde à ralentir et dépasserait quand même la cible.
	_flight_speed = minf(_flight_speed, turn_limit)

	# --- Orientation : rotation plafonnée en vol ---
	if to_goal.length_squared() >= 0.000001:
		_face(to_goal, Vector3.UP, delta, simulation.max_flight_turn_rate)

	# --- Déplacement ---
	var step := _flight_speed * delta
	if to_goal.length() <= step:
		# Dernier pas : arrivée exacte sur le point visé
		global_position = goal
	else:
		# Loin de la cible : droit devant (axe du corps, après rotation).
		# Près de la cible : mélange progressif avec la direction directe,
		# pour ne pas tourner autour sans jamais l'atteindre.
		var homing := 1.0 - clampf(dist / simulation.homing_distance, 0.0, 1.0)
		var move_dir := global_basis.z.normalized().lerp(to_goal.normalized(), homing)
		# Avant et cible opposés avec homing ≈ 0,5 : le mélange s'annule, on prend la direction directe
		if move_dir.length_squared() < 0.0001:
			move_dir = to_goal
		global_position += move_dir.normalized() * step

	# Filet de sécurité : jamais sous le sol
	var floor_y := get_ground_height(global_position) + simulation.ground_clearance
	if global_position.y < floor_y:
		global_position.y = floor_y

	_update_bank(delta)

## Vol vers `target` à la vitesse `speed`, le haut de l'abeille ramené progressivement vers `up`.
func fly_towards_at(target: Vector3, speed: float, up: Vector3, delta: float) -> void:
	var dir := target - global_position
	global_position = global_position.move_toward(target, speed * delta)
	orient(dir, up, delta)

## Oriente l'abeille face à `forward` (projeté dans le plan perpendiculaire à `up`), haut sur `up`.
func orient(forward: Vector3, up: Vector3, delta: float) -> void:
	forward -= up * forward.dot(up)
	if forward.length_squared() < 1e-8:
		# Direction parallèle à la normale (descente finale) : on garde le cap actuel.
		forward = -global_basis.z - up * (-global_basis.z).dot(up)
	if forward.length_squared() < 1e-8:
		# Cap lui-même parallèle à la normale : on prend l'ancien haut projeté.
		forward = global_basis.y - up * global_basis.y.dot(up)
	var target_q := Basis.looking_at(forward.normalized(), up).get_rotation_quaternion()
	var w := 1.0 - exp(-simulation.turn_speed * delta)   # même lissage que _move_towards
	var s := global_basis.get_scale()                     # suppose une échelle uniforme
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target_q, w)).scaled(s)

## Vitesse de vol courante (m/s). Lue par FieldState pour enchaîner sans rupture
## entre fly_towards() et ses phases de décollage et d'approche finale.
func get_flight_speed() -> float:
	return _flight_speed

## Impose la vitesse de vol courante. Appelée par FieldState à la fin du décollage
## et pendant l'approche finale, pour que fly_towards() reparte de la bonne vitesse.
func set_flight_speed(speed: float) -> void:
	_flight_speed = speed

## Remet la vitesse de vol à zéro. À appeler dès que l'abeille est posée
## (fleur, planche d'envol) : le prochain vol repartira d'un décollage.
func land() -> void:
	_flight_speed = 0.0
	_bank = 0.0
	_prev_forward = Vector3.ZERO   # pas de lacet mesuré au prochain décollage
	_model.transform.basis = _model_base_basis
	_camera_anchor.transform.basis = _camera_anchor_base_basis

## true si l'abeille est posée : land() a remis sa vitesse de vol à zéro
## et aucun vol n'a repris depuis. FieldState s'en sert pour décider d'un décollage.
func is_landed() -> bool:
	return is_zero_approx(_flight_speed)

# =============================================================================
# Marche (appelé par les états)
# =============================================================================

## Marche vers [param target] à la vitesse [member Simulation.walk_speed],
## multipliée par [param speed_factor].
## Réservé aux états du super-état Ruche.
## [param up] est la normale de la surface parcourue : passer
## [method Hive.get_comb_normal] pour que l'abeille reste à plat sur le cadre.
## Règle aussi la cadence des pattes sur la vitesse appliquée.
func walk_towards(target: Vector3, delta: float, up: Vector3 = Vector3.UP, speed_factor: float = 1.0) -> void:
	_move_towards(target, simulation.walk_speed * speed_factor * delta, up, delta)
	# Les pattes suivent la vitesse appliquée : walker (cadre, plancher, tunnel)
	# comme lignes droites de LEAVE et ENTER sur la planche
	play_walk(speed_factor)

## Se déplace vers [param target] à [param speed] m/s, sans s'orienter dans le sens
## du mouvement : l'abeille tourne progressivement pour regarder vers [param facing],
## avec [param up] comme vecteur haut. Sert aux petits sauts entre le bas du cadre
## et le plancher, où elle se retourne en tombant.
func hop_towards(target: Vector3, speed: float, facing: Vector3, up: Vector3, delta: float) -> void:
	_face(facing, up, delta)
	# move_toward ne dépasse jamais la cible : arrivée exacte
	global_position = global_position.move_toward(target, speed * delta)

# =============================================================================
# Requêtes (appelé par les états)
# =============================================================================

## Renvoie [code]true[/code] si l'abeille est à moins de [param radius] de [param target].
## Sert de test d'arrivée pour GO, RETURN, etc.
func is_near(target: Vector3, radius: float) -> bool:
	# Comparaison des carrés : évite une racine carrée à chaque appel
	return global_position.distance_squared_to(target) <= radius * radius

## Distance (m) du centre de l'abeille à sa tête, le long de son axe avant (+Z).
## Mesurée sur le marqueur : suit automatiquement l'échelle du modèle.
func get_head_offset() -> float:
	return (_head.global_position - global_position).dot(global_basis.z.normalized())

## Hauteur du terrain sous [param pos], ou -INF si inconnue
## (pas de terrain assigné, trou dans le terrain, hors de la carte).
func get_ground_height(pos: Vector3) -> float:
	if simulation.terrain == null:
		return -INF
	# Terrain3D renvoie NAN dans les trous et hors des régions peintes
	var h := simulation.terrain.data.get_height(pos)
	return -INF if is_nan(h) else h

## Renvoie true si aucun obstacle ne coupe le segment [param from] → [param to].
## Sert à ScoutState pour écarter les segments qui traversent un arbre ou la ruche.
func is_path_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, simulation.obstacle_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# =============================================================================
# Source connue (appelé par les états)
# =============================================================================

## Mémorise [param flower] comme source. [param dancer] : danseuse suivie en WATCH,
## null pour une source trouvée en exploration. La rentabilité est inconnue
## tant que la source n'a pas été évaluée au déchargement.
func learn_source(flower: Flower, dancer: Bee = null) -> void:
	known_flower = flower
	known_profitability = 0.0
	recruited_by = dancer

## Oublie la source connue (vide, ou jugée trop peu rentable).
func forget_source() -> void:
	known_flower = null
	known_profitability = 0.0
	recruited_by = null

# =============================================================================
# Animation (appelé par les états)
# =============================================================================

## Joue [param anim_name] depuis un point aléatoire, pour que les abeilles
## ne battent pas des ailes en parfaite synchronisation.
func play_animation(anim_name: StringName) -> void:
	# Toute demande explicite annule la file : sans ça, un _bee_hover mis en file
	# au décollage pourrait démarrer après _bee_landing si le vol est très court
	_anim.clear_queue()
	_anim.speed_scale = 1.0
	if _anim.current_animation == anim_name:
		return
	_anim.play(anim_name)
	if _anim.get_animation(anim_name).loop_mode != Animation.LOOP_NONE:
		_anim.seek(randf() * _anim.current_animation_length, true)

## Joue _bee_walk à la cadence qui correspond à la vitesse réelle, ou _bee_idle à l'arrêt.
## [param speed_factor] multiplie walk_speed, comme dans walk_towards().
func play_walk(speed_factor: float) -> void:
	if speed_factor < WALK_MIN_FACTOR:
		play_animation(&"_bee_idle")
		return
	play_animation(&"_bee_walk")
	# Cadence des pattes = vitesse réelle / vitesse de l'animation à speed_scale = 1
	_anim.speed_scale = simulation.walk_speed * speed_factor / _walk_anim_world_speed

## Met [param anim_name] en file d'attente : elle démarrera à la fin de l'animation en cours
## (qui ne doit donc pas être bouclée). Sert à enchaîner _bee_takeoff puis _bee_hover.
func queue_animation(anim_name: StringName) -> void:
	_anim.queue(anim_name)

# =============================================================================
# Pelotes de pollen (appelé par les états)
# =============================================================================

## Applique le matériau de [param flower] aux deux pelotes.
## material_override ne modifie pas la ressource : chaque abeille pointe
## simplement vers l'un des trois matériaux partagés.
func set_pollen_from(flower: Flower) -> void:
	for p in _pollen:
		p.material_override = flower.pollen_material

## Met à jour les pelotes selon le remplissage de l'abeille (entre 0 et 1).
## À appeler après chaque récolte (FORAGE) et après le déchargement (UNLOAD).
func update_pollen() -> void:
	var ratio := clampf(nectar / simulation.forage_capacity, 0.0, 1.0)

	# Un tween précédent encore actif écraserait la nouvelle taille
	if _pollen_tween != null and _pollen_tween.is_valid():
		_pollen_tween.kill()

	# Abeille vide : pelotes masquées, sans animation
	if ratio <= 0.0:
		for p in _pollen:
			p.visible = false
		return

	# Fraction de la taille maximale correspondant à la charge
	var factor := lerpf(POLLEN_MIN_SCALE, 1.0, ratio)
	_pollen_tween = create_tween().set_parallel()
	for i in _pollen.size():
		var p := _pollen[i]
		var full := _pollen_full_scale[i]
		# Première apparition : la pelote part de la moitié de la taille minimale
		if not p.visible:
			p.scale = full * POLLEN_MIN_SCALE * 0.5
			p.visible = true
		_pollen_tween.tween_property(p, "scale", full * factor, POLLEN_GROW_TIME)

# =============================================================================
# Utilitaires internes
# =============================================================================

# --- Vol ---

## Point à viser à cette frame pour aller vers [param target] sans traverser
## d'obstacle ni le sol.
func _flight_goal(target: Vector3) -> Vector3:
	var to_target := target - global_position
	var dist := to_target.length()
	if dist < 0.000001:
		return target
	var look := simulation.obstacle_look_ahead

	# Point visé si rien ne gêne : à courte distance sur la ligne droite,
	# relevé au-dessus du sol (hauteur de croisière loin de la cible)
	var goal := target if dist <= look else global_position + to_target / dist * look
	goal = _above_ground(goal, target)

	# Rayon vers CE point, et non vers la cible : c'est là que l'abeille va réellement.
	# Il s'arrête un peu avant la cible : la planche d'envol fait partie de la ruche,
	# il ne faut pas qu'elle soit vue comme un obstacle au moment d'atterrir.
	var to_goal := goal - global_position
	var reach := minf(to_goal.length(), dist - simulation.obstacle_clearance)
	if reach <= 0.0:
		return goal
	var dir := to_goal.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + dir * reach, simulation.obstacle_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return goal

	# Obstacle : on glisse le long de la surface touchée
	var normal: Vector3 = hit.normal
	var along := dir.slide(normal)
	# Obstacle pile en face : le glissement est quasi nul, on contourne par le côté
	if along.length_squared() < 0.01:
		along = normal.cross(Vector3.UP) * _avoid_side
		# Surface horizontale (dessous du toit, par exemple) : autre axe de secours
		if along.length_squared() < 0.01:
			along = normal.cross(Vector3.RIGHT)
	var detour: Vector3 = hit.position + normal * simulation.obstacle_clearance \
			+ along.normalized() * look

	# Pas de relèvement à la hauteur de croisière : il ferait repasser le détour
	# à travers l'obstacle. On garantit seulement de ne pas passer sous le sol.
	detour.y = maxf(detour.y, get_ground_height(detour) + simulation.ground_clearance)
	return detour

## Relève [param point] à la hauteur minimale de vol au-dessus du sol. Cette hauteur
## diminue à l'approche de [param target], pour que l'abeille puisse descendre se poser.
func _above_ground(point: Vector3, target: Vector3) -> Vector3:
	var ground := get_ground_height(point)
	if ground == -INF:
		return point
	# Distance horizontale restante jusqu'à la cible : 0 dessus, 1 au-delà de descent_distance
	var horizontal := Vector2(target.x - point.x, target.z - point.z).length()
	var t := clampf(horizontal / simulation.descent_distance, 0.0, 1.0)
	var min_y := ground + lerpf(simulation.ground_clearance, simulation.cruise_height, t)
	point.y = maxf(point.y, min_y)
	return point

## Incline le modèle dans les virages, proportionnellement à la vitesse de lacet.
## Purement visuel : la trajectoire n'est pas modifiée.
func _update_bank(delta: float) -> void:
	# Avant de l'abeille ramené à l'horizontale (avant du modèle sur +Z)
	var forward := global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx() or delta <= 0.0:
		return
	forward = forward.normalized()

	# Vitesse de lacet (rad/s) : angle tourné autour de la verticale depuis l'image précédente.
	# Positive pour un virage à gauche (sens trigonométrique vu de dessus).
	var yaw_rate := 0.0
	if _prev_forward != Vector3.ZERO:
		yaw_rate = _prev_forward.signed_angle_to(forward, Vector3.UP) / delta
	_prev_forward = forward

	# Virage à gauche → aile gauche vers le bas. Si l'abeille penche
	# du mauvais côté, inverser le signe.
	var target := clampf(-yaw_rate * BANK_GAIN, -MAX_BANK, MAX_BANK)
	_bank = lerpf(_bank, target, 1.0 - exp(-BANK_SMOOTHING * delta))

	# Rotation autour de l'axe avant (+Z) de Bee, appliquée par-dessus l'orientation d'origine
	_model.transform.basis = Basis(Vector3.BACK, _bank) * _model_base_basis

	# Même rotation autour de l'axe avant de Bee, atténuée pour la caméra.
	# Seule l'orientation change : la position de l'œil reste celle réglée dans bee.tscn.
	_camera_anchor.transform.basis = Basis(Vector3.BACK, _bank * CAMERA_BANK_FACTOR) * _camera_anchor_base_basis

# --- Orientation ---

## Avance d'au plus [param step] vers [param target], en s'orientant progressivement
## dans la direction du mouvement avec [param up] comme vecteur haut.
## [param step] est déjà multiplié par delta ; [param delta] sert à la rotation.
func _move_towards(target: Vector3, step: float, up: Vector3, delta: float) -> void:
	var to_target := target - global_position
	# Presque sur la cible : on finit d'avancer sans tourner, car la direction
	# d'un vecteur quasi nul n'a pas de sens pour l'orientation
	if to_target.length_squared() >= 0.000001:
		_face(to_target, up, delta)
	# move_toward ne dépasse jamais la cible : pas d'oscillation à l'arrivée,
	# et la cible est atteinte exactement
	global_position = global_position.move_toward(target, step)

## [param max_rate] : vitesse angulaire maximale (rad/s). INF = lissage seul (marche).
func _face(direction: Vector3, up: Vector3, delta: float, max_rate := INF) -> void:
	var dir := direction.normalized()
	# Basis.looking_at échoue si la direction est parallèle au vecteur haut
	# (vol vertical, ou cible hors du plan du cadre) : on prend alors un vecteur de secours
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP

	# Orientation visée. true : +Z comme avant du modèle au lieu de -Z (convention Godot)
	var target_rot := Basis.looking_at(dir, up, true).get_rotation_quaternion()
	var current_rot := global_basis.get_rotation_quaternion()

	# Interpolation indépendante du framerate : 1 - exp(-k·delta) donne la même
	# vitesse de rotation à 30 ou à 144 images par seconde
	var weight := 1.0 - exp(-simulation.turn_speed * delta)
	# Le lissage exponentiel seul tourne d'autant plus vite que l'écart est grand :
	# on plafonne la vitesse angulaire pour éviter les coups secs.
	# angle_to renvoie l'angle de rotation entre les deux orientations (0 à π).
	# (gap et non angle : angle est déjà une variable membre de Bee)
	var gap := current_rot.angle_to(target_rot)
	if gap > 0.0001:
		weight = minf(weight, max_rate * delta / gap)

	# On travaille en quaternions (rotation seule), puis on réapplique l'échelle
	# du nœud pour ne pas la perdre si l'abeille est mise à l'échelle dans bee.tscn
	var s := global_basis.get_scale()
	global_basis = Basis(current_rot.slerp(target_rot, weight)) * Basis.from_scale(s)

# --- Son ---

## Allume, fond et coupe le bourdonnement individuel. L'abeille bourdonne dehors
## tant qu'elle bat des ailes :
##   - en vol : vitesse non nulle, de la fin du décollage jusqu'au land() de la pose
##     (approche finale et stationnaire devant la fleur compris) ;
##   - au décollage, où la vitesse est encore nulle : animation _bee_takeoff ;
##   - posée mais en stationnaire (ForageState, prélèvement refusé) : animation _bee_hover.
## Dans la ruche, le son individuel reste coupé : le bourdonnement collectif de Hive le remplace.
func _update_buzz(delta: float) -> void:
	# La vitesse seule ne suffit pas : nulle pendant tout le décollage.
	# L'animation seule non plus : _bee_landing n'est pas bouclée et peut finir
	# pendant le stationnaire devant la fleur, ailes encore battantes.
	var flapping := current_state is FieldState \
			and (not is_landed() or _anim.current_animation in WING_ANIMS)
	var target_db := _buzz_on_db if flapping else BUZZ_OFF_DB

	# Début du battement : on part du silence, à un point aléatoire de la boucle
	# pour que les abeilles ne bourdonnent pas en phase
	if flapping and not _buzz.playing:
		_buzz.volume_db = BUZZ_OFF_DB
		_buzz.play(randf() * _buzz.stream.get_length())

	if _buzz.playing:
		# Fondu indépendant de la fréquence d'images (même formule que pour l'orientation)
		var w := 1.0 - exp(-BUZZ_FADE_SPEED * delta)
		_buzz.volume_db = lerpf(_buzz.volume_db, target_db, w)
		# Ailes au repos et son quasi éteint : on libère le lecteur
		if not flapping and _buzz.volume_db < BUZZ_OFF_DB + 1.0:
			_buzz.stop()
