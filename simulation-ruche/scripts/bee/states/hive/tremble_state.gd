class_name TrembleState extends HiveState
## Danse trémulante : une butineuse revenue d'une bonne source, mais qui a mis très
## longtemps à trouver une receveuse, parcourt le cadre en tremblant. Elle signale
## que la colonie récolte plus qu'elle ne peut traiter (Seeley 1992).
##
## Déclenchement (UnloadState) : recherche d'une receveuse d'au moins
## tremble_wait_threshold secondes, pour une source qu'elle aurait annoncée par
## une danse frétillante si la ruche n'était pas saturée.
## Mesures de Seeley (1992) : recherche de moins de 20 s → danse frétillante,
## de plus de 50 s → danse trémulante, entre les deux, ni l'une ni l'autre.
## Sortie : GO (elle retourne butiner sa source), ou IDLE la nuit (go_out_if_day).
##
## Deux effets, tous deux locaux :
##   - recrutement de receveuses : une abeille en IDLE sans source, au contact d'une
##     trémulante, devient receveuse avec la probabilité tremble_recruit_rate par
##     seconde au lieu de p_receive (IdleState). Seeley et al. (1996) ont mesuré
##     une hausse de 17 % à 30-50 % de receveuses après les danses trémulantes ;
##   - signal d'arrêt : la trémulante qui croise une danseuse frétillante sur la piste
##     peut lui donner un bref coup de tête vibrant, qui écourte sa danse
##     (DanceState.receive_stop_signal, Kirchner 1993 ; Nieh 1993).
## Les deux vont dans le même sens : plus de capacité de traitement, moins de
## recrutement de nouvelles butineuses. C'est une boucle négative sur la saturation.
##
## Mouvement (Seeley 1992) : marche lente sur le cadre, corps secoué d'avant en arrière
## et de côté, axe du corps tourné d'environ 50° à peu près toutes les secondes.
## Les fréquences et amplitudes du tremblement ne sont pas mesurées : valeurs de réglage.
##
## Simplifications :
##   - la danse commence après le déchargement. En réalité, une trémulante peut
##     commencer avant d'avoir trouvé une receveuse ;
##   - seule la cause « attente au déchargement » est modélisée. En conditions
##     naturelles, environ la moitié des danses trémulantes ont d'autres causes
##     (Thom et al. 2003) ;
##   - durée raccourcie : la durée moyenne mesurée est de 30 min, ramenée ici
##     à tremble_duration pour rester cohérente avec la danse frétillante
##     (dance_duration_max), qui n'est pas non plus à l'échelle réelle.

# =============================================================================
# Constantes
# =============================================================================

## Facteur de vitesse (multiplie walk_speed) : la trémulante marche lentement.
## Valeur de réglage, non mesurée.
const WALK_SPEED := 0.3

## Rotation de l'axe du corps (rad) à chaque virage : environ 50° (Seeley 1992).
const TURN_ANGLE := 0.87

## Intervalle (s) entre deux virages, tiré entre ces bornes : « à peu près toutes
## les secondes » (Seeley 1992).
const TURN_INTERVAL_MIN := 0.7
const TURN_INTERVAL_MAX := 1.3

## Tremblement latéral : rotation du corps autour de la normale du cadre.
## Somme de deux sinusoïdes de fréquences non multiples : l'oscillation est irrégulière,
## à l'œil bien différente du frétillement régulier de la danse frétillante.
## Doit rester sous la moitié de la fréquence physique.
## Valeurs de réglage, non mesurées.
const SHAKE_FREQUENCY := 9.0
const SHAKE_AMPLITUDE := 0.15

## Tremblement d'avant en arrière : petit déplacement le long de l'axe du corps (m).
## Valeurs de réglage, non mesurées.
const SURGE_FREQUENCY := 6.0
const SURGE_AMPLITUDE := 0.0008

## Écart relatif de durée d'une trémulante à l'autre (± 30 %) : elles ne s'arrêtent
## pas toutes au même moment.
const DURATION_SPREAD := 0.3

## Distance (m) en dessous de laquelle la trémulante peut donner un signal d'arrêt
## à une danseuse : au contact, une longueur d'abeille.
const STOP_SIGNAL_RADIUS := 0.015

## Durée (s) du signal d'arrêt : la trémulante s'arrête et se tourne vers la danseuse.
## Le signal réel est une vibration d'environ 150 ms ; on laisse un peu plus de temps
## pour que le geste se voie.
const STOP_SIGNAL_TIME := 0.4

## La recherche de danseuses ne se fait qu'une frame physique sur N.
const CHECK_STEP := 4

# =============================================================================
# État interne
# =============================================================================

## Durée tirée pour cette danse (s).
var _duration := 0.0

## Temps de danse restant (s).
var _remaining := 0.0

## Temps restant (s) avant le prochain virage de 50°.
var _turn_left := 0.0

## Normale du cadre, lue à l'entrée.
var _normal := Vector3.ZERO

## Temps écoulé (s), pour la phase du tremblement.
var _shake_time := 0.0

## Rotation de tremblement actuellement appliquée au corps (rad).
var _shake_yaw := 0.0

## Décalage de tremblement actuellement appliqué à la position (m).
var _shake_offset := Vector3.ZERO

## Temps restant (s) du signal d'arrêt en cours, 0 sinon.
var _signal_left := 0.0

## Danseuse qui reçoit le signal d'arrêt en cours.
var _signal_target: Bee = null

## Décalage propre à chaque abeille : les recherches sont étalées sur les frames.
var _check_offset := 0

