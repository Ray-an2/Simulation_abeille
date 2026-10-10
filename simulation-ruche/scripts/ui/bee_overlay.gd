class_name BeeOverlay extends Control
## Surcouche 2D au-dessus du rendu 3D : un marqueur à l'écran pour chaque abeille,
## et une infobulle avec ses données pour l'abeille survolée ou épinglée.
##
## M : afficher / masquer les marqueurs.
## I : activer / désactiver les infobulles.
## Clic gauche (infobulles actives) : épingler l'abeille sous le curseur, ou désépingler.
##
## À placer sous un CanvasLayer dont le layer est supérieur à celui du filtre
## de vision d'abeille, pour que les marqueurs ne soient pas pixelisés.

# =============================================================================
# Constantes
# =============================================================================

## Couleur par état, quand l'abeille ne transporte pas la couleur d'une source.
## Les états pas encore codés (WATCH, DANCE) sont déjà prévus.
const STATE_COLORS := {
	&"IdleState": Color(1.0, 0.85, 0.1),     # jaune, comme demandé par le sujet
	&"WatchState": Color(1.0, 0.85, 0.1),
	&"DanceState": Color(1.0, 0.5, 0.0),
	&"UnloadState": Color(1.0, 0.65, 0.2),
	&"LeaveState": Color(0.9, 0.9, 0.6),
	&"EnterState": Color(0.9, 0.9, 0.6),
	&"ScoutState": Color.WHITE,              # exploratrice : aucune source connue
	&"ReturnState": Color(0.6, 0.6, 0.6),    # rentre bredouille (sinon couleur de la source)
}

## Couleur des états absents de STATE_COLORS : repère visuel d'un état oublié.
const UNKNOWN_STATE_COLOR := Color.MAGENTA

# =============================================================================
# Paramètres réglables
# =============================================================================

## Conteneur des abeilles créées par Simulation (Simulation/Bees).
@export var bees_container: Node3D

@export_group("Marqueurs")

## Rayon (px) du marqueur, constant quelle que soit la distance.
@export var marker_radius := 4.0

## Épaisseur (px) du contour sombre, pour que le marqueur ressorte sur l'herbe comme sur le ciel.
@export var outline_width := 1.5

## Distance (m) caméra-abeille en dessous de laquelle le marqueur est masqué :
## de près, l'abeille est assez grande pour être vue et le marqueur la cacherait.
## Masque aussi l'abeille suivie en vue abeille (caméra posée dessus).
@export var hide_distance := 0.5

## Distance (m), au-delà de hide_distance, sur laquelle le marqueur apparaît en fondu.
@export var fade_distance := 0.5

@export_group("Infobulle")

## Distance (px) entre la souris et un marqueur en dessous de laquelle l'abeille est touchée.
## De près, la silhouette de l'abeille prend le relais si elle est plus grande.
@export var pick_radius := 12.0

## Longueur (m) d'une abeille, pour calculer sa taille à l'écran.
## De près, toute l'abeille devient cliquable, pas seulement son centre.
@export var bee_size := 0.015

## Taille de police (px) du texte de l'infobulle.
@export var font_size := 14

## Marge intérieure (px) de l'infobulle.
@export var padding := 6.0

@export_group("Touches")

## Touche qui affiche / masque les marqueurs. Comparée à la lettre produite
## selon la disposition du clavier : M est bien la touche M en AZERTY.
@export var markers_key: Key = KEY_M

## Touche qui active / désactive les infobulles.
@export var info_key: Key = KEY_I

# =============================================================================
# État interne
# =============================================================================

## Marqueurs et infobulles masqués au lancement : on les active avec les touches.
var _markers_enabled := false
var _info_enabled := false

## Abeille épinglée par un clic : son infobulle reste affichée même sans survol.
var _pinned: Bee = null

## Position à l'écran de chaque abeille visible à la dernière image.
## Sert à retrouver l'abeille sous la souris (survol et clic).
var _screen_positions: Dictionary[Bee, Vector2] = {}

## Rayon apparent (px) de chaque abeille visible à la dernière image.
var _screen_radii: Dictionary[Bee, float] = {}

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	# set_anchors_and_offsets_preset (et non set_anchors_preset) remet aussi les marges à 0 :
	# le Control couvre exactement l'écran, quelle que soit sa taille dans l'éditeur
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Laisse passer la souris et les clics vers le jeu (caméras, etc.)
	mouse_filter = MOUSE_FILTER_IGNORE
	if bees_container == null:
		push_warning("BeeOverlay : bees_container non assigné, aucun marqueur ne sera dessiné")


func _process(_delta: float) -> void:
	# Les abeilles bougent à chaque image : on redessine dès qu'un affichage est actif
	if _markers_enabled or _info_enabled:
		queue_redraw()

# =============================================================================
# Entrées
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Clic gauche, infobulles actives : épingle l'abeille sous le curseur,
	# ou désépingle si on clique dans le vide
	if _info_enabled and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_pinned = _bee_at(event.position)
		queue_redraw()
		return

	# echo : ignore la répétition quand la touche reste enfoncée
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# keycode et non physical_keycode : lettre imprimée sur la touche selon la
	# disposition du clavier, donc M est bien la touche M en AZERTY
	if event.keycode == markers_key:
		_markers_enabled = not _markers_enabled
		queue_redraw()   # efface les marqueurs si on vient de les masquer
	elif event.keycode == info_key:
		_info_enabled = not _info_enabled
		if not _info_enabled:
			_pinned = null
		queue_redraw()

# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	# Repartir de zéro : une abeille hors champ ne doit plus être sélectionnable
	_screen_positions.clear()
	_screen_radii.clear()
	if not (_markers_enabled or _info_enabled) or bees_container == null:
		return
	# Caméra réellement utilisée pour le rendu (celle pilotée par PhantomCameraHost)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Axe horizontal de l'écran, pour mesurer la taille apparente des abeilles
	var cam_right := cam.global_basis.x

	# --- Positions à l'écran et marqueurs ---
	for node in bees_container.get_children():
		var bee := node as Bee
		if bee == null or bee.current_state == null:
			continue
		var world := bee.global_position
		# Hors champ ou derrière la caméra : unproject_position donnerait un point faux
		if not cam.is_position_in_frustum(world):
			continue

		var p := cam.unproject_position(world)
		# Rayon apparent (px) : demi-longueur de l'abeille projetée à l'écran
		var edge := cam.unproject_position(world + cam_right * bee_size * 0.5)
		# Toujours sélectionnable, même de près où le marqueur est masqué
		_screen_positions[bee] = p
		_screen_radii[bee] = p.distance_to(edge)

		if not _markers_enabled:
			continue
		# Fondu selon la distance : invisible de près, opaque de loin
		var dist := cam.global_position.distance_to(world)
		var alpha := clampf((dist - hide_distance) / fade_distance, 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var color := _marker_color(bee)
		color.a = alpha
		draw_circle(p, marker_radius + outline_width, Color(0.0, 0.0, 0.0, alpha))
		draw_circle(p, marker_radius, color)

	# --- Infobulle ---
	if not _info_enabled:
		return
	# Abeille épinglée en priorité, sinon celle survolée par la souris
	var shown: Bee = _pinned if is_instance_valid(_pinned) \
			else _bee_at(get_local_mouse_position())
	# Abeille épinglée hors champ : pas d'infobulle, elle revient quand l'abeille réapparaît
	if shown == null or not _screen_positions.has(shown):
		return
	var at := _screen_positions[shown]
	# L'anneau entoure le marqueur de loin, l'abeille entière de près
	var ring := maxf(marker_radius, _screen_radii[shown]) + 4.0
	draw_arc(at, ring, 0.0, TAU, 32, Color.WHITE, 1.5)
	_draw_tooltip(shown, at, ring)


## Dessine un cadre semi-transparent contenant les données de [param bee],
## à droite de l'anneau de rayon [param ring], sans sortir de l'écran.
func _draw_tooltip(bee: Bee, at: Vector2, ring: float) -> void:
	var font := get_theme_default_font()
	var text := _bee_info(bee)
	var text_size := font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box_size := text_size + Vector2.ONE * 2.0 * padding

	# À droite de l'anneau, centré verticalement, puis ramené dans l'écran
	var pos := at + Vector2(ring + 6.0, -box_size.y * 0.5)
	pos.x = clampf(pos.x, 0.0, size.x - box_size.x)
	pos.y = clampf(pos.y, 0.0, size.y - box_size.y)

	draw_rect(Rect2(pos, box_size), Color(0.0, 0.0, 0.0, 0.75))
	# draw_multiline_string place la ligne de base de la première ligne en pos : on ajoute l'ascendante
	var baseline := pos + Vector2(padding, padding + font.get_ascent(font_size))
	draw_multiline_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

# =============================================================================
# Sélection
# =============================================================================

## Abeille sous [param pos], ou null. Une abeille est touchée si [param pos] est
## à moins de pick_radius de son centre, ou à l'intérieur de sa silhouette si elle est
## plus grande à l'écran. Si plusieurs se chevauchent, on garde la plus centrée.
## Se base sur les positions calculées à la dernière image.
func _bee_at(pos: Vector2) -> Bee:
	var best: Bee = null
	var best_ratio := 1.0
	for bee in _screen_positions:
		var reach := maxf(pick_radius, _screen_radii[bee])
		# Distance rapportée à la taille : 0 au centre, 1 au bord de la zone cliquable
		var ratio := pos.distance_to(_screen_positions[bee]) / reach
		if ratio < best_ratio:
			best = bee
			best_ratio = ratio
	return best

# =============================================================================
# Données affichées
# =============================================================================

## Couleur de la source (pelote de pollen) pour une abeille dehors qui en connaît une,
## couleur de l'état sinon.
func _marker_color(bee: Bee) -> Color:
	var flower := bee.known_flower
	if bee.current_state is FieldState and is_instance_valid(flower) \
			and flower.pollen_material != null:
		return flower.pollen_material.albedo_color
	return STATE_COLORS.get(_state_name(bee), UNKNOWN_STATE_COLOR)


## Nom de classe de l'état courant (IdleState, ScoutState…), tiré du class_name du script.
func _state_name(bee: Bee) -> StringName:
	return bee.current_state.get_script().get_global_name()


## Texte de l'infobulle : une ligne par donnée utile au réglage des boucles.
func _bee_info(bee: Bee) -> String:
	var lines := PackedStringArray()
	lines.append(str(bee.name))
	lines.append("État : %s" % _state_name(bee).trim_suffix("State"))
	lines.append("Nectar : %.1f / %.1f" % [bee.nectar, bee.simulation.forage_capacity])

	var flower := bee.known_flower
	if is_instance_valid(flower):
		lines.append("Source : %s (%s)" % [flower.name, Flower.Species.keys()[flower.species]])
		lines.append("Stock source : %.0f" % flower.resource)
		lines.append("Rentabilité : %.2f" % bee.known_profitability)
	else:
		lines.append("Source : aucune")

	# Le chrono n'avance que dehors (Bee._physics_process)
	if bee.current_state is FieldState:
		lines.append("Trajet : %.1f s" % bee.trip_time)
	return "\n".join(lines)
