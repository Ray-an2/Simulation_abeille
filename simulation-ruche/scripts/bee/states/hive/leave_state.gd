class_name LeaveState extends HiveState
## Sortie de la ruche : marche sur le cadre jusqu'au début du chemin de sortie,
## suit le chemin jusqu'à la planche d'envol, puis décolle vers l'état prévu (SCOUT ou GO).
## Usage depuis un autre état : return bee.leave_hive.then(bee.scout)

# =============================================================================
# Constantes
# =============================================================================

## Vitesse de virage (rad/s) pour se diriger vers le début du chemin sur le cadre.
## Assez grande pour que l'abeille ne tourne pas en rond autour du point.
const STEER_RATE := 6.0

## Distance (m) au début du chemin en dessous de laquelle l'abeille s'engage dessus.
const PATH_ENTRY_RADIUS := 0.005

# =============================================================================
# Types
# =============================================================================

## Étapes de la sortie.
enum Phase {
	TO_PATH,   ## Marche sur le cadre vers le début du chemin
	ON_PATH,   ## Suivi du chemin jusqu'à la planche d'envol
}

# =============================================================================
# État interne
# =============================================================================

## État dans lequel entrer après le décollage (SCOUT ou GO).
var _next: BeeState

## Étape en cours.
var _phase := Phase.TO_PATH

## Guidage le long du chemin de sortie.
var _follower: PathFollower

# =============================================================================
# Méthodes de l'état
# =============================================================================

func _init(owner_bee: Bee) -> void:
	super(owner_bee)
	_follower = PathFollower.new(owner_bee)

## Fixe l'état suivant et renvoie l'état lui-même, pour pouvoir écrire
## « return bee.leave_hive.then(bee.go) » dans les autres états.
func then(next: BeeState) -> LeaveState:
	_next = next
	return self

func enter() -> void:
	assert(_next != null, "LeaveState : état suivant non défini, utiliser then()")
	bee.play_animation(&"_bee_idle")
	_phase = Phase.TO_PATH

func update(delta: float) -> BeeState:
	match _phase:
		Phase.TO_PATH:
			# Point d'entrée ramené sur le cadre : le début du chemin peut être légèrement
			# hors du rectangle de déambulation ou hors du plan de marche, ce qui le rendrait
			# inaccessible au walker (borné au cadre). On vise donc le point du cadre le plus proche.
			var entry := bee.hive.clamp_to_comb(bee.hive.get_exit_path_start())
			bee.walker.steer_towards(entry, STEER_RATE, delta)
			# Sans retour vers le centre : il contrarierait la marche vers le bord du cadre
			bee.walker.step(1.0, delta, false)
			if bee.is_near(entry, PATH_ENTRY_RADIUS):
				# Le suivi démarre au point de la courbe le plus proche de l'abeille :
				# le premier segment la fait quitter le cadre, sans bornage cette fois
				_follower.start(bee.hive.get_exit_path(), true)
				_phase = Phase.ON_PATH

		Phase.ON_PATH:
			_follower.step(delta)
			if _follower.is_finished():
				# Bout de la planche : décollage. Le passage à un état Dehors
				# démarre le bourdonnement individuel (Bee.change_state).
				return _next

	return null
