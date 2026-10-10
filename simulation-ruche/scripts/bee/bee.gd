class_name Bee extends Node3D
## Agent abeille ouvrière, piloté par une machine à états hiérarchique.

# =============================================================================
# Constantes
# =============================================================================

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

# =============================================================================
# Pelotes de pollen (indicateur visuel de charge)
# =============================================================================

## Durée (s) de l'animation de croissance des pelotes après chaque visite.
const POLLEN_GROW_TIME := 0.8

## Taille des pelotes pour une charge minimale (fraction de leur taille maximale).
const POLLEN_MIN_SCALE := 0.3

## Pelotes de pollen, enfants des BoneAttachment3D des pattes arrière.
## On agit sur elles et non sur les attachements, dont la transformation
## est imposée par l'os à chaque frame.
@onready var _pollen: Array[MeshInstance3D] = [
	$BonePollenLeft/PollenBall,
	$BonePollenRight/PollenBall,
]

## Tween en cours sur les pelotes, pour l'interrompre si la charge change de nouveau.
var _pollen_tween: Tween

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

## Lecteur d'animations du modèle glTF (hover, idle, take_off_and_land).
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer

## Bourdonnement individuel, audible uniquement en vol.
@onready var _buzz: AudioStreamPlayer3D = $Buzz

# =============================================================================
# Données partagées entre les états
# =============================================================================

## Locomotion sur le cadre (cap, vitesse, évitement), partagée par les états Ruche.
## Conservée d'un état à l'autre, réinitialisée à chaque arrivée dans la ruche.
var walker: CombWalker

## Vitesse de vol actuelle (m/s). Repart de 0 à chaque décollage et rejoint
## fly_speed avec fly_acceleration ; diminue à l'approche de la cible.
var _flight_speed := 0.0

## Vitesse d'avance (m/s) du corps dans _bee_walk à speed_scale = 1, en unités du monde.
## Calculée une fois dans _ready() : l'échelle du modèle ne change pas pendant la simulation.
var _walk_anim_world_speed := 0.0

## Sens de contournement préféré (+1 ou -1), tiré à la création : face à un obstacle
## pile dans l'axe, les abeilles se répartissent des deux côtés au lieu de partir toutes à gauche.
var _avoid_side := 1.0

## Quantité de nectar transportée. Remplie en FORAGE, vidée en UNLOAD.
var nectar: float = 0.0

## Source mémorisée : apprise en WATCH, ou trouvée en SCOUT. Cible de l'état GO.
## [code]null[/code] si l'abeille ne connaît aucune source.
var known_flower: Flower = null

## Rentabilité de [member known_flower] (entre 0 et 1), évaluée en UNLOAD.
## Détermine la transition suivante (DANCE, GO ou IDLE) et la durée de la danse.
var known_profitability: float = 0.0

## Durée du trajet en cours hors de la ruche
var trip_time: float = 0.0

## Distance à plat ruche -> source
var distance: float = 0.0

## Angle (rad) entre la direction du soleil et celle de la source, vu de la ruche.
## Calculé en UNLOAD, encodé par DANCE dans l'orientation de la phase frétillante.
var angle: float = 0.0

# =============================================================================
# États
# =============================================================================

# Attente dans la ruche (jaune). État initial.
var idle: IdleState

## Sortie à pied jusqu'à la planche d'envol, puis décollage (voir LeaveState.then()).
var leave_hive: LeaveState

## Entrée à pied de la planche d'envol jusqu'au cadre.
var enter_hive: EnterState

## Exploration à la recherche d'une fleur, avec timeout.
var scout: ScoutState

## État actif. Son [method BeeState.update] est appelé à chaque frame physique.
var current_state: BeeState

## État de retour à la ruche
var return_home: ReturnState

## Décharge le nectar dans la ruche
var unload: UnloadState

## Vol en direction d'une source connue
var go: GoState

## Butine une source
var forage: ForageState

