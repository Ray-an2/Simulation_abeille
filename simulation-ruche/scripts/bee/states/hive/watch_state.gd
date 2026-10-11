class_name WatchState extends HiveState
## Suivi d'une danse : l'abeille court derrière la danseuse pour mémoriser la source
## annoncée. Si elle reste au contact assez longtemps, elle copie la source et sort
## la butiner (→ GO) ; si la danse s'arrête avant, ou si elle perd la danseuse,
## elle retourne attendre (→ IDLE).
##
## Comportement réel repris ici (Rohrseitz et Tautz, 1999) : en début de course,
## les suiveuses sont réparties autour de la danseuse ; en fin de course, toutes se
## trouvent dans un arc de ±60° derrière elle. Pendant la boucle de retour, elles la
## suivent en restant au contact des antennes. Suivre de côté ou de derrière donne
## la même précision (Tanner et Visscher, 2008) : seul le temps passé au contact compte.
##
## Entrée : IDLE appelle « return bee.watch.follow(danseuse) ».
## Le déplacement passe par le walker : l'évitement maintient environ une longueur
## d'abeille entre suiveuse et danseuse, et entre suiveuses.

# =============================================================================
# Constantes
# =============================================================================

## Distance (m) visée entre le centre de la suiveuse et celui de la danseuse :
## un peu moins d'une longueur d'abeille, l'évitement fait le reste.
const FOLLOW_DISTANCE := 0.013

## Demi-ouverture (rad) de l'arc derrière la danseuse où la suiveuse se place (±60°).
const REAR_ARC := PI / 3.0

## Distance (m) au point visé en dessous de laquelle la suiveuse s'arrête.
const SLOT_RADIUS := 0.003

## Gain de vitesse : facteur de walk_speed par mètre d'écart au point visé.
## À 1 cm, la suiveuse marche à walk_speed ; plus loin, elle accélère.
const CATCH_UP_GAIN := 100.0

## Facteur de vitesse maximal pour rattraper la danseuse, qui fait sa boucle
## de retour à environ walk_speed.
const MAX_SPEED := 1.6

## Vitesse de virage (rad/s) vers le point visé : élevée, la danseuse tourne vite.
const STEER_RATE := 8.0

## Distance (m) au centre de la danseuse en dessous de laquelle la suiveuse
## est considérée au contact (corps + antennes).
const CONTACT_RADIUS := 0.025

## Temps (s) hors contact au-delà duquel la suiveuse abandonne.
const LOST_TIMEOUT := 3.0

# =============================================================================
# État interne
# =============================================================================

## Danseuse suivie, fixée par follow() juste avant l'entrée dans l'état.
var _dancer: Bee = null

## Temps (s) passé au contact de la danseuse.
var _contact_time := 0.0

## Temps (s) écoulé depuis le dernier contact.
var _lost_time := 0.0

## Angle de la place visée derrière la danseuse (0 = pile derrière), tiré à l'entrée :
## les suiveuses se répartissent dans l'arc au lieu de viser toutes le même point.
var _slot_angle := 0.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

## Fixe la danseuse à suivre et renvoie l'état lui-même, pour pouvoir écrire
## « return bee.watch.follow(dancer) » dans IDLE (même principe que LeaveState.then()).
func follow(dancer: Bee) -> WatchState:
	_dancer = dancer
	return self

func enter() -> void:
	assert(_dancer != null, "WatchState : danseuse non définie, utiliser follow()")
	_contact_time = 0.0
	_lost_time = 0.0
	_slot_angle = randf_range(-REAR_ARC, REAR_ARC)
	_reset_wander()
	# Compte parmi les suiveuses : IDLE n'envoie plus personne à une danseuse complète
	bee.hive.add_follower(_dancer)

func exit() -> void:
	if is_instance_valid(_dancer):
		bee.hive.remove_follower(_dancer)
	# Pas de référence gardée : la danseuse peut repartir, voire être supprimée
	_dancer = null

func update(delta: float) -> BeeState:
	var hive := bee.hive

	# Danse terminée (ou danseuse disparue) avant mémorisation : retour à l'attente
	if not is_instance_valid(_dancer) or not hive.is_dancing(_dancer):
		return bee.idle

	# Contact : seul le temps passé contre la danseuse compte pour mémoriser
	if bee.is_near(_dancer.global_position, CONTACT_RADIUS):
		_contact_time += delta
		_lost_time = 0.0
	else:
		_lost_time += delta
		if _lost_time > LOST_TIMEOUT:
			return bee.idle

	# Source mémorisée : l'abeille la copie et sort la butiner
	if _contact_time >= bee.simulation.watch_min_duration:
		# learn_source() retient aussi la danseuse (chaîne de recrutement) et remet
		# la rentabilité à zéro : inconnue tant que le trajet n'est pas fait, UNLOAD l'évaluera
		bee.learn_source(hive.get_dance_flower(_dancer), _dancer)
		return go_out_if_day(bee.go)

	_move_to_slot(delta)
	return null

# =============================================================================
# Lecture (appelé par l'interface)
# =============================================================================

## Danseuse suivie, ou null hors de l'état.
func get_dancer() -> Bee:
	return _dancer if is_instance_valid(_dancer) else null

## Temps (s) passé au contact de la danseuse depuis l'entrée dans l'état.
## C'est lui, et non le temps passé dans l'état, qui doit atteindre watch_min_duration.
func get_contact_time() -> float:
	return _contact_time

# =============================================================================
# Utilitaires internes
# =============================================================================

## Rejoint la place visée derrière la danseuse, à une vitesse qui croît avec l'écart.
func _move_to_slot(delta: float) -> void:
	var slot := _slot_position()
	var dist := bee.global_position.distance_to(slot)

	var speed := 0.0
	if dist > SLOT_RADIUS:
		speed = clampf(dist * CATCH_UP_GAIN, 0.0, MAX_SPEED)
		bee.walker.steer_towards(slot, STEER_RATE, delta)
	else:
		# En place : on tourne le cap vers la danseuse, pour repartir dans sa direction
		bee.walker.steer_towards(_dancer.global_position, STEER_RATE, delta)

	# Appelé aussi à l'arrêt (vitesse visée 0) : l'abeille finit de freiner
	bee.walker.step(speed, delta)

## Point visé : à FOLLOW_DISTANCE derrière la danseuse, décalé de _slot_angle
## autour de la normale du cadre. Suit la danseuse quand elle tourne en boucle.
func _slot_position() -> Vector3:
	var normal := bee.hive.get_comb_normal()
	# Avant de l'abeille : +Z (Basis.looking_at(..., true) dans Bee._face)
	var back := -_dancer.global_basis.z.slide(normal)
	if back.is_zero_approx():
		back = (bee.global_position - _dancer.global_position).slide(normal)
	back = back.normalized().rotated(normal, _slot_angle)
	return bee.hive.clamp_to_comb(_dancer.global_position + back * FOLLOW_DISTANCE)
