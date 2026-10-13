class_name BeeHud extends Control
## Tableau de bord de la vue abeille. Les panneaux occupent les quatre coins pour
## laisser le centre de la vue libre, et leur contenu dépend de ce que fait l'abeille :
##   haut gauche  : identité, état et sa progression, vol, compteurs de vie ;
##   haut droit   : journal des dernières transitions ;
##   bas gauche   : charge transportée, source connue et chaîne de recrutement ;
##   bas droit    : danse qui annoncerait la source (direction et distance),
##                  rentabilité et décision prévue ;
##   dans la vue  : direction de la ruche et de la source, sur le bord si hors champ.
##
## S'affiche en vue abeille quand les infobulles de BeeOverlay sont actives (touche I).

# =============================================================================
# Constantes
# =============================================================================

## Couleurs de l'interface.
const PANEL_COLOR := Color(0.05, 0.05, 0.07, 0.72)
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const TEXT_COLOR := Color(0.93, 0.93, 0.93)
const DIM_COLOR := Color(0.65, 0.65, 0.65)
const GAUGE_BG_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const NECTAR_COLOR := Color(1.0, 0.75, 0.2)
const SUN_COLOR := Color(1.0, 0.85, 0.3)
const HIVE_COLOR := Color(1.0, 0.8, 0.4)

## Couleurs de la décision prévue : danse, repart sans danser, abandon.
const GOOD_COLOR := Color(0.45, 0.85, 0.4)
const MID_COLOR := Color(0.95, 0.75, 0.25)
const BAD_COLOR := Color(0.9, 0.35, 0.3)

## Libellé affiché pour chaque état.
const STATE_LABELS := {
	&"IdleState": "Attente",
	&"LeaveState": "Sortie",
	&"EnterState": "Entrée",
	&"ScoutState": "Exploration",
	&"GoState": "Vers la source",
	&"ForageState": "Butinage",
	&"ReturnState": "Retour",
	&"UnloadState": "Déchargement",
	&"WatchState": "Suit une danse",
	&"DanceState": "Danse",
}

# =============================================================================
# Paramètres réglables
# =============================================================================

## Surcouche des marqueurs : fournit l'abeille suivie et l'état de la touche I.
@export var overlay: BeeOverlay

## Historique des abeilles : temps dans l'état, journal, compteurs.
@export var tracker: BeeTracker

@export_group("Mise en page")

## Taille de police (px) du texte courant et du nom de l'abeille.
@export var font_size := 15
@export var title_font_size := 20

## Distance (px) entre les panneaux et les bords de l'écran.
@export var margin := 16.0

## Marge intérieure (px) des panneaux.
@export var padding := 10.0

## Largeur (px) des panneaux.
@export var panel_width := 300.0

## Épaisseur (px) des jauges.
@export var gauge_height := 6.0

## Rayon (px) de la boussole de danse.
@export var compass_radius := 46.0

## Longueur minimale de la flèche de la boussole, en fraction du rayon :
## une source toute proche reste lisible.
@export_range(0.0, 1.0) var compass_min_arrow := 0.3

## Distance (px) entre les indicateurs de cible hors champ et le bord de l'écran.
@export var edge_inset := 40.0

# =============================================================================
# État interne
# =============================================================================

## Police par défaut du thème, relue à chaque dessin.
var _font: Font

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	# Couvre exactement l'écran, et laisse passer la souris vers le jeu
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	if overlay == null:
		push_warning("BeeHud : overlay non assigné, le tableau de bord ne s'affichera pas")
	if tracker == null:
		push_warning("BeeHud : tracker non assigné, pas de journal ni de compteurs")


func _process(_delta: float) -> void:
	# Redessin à chaque image : les valeurs changent en continu, et un dessin vide
	# efface le tableau de bord quand on quitte la vue abeille ou qu'on appuie sur I
	queue_redraw()

# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	var bee := _target_bee()
	if bee == null:
		return
	_font = get_theme_default_font()
	var rec: BeeTracker.Record = tracker.get_record(bee) if tracker != null else null

	# Indicateurs d'abord : les panneaux passent par-dessus s'ils se chevauchent
	_draw_target_indicators(bee)
	_draw_panel(_identity_rows(bee, rec), CORNER_TOP_LEFT)
	_draw_panel(_journal_rows(bee, rec), CORNER_TOP_RIGHT)
	_draw_panel(_cargo_rows(bee, rec), CORNER_BOTTOM_LEFT)
	_draw_panel(_dance_rows(bee), CORNER_BOTTOM_RIGHT)


## Abeille suivie en vue abeille, si les infobulles sont actives ; null sinon.
func _target_bee() -> Bee:
	if overlay == null or not overlay.is_info_enabled():
		return null
	return overlay.followed_bee if is_instance_valid(overlay.followed_bee) else null

# =============================================================================
# Contenu des panneaux
# =============================================================================

## Haut gauche : qui est l'abeille, ce qu'elle fait, où elle en est.
func _identity_rows(bee: Bee, rec: BeeTracker.Record) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var state := BeeTracker.state_of(bee)
	var in_state := tracker.clock - rec.state_since if rec != null else 0.0

	rows.append(_row_title(str(bee.name)))
	var since := "depuis %.1f s" % in_state if rec != null else ""
	rows.append(_row_badge(_state_label(state), _state_color(state), since))
	rows.append_array(_state_rows(bee, state, in_state))

	# Données de vol : seulement dehors
	if bee.current_state is FieldState:
		rows.append(_row_gap())
		if rec != null:
			rows.append(_row_pair("Vitesse", "%.1f m/s" % rec.speed))
		var ground := bee.get_ground_height(bee.global_position)
		if ground != -INF:
			rows.append(_row_pair("Hauteur", "%.1f m" % (bee.global_position.y - ground)))
		rows.append(_row_pair("Durée du trajet", "%.0f s" % bee.trip_time))

	# Compteurs de vie
	if rec != null:
		rows.append(_row_gap())
		var trips := str(rec.trips)
		if rec.empty_trips > 0:
			trips += " (dont %d bredouille%s)" % [rec.empty_trips, "s" if rec.empty_trips > 1 else ""]
		rows.append(_row_pair("Voyages", trips))
		rows.append(_row_pair("Nectar livré", "%.0f" % rec.nectar_delivered))
		rows.append(_row_pair("Danses", str(rec.dances)))
		rows.append(_row_pair("Abeilles recrutées", str(rec.recruits)))
	return rows


