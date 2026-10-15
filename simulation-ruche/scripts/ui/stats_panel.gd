class_name StatsPanel extends CanvasLayer
## Panneau de statistiques globales, F1 pour l'afficher ou le masquer.
## Trois onglets :
##   - Fleurs : caractéristiques et prévision par espèce (un massif par espèce),
##     état en direct, courbe des butineuses par espèce (concurrence du recrutement) ;
##   - Abeilles : répartition par état, courbe des sorties, danses et receveuses ;
##   - Bilan : composition des réserves par espèce, comparée au rang prévu.
##
## Les données viennent de StatsCollector, créé ici comme enfant : il relève
## l'historique en permanence, même panneau fermé. Le panneau n'est rafraîchi
## que lorsqu'il est visible.
##
## Mise en place : ajouter un nœud CanvasLayer dans Main, lui attacher ce script,
## puis glisser le nœud Simulation dans le champ « Simulation » de l'inspecteur.

# =============================================================================
# Constantes
# =============================================================================

## États dans l'ordre d'affichage : super-état Ruche, puis Dehors.
const STATE_ORDER: Array[StringName] = [
	&"IdleState", &"WatchState", &"DanceState", &"TrembleState", &"UnloadState",
	&"ReceiveState", &"LeaveState", &"EnterState",
	&"ScoutState", &"GoState", &"ForageState", &"ReturnState",
]

## Libellés des états, par nom de classe.
const STATE_LABELS := {
	&"IdleState": "Repos",
	&"WatchState": "Suit une danse",
	&"DanceState": "Danse frétillante",
	&"TrembleState": "Danse trémulante",
	&"UnloadState": "Déchargement",
	&"ReceiveState": "Receveuse",
	&"LeaveState": "Sortie de la ruche",
	&"EnterState": "Entrée dans la ruche",
	&"ScoutState": "Exploration",
	&"GoState": "Vol vers une source",
	&"ForageState": "Butinage",
	&"ReturnState": "Retour",
}

## Largeur (en caractères) des barres de répartition.
const BAR_WIDTH := 24

# --- Aération ---

## Marges (px) intérieures du panneau, autour de l'en-tête et des onglets.
const PANEL_MARGIN := 14

## Espace (px) entre l'en-tête et la barre d'onglets.
const HEADER_GAP := 10

## Marges (px) du contenu de chaque onglet : en haut, l'écart avec la barre
## d'onglets ; à droite, la place de la barre de défilement.
const TAB_MARGIN_TOP := 12
const TAB_MARGIN_SIDE := 8
const TAB_MARGIN_RIGHT := 16

## Espace (px) entre deux blocs d'un onglet (texte, tableaux, courbe).
const BLOCK_GAP := 22

## Espace (px) entre deux colonnes et entre deux lignes des tableaux.
const TABLE_H_GAP := 22
const TABLE_V_GAP := 6

## Espace (px) supplémentaire entre deux lignes de texte.
const LINE_GAP := 3

## Taille (px) du texte courant et des titres de section.
const TEXT_SIZE := 14
const TITLE_SIZE := 16

## Couleurs du texte (BBCode).
const DIM_HEX := "#9a9a9a"
const BAR_BG_HEX := "#ffffff22"

## Couleurs des courbes de l'onglet Abeilles.
const OUTSIDE_COLOR := Color("#7fb3ff")
const DANCE_COLOR := Color("#ffd166")
const RECEIVER_COLOR := Color("#9be38c")

## Couleur d'une espèce sans matériau de pollen, ou d'origine inconnue.
const UNKNOWN_COLOR := Color("#bbbbbb")

# =============================================================================
# Paramètres
# =============================================================================

## Simulation observée.
@export var simulation: Simulation

## Touche d'affichage. keycode et non physical_keycode, comme les autres
## raccourcis de l'interface (BeeOverlay) : F1 est la même touche en AZERTY.
@export var toggle_key: Key = KEY_F1

## Intervalle (s réelles) de rafraîchissement de l'affichage.
@export var refresh_interval := 0.5

