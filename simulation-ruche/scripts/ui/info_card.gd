class_name InfoCard extends RefCounted
## Fiche d'information dessinée à l'écran par BeeOverlay (ruche, fleur).
## On la remplit ligne par ligne (title, section, pair, gauge, bar, note),
## get_card_size() la mesure pour la placer, puis draw() la dessine.
## Reconstruite à chaque image : les valeurs changent en continu, et une
## vingtaine de petits dictionnaires par image ne coûtent rien.
## Même principe que les panneaux de BeeHud, en plus grand et découpé en sections.

# =============================================================================
# Couleurs
# =============================================================================

## Fond de la fiche, assez opaque pour rester lisible sur le terrain comme sur le rayon.
const PANEL_COLOR := Color(0.07, 0.07, 0.08, 0.88)
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const TEXT_COLOR := Color(0.96, 0.96, 0.96)
const DIM_COLOR := Color(0.70, 0.70, 0.74)
const SECTION_COLOR := Color(0.55, 0.55, 0.60)

## Partie vide des jauges.
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.12)

## Repères verticaux des jauges (seuils).
const TICK_COLOR := Color(1.0, 1.0, 1.0, 0.9)

## Largeur (px) de la bande colorée du bord gauche, à la couleur de l'objet décrit.
const ACCENT_WIDTH := 6.0

## Espace (px) au-dessus d'un titre de section, pour séparer les groupes.
const SECTION_SPACING := 10.0

# =============================================================================
# Réglages (recopiés depuis les exports de BeeOverlay par _new_card)
# =============================================================================

## Taille (px) du texte courant.
var font_size := 18

## Taille (px) du titre.
var title_font_size := 26

## Largeur totale (px) de la fiche.
var width := 380.0

## Marge intérieure (px).
var padding := 14.0

## Épaisseur (px) des jauges.
var gauge_height := 8.0

## Couleur de la bande du bord gauche.
var accent := Color.WHITE

## Lignes à dessiner, dans l'ordre.
var _rows: Array[Dictionary] = []


func _init(accent_color := Color.WHITE) -> void:
	accent = accent_color

# =============================================================================
# Remplissage
# =============================================================================

## Titre en grand, suivi d'un sous-titre précédé d'une pastille [param subtitle_color].
func title(text: String, subtitle := "", subtitle_color := DIM_COLOR) -> void:
	_rows.append({"kind": &"title", "text": text, "subtitle": subtitle, "color": subtitle_color})


## Titre de section en petites capitales, prolongé d'un filet.
func section(text: String) -> void:
	_rows.append({"kind": &"section", "text": text})


## Libellé à gauche, valeur alignée à droite.
func pair(label: String, value: String, value_color := TEXT_COLOR) -> void:
	_rows.append({"kind": &"pair", "label": label, "value": value, "color": value_color})


## Libellé et valeur, puis une jauge pleine largeur remplie à [param ratio] (0 à 1).
## [param ticks] : repères verticaux (seuils), en fractions de la largeur.
func gauge(label: String, value: String, ratio: float, color: Color, ticks: Array = []) -> void:
	_rows.append({"kind": &"gauge", "label": label, "value": value,
			"ratio": ratio, "color": color, "ticks": ticks})


## Libellé, barre courte et valeur sur une seule ligne. Pour comparer plusieurs
## grandeurs du même ordre (danses par espèce).
func bar(label: String, value: String, ratio: float, color: Color) -> void:
	_rows.append({"kind": &"bar", "label": label, "value": value, "ratio": ratio, "color": color})


## Ligne de texte libre.
func note(text: String, color := DIM_COLOR) -> void:
	_rows.append({"kind": &"note", "text": text, "color": color})

# =============================================================================
# Mesure
# =============================================================================

## Taille (px) de la fiche, marges comprises.
func get_card_size(font: Font) -> Vector2:
	var height := padding * 2.0
	for row in _rows:
		height += _row_height(font, row)
	return Vector2(width, height)


## Largeur (px) disponible pour le contenu, entre la bande et la marge droite.
func _inner_width() -> float:
	return width - ACCENT_WIDTH - 2.0 * padding


## Les titres de section sont plus petits que le texte courant.
func _section_font_size() -> int:
	return maxi(roundi(font_size * 0.72), 10)


## Hauteur (px) occupée par une ligne.
func _row_height(font: Font, row: Dictionary) -> float:
	var lh := font.get_height(font_size)
	match row.kind:
		&"title":
			var h := font.get_height(title_font_size) + 4.0
			if not row.subtitle.is_empty():
				h += lh + 2.0
			return h
		&"section":
			return SECTION_SPACING + font.get_height(_section_font_size()) + 4.0
		&"gauge":
			return lh + 2.0 + gauge_height + 8.0
		&"pair", &"bar":
			return lh + 4.0
		&"note":
			return lh + 2.0
	return lh