## Lignes propres à l'état courant : la progression de ce que fait l'abeille.
## [param in_state] : temps (s) passé dans l'état, mesuré par le tracker.
func _state_rows(bee: Bee, state: StringName, in_state: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var sim := bee.simulation
	match state:
		&"IdleState":
			# p_scout est une probabilité par seconde : attente moyenne 1 / p_scout
			rows.append(_row_text("Part explorer au bout de %.0f s en moyenne"
					% (1.0 / maxf(sim.p_scout, 0.0001))))
		&"ScoutState":
			# Le minuteur de SCOUT repart à chaque entrée dans l'état, comme in_state
			var left := maxf(sim.scout_timeout - in_state, 0.0)
			rows.append(_row_gauge("Exploration", "reste %.0f s" % left,
					in_state / maxf(sim.scout_timeout, 0.001), Color.WHITE))
		&"GoState":
			if is_instance_valid(bee.known_flower):
				var d := bee.global_position.distance_to(bee.known_flower.get_landing_position())
				rows.append(_row_pair("Distance à la fleur", "%.1f m" % d))
			elif bee.go.is_searching():
				# Recrue autour du point dansé : temps de recherche restant
				var left: float = bee.go.get_search_left()
				rows.append(_row_gauge("Recherche (recrue)", "reste %.0f s" % left,
						1.0 - left / maxf(sim.recruit_search_timeout, 0.001), Color.WHITE))
			elif bee.has_dance_vector():
				var d := sim.get_flat_distance(bee.global_position, bee.dance_target)
				rows.append(_row_pair("Distance au point dansé", "%.1f m" % d))
		&"ForageState":
			if is_instance_valid(bee.known_flower):
				rows.append(_row_pair("Fleur", _flower_state_label(bee.known_flower)))
		&"ReturnState":
			var d := bee.global_position.distance_to(bee.hive.get_landing_position())
			rows.append(_row_pair("Distance à la ruche", "%.1f m" % d))
		&"UnloadState":
			# Boucle de saturation : l'attente réduit l'envie de danser
			var wait := bee.hive.get_wait_time(bee)
			var ratio := clampf(wait / maxf(sim.max_wait_time, 0.001), 0.0, 1.0)
			rows.append(_row_pair("File d'attente", "%d abeille(s)" % bee.hive.get_queue_length()))
			rows.append(_row_gauge("Attente d'une receveuse", "%.1f s" % wait, ratio, BAD_COLOR))
			rows.append(_row_text("Envie de danser réduite de %d %%"
					% roundi(sim.wait_penalty * ratio * 100.0)))
		&"WatchState":
			var dancer := bee.watch.get_dancer()
			if dancer != null:
				rows.append(_row_pair("Suit la danse de", str(dancer.name)))
			# Seul le temps au contact compte : la jauge peut stagner si l'abeille
			# perd la danseuse, et l'abeille abandonne au bout de LOST_TIMEOUT
			var contact := bee.watch.get_contact_time()
			rows.append(_row_gauge("Mémorisation (au contact)",
					"%.1f / %.1f s" % [contact, sim.watch_min_duration],
					contact / maxf(sim.watch_min_duration, 0.001), GOOD_COLOR))
		&"DanceState":
			# Durée prévue par DanceState : proportionnelle à la rentabilité
			var total := sim.dance_duration_max * bee.known_profitability
			rows.append(_row_gauge("Danse", "reste %.1f s" % maxf(total - in_state, 0.0),
					in_state / maxf(total, 0.001), MID_COLOR))
			# Boucle de recrutement : abeilles qui suivent cette danse en ce moment
			rows.append(_row_pair("Suiveuses", "%d / %d"
					% [bee.hive.get_follower_count(bee), sim.max_followers]))
	return rows


## Haut droit : dernières transitions, la plus récente en haut.
func _journal_rows(bee: Bee, rec: BeeTracker.Record) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if rec == null or rec.transitions.is_empty():
		rows.append(_row_text("Aucune transition observée"))
		return rows
	rows.append(_row_text("Dernières transitions"))
	for i in rec.transitions.size():
		var t: Dictionary = rec.transitions[i]
		# Les plus anciennes s'estompent
		var fade := 1.0 - 0.12 * i
		var label := "%s → %s" % [_state_label(t.from), _state_label(t.to)]
		var ago := "%.0f s" % (tracker.clock - t.time)
		var color := _state_color(t.to)
		color.a = fade
		var dim := DIM_COLOR
		dim.a = fade
		rows.append(_row_pair(label, ago, dim, color))
	return rows


## Bas gauche : ce que l'abeille transporte, ce qu'elle sait de sa source
## et de qui elle la tient.
func _cargo_rows(bee: Bee, rec: BeeTracker.Record) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var sim := bee.simulation
	var flower: Flower = bee.known_flower if is_instance_valid(bee.known_flower) else null
	var flower_color := _flower_color(flower)

	var capacity := maxf(sim.forage_capacity, 0.001)
	rows.append(_row_gauge("Nectar transporté", "%.1f / %.1f" % [bee.nectar, sim.forage_capacity],
			bee.nectar / capacity, flower_color))
	if flower == null:
		rows.append(_row_text("Aucune source connue"))
		return rows

	rows.append(_row_gap())
	rows.append(_row_badge(_species_label(flower.species), flower_color, str(flower.name)))
	# Repère sur la jauge : seuil sous lequel la fleur passe en EMPTY
	var max_res := maxf(sim.max_resource, 0.001)
	rows.append(_row_gauge("Stock de la fleur", "%.0f / %.0f" % [flower.resource, sim.max_resource],
			flower.resource / max_res, flower_color, [sim.threshold / max_res]))
	rows.append(_row_pair("État de la fleur", _flower_state_label(flower)))
	# Origine de la source : exploration, ou danse (avec la chaîne de recrutement)
	var chain := _recruitment_chain(bee)
	if chain.is_empty():
		rows.append(_row_pair("Connue par", "exploration"))
	else:
		rows.append(_row_pair("Connue par", "danse de " + chain[0]))
		if chain.size() > 1:
			rows.append(_row_text("Recrutement : " + " ← ".join(chain)))
	return rows


## Bas droit : comment la source serait dansée, et ce que l'abeille va décider.
## Panneau masqué sans source connue.
func _dance_rows(bee: Bee) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var flower: Flower = bee.known_flower if is_instance_valid(bee.known_flower) else null
	if flower == null:
		return rows
	var sim := bee.simulation

	# Angle recalculé à chaque image : le soleil tourne avec l'heure simulée.
	# Distance à plat ruche → source : celle que la danse encode.
	var angle := sim.get_dance_angle(flower.global_position, bee.hive.global_position)
	var dist := sim.get_flat_distance(bee.hive.global_position, flower.global_position)
	var dist_ratio := clampf(dist / maxf(sim.max_source_distance, 0.001), 0.0, 1.0)
	rows.append(_row_text("Danse de cette source"))
	rows.append({"kind": &"compass", "angle": angle, "color": _flower_color(flower),
			"distance": dist, "distance_ratio": dist_ratio})
	# Côté écrit en toutes lettres : un « + » se lit souvent « à droite » (sens des
	# relèvements), alors qu'ici un angle positif est un angle trigonométrique, à gauche
	var deg := rad_to_deg(angle)
	var angle_text := "face au soleil" if absf(deg) < 0.5 \
			else "%.0f° à %s" % [absf(deg), "gauche" if deg > 0.0 else "droite"]
	rows.append(_row_pair("Angle au soleil", angle_text))
	rows.append(_row_pair("Distance", "%.1f m" % dist))
	rows.append(_row_gap())

	# Rentabilité calculée par UNLOAD au dernier déchargement, comparée aux deux seuils
	var p := bee.known_profitability
	if p <= 0.0:
		rows.append(_row_text("Rentabilité évaluée au prochain déchargement"))
		return rows
	var low := sim.profitability_low
	var high := sim.profitability_high
	var color := GOOD_COLOR if p >= high else (MID_COLOR if p >= low else BAD_COLOR)
	rows.append(_row_gauge("Rentabilité", "%.2f" % p, p, color, [low, high]))
	rows.append(_row_pair("Efficacité énergétique", "%.1f" % bee.known_efficiency))
	var verdict := "Dansera, si l'attente à la ruche reste courte" if p >= high \
			else ("Repartira sans danser" if p >= low else "Abandonnera la source")
	rows.append(_row_text(verdict, color))
	return rows

# =============================================================================
# Indicateurs de cible dans la vue
# =============================================================================

## Dehors : direction de la ruche et de la source connue.
func _draw_target_indicators(bee: Bee) -> void:
	if not (bee.current_state is FieldState):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_draw_target(cam, bee, bee.hive.get_landing_position(), "Ruche", HIVE_COLOR)
	if is_instance_valid(bee.known_flower):
		_draw_target(cam, bee, bee.known_flower.get_landing_position(), "Source",
				_flower_color(bee.known_flower))


## Cible à l'écran : un cercle dessus si elle est visible, sinon une flèche
## sur le bord de l'écran, dans sa direction.
func _draw_target(cam: Camera3D, bee: Bee, world: Vector3, label: String, color: Color) -> void:
	var text := "%s  %.0f m" % [label, bee.global_position.distance_to(world)]
	var lh := _line_height(font_size)
	var bounds := Rect2(Vector2.ZERO, size).grow(-edge_inset)

	var screen := cam.unproject_position(world)
	if cam.is_position_in_frustum(world) and bounds.has_point(screen):
		draw_arc(screen, 8.0, 0.0, TAU, 24, color, 2.0)
		_text(screen + Vector2(14.0, -lh * 0.5), text, color)
		return

	# Hors champ : direction de la cible dans le repère de la caméra (qui regarde vers -Z).
	# Même derrière la caméra, x et y indiquent de quel côté tourner.
	var local := cam.global_transform.affine_inverse() * world
	var dir := Vector2(local.x, -local.y)
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN   # pile derrière : flèche en bas
	dir = dir.normalized()

	# Rayon depuis le centre de l'écran, arrêté sur le bord du rectangle bounds
	var half := bounds.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var tip := size * 0.5 + dir * t
	var side := dir.orthogonal() * 7.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 10.0, tip + side, tip - side]), color)

	# Texte en retrait vers le centre, gardé dans l'écran
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := tip - dir * 24.0 - Vector2(text_w * 0.5, lh * 0.5)
	pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - text_w)
	pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - lh)
	_text(pos, text, color)