## Part de la largeur de l'écran occupée par le panneau, collé à droite :
## la simulation reste visible à gauche.
@export_range(0.3, 1.0) var width_ratio := 0.55

# =============================================================================
# État interne
# =============================================================================

var _collector: StatsCollector
var _header: Label
var _flowers_text: RichTextLabel
var _flowers_chart: LineChart
var _bees_text: RichTextLabel
var _bees_chart: LineChart
var _summary_text: RichTextLabel
var _summary_chart: LineChart
var _timer := 0.0

## Couleur de pollen par espèce (Flower.Species → Color), relevée une fois.
var _species_colors := {}

# =============================================================================
# Cycle de vie
# =============================================================================

func _ready() -> void:
	# Au-dessus de SimulationHud (couche 100)
	layer = 110
	visible = false
	if simulation == null:
		push_warning("StatsPanel : simulation non assignée, le panneau restera vide")
	_collector = StatsCollector.new()
	_collector.name = "StatsCollector"
	_collector.simulation = simulation
	add_child(_collector)
	_build_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		visible = not visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	_refresh()

# =============================================================================
# Construction de l'interface
# =============================================================================

func _build_ui() -> void:
	var panel := PanelContainer.new()
	# Collé au bord droit, sur toute la hauteur, avec une marge
	panel.anchor_left = 1.0 - width_ratio
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 12.0
	panel.offset_right = -12.0
	panel.offset_bottom = -12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	style.set_content_margin_all(PANEL_MARGIN)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", HEADER_GAP)
	panel.add_child(box)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 14)
	box.add_child(_header)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Pas de focus clavier : Tab doit continuer à changer d'abeille suivie (CameraSwitcher)
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)

	var flowers_tab := _add_tab(tabs, "Fleurs")
	_flowers_text = _add_text(flowers_tab)
	_flowers_chart = _add_chart(flowers_tab, "Abeilles qui connaissent une source, par espèce")

	var bees_tab := _add_tab(tabs, "Abeilles")
	_bees_text = _add_text(bees_tab)
	_bees_chart = _add_chart(bees_tab, "Activité de la colonie")

	var summary_tab := _add_tab(tabs, "Bilan")
	_summary_text = _add_text(summary_tab)
	_summary_chart = _add_chart(summary_tab, "Part du sucre stocké, cumulée")
	_summary_chart.y_max = 100.0
	_summary_chart.y_format = "%.0f %%"


## Onglet défilant ; le nom du nœud sert de titre à l'onglet.
func _add_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.focus_mode = Control.FOCUS_NONE
	# Pas de défilement horizontal : les tableaux prennent la largeur du panneau
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	# Marge entre la barre d'onglets et le contenu, et de part et d'autre du contenu
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", TAB_MARGIN_TOP)
	margin.add_theme_constant_override("margin_left", TAB_MARGIN_SIDE)
	margin.add_theme_constant_override("margin_right", TAB_MARGIN_RIGHT)
	margin.add_theme_constant_override("margin_bottom", TAB_MARGIN_SIDE)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Écart entre les blocs : texte, courbe
	box.add_theme_constant_override("separation", BLOCK_GAP)
	margin.add_child(box)
	return box


## Zone de texte BBCode (tableaux), à hauteur de son contenu.
func _add_text(box: VBoxContainer) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	text.add_theme_font_size_override("bold_font_size", TEXT_SIZE)
	# Espaces entre colonnes et entre lignes des tableaux, plutôt que des espaces
	# ajoutées dans les cellules
	text.add_theme_constant_override("table_h_separation", TABLE_H_GAP)
	text.add_theme_constant_override("table_v_separation", TABLE_V_GAP)
	text.add_theme_constant_override("line_separation", LINE_GAP)
	box.add_child(text)
	return text


func _add_chart(box: VBoxContainer, title: String) -> LineChart:
	var chart := LineChart.new()
	chart.title = title
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(chart)
	return chart

# =============================================================================
# Rafraîchissement
# =============================================================================

