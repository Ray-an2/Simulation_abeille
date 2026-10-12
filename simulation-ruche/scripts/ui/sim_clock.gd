class_name SimClock extends Control
## Horloge de la simulation : heure et date simulées, en haut au centre de l'écran.
##
## Affichée en permanence, dans toutes les vues : c'est le seul affichage de l'heure
## (BeeHud ne la reprend plus). Placée en haut au centre pour ne pas recouvrir
## les panneaux de BeeHud, qui occupent les quatre coins en vue abeille.
## Doit être dessinée au-dessus du filtre « vision d'abeille » (voir le CanvasLayer).
##
## La date vient du TimeOfDay de Sky3D (sky.tod) : quand Simulation fait passer
## current_time au-delà de 24 h, TimeOfDay incrémente lui-même le jour, puis le mois.

# =============================================================================
# Constantes
# =============================================================================

## Couleurs reprises de BeeHud, pour un style commun.
const PANEL_COLOR := Color(0.05, 0.05, 0.07, 0.72)
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const TEXT_COLOR := Color(0.93, 0.93, 0.93)
const DIM_COLOR := Color(0.65, 0.65, 0.65)
const SUN_COLOR := Color(1.0, 0.85, 0.3)
const MOON_COLOR := Color(0.78, 0.82, 0.95)

## Texte de référence pour la largeur de l'heure : la largeur réservée ne dépend
## pas des chiffres affichés, le panneau ne tremble pas à chaque minute.
const TIME_REFERENCE := "00:00"

## Noms des mois, indice 0 = janvier (TimeOfDay.month va de 1 à 12).
const MONTH_NAMES: Array[String] = ["janvier", "février", "mars", "avril", "mai", "juin",
		"juillet", "août", "septembre", "octobre", "novembre", "décembre"]

# =============================================================================
# Paramètres réglables
# =============================================================================

## Nœud de pilotage : heure de départ, heures écoulées, jour ou nuit, Sky3D.
## À assigner dans l'inspecteur.
@export var simulation: Simulation

@export_group("Mise en page")

## Taille de police (px) de l'heure. La date est écrite à 70 % de cette taille.
@export var font_size := 22

## Distance (px) entre le panneau et le haut de l'écran.
@export var margin := 16.0

## Marge intérieure (px) du panneau.
@export var padding := 10.0

## Espace (px) entre l'icône, l'heure et la date.
@export var spacing := 10.0

## Rayon (px) de l'icône soleil / lune.
@export var icon_radius := 7.0

# =============================================================================
# État interne
# =============================================================================

## Minute simulée affichée au dernier dessin : on ne redessine qu'à son changement.
## Avec une journée de 600 s, une minute simulée dure environ 0,4 s réelle.
## Le changement de date tombe toujours sur un changement de minute (minuit).
var _shown_minute := -1

## Jour ou nuit au dernier dessin : l'icône change au lever et au coucher du soleil,
## qui ne tombent pas forcément sur un changement de minute.
var _shown_day := true

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	# Couvre l'écran pour se centrer quelle que soit sa taille, et laisse passer
	# la souris vers le jeu (épinglage, rotation de la caméra)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	if simulation == null:
		push_warning("SimClock : simulation non assignée, l'horloge ne s'affichera pas")


func _process(_delta: float) -> void:
	if simulation == null or simulation.sky == null:
		return
	# Pas de redessin à chaque image : l'affichage ne change qu'une fois par minute simulée
	var minute := int(_total_hours() * 60.0)
	var is_day := simulation.is_daytime()
	if minute != _shown_minute or is_day != _shown_day:
		_shown_minute = minute
		_shown_day = is_day
		queue_redraw()

# =============================================================================
# Temps et date
# =============================================================================

## Heures simulées depuis minuit du premier jour. Simulation._process fait avancer
## sim_hours et sky.current_time du même pas : modulo 24, c'est l'heure du soleil.
func _total_hours() -> float:
	return simulation.start_hour + simulation.sim_hours


## Date du calendrier de Sky3D, par ex. « 1er juin · jour 3 ».
## Le numéro de jour compte les jours de simulation depuis le lancement (jour 1).
## Sans TimeOfDay (Sky3D pas encore prêt), seul le numéro de jour est affiché.
func _date_text(total_hours: float) -> String:
	var sim_day := "jour %d" % (int(total_hours / 24.0) + 1)
	var tod := simulation.sky.tod
	if tod == null:
		return sim_day
	# Convention française : « 1er » pour le premier jour du mois
	var day := "1er" if tod.day == 1 else str(tod.day)
	return "%s %s · %s" % [day, MONTH_NAMES[tod.month - 1], sim_day]


# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	if simulation == null or simulation.sky == null:
		return
	var font := get_theme_default_font()
	var small_size := roundi(font_size * 0.7)

	# Heure du jour et date
	var total := _total_hours()
	var h := fposmod(total, 24.0)
	var time_text := "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
	var date_text := _date_text(total)

	# Largeurs : celle de l'heure est fixe (TIME_REFERENCE) ; celle de la date
	# ne change qu'une fois par jour simulé, le recentrage passe inaperçu
	var time_w := font.get_string_size(TIME_REFERENCE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var date_w := font.get_string_size(date_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
	var content_w := icon_radius * 2.0 + spacing + time_w + spacing + date_w

	# Panneau centré en haut de l'écran
	var panel := Rect2(
			Vector2((size.x - content_w) * 0.5 - padding, margin),
			Vector2(content_w + padding * 2.0, font.get_height(font_size) + padding * 2.0))
	draw_rect(panel, PANEL_COLOR)
	draw_rect(panel, BORDER_COLOR, false, 1.0)

	# Ligne de base commune : draw_string place le texte sur sa ligne de base,
	# pas sur son bord haut
	var baseline := panel.position.y + padding + font.get_ascent(font_size)
	var x := panel.position.x + padding

	_draw_sky_icon(Vector2(x + icon_radius, panel.get_center().y))
	x += icon_radius * 2.0 + spacing
	# Heure centrée dans sa largeur réservée
	draw_string(font, Vector2(x, baseline), time_text, HORIZONTAL_ALIGNMENT_CENTER,
			time_w, font_size, TEXT_COLOR)
	x += time_w + spacing
	draw_string(font, Vector2(x, baseline), date_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, small_size, DIM_COLOR)


## Soleil (disque et rayons) le jour, lune (disque pâle) la nuit, selon
## Simulation.is_daytime() : le même critère que le son d'ambiance.
func _draw_sky_icon(center: Vector2) -> void:
	if not _shown_day:
		draw_circle(center, icon_radius * 0.85, MOON_COLOR)
		return
	draw_circle(center, icon_radius * 0.6, SUN_COLOR)
	# Huit rayons courts autour du disque
	for i in 8:
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(center + dir * icon_radius * 0.8, center + dir * icon_radius * 1.15,
				SUN_COLOR, 1.5)