# =============================================================================
# Lignes de panneau
# =============================================================================
# Un panneau est une liste de lignes (dictionnaires) : _draw_panel mesure leur
# hauteur totale pour placer le panneau dans son coin, puis les dessine une à une.

func _row_title(text: String) -> Dictionary:
	return {"kind": &"title", "text": text}


func _row_text(text: String, color := DIM_COLOR) -> Dictionary:
	return {"kind": &"text", "text": text, "color": color}


## Libellé à gauche, valeur alignée à droite.
func _row_pair(label: String, value: String, label_color := DIM_COLOR,
		value_color := TEXT_COLOR) -> Dictionary:
	return {"kind": &"pair", "label": label, "value": value,
			"label_color": label_color, "value_color": value_color}


## Pastille colorée suivie d'une note grise.
func _row_badge(text: String, color: Color, note := "") -> Dictionary:
	return {"kind": &"badge", "text": text, "color": color, "note": note}


## Libellé et valeur, puis une jauge remplie à [param ratio] (0 à 1).
## [param ticks] : repères verticaux (seuils), en fractions de la largeur.
func _row_gauge(label: String, value: String, ratio: float, color: Color,
		ticks: Array = []) -> Dictionary:
	return {"kind": &"gauge", "label": label, "value": value,
			"ratio": ratio, "color": color, "ticks": ticks}