func _refresh() -> void:
	if simulation == null or not _collector.is_ready():
		_header.text = "Statistiques : en attente de la simulation…"
		return
	var live := _collector.live()
	var hours := fmod(simulation.sky.current_time, 24.0)
	_header.text = "Heure simulée %02d:%02d (%s) · %.1f h simulées depuis le lancement · F1 pour fermer" % [
		int(hours), int(fmod(hours, 1.0) * 60.0),
		"jour" if simulation.is_daytime() else "nuit", simulation.sim_hours]
	_refresh_flowers(live)
	_refresh_bees(live)
	_refresh_summary()

# --- Fleurs -------------------------------------------------------------------

func _refresh_flowers(live: Dictionary) -> void:
	var sim := simulation
	var t := ""

	# Caractéristiques et prévision (fixes : calculées au lancement)
	t += _title("Caractéristiques et prévision")
	t += "[color=%s]Rentabilité calculée avec la formule des abeilles, pour un trajet seul : " % DIM_HEX
	t += "jabot plein sur des fleurs pleines, sans concurrence. Débit max. : sucre que le massif "
	t += "sécrète par heure simulée quand toutes ses fleurs sont vides (plafond de la récolte).[/color]\n\n"
	t += "[table=8]"
	t += _header_row(["Espèce", "Fleurs", "Distance", "Sucre", "τ sécrétion",
			"Rentabilité", "Rang prévu", "Débit max."])
	for sp in _collector.species_list:
		var p: Dictionary = _collector.predictions[sp]
		t += _row([
			_species_tag(sp),
			str(p["flowers"]),
			_format_distance(p["distance"]),
			"%d %%" % roundi(p["concentration"] * 100.0),
			"%.1f h" % p["tau"],
			"%.2f" % p["profitability"],
			str(p["rank"]),
			Units.mass(p["max_sugar_rate"]) + "/h",
		])
	t += "[/table]\n\n\n"

	# État en direct
	t += _title("En direct")
	t += "[table=8]"
	t += _header_row(["Espèce", "Disponibles", "Occupées", "Fermées", "Stock moyen",
			"Butineuses", "Recrues en route", "Danses"])
	var flowers: Dictionary = live["flowers"]
	var max_res := maxf(sim.max_resource, 0.001)
	for sp in _collector.species_list:
		var f: Dictionary = flowers.get(sp, {"count": 0, "available": 0, "busy": 0, "empty": 0, "resource": 0.0})
		var mean_fill: float = f["resource"] / maxf(f["count"], 1) / max_res
		t += _row([
			_species_tag(sp),
			str(f["available"]),
			str(f["busy"]),
			_highlight_if(f["empty"] > 0, str(f["empty"])),
			"%d %%" % roundi(mean_fill * 100.0),
			str(live["foragers"].get(sp, 0)),
			str(live["recruits"].get(sp, 0)),
			str(live["dances"].get(sp, 0)),
		])
	t += "[/table]"
	_flowers_text.text = t

	# Courbe : abeilles qui connaissent une fleur de chaque espèce
	var series: Array[Dictionary] = []
	for sp in _collector.species_list:
		var values := PackedFloat32Array()
		for sample in _collector.samples:
			values.append(sample["foragers"].get(sp, 0))
		series.append({"name": _species_label(sp), "color": _species_color(sp), "values": values})
	_flowers_chart.set_data(_sample_hours(), series)

# --- Abeilles -----------------------------------------------------------------

