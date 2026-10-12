class_name AmbiancePlayer extends AudioStreamPlayer
## Son d'ambiance : fondu d'entrée au démarrage, puis fondu enchaîné entre l'ambiance
## de jour (Stream de ce nœud) et celle de nuit, au coucher et au lever du soleil.

# =============================================================================
# Constantes
# =============================================================================

## Volume (dB) considéré comme silencieux : -80 dB est inaudible.
const SILENT_DB := -80.0

# =============================================================================
# Paramètres réglables
# =============================================================================

## Nœud de pilotage : indique s'il fait jour (Simulation.is_daytime()).
## À assigner dans l'inspecteur.
@export var simulation: Simulation

## Ambiance de nuit. Celle de jour est le Stream de ce nœud.
@export var night_stream: AudioStream

## Durée (s) du fondu d'entrée au démarrage.
@export var fade_duration: float = 2.0

## Volume (dB) de l'ambiance de jour.
@export var target_volume_db: float = -10.0

## Volume (dB) de l'ambiance de nuit. Réglé à part : les deux fichiers
## n'ont pas forcément le même niveau d'enregistrement.
@export var night_volume_db: float = -10.0

## Durée réelle (s) du fondu enchaîné. Avec une journée de 600 s,
## une heure simulée dure 25 s.
@export var crossfade_duration: float = 15.0

# =============================================================================
# État interne
# =============================================================================

## Lecteur de l'ambiance de nuit, créé dans _ready(). Ce nœud joue celle de jour.
var _night: AudioStreamPlayer

## Niveau général, de 0 (silence) à 1 : monte une seule fois, au démarrage.
var _level := 0.0

## Mélange, de 0 (jour seul) à 1 (nuit seule).
var _mix := 0.0

## Jour ou nuit lors de la dernière vérification ; null avant la première frame.
var _was_day = null

## Fondu enchaîné en cours, pour l'interrompre si le jour revient avant la fin.
var _mix_tween: Tween

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	assert(simulation != null, "AmbiancePlayer : simulation doit être assignée dans l'inspecteur")

	# Second lecteur pour la nuit, sur le même bus que l'ambiance de jour
	_night = AudioStreamPlayer.new()
	_night.stream = night_stream
	_night.bus = bus
	add_child(_night)

	# Les deux ambiances tournent en permanence : seul leur volume change
	_apply_volumes()
	play()
	_night.play()

	# Fondu d'entrée : le niveau général monte de 0 à 1
	create_tween().tween_property(self, "_level", 1.0, fade_duration)

func _process(_delta: float) -> void:
	var is_day := simulation.is_daytime()
	if _was_day == null:
		# Première frame : on part directement sur la bonne ambiance, sans fondu enchaîné.
		# Pas fait dans _ready() : Simulation n'a peut-être pas encore réglé l'heure de départ.
		_mix = 0.0 if is_day else 1.0
	elif is_day != _was_day:
		_start_crossfade(0.0 if is_day else 1.0)
	_was_day = is_day
	_apply_volumes()

# =============================================================================
# Fondus
# =============================================================================

## Lance le fondu enchaîné vers [param to] (0 = jour, 1 = nuit).
## S'il y en a déjà un en cours, il repart de la valeur actuelle.
func _start_crossfade(to: float) -> void:
	if _mix_tween != null:
		_mix_tween.kill()
	_mix_tween = create_tween()
	_mix_tween.tween_property(self, "_mix", to, crossfade_duration)

## Applique _level et _mix aux deux lecteurs.
## Fondu à puissance constante : cos² + sin² = 1, le volume total ne se creuse pas
## à mi-parcours, contrairement à un fondu linéaire en dB.
func _apply_volumes() -> void:
	var day_gain := _level * cos(_mix * PI / 2.0)
	var night_gain := _level * sin(_mix * PI / 2.0)
	volume_db = _to_db(target_volume_db, day_gain)
	_night.volume_db = _to_db(night_volume_db, night_gain)

## Volume (dB) d'un lecteur de volume nominal [param base_db] multiplié par [param gain].
## linear_to_db(0) vaut -inf : on borne au silence.
func _to_db(base_db: float, gain: float) -> float:
	return maxf(base_db + linear_to_db(gain), SILENT_DB)