## Petit espace entre deux groupes de lignes.
func _row_gap() -> Dictionary:
	return {"kind": &"gap"}

# =============================================================================
# Dessin des panneaux
# =============================================================================

## Dessine les lignes [param rows] dans un panneau placé dans le coin [param corner].
func _draw_panel(rows: Array[Dictionary], corner: Corner) -> void:
	if rows.is_empty():
		return
	# Largeur utile calculée d'abord : la hauteur des textes longs en dépend
	var width := panel_width - 2.0 * padding
	var height := padding * 2.0
	for row in rows:
		height += _row_height(row, width)

	var pos := Vector2(margin, margin)
	if corner == CORNER_TOP_RIGHT or corner == CORNER_BOTTOM_RIGHT:
		pos.x = size.x - margin - panel_width
	if corner == CORNER_BOTTOM_LEFT or corner == CORNER_BOTTOM_RIGHT:
		pos.y = size.y - margin - height
	var rect := Rect2(pos, Vector2(panel_width, height))
	draw_rect(rect, PANEL_COLOR)
	draw_rect(rect, BORDER_COLOR, false, 1.0)

	var at := pos + Vector2(padding, padding)
	for row in rows:
		_draw_row(row, at, width)
		at.y += _row_height(row, width)


## Hauteur (px) occupée par une ligne, pour une largeur utile de [param width] pixels.
func _row_height(row: Dictionary, width: float) -> float:
	var lh := _line_height(font_size)
	match row.kind:
		&"title":
			return _line_height(title_font_size)
		&"text":
			# Texte renvoyé à la ligne : autant de lignes qu'il en faut dans la largeur
			return _font.get_multiline_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT,
					width, font_size).y + 3.0
		&"badge":
			return lh + 6.0
		&"gauge":
			return lh + gauge_height + 6.0
		&"gap":
			return lh * 0.4
		&"compass":
			return compass_radius * 2.0 + 16.0
	return lh


