class_name DanceState extends HiveState
## Danse frétillante : l'abeille annonce sa source à la ruche pendant une durée
## proportionnelle à sa rentabilité (boucle de recrutement), puis ressort la butiner.
##
## Version minimale pour débloquer la machine à états : l'abeille reste sur place
## le temps de la danse. Le déplacement en huit et l'annonce à la ruche
## (start_dance / stop_dance, lus par IDLE pour passer en WATCH) restent à écrire.

# =============================================================================
# État interne
# =============================================================================

## Temps de danse restant (s).
var _remaining := 0.0

# =============================================================================
# Méthodes de l'état
# =============================================================================

## Durée de danse : dance_duration_max pour une rentabilité de 1.
## UNLOAD a déjà réduit known_profitability selon l'attente à la file (saturation).
func enter() -> void:
	_remaining = bee.simulation.dance_duration_max * bee.known_profitability
	bee.play_animation(&"_bee_idle")
	# TODO : bee.hive.start_dance(bee, bee.known_flower)

func exit() -> void:
	# TODO : bee.hive.stop_dance(bee)
	pass

## Fin de la danse : sortie à pied jusqu'à la planche, puis vol vers la source.
func update(delta: float) -> BeeState:
	_remaining -= delta
	if _remaining <= 0.0:
		return bee.leave_hive.then(bee.go)
	return null