func _refresh_bees(live: Dictionary) -> void:
	var hive := simulation.hive
	var total: int = live["total"]
	var t := ""
	t += _title("Colonie")
	t += "[b]%d abeilles[/b] · dehors %d · connaissent une source %d\n" % [
		total, live["outside"], live["with_source"]]
	t += "Receveuses %d (%d libres) · butineuses qui cherchent une receveuse %d · danses trémulantes %d\n\n\n" % [
		hive.get_receiver_count(), hive.get_free_receiver_count(),
		hive.get_searching_count(), hive.get_tremble_count()]
	t += _title("Répartition par état")

	# Répartition par état, dans l'ordre Ruche puis Dehors ; états inconnus à la fin
	var states: Dictionary = live["states"]
	var order: Array[StringName] = STATE_ORDER.duplicate()
	for state_name in states:
		if not order.has(state_name):
			order.append(state_name)
	t += "[table=4]"
	t += _header_row(["État", "Abeilles", "Part", ""])
	for state_name in order:
		var count: int = states.get(state_name, 0)
		var ratio := count / float(maxi(total, 1))
		t += _row([
			STATE_LABELS.get(state_name, String(state_name)),
			str(count),
			"%d %%" % roundi(ratio * 100.0),
			_bar(ratio, OUTSIDE_COLOR.to_html(false) if _is_field_state(state_name) else "e0c070"),
		])
	t += "[/table]"
	_bees_text.text = t

	# Courbes : sorties (recrutement), danses (boucle positive), receveuses (saturation)
	var outside := PackedFloat32Array()
	var dances := PackedFloat32Array()
	var receivers := PackedFloat32Array()
	for sample in _collector.samples:
		outside.append(sample["outside"])
		dances.append(sample["dances"])
		receivers.append(sample["receivers"])
	var series: Array[Dictionary] = [
		{"name": "Dehors", "color": OUTSIDE_COLOR, "values": outside},
		{"name": "Danses frétillantes", "color": DANCE_COLOR, "values": dances},
		{"name": "Receveuses", "color": RECEIVER_COLOR, "values": receivers},
	]
	_bees_chart.set_data(_sample_hours(), series)

# --- Bilan --------------------------------------------------------------------

func _refresh_summary() -> void:
	var hive := simulation.hive
	var sugar: Dictionary = hive.sugar_by_species
	var nectar: Dictionary = hive.nectar_by_species
	var recent := _collector.recent_sugar()
	var total_sugar := _sum(sugar)
	var total_nectar := _sum(nectar)
	var total_recent := _sum(recent)

	var t := ""
	t += _title("Réserves de la ruche")
	t += "Sucre %s · nectar %s\n" % [
		Units.mass(hive.sugar_stock), Units.volume(hive.nectar_stock)]
	t += "[color=%s]Part du sucre : énergie réellement rapportée. Dernière heure : régime actuel, " % DIM_HEX
	t += "sans le démarrage (ordre de découverte des sources par les éclaireuses).[/color]\n\n"

	# Espèces dans l'ordre du rang prévu, pour comparer directement les deux rangs
	var by_prediction: Array[int] = _collector.species_list.duplicate()
	by_prediction.sort_custom(func(a: int, b: int) -> bool:
		return _collector.predictions[a]["rank"] < _collector.predictions[b]["rank"])
	var observed_rank := _rank_by(sugar, by_prediction)

	t += "[table=8]"
	t += _header_row(["Espèce", "Rentabilité prévue", "Rang prévu", "Rang observé",
			"Sucre stocké", "Part du sucre", "Part du volume", "Part, dernière heure"])
	for sp in by_prediction:
		var p: Dictionary = _collector.predictions[sp]
		var s: float = sugar.get(sp, 0.0)
		t += _row([
			_species_tag(sp),
			"%.2f" % p["profitability"],
			str(p["rank"]),
			_highlight_if(observed_rank.get(sp, 0) != p["rank"], str(observed_rank.get(sp, "-"))),
			Units.mass(s),
			_percent(s, total_sugar),
			_percent(nectar.get(sp, 0.0), total_nectar),
			_percent(recent.get(sp, 0.0), total_recent),
		])
	# Nectar déposé sans espèce connue (ne devrait pas arriver) : affiché pour le repérer
	if sugar.has(-1):
		t += _row([_species_tag(-1), "-", "-", "-", Units.mass(sugar[-1]),
				_percent(sugar[-1], total_sugar), _percent(nectar.get(-1, 0.0), total_nectar),
				_percent(recent.get(-1, 0.0), total_recent)])
	t += "[/table]"
	_summary_text.text = t

	# Courbe : part cumulée de chaque espèce dans le sucre stocké
	var series: Array[Dictionary] = []
	for sp in _collector.species_list:
		var values := PackedFloat32Array()
		for sample in _collector.samples:
			var stock: Dictionary = sample["sugar"]
			var sample_total := _sum(stock)
			values.append(100.0 * stock.get(sp, 0.0) / sample_total if sample_total > 0.0 else 0.0)
		series.append({"name": _species_label(sp), "color": _species_color(sp), "values": values})
	_summary_chart.set_data(_sample_hours(), series)

