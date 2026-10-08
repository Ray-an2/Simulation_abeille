class_name Bee extends Node3D
## Agent abeille ouvrière, piloté par une machine à états hiérarchique.

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

## Quantité de nectar transportée. Remplie en FORAGE, vidée en UNLOAD.
var nectar: float = 0.0

## Source mémorisée : apprise en WATCH, ou trouvée en SCOUT. Cible de l'état GO.
## [code]null[/code] si l'abeille ne connaît aucune source.
var known_flower: Flower = null

## Rentabilité de [member known_flower] (entre 0 et 1), évaluée en UNLOAD.
## Détermine la transition suivante (DANCE, GO ou IDLE) et la durée de la danse.
var known_profitability: float = 0.0

# =============================================================================
# États
# =============================================================================

# Attente dans la ruche (jaune). État initial.
var idle: IdleState

## Exploration à la recherche d'une fleur, avec timeout.
var scout: ScoutState

## État actif. Son [method BeeState.update] est appelé à chaque frame physique.
var current_state: BeeState

## État de retour à la ruche
var return_home: ReturnState

# =============================================================================
# Cycle de vie
# =============================================================================

## Crée les huit états et active l'état initial IDLE.
func _ready() -> void:
	assert(hive != null and simulation != null,
		"Bee '%s' : hive=%s, simulation=%s — doivent être assignés avant add_child()"
		% [name, hive, simulation])
	idle = IdleState.new(self)
	scout = ScoutState.new(self)
	return_home = ReturnState.new(self)
	# Hauteur légèrement différente par abeille : évite l'effet « 200 clones »
	_buzz.pitch_scale = randf_range(0.9, 1.1)
	change_state(idle)

## Exécute l'état courant et applique la transition qu'il renvoie, le cas échéant.
func _physics_process(delta: float) -> void:
	if current_state == null:
		return
	var next: BeeState = current_state.update(delta)
	if next != null:
		change_state(next)

## Quitte l'état courant ([method BeeState.exit]) puis entre dans [param next]
## ([method BeeState.enter]). Seul point de passage de toutes les transitions.
func change_state(next: BeeState) -> void:
	# Super-état avant / après : seul un passage Ruche ↔ Dehors nous intéresse
	var was_inside := current_state is HiveState   # false au premier appel (null)
	var is_inside := next is HiveState
	
	if current_state != null:
		current_state.exit()
	current_state = next
	
	if is_inside != was_inside:
		_on_location_changed(is_inside)
		
	current_state.enter()

## Prévient la ruche et allume/coupe le bourdonnement individuel.
func _on_location_changed(inside: bool) -> void:
	if inside:
		hive.bee_entered()
		_buzz.stop()
	else:
		hive.bee_left()
		# Départ aléatoire dans la boucle : les abeilles ne sont pas en phase
		_buzz.play(randf() * _buzz.stream.get_length())

# =============================================================================
# Déplacement (appelé par les états)
# =============================================================================

## Vole en ligne droite vers [param target] à la vitesse [member Simulation.fly_speed].
## À appeler à chaque update() tant que la cible n'est pas atteinte.
## Le haut de l'abeille reste aligné sur la verticale du monde.
func fly_towards(target: Vector3, delta: float) -> void:
	_move_towards(target, simulation.fly_speed * delta, Vector3.UP, delta)

## Marche vers [param target] à la vitesse [member Simulation.walk_speed],
## multipliée par [param speed_factor].
## Réservé aux états du super-état Ruche.
## [param up] est la normale de la surface parcourue : passer
## [method Hive.get_comb_normal] pour que l'abeille reste à plat sur le cadre.
func walk_towards(target: Vector3, delta: float, up: Vector3 = Vector3.UP, speed_factor: float = 1.0) -> void:
	_move_towards(target, simulation.walk_speed * speed_factor * delta, up, delta)
	
## Renvoie [code]true[/code] si l'abeille est à moins de [param radius] de [param target].
## Sert de test d'arrivée pour GO, RETURN, etc.
func is_near(target: Vector3, radius: float) -> bool:
	# Comparaison des carrés : évite une racine carrée à chaque appel
	return global_position.distance_squared_to(target) <= radius * radius
	
# =============================================================================
# Animation (appelé par les états)
# =============================================================================

## Joue [param anim_name] depuis un point aléatoire, pour que les abeilles
## ne battent pas des ailes en parfaite synchronisation.
func play_animation(anim_name: StringName) -> void:
	if _anim.current_animation == anim_name:
		return
	_anim.play(anim_name)
	if _anim.get_animation(anim_name).loop_mode != Animation.LOOP_NONE:
		_anim.seek(randf() * _anim.current_animation_length, true)
		
# =============================================================================
# Son et présence dans la ruche (appelé par change_state)
# =============================================================================
	
## Joue le bourdonnement dans les états « Dehors », le coupe dans la ruche
## (où un son collectif posé sur Hive prend le relais).
func _update_buzz() -> void:
	var flying := current_state is FieldState
	# Rien à faire si le son est déjà dans le bon état (ex. SCOUT → FORAGE)
	if flying == _buzz.playing:
		return
	if flying:
		# Départ à un point aléatoire de la boucle : les abeilles ne sont pas en phase
		_buzz.play(randf() * _buzz.stream.get_length())
	else:
		_buzz.stop()
	
# =============================================================================
# Utilitaires internes
# =============================================================================
	
## Avance d'au plus [param step] vers [param target], en s'orientant progressivement
## dans la direction du mouvement avec [param up] comme vecteur haut.
## [param step] est déjà multiplié par delta ; [param delta] sert à la rotation.
func _move_towards(target: Vector3, step: float, up: Vector3, delta: float) -> void:
	var to_target := target - global_position
	# Déjà sur la cible : on ne bouge pas, et on évite un look_at sur un vecteur nul
	if to_target.length_squared() < 0.000001:
		return
	_face(to_target, up, delta)
	# move_toward ne dépasse jamais la cible : pas d'oscillation à l'arrivée
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
