extends CanvasLayer
## Affichage de contrôle : état des abeilles, de la ruche et des fleurs.
## F3 pour l'afficher ou le masquer.
##
## Mise en place : ajouter un nœud CanvasLayer dans Main, lui attacher ce script,
## puis glisser le nœud Simulation dans le champ « Simulation » de l'inspecteur.

## Simulation observée
@export var simulation: Simulation

## Intervalle (s) de rafraîchissement du texte
@export var refresh_interval := 0.5

## Ordre d'affichage des états (les états inconnus sont ajoutés à la fin)
const STATE_ORDER := ["IDLE", "LEAVE", "SCOUT", "WATCH", "GO", "FORAGE", "RETURN", "ENTER", "UNLOAD", "DANCE", "RECEIVER"]

var _label: Label
var _timer := 0.0

## Temps (s) écoulé depuis le lancement, pour mesurer le « dernier butinage »
var _elapsed := 0.0

## Les signaux des fleurs sont connectés une seule fois, quand la liste est prête
var _connected := false

## Butinages terminés par espèce, et instant du dernier
var _harvests := {}
var _last_harvest := {}


func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	# Police à chasse fixe pour aligner les colonnes
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Monospace", "DejaVu Sans Mono", "Consolas"])

	_label = Label.new()
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_label)
	add_child(panel)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	if simulation == null:
		return
	_elapsed += delta
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	_connect_flowers()
	_label.text = _build_text()


## Compte les butinages terminés, par espèce.
## Fait ici et non dans _ready : Simulation remplit sa liste de fleurs un peu plus tard.
func _connect_flowers() -> void:
	if _connected or simulation.flowers.is_empty():
		return
	for flower in simulation.flowers:
		flower.foraging_finished.connect(_on_foraging_finished)
	_connected = true


func _on_foraging_finished(flower: Flower) -> void:
	var sp: Flower.Species = flower.species
	_harvests[sp] = _harvests.get(sp, 0) + 1
	_last_harvest[sp] = _elapsed


func _build_text() -> String:
	var sim := simulation
	var lines: PackedStringArray = []

	# --- Temps ---
	var hours := fmod(sim.sky.current_time, 24.0)
	lines.append("Heure simulée %02d:%02d (%s) | FPS %d" % [
		int(hours), int(fmod(hours, 1.0) * 60.0),
		"jour" if sim.is_daytime() else "nuit", Engine.get_frames_per_second()])

	# --- Abeilles : nombre par état ---
	var counts := {}
	var with_source := 0
	var carried := 0.0
	for node in sim.bees_container.get_children():
		var bee := node as Bee
		if bee == null or bee.current_state == null:
			continue
		var key := String(bee.current_state.get_script().get_global_name()).trim_suffix("State").to_upper()
		counts[key] = counts.get(key, 0) + 1
		if bee.known_flower != null:
			with_source += 1
		carried += bee.get_carried_nectar()

	lines.append("")
	lines.append("ABEILLES (%d) | connaissent une source : %d | nectar porté : %.1f µL" % [
		sim.bees_container.get_child_count(), with_source, carried])
	var names: Array = STATE_ORDER.duplicate()
	for key in counts:
		if not names.has(key):
			names.append(key)
	var parts: PackedStringArray = []
	for key in names:
		parts.append("%s %d" % [key, counts.get(key, 0)])
	for i in range(0, parts.size(), 5):
		lines.append("  " + "   ".join(parts.slice(i, i + 5)))

	# --- Ruche (les valeurs absentes de hive.gd s'affichent « ? ») ---
	var hive := sim.hive
	var stock: Variant = hive.get("nectar_stock")
	var sugar: Variant = hive.get("sugar_stock")
	lines.append("")
	lines.append("RUCHE | nectar stocké : %s | sucre : %s | receveuses : %d (%d libres) | en recherche : %d" % [
		Units.volume(stock) if stock != null else "?",
		Units.mass(sugar) if sugar != null else "?",
		hive.get_receiver_count(), hive.get_free_receiver_count(), hive.get_searching_count()])

	# --- Fleurs : états par espèce ---
	var stats := {}   # Species -> [disponibles, occupées, vides, total]
	for flower in sim.flowers:
		var s: Array = stats.get(flower.species, [0, 0, 0, 0])
		s[flower.state] += 1
		s[3] += 1
		stats[flower.species] = s

	lines.append("")
	lines.append("FLEURS (%d)" % sim.flowers.size())
	var total := 0
	for sp in Flower.Species.values():
		var s: Array = stats.get(sp, [0, 0, 0, 0])
		var count: int = _harvests.get(sp, 0)
		total += count
		var ago := "-"
		if _last_harvest.has(sp):
			ago = "il y a %d s" % int(_elapsed - _last_harvest[sp])
		lines.append("  %s %2d fleurs | butinages %3d | dispo %d  occ. %d  vides %d | dernier : %s" % [
			String(Flower.Species.keys()[sp]).rpad(10), s[3], count, s[0], s[1], s[2], ago])
	var per_minute := total / maxf(_elapsed / 60.0, 0.1)
	lines.append("  Total : %d butinages (%.1f / min)" % [total, per_minute])

	return "\n".join(lines)
