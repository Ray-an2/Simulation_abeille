class_name IdleState extends HiveState
## Attente dans la ruche (abeille jaune). État initial.
## L'abeille déambule sur le cadre par petits pas entrecoupés de pauses,
## jusqu'à détecter une danse (→ WATCH) ou partir explorer (→ SCOUT).

# =============================================================================
# Constantes
# =============================================================================

## Distance maximale (m) d'un pas sur le cadre, sur chaque axe du plan.
## Des petits pas autour de la position courante donnent une marche plus naturelle
## que des traversées complètes du cadre.
const STEP_RADIUS := 0.03

## Durée (s) de la pause entre deux pas, tirée au hasard dans cet intervalle.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 3.0

## Distance (m) en dessous de laquelle la cible est considérée comme atteinte.
const ARRIVAL_RADIUS := 0.002

# =============================================================================
# État interne
# =============================================================================

## Point du cadre vers lequel l'abeille marche actuellement.
var _target: Vector3

## Temps de pause restant (s). Tant qu'il est positif, l'abeille ne bouge pas.
var _pause := 0.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

func enter() -> void:
	bee.play_animation(&"_bee_idle")
	# Pause initiale aléatoire : évite que toutes les abeilles démarrent leur premier pas
	# en même temps au lancement de la simulation
	_pause = randf_range(0.0, PAUSE_MAX)
	_pick_next_target()

func update(delta: float) -> BeeState:
	# TODO : détecter une danse à proximité (→ WATCH)

	# p_scout est une probabilité par seconde : × delta pour ne pas dépendre du framerate
	if randf() < bee.simulation.p_scout * delta:
		return bee.scout

	_wander(delta)
	return null

# =============================================================================
# Utilitaires internes
# =============================================================================

## Fait avancer l'abeille vers sa cible, ou décompte la pause en cours.
## Une fois la cible atteinte, démarre une nouvelle pause et choisit le pas suivant.
func _wander(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return

	# La normale du cadre sert de vecteur haut : l'abeille reste à plat sur la cire
	bee.walk_towards(_target, delta, bee.hive.get_comb_normal())

	if bee.is_near(_target, ARRIVAL_RADIUS):
		_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
		_pick_next_target()

## Choisit le prochain point de la marche, autour de la position actuelle.
## La ruche se charge de le borner au cadre et de le ramener dans son plan.
func _pick_next_target() -> void:
	_target = bee.hive.get_comb_point_near(bee.global_position, STEP_RADIUS)
