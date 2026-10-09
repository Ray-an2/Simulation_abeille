class_name EnterState extends HiveState
## Entrée dans la ruche : marche de la planche d'envol jusqu'au cadre en suivant
## le chemin de sortie à l'envers, puis attente sur le cadre.
## Mènera à UNLOAD une fois cet état écrit ; IDLE en attendant.

# =============================================================================
# État interne
# =============================================================================

## Guidage le long du chemin, parcouru de la fin vers le début.
var _follower: PathFollower

# =============================================================================
# Méthodes de l'état
# =============================================================================

func _init(owner_bee: Bee) -> void:
	super(owner_bee)
	_follower = PathFollower.new(owner_bee)

func enter() -> void:
	bee.play_animation(&"_bee_idle")
	_follower.start(bee.hive.get_exit_path(), false)

func update(delta: float) -> BeeState:
	_follower.step(delta)
	if _follower.is_finished():
		return bee.idle   # TODO : bee.unload une fois UNLOAD écrit
	return null

func exit() -> void:
	# Le cap du walker date de l'atterrissage sur la planche : on le recalcule
	# maintenant que l'abeille est sur le cadre, orientée le long du chemin
	bee.walker.reset()