# =============================================================================
# Cycle de vie
# =============================================================================

## Crée les huit états et active l'état initial IDLE.
func _ready() -> void:
	assert(hive != null and simulation != null,
		"Bee '%s' : hive=%s, simulation=%s — doivent être assignés avant add_child()"
		% [name, hive, simulation])
	idle = IdleState.new(self)
	leave_hive = LeaveState.new(self)
	enter_hive = EnterState.new(self)
	scout = ScoutState.new(self)
	return_home = ReturnState.new(self)
	walker = CombWalker.new(self)
	unload = UnloadState.new(self)
	go = GoState.new(self)
	forage = ForageState.new(self)
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
	
	_avoid_side = 1.0 if randf() < 0.5 else -1.0
	
	# Abeille vide au départ : pelotes masquées
	update_pollen()
	
	change_state(idle)

## Exécute l'état courant et applique la transition qu'il renvoie, le cas échéant.
func _physics_process(delta: float) -> void:
	if current_state == null:
		return
	# Chronomètre du trajet : temps passé dehors, remis à zéro par UNLOAD
	# après évaluation de la source
	if current_state is FieldState:
		trip_time += delta
	var next: BeeState = current_state.update(delta)
	if next != null:
		change_state(next)

## Quitte l'état courant ([method BeeState.exit]) puis entre dans [param next]
## ([method BeeState.enter]). Seul point de passage de toutes les transitions.
## Prévient aussi la ruche et le son quand l'abeille passe de Ruche à Dehors ou l'inverse.
func change_state(next: BeeState) -> void:
	# Super-état avant / après : seul un passage Ruche ↔ Dehors nous intéresse
	var was_inside := current_state is HiveState   # false au premier appel (null)
	var is_inside := next is HiveState

	if current_state != null:
		current_state.exit()
	current_state = next

	# Fait avant enter() pour que l'état puisse déjà interroger ses voisines
	if is_inside != was_inside:
		_on_location_changed(is_inside)

	current_state.enter()

## Prévient la ruche, réinitialise la marche et allume/coupe le bourdonnement individuel.
func _on_location_changed(inside: bool) -> void:
	# Passage Ruche ↔ Dehors : toujours posée sur la planche d'envol
	land()
	if inside:
		hive.bee_entered(self)
		# Arrivée sur le cadre : l'abeille repart immobile, dans la direction où elle regarde
		walker.reset()
		_buzz.stop()
	else:
		hive.bee_left(self)
		# Départ aléatoire dans la boucle : les abeilles ne sont pas en phase
		_buzz.play(randf() * _buzz.stream.get_length())

## Retire l'abeille de la ruche si elle est supprimée alors qu'elle y est.
func _exit_tree() -> void:
	if current_state is HiveState:
		hive.bee_left(self)

# =============================================================================
# Déplacement (appelé par les états)
# =============================================================================

## Vole vers [param target] : le corps tourne progressivement vers le point visé
## et l'abeille avance dans l'axe de son corps. Contourne les obstacles, reste au-dessus du sol.
## À appeler à chaque update() tant que la cible n'est pas atteinte.
func fly_towards(target: Vector3, delta: float) -> void:
	var goal := _flight_goal(target)
	var to_goal := goal - global_position
	var dist := global_position.distance_to(target)

	# --- Vitesse voulue ---
	# Plafond de freinage : vitesse maximale qui permet encore de s'arrêter sur la cible
	var brake_limit := sqrt(2.0 * simulation.fly_deceleration * dist)
	var wanted := clampf(brake_limit, simulation.landing_speed, simulation.fly_speed)
	# Cible derrière ou sur le côté : on ralentit pour virer serré.
	# Alignement ramené de [-1, 1] à [0, 1] : 1 droit devant, 0 pile derrière.
	var forward := global_basis.z.normalized()   # avant du modèle sur +Z (glTF)
	if not to_goal.is_zero_approx():
		var alignment := (forward.dot(to_goal.normalized()) + 1.0) * 0.5
		wanted *= lerpf(simulation.turning_speed_factor, 1.0, alignment)

	# La vitesse courante rejoint la vitesse voulue sans à-coup
	var rate := simulation.fly_acceleration if wanted > _flight_speed else simulation.fly_deceleration
	_flight_speed = move_toward(_flight_speed, wanted, rate * delta)

	# --- Orientation : le corps tourne vers le point visé, à turn_speed ---
	if to_goal.length_squared() >= 0.000001:
		_face(to_goal, Vector3.UP, delta)

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
	
