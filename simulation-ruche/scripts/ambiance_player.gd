class_name AmbiancePlayer extends AudioStreamPlayer
## Lance l'ambiance avec un fondu progressif au démarrage.

## Durée (s) du fondu d'entrée.
@export var fade_duration: float = 2.0

## Volume final (dB) une fois le fondu terminé.
@export var target_volume_db: float = -10.0

func _ready() -> void:
	# Départ quasi silencieux : -80 dB est inaudible
	volume_db = -80.0
	play()
	# Le tween fait monter le volume jusqu'à la valeur cible
	create_tween().tween_property(self, "volume_db", target_volume_db, fade_duration)