## Signaux d'arrêt donnés pendant cette danse (interface).
var _stop_signals := 0

## Abeilles devenues receveuses à son contact pendant cette danse (interface).
var _recruits := 0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	_normal = bee.hive.get_comb_normal()
	_duration = bee.simulation.tremble_duration \
			* randf_range(1.0 - DURATION_SPREAD, 1.0 + DURATION_SPREAD)
	_remaining = _duration
	_turn_left = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
	_shake_time = 0.0
	_shake_yaw = 0.0
	_shake_offset = Vector3.ZERO
	_signal_left = 0.0
	_signal_target = null
	_check_offset = randi() % CHECK_STEP
	_stop_signals = 0
	_recruits = 0
	# Visible des abeilles en IDLE (recrutement de receveuses)
	bee.hive.start_tremble(bee)

func exit() -> void:
	bee.hive.stop_tremble(bee)
	_unshake()
	_signal_target = null
	# Le tremblement et le signal d'arrêt déplacent l'abeille sans le walker :
	# on le recale sur son orientation actuelle, comme en sortie de DANCE
	bee.walker.reset()

func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		# Retour à sa source, qu'elle juge toujours bonne
		return go_out_if_day(bee.go)

	# Le tremblement est retiré avant de déplacer l'abeille, puis réappliqué :
	# le walker part ainsi de l'orientation et de la position réelles
	_unshake()

	if _signal_left > 0.0:
		_update_stop_signal(delta)
	else:
		_try_stop_signal(delta)
		if _signal_left <= 0.0:
			_walk(delta)

	_shake(delta)
	return null

# =============================================================================
# Lecture (appelé par l'interface et par IdleState)
# =============================================================================

## Temps de danse restant (s).
func get_remaining() -> float:
	return maxf(_remaining, 0.0)

## Durée tirée pour cette danse (s).
func get_duration() -> float:
	return _duration

## Signaux d'arrêt donnés depuis le début de la danse.
func get_stop_signals() -> int:
	return _stop_signals

## Abeilles devenues receveuses à son contact depuis le début de la danse.
func get_recruits() -> int:
	return _recruits

## Une abeille en IDLE vient de devenir receveuse à son contact (IdleState).
## Sert seulement à l'interface : la trémulante ne s'en sert pas pour décider.
func credit_recruit() -> void:
	_recruits += 1

# =============================================================================
# Marche
# =============================================================================

## Marche lente, avec un virage d'environ 50° à peu près toutes les secondes.
## Le walker garde l'évitement des voisines et le retour depuis les bords du cadre.
func _walk(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
		bee.walker.turn(TURN_ANGLE if randf() < 0.5 else -TURN_ANGLE)
	bee.walker.step(WALK_SPEED, delta)

# =============================================================================
# Signal d'arrêt
# =============================================================================

## Cherche une danseuse frétillante au contact et, avec la probabilité
## stop_signal_rate par seconde, lui donne un signal d'arrêt.
func _try_stop_signal(delta: float) -> void:
	if (Engine.get_physics_frames() + _check_offset) % CHECK_STEP != 0:
		return
	# Probabilité par seconde, ramenée aux CHECK_STEP frames écoulées
	if randf() >= bee.simulation.stop_signal_rate * delta * CHECK_STEP:
		return
	# Seules les danses déclarées (sur la piste) sont visibles
	var dancers := bee.hive.get_dancers_near(bee.global_position, STOP_SIGNAL_RADIUS)
	if dancers.is_empty():
		return
	var target: Bee = dancers[0]
	if target.current_state != target.dance:
		return
	target.dance.receive_stop_signal()
	_stop_signals += 1
	_signal_target = target
	_signal_left = STOP_SIGNAL_TIME

## Pendant le signal : la trémulante s'arrête et se tourne vers la danseuse.
## À la fin, elle repart de l'arrêt dans sa nouvelle direction.
func _update_stop_signal(delta: float) -> void:
	_signal_left -= delta
	if is_instance_valid(_signal_target):
		_turn_to_face(_signal_target.global_position, FACE_TURN_RATE, delta)
	if _signal_left <= 0.0:
		_signal_target = null
		bee.walker.reset()

# =============================================================================
# Tremblement
# =============================================================================

## Applique le tremblement de cette frame : rotation autour de la normale,
## puis petit déplacement le long de l'axe du corps.
func _shake(delta: float) -> void:
	_shake_time += delta
	var t := _shake_time
	var yaw := SHAKE_AMPLITUDE * (0.6 * sin(TAU * SHAKE_FREQUENCY * t)
			+ 0.4 * sin(TAU * SHAKE_FREQUENCY * 1.37 * t))
	_rotate_body(yaw)
	_shake_yaw = yaw
	var forward := bee.global_basis.z.slide(_normal).normalized()
	_shake_offset = forward * SURGE_AMPLITUDE * sin(TAU * SURGE_FREQUENCY * t)
	bee.global_position += _shake_offset

## Retire le tremblement appliqué à la frame précédente.
func _unshake() -> void:
	if _shake_offset != Vector3.ZERO:
		bee.global_position -= _shake_offset
		_shake_offset = Vector3.ZERO
	if _shake_yaw != 0.0:
		_rotate_body(-_shake_yaw)
		_shake_yaw = 0.0

## Tourne l'abeille de [param angle] radians autour de la normale du cadre,
## sans la déplacer.
func _rotate_body(angle: float) -> void:
	bee.global_basis = Basis(_normal, angle) * bee.global_basis