## Renvoie [code]true[/code] si l'abeille est à moins de [param radius] de [param target].
## Sert de test d'arrivée pour GO, RETURN, etc.
func is_near(target: Vector3, radius: float) -> bool:
	# Comparaison des carrés : évite une racine carrée à chaque appel
	return global_position.distance_squared_to(target) <= radius * radius

## Se déplace vers [param target] à [param speed] m/s, sans s'orienter dans le sens
## du mouvement : l'abeille tourne progressivement pour regarder vers [param facing],
## avec [param up] comme vecteur haut. Sert aux petits sauts entre le bas du cadre
## et le plancher, où elle se retourne en tombant.
func hop_towards(target: Vector3, speed: float, facing: Vector3, up: Vector3, delta: float) -> void:
	_face(facing, up, delta)
	# move_toward ne dépasse jamais la cible : arrivée exacte
	global_position = global_position.move_toward(target, speed * delta)

## Remet la vitesse de vol à zéro. À appeler dès que l'abeille est posée
## (fleur, planche d'envol) : le prochain vol repartira d'un décollage.
func land() -> void:
	_flight_speed = 0.0
	
# =============================================================================
# Animation (appelé par les états)
# =============================================================================

## Joue _bee_walk à la cadence qui correspond à la vitesse réelle, ou _bee_idle à l'arrêt.
## [param speed_factor] multiplie walk_speed, comme dans walk_towards().
func play_walk(speed_factor: float) -> void:
	if speed_factor < WALK_MIN_FACTOR:
		play_animation(&"_bee_idle")
		return
	play_animation(&"_bee_walk")
	# Cadence des pattes = vitesse réelle / vitesse de l'animation à speed_scale = 1
	_anim.speed_scale = simulation.walk_speed * speed_factor / _walk_anim_world_speed

## Joue [param anim_name] depuis un point aléatoire, pour que les abeilles
## ne battent pas des ailes en parfaite synchronisation.
func play_animation(anim_name: StringName) -> void:
	_anim.speed_scale = 1.0
	if _anim.current_animation == anim_name:
		return
	_anim.play(anim_name)
	if _anim.get_animation(anim_name).loop_mode != Animation.LOOP_NONE:
		_anim.seek(randf() * _anim.current_animation_length, true)

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

	var target := Vector3.ONE * lerpf(POLLEN_MIN_SCALE, 1.0, ratio)
	_pollen_tween = create_tween().set_parallel()
	for p in _pollen:
		# Première apparition : la pelote part de la moitié de la taille minimale
		if not p.visible:
			p.scale = Vector3.ONE * POLLEN_MIN_SCALE * 0.5
			p.visible = true
		_pollen_tween.tween_property(p, "scale", target, POLLEN_GROW_TIME)
	
# =============================================================================
# Utilitaires internes
# =============================================================================
	
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
	
## Tourne progressivement l'abeille vers [param direction], avec [param up] comme vecteur
## haut (avant du modèle sur +Z, convention glTF).
func _face(direction: Vector3, up: Vector3, delta: float) -> void:
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

	# On travaille en quaternions (rotation seule), puis on réapplique l'échelle
	# du nœud pour ne pas la perdre si l'abeille est mise à l'échelle dans bee.tscn
	var s := global_basis.get_scale()
	global_basis = Basis(current_rot.slerp(target_rot, weight)) * Basis.from_scale(s)