## Dessine une ligne, coin haut gauche en [param at], sur [param width] pixels.
func _draw_row(row: Dictionary, at: Vector2, width: float) -> void:
	var lh := _line_height(font_size)
	match row.kind:
		&"title":
			_text(at, row.text, TEXT_COLOR, title_font_size)
		&"text":
			_text_wrapped(at, row.text, row.color, width)
		&"pair":
			_text(at, row.label, row.label_color)
			_text_right(at + Vector2(width, 0.0), row.value, row.value_color)
		&"badge":
			var text_w := _font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var badge := Rect2(at, Vector2(text_w + 12.0, lh + 2.0))
			draw_rect(badge, row.color)
			# Texte sombre : toutes les couleurs d'état et de fleur sont assez claires
			_text(at + Vector2(6.0, 1.0), row.text, Color(0.08, 0.08, 0.08))
			if row.note != "":
				_text(at + Vector2(badge.size.x + 8.0, 1.0), row.note, DIM_COLOR)
		&"gauge":
			_text(at, row.label, DIM_COLOR)
			_text_right(at + Vector2(width, 0.0), row.value, TEXT_COLOR)
			var bar := Rect2(at + Vector2(0.0, lh + 1.0), Vector2(width, gauge_height))
			_draw_gauge(bar, row.ratio, row.color, row.ticks)
		&"compass":
			_draw_compass(at + Vector2(width * 0.5, compass_radius + 8.0), row.angle, row.color,
					row.distance, row.distance_ratio)


## Jauge horizontale remplie à [param ratio], avec des repères aux fractions [param ticks].
func _draw_gauge(rect: Rect2, ratio: float, color: Color, ticks: Array) -> void:
	draw_rect(rect, GAUGE_BG_COLOR)
	var fill := rect
	fill.size.x *= clampf(ratio, 0.0, 1.0)
	draw_rect(fill, color)
	for t in ticks:
		var x: float = rect.position.x + rect.size.x * clampf(t, 0.0, 1.0)
		draw_line(Vector2(x, rect.position.y - 3.0), Vector2(x, rect.end.y + 3.0), TEXT_COLOR, 1.5)


## Boussole de danse centrée en [param center] : le soleil en haut, comme le haut du
## rayon pour une abeille qui danse, et une flèche vers la source à [param angle] du soleil.
## La longueur de la flèche suit [param distance_ratio] (distance / max_source_distance),
## comme la durée de la phase frétillante suit la distance dans une vraie danse.
## [param distance] (m) est écrite à l'opposé de la flèche, pour ne pas la recouvrir.
func _draw_compass(center: Vector2, angle: float, color: Color, distance: float,
		distance_ratio: float) -> void:
	draw_arc(center, compass_radius, 0.0, TAU, 48, BORDER_COLOR, 1.5)
	# Cercle intermédiaire : repère de la moitié de max_source_distance
	draw_arc(center, compass_radius * 0.5, 0.0, TAU, 32, BORDER_COLOR, 1.0)
	draw_circle(center + Vector2(0.0, -compass_radius), 6.0, SUN_COLOR)

	# get_dance_angle tourne autour de +Y (sens trigonométrique vu du dessus).
	# À l'écran, l'axe Y descend : le même sens s'obtient avec une rotation négative.
	var dir := Vector2.UP.rotated(-angle)
	var length := (compass_radius - 8.0) * lerpf(compass_min_arrow, 1.0, distance_ratio)
	var tip := center + dir * length
	draw_line(center, tip, color, 3.0)
	var side := dir.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 7.0, tip + side, tip - side]), color)
	draw_circle(center, 3.0, TEXT_COLOR)

	# Distance de l'autre côté du centre, centrée sur son point d'ancrage
	var text := "%.0f m" % distance
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var anchor := center - dir * compass_radius * 0.55
	_text(anchor - Vector2(text_size.x * 0.5, _line_height(font_size) * 0.5), text, TEXT_COLOR)