# =============================================================================
# Utilitaires
# =============================================================================

## Abscisses des courbes : heure simulée de chaque relevé.
func _sample_hours() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for sample in _collector.samples:
		xs.append(sample["hour"])
	return xs


## Rang (1 = la plus grande valeur) de chaque espèce de [param species] dans
## [param values]. Les espèces sans récolte sont classées dernières.
func _rank_by(values: Dictionary, species: Array[int]) -> Dictionary:
	var sorted: Array[int] = species.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return values.get(a, 0.0) > values.get(b, 0.0))
	var ranks := {}
	for i in sorted.size():
		ranks[sorted[i]] = i + 1
	return ranks


func _sum(values: Dictionary) -> float:
	var total := 0.0
	for key in values:
		total += values[key]
	return total


func _percent(value: float, total: float) -> String:
	if total <= 0.0:
		return "-"
	return "%d %%" % roundi(100.0 * value / total)


## Distance de la scène, suivie de son équivalent sur le terrain réel (distance_scale).
func _format_distance(scene_m: float) -> String:
	var real := scene_m * simulation.distance_scale
	var real_text: String = "%.1f km" % (real / 1000.0) if real >= 1000.0 else "%d m" % roundi(real)
	return "%.0f m (≈ %s)" % [scene_m, real_text]


func _is_field_state(state_name: StringName) -> bool:
	return state_name in [&"ScoutState", &"GoState", &"ForageState", &"ReturnState"]


## Barre de texte : partie pleine colorée, reste en gris transparent.
func _bar(ratio: float, color_hex: String) -> String:
	var filled := roundi(clampf(ratio, 0.0, 1.0) * BAR_WIDTH)
	return "[color=#%s]%s[/color][color=%s]%s[/color]" % [
		color_hex, "█".repeat(filled), BAR_BG_HEX, "█".repeat(BAR_WIDTH - filled)]


## Texte en orange si [param condition] : signale un écart (fleurs fermées,
## rang observé différent du rang prévu).
func _highlight_if(condition: bool, text: String) -> String:
	return "[color=#ffa64d]%s[/color]" % text if condition else text


## Titre de section, un peu plus grand que le texte, suivi d'une ligne vide.
func _title(text: String) -> String:
	return "[font_size=%d][b]%s[/b][/font_size]\n\n" % [TITLE_SIZE, text]


func _header_row(cells: Array) -> String:
	var s := ""
	for c in cells:
		s += "[cell][b]%s[/b][/cell]" % c
	return s


func _row(cells: Array) -> String:
	var s := ""
	for c in cells:
		s += "[cell]%s[/cell]" % c
	return s


## Pastille de couleur suivie du nom de l'espèce.
func _species_tag(sp: int) -> String:
	return "[color=#%s]■[/color] %s" % [_species_color(sp).to_html(false), _species_label(sp)]


func _species_label(sp: int) -> String:
	if sp == -1:
		return "Origine inconnue"
	return Flower.SPECIES_LABELS.get(sp, "?")


## Couleur de pollen de [param sp], relevée sur la première fleur de chaque espèce
## (même principe que BeeOverlay). Parcours fait une seule fois.
func _species_color(sp: int) -> Color:
	if _species_colors.is_empty():
		for flower in simulation.flowers:
			if flower.pollen_material != null and not _species_colors.has(flower.species):
				_species_colors[flower.species] = flower.pollen_material.albedo_color
	return _species_colors.get(sp, UNKNOWN_COLOR)
