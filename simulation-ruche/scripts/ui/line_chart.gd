class_name LineChart extends Control
## Courbes simples tracées avec _draw() : une ligne par série, axe des X en heures
## simulées depuis le lancement. Utilisé par StatsPanel.

# =============================================================================
# Constantes
# =============================================================================

## Marges (px) autour de la zone de tracé : graduations à gauche, heures en bas,
## titre et légende en haut.
const MARGIN_LEFT := 52.0
const MARGIN_RIGHT := 10.0
const MARGIN_TOP := 26.0
const MARGIN_BOTTOM := 20.0

## Taille (px) du texte du graphique.
const FONT_SIZE := 12

## Nombre d'intervalles de la grille horizontale.
const GRID_STEPS := 4

const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.4)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.75)

# =============================================================================
# Paramètres
# =============================================================================

## Titre affiché en haut à gauche, suivi de la légende.
var title := ""

## Maximum de l'axe Y ; 0 = ajusté aux données (avec 10 % de marge).
var y_max := 0.0

## Format des graduations de l'axe Y (ex. "%.0f", "%.0f %%").
var y_format := "%.0f"

# =============================================================================
# Données
# =============================================================================

## Abscisses (heures simulées), communes à toutes les séries.
var _xs := PackedFloat32Array()

## Séries : {name: String, color: Color, values: PackedFloat32Array}.
var _series: Array[Dictionary] = []

# =============================================================================
# Cycle de vie
# =============================================================================

func _init() -> void:
	custom_minimum_size = Vector2(0, 180)
	# Simple affichage : ne capte pas la souris
	mouse_filter = MOUSE_FILTER_IGNORE


## Remplace les données et redessine.
func set_data(xs: PackedFloat32Array, series: Array[Dictionary]) -> void:
	_xs = xs
	_series = series
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	_draw_title_and_legend(font)

	var plot := Rect2(MARGIN_LEFT, MARGIN_TOP,
			size.x - MARGIN_LEFT - MARGIN_RIGHT, size.y - MARGIN_TOP - MARGIN_BOTTOM)
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return

	# Échelle Y : imposée, ou ajustée au maximum des données
	var top := y_max
	if top <= 0.0:
		for s in _series:
			for v in s["values"]:
				top = maxf(top, v)
		top = maxf(top, 1.0) * 1.1

	# Grille horizontale et graduations
	for i in GRID_STEPS + 1:
		var t := float(i) / GRID_STEPS
		var y := plot.end.y - t * plot.size.y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOR)
		draw_string(font, Vector2(0.0, y + 4.0), y_format % (top * t),
				HORIZONTAL_ALIGNMENT_RIGHT, MARGIN_LEFT - 6.0, FONT_SIZE, TEXT_COLOR)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, AXIS_COLOR)

	if _xs.size() < 2:
		draw_string(font, plot.position + Vector2(8.0, plot.size.y * 0.5), "En attente de relevés…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		return

	# Axe X : première et dernière heure relevées
	var x0 := _xs[0]
	var x1 := _xs[_xs.size() - 1]
	var span := maxf(x1 - x0, 0.001)
	var label_y := plot.end.y + 15.0
	draw_string(font, Vector2(plot.position.x, label_y), "%.1f h" % x0,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(plot.end.x - 80.0, label_y), "%.1f h" % x1,
			HORIZONTAL_ALIGNMENT_RIGHT, 80.0, FONT_SIZE, TEXT_COLOR)

	# Courbes
	for s in _series:
		var values: PackedFloat32Array = s["values"]
		var points := PackedVector2Array()
		for i in mini(values.size(), _xs.size()):
			var px := plot.position.x + (_xs[i] - x0) / span * plot.size.x
			var py := plot.end.y - clampf(values[i] / top, 0.0, 1.0) * plot.size.y
			points.append(Vector2(px, py))
		if points.size() >= 2:
			draw_polyline(points, s["color"], 2.0, true)


## Titre puis légende (pastille de couleur et nom de chaque série) sur la même ligne.
func _draw_title_and_legend(font: Font) -> void:
	var baseline := 14.0
	draw_string(font, Vector2(0.0, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	var x := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 18.0
	for s in _series:
		var label: String = s["name"]
		draw_rect(Rect2(x, baseline - 9.0, 10.0, 10.0), s["color"])
		draw_string(font, Vector2(x + 14.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		x += 14.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 14.0