# =============================================================================
# Texte
# =============================================================================

## Hauteur (px) d'une ligne de texte de taille [param fsize], interligne compris.
func _line_height(fsize: int) -> float:
	return get_theme_default_font().get_height(fsize) + 3.0


## Texte dont le coin haut gauche est en [param pos].
func _text(pos: Vector2, text: String, color: Color, fsize := -1) -> void:
	var s := font_size if fsize < 0 else fsize
	# draw_string place la ligne de base en pos : on ajoute l'ascendante
	draw_string(_font, pos + Vector2(0.0, _font.get_ascent(s)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, s, color)
			
## Texte renvoyé à la ligne dans [param width] pixels, coin haut gauche en [param pos].
func _text_wrapped(pos: Vector2, text: String, color: Color, width: float) -> void:
	# Comme draw_string, draw_multiline_string place la ligne de base de la 1re ligne en pos
	draw_multiline_string(_font, pos + Vector2(0.0, _font.get_ascent(font_size)), text,
			HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, color)


## Texte dont le coin haut droit est en [param pos].
func _text_right(pos: Vector2, text: String, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(pos - Vector2(w, 0.0), text, color)

# =============================================================================
# Recrutement
# =============================================================================

## Chaîne de recrutement, de la danseuse la plus proche à la plus ancienne.
## La première est toujours affichée. On ne remonte au-delà que si la danseuse
## connaît encore la même fleur : sinon elle a changé de source, et son propre
## recrutement concerne une autre fleur. 4 maillons au plus, ce qui protège aussi
## d'un cycle (A recrutée par B, recrutée par A).
func _recruitment_chain(bee: Bee) -> PackedStringArray:
	var names := PackedStringArray()
	var dancer := bee.recruited_by
	while is_instance_valid(dancer) and names.size() < 4:
		names.append(str(dancer.name))
		if dancer.known_flower != bee.known_flower:
			break
		dancer = dancer.recruited_by
	return names

# =============================================================================
# Libellés et couleurs
# =============================================================================

func _state_label(state: StringName) -> String:
	return STATE_LABELS.get(state, String(state).trim_suffix("State"))


## Couleur de l'état, la même que celle des marqueurs.
func _state_color(state: StringName) -> Color:
	return BeeOverlay.STATE_COLORS.get(state, BeeOverlay.UNKNOWN_STATE_COLOR)


## Couleur des pelotes de pollen de [param flower], couleur du nectar à défaut.
func _flower_color(flower: Flower) -> Color:
	if flower != null and flower.pollen_material != null:
		return flower.pollen_material.albedo_color
	return NECTAR_COLOR


func _species_label(species: Flower.Species) -> String:
	match species:
		Flower.Species.LILY:
			return "Lys"
		Flower.Species.ROSE_BLUE:
			return "Rose bleue"
		Flower.Species.ROSE_RED:
			return "Rose rouge"
	return "?"


func _flower_state_label(flower: Flower) -> String:
	match flower.state:
		Flower.State.AVAILABLE:
			return "Disponible"
		Flower.State.BUSY:
			return "Occupée"
		Flower.State.EMPTY:
			return "Vide, en recharge"
	return "?"