# =============================================================================
# Dessin
# =============================================================================

## Dessine la fiche sur [param canvas], coin haut gauche en [param pos].
func draw(canvas: CanvasItem, pos: Vector2, font: Font) -> void:
	var card := Rect2(pos, get_card_size(font))
	canvas.draw_rect(card, PANEL_COLOR)
	canvas.draw_rect(Rect2(pos, Vector2(ACCENT_WIDTH, card.size.y)), accent)
	canvas.draw_rect(card, BORDER_COLOR, false, 1.0)

	var at := pos + Vector2(ACCENT_WIDTH + padding, padding)
	var inner := _inner_width()
	for row in _rows:
		_draw_row(canvas, font, row, at, inner)
		at.y += _row_height(font, row)


## Dessine une ligne, coin haut gauche en [param at], sur [param inner] pixels de large.
func _draw_row(canvas: CanvasItem, font: Font, row: Dictionary, at: Vector2, inner: float) -> void:
	var lh := font.get_height(font_size)
	match row.kind:
		&"title":
			_text(canvas, font, at, row.text, title_font_size, TEXT_COLOR)
			if not row.subtitle.is_empty():
				var sub_y := at.y + font.get_height(title_font_size) + 4.0
				var r := font_size * 0.3
				canvas.draw_circle(Vector2(at.x + r, sub_y + lh * 0.5), r, row.color)
				_text(canvas, font, Vector2(at.x + 2.0 * r + 8.0, sub_y), row.subtitle, font_size, row.color)

		&"section":
			var fs := _section_font_size()
			var sec_y := at.y + SECTION_SPACING
			var label: String = row.text.to_upper()
			_text(canvas, font, Vector2(at.x, sec_y), label, fs, SECTION_COLOR)
			# Filet qui prolonge le titre jusqu'au bord droit
			var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var line_y := sec_y + font.get_height(fs) * 0.5
			if text_w + 8.0 < inner:
				canvas.draw_line(Vector2(at.x + text_w + 8.0, line_y),
						Vector2(at.x + inner, line_y), BORDER_COLOR, 1.0)

		&"pair":
			_text(canvas, font, at, row.label, font_size, DIM_COLOR)
			_text_right(canvas, font, Vector2(at.x + inner, at.y), row.value, font_size, row.color)

		&"gauge":
			_text(canvas, font, at, row.label, font_size, DIM_COLOR)
			_text_right(canvas, font, Vector2(at.x + inner, at.y), row.value, font_size, TEXT_COLOR)
			var track := Rect2(at.x, at.y + lh + 2.0, inner, gauge_height)
			_draw_gauge(canvas, track, row.ratio, row.color, row.ticks)

		&"bar":
			# Libellé dans la colonne de gauche, valeur à droite, barre entre les deux
			_text(canvas, font, at, row.label, font_size, DIM_COLOR)
			_text_right(canvas, font, Vector2(at.x + inner, at.y), row.value, font_size, TEXT_COLOR)
			var value_w := font.get_string_size(row.value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var start := at.x + inner * 0.42
			var end := at.x + inner - value_w - 10.0
			if end > start:
				var bar_track := Rect2(start, at.y + (lh - gauge_height) * 0.5, end - start, gauge_height)
				_draw_gauge(canvas, bar_track, row.ratio, row.color, [])

		&"note":
			_text(canvas, font, at, row.text, font_size, row.color)


## Jauge : fond, partie remplie à [param ratio], puis repères [param ticks].
func _draw_gauge(canvas: CanvasItem, track: Rect2, ratio: float, color: Color, ticks: Array) -> void:
	canvas.draw_rect(track, TRACK_COLOR)
	var fill := track
	fill.size.x = track.size.x * clampf(ratio, 0.0, 1.0)
	if fill.size.x > 0.0:
		canvas.draw_rect(fill, color)
	for t in ticks:
		var x := track.position.x + track.size.x * clampf(t, 0.0, 1.0)
		canvas.draw_line(Vector2(x, track.position.y - 3.0), Vector2(x, track.end.y + 3.0), TICK_COLOR, 2.0)


## Texte dont le haut (et non la ligne de base) est en [param pos].
func _text(canvas: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, color: Color) -> void:
	canvas.draw_string(font, pos + Vector2(0.0, font.get_ascent(fs)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Texte aligné à droite sur [param pos].x.
func _text_right(canvas: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(canvas, font, pos - Vector2(w, 0.0), text, fs, color)
