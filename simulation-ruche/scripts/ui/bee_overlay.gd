class_name BeeOverlay extends Control
## Surcouche 2D au-dessus du rendu 3D : un marqueur à l'écran pour chaque abeille,
## et une infobulle avec ses données pour l'abeille survolée ou épinglée.
## Les fleurs ont aussi une infobulle (survol ou clic), la ruche seulement au clic.
## En vue abeille, le tableau de bord (BeeHud) prend le relais pour l'abeille suivie.
##
## M : afficher / masquer les marqueurs.
## I : activer / désactiver les infobulles et le tableau de bord de la vue abeille.
## Clic gauche (infobulles actives) : épingler l'abeille, la fleur ou la ruche
## sous le curseur, ou désépingler. Un second clic sur la ruche épinglée la désépingle.
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

## Fond du cadre de l'infobulle.
const BOX_COLOR := Color(0.0, 0.0, 0.0, 0.75)

# =============================================================================
# Paramètres réglables
# =============================================================================

## Conteneur des abeilles créées par Simulation (Simulation/Bees).
@export var bees_container: Node3D

## Ruche dont on affiche les données. Facultatif : si vide, on prend
## la ruche de rattachement de la première abeille.
@export var hive: Hive

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
## Vaut aussi pour le pistil des fleurs et le centre de la ruche.
@export var pick_radius := 12.0

## Longueur (m) d'une abeille, pour calculer sa taille à l'écran.
## De près, toute l'abeille devient cliquable, pas seulement son centre.
@export var bee_size := 0.015

## Diamètre (m) d'une fleur, pour calculer sa taille à l'écran.
## De près, toute la corolle devient cliquable. Ordre de grandeur réel :
## 5 à 10 cm pour une rose, 10 à 15 cm pour un lys ; à ajuster aux modèles.
@export var flower_size := 0.1

## Diamètre (m) de la zone cliquable de la ruche, centrée sur le cadre.
## Un cadre Dadant de corps mesure environ 47 × 30 cm hors tout : une ruchette
## d'observation 1 cadre fait donc autour de 50 cm de large. À ajuster au modèle.
@export var hive_size := 0.5

## Taille de police (px) du texte de l'infobulle.
@export var font_size := 14

## Marge intérieure (px) des cadres de texte.
@export var padding := 6.0

@export_group("Touches")

## Touche qui affiche / masque les marqueurs. Comparée à la lettre produite
## selon la disposition du clavier : M est bien la touche M en AZERTY.
@export var markers_key: Key = KEY_M

## Touche qui active / désactive les infobulles et le tableau de bord de la vue abeille.
@export var info_key: Key = KEY_I

# =============================================================================
# Liens avec CameraSwitcher
# =============================================================================

## Abeille suivie par la caméra en vue abeille, null dans les vues fixes.
## Renseignée par CameraSwitcher à chaque changement de vue ou d'abeille,
## lue par BeeHud pour son tableau de bord.
var followed_bee: Bee = null

# =============================================================================
# État interne
# =============================================================================

## Marqueurs et infobulles masqués au lancement : on les active avec les touches.
var _markers_enabled := false
var _info_enabled := true

## Abeille épinglée par un clic : son infobulle reste affichée même sans survol.
var _pinned: Bee = null

## Fleur épinglée par un clic. Exclusive avec _pinned : épingler l'une désépingle l'autre.
var _pinned_flower: Flower = null

## Ruche épinglée par un clic. Exclusive avec les deux épingles précédentes.
var _pinned_hive := false

## Position à l'écran de chaque abeille visible à la dernière image.
## Sert à retrouver l'abeille sous la souris (survol et clic).
var _screen_positions: Dictionary[Bee, Vector2] = {}

## Rayon apparent (px) de chaque abeille visible à la dernière image.
var _screen_radii: Dictionary[Bee, float] = {}

## Position et rayon apparent (px) de chaque fleur visible à la dernière image.
## Calculés seulement quand les infobulles sont actives.
var _flower_positions: Dictionary[Flower, Vector2] = {}
var _flower_radii: Dictionary[Flower, float] = {}

## Centre du cadre de la ruche à l'écran et rayon apparent (px) de sa zone cliquable,
## à la dernière image. Valables seulement si _hive_visible.
var _hive_position := Vector2.ZERO
var _hive_radius := 0.0
var _hive_visible := false

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
	# Clic gauche, infobulles actives : épingle ce qui est sous le curseur,
	# dans l'ordre abeille, fleur, ruche ; un clic dans le vide désépingle tout
	if _info_enabled and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_pinned = _bee_at(event.position)
		_pinned_flower = _flower_at(event.position) if _pinned == null else null
		var on_hive := _pinned == null and _pinned_flower == null and _hive_at(event.position)
		# Un clic sur la ruche déjà épinglée la désépingle : de près, elle couvre
		# tout l'écran et on ne pourrait plus cliquer « dans le vide »
		_pinned_hive = on_hive and not _pinned_hive
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
			_pinned_flower = null
			_pinned_hive = false
		queue_redraw()

# =============================================================================
# Sélection (aussi utilisée par CameraSwitcher et BeeHud)
# =============================================================================

## Infobulles actives (touche I). Le tableau de bord de la vue abeille suit la même touche.
func is_info_enabled() -> bool:
	return _info_enabled


## Abeille épinglée par un clic, ou null. Permet à CameraSwitcher de passer
## en vue abeille directement sur l'abeille choisie.
func get_pinned_bee() -> Bee:
	return _pinned if is_instance_valid(_pinned) else null


## Épingle [param bee], ou désépingle avec null. Utilisé par CameraSwitcher
## pour que l'épingle suive l'abeille quand on change d'abeille avec Tab.
## Épingler une abeille lâche la fleur ou la ruche épinglée.
func set_pinned_bee(bee: Bee) -> void:
	_pinned = bee
	if bee != null:
		_pinned_flower = null
		_pinned_hive = false
	queue_redraw()


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


## Fleur sous [param pos], ou null. Même règle que _bee_at : pick_radius autour
## du pistil, ou la corolle entière si elle est plus grande à l'écran.
func _flower_at(pos: Vector2) -> Flower:
	var best: Flower = null
	var best_ratio := 1.0
	for flower in _flower_positions:
		var reach := maxf(pick_radius, _flower_radii[flower])
		var ratio := pos.distance_to(_flower_positions[flower]) / reach
		if ratio < best_ratio:
			best = flower
			best_ratio = ratio
	return best


## true si [param pos] tombe dans la zone cliquable de la ruche : pick_radius autour
## du centre du cadre de loin, un disque de diamètre hive_size de près.
func _hive_at(pos: Vector2) -> bool:
	return _hive_visible \
			and pos.distance_to(_hive_position) < maxf(pick_radius, _hive_radius)


## Ruche affichée : celle de l'inspecteur, sinon celle de la première abeille.
func _get_hive() -> Hive:
	if hive != null:
		return hive
	var bee := _first_bee()
	return bee.hive if bee != null else null


## Première abeille du conteneur, ou null. Sert à atteindre la ruche et la simulation
## sans ajouter de référence à régler dans l'inspecteur.
func _first_bee() -> Bee:
	if bees_container == null:
		return null
	for node in bees_container.get_children():
		var bee := node as Bee
		if bee != null:
			return bee
	return null

# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	# Repartir de zéro : un objet hors champ ne doit plus être sélectionnable
	_screen_positions.clear()
	_screen_radii.clear()
	_flower_positions.clear()
	_flower_radii.clear()
	_hive_visible = false
	if not (_markers_enabled or _info_enabled) or bees_container == null:
		return
	# Caméra réellement utilisée pour le rendu (celle pilotée par PhantomCameraHost)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Axe horizontal de l'écran, pour mesurer la taille apparente des objets
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

	if not _info_enabled:
		return

	# --- Infobulle ---
	# Fleurs et ruche repérées ici seulement : sans marqueur, elles ne servent qu'aux infobulles
	_locate_flowers(cam, cam_right)
	_locate_hive(cam, cam_right)

	# Priorité : abeille, fleur puis ruche épinglées, sinon ce qui est sous la souris
	# (abeille d'abord : une butineuse posée cache le pistil de sa fleur)
	var bee: Bee = null
	var flower: Flower = null
	var show_hive := false
	if is_instance_valid(_pinned):
		bee = _pinned
	elif is_instance_valid(_pinned_flower):
		flower = _pinned_flower
	elif _pinned_hive:
		show_hive = true
	else:
		# Pas de survol pour la ruche : de près elle remplit l'écran, et son infobulle
		# masquerait en permanence les abeilles qu'on regarde sur le cadre
		var mouse := get_local_mouse_position()
		bee = _bee_at(mouse)
		if bee == null:
			flower = _flower_at(mouse)

	var followed: Bee = followed_bee if is_instance_valid(followed_bee) else null
	# Pas d'infobulle pour l'abeille suivie : le tableau de bord affiche déjà ses données.
	# Épinglée mais hors champ : l'infobulle revient quand elle réapparaît
	if bee != null and bee != followed and _screen_positions.has(bee):
		var at := _screen_positions[bee]
		# L'anneau entoure le marqueur de loin, l'abeille entière de près
		var ring := maxf(marker_radius, _screen_radii[bee]) + 4.0
		draw_arc(at, ring, 0.0, TAU, 32, Color.WHITE, 1.5)
		_draw_tooltip(_bee_info(bee), at, ring)
	elif flower != null and _flower_positions.has(flower):
		var at := _flower_positions[flower]
		# L'anneau entoure la zone cliquable : le pistil de loin, la corolle de près
		var ring := maxf(pick_radius, _flower_radii[flower]) + 4.0
		draw_arc(at, ring, 0.0, TAU, 32, Color.WHITE, 1.5)
		_draw_tooltip(_flower_info(flower), at, ring)
	elif show_hive and _hive_visible:
		var ring := maxf(pick_radius, _hive_radius) + 4.0
		# De près, l'anneau déborderait de l'écran : on n'affiche que le cadre de texte,
		# posé sur le centre de la ruche (puis ramené dans l'écran par _draw_tooltip)
		if ring < 0.5 * minf(size.x, size.y):
			draw_arc(_hive_position, ring, 0.0, TAU, 48, Color.WHITE, 1.5)
		else:
			ring = 0.0
		_draw_tooltip(_hive_info(_get_hive()), _hive_position, ring)


## Calcule la position et le rayon apparent à l'écran de chaque fleur visible.
## Les fleurs s'inscrivent elles-mêmes dans le groupe « flowers » (Flower._ready).
func _locate_flowers(cam: Camera3D, cam_right: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(&"flowers"):
		var flower := node as Flower
		# simulation null : setup() pas encore appelé, stock non initialisé
		if flower == null or flower.simulation == null:
			continue
		# Pistil plutôt que l'origine du nœud (au pied de la tige) : c'est la partie visible
		var world := flower.get_landing_position()
		if not cam.is_position_in_frustum(world):
			continue
		var p := cam.unproject_position(world)
		var edge := cam.unproject_position(world + cam_right * flower_size * 0.5)
		_flower_positions[flower] = p
		_flower_radii[flower] = p.distance_to(edge)


## Calcule la position et le rayon apparent à l'écran de la ruche, si elle est visible.
## Repère : le centre du cadre plutôt que l'origine du nœud (posée au pied de la ruche),
## car c'est le cadre qu'on regarde et qu'on vise naturellement.
func _locate_hive(cam: Camera3D, cam_right: Vector3) -> void:
	var h := _get_hive()
	if h == null:
		return
	var world := h.get_comb_center()
	if not cam.is_position_in_frustum(world):
		return
	_hive_position = cam.unproject_position(world)
	var edge := cam.unproject_position(world + cam_right * hive_size * 0.5)
	_hive_radius = _hive_position.distance_to(edge)
	_hive_visible = true


## Dessine l'infobulle [param text] à droite de l'anneau de rayon [param ring],
## sans sortir de l'écran.
func _draw_tooltip(text: String, at: Vector2, ring: float) -> void:
	var box_size := _box_size(text, font_size)
	# À droite de l'anneau, centré verticalement, puis ramené dans l'écran
	var pos := at + Vector2(ring + 6.0, -box_size.y * 0.5)
	pos.x = clampf(pos.x, 0.0, size.x - box_size.x)
	pos.y = clampf(pos.y, 0.0, size.y - box_size.y)
	_draw_box(text, pos, font_size)


## Taille (px) du cadre nécessaire pour afficher [param text], marges comprises.
func _box_size(text: String, fsize: int) -> Vector2:
	var text_size := get_theme_default_font().get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	return text_size + Vector2.ONE * 2.0 * padding


## Dessine un cadre semi-transparent contenant [param text], coin haut gauche en [param pos].
func _draw_box(text: String, pos: Vector2, fsize: int) -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(pos, _box_size(text, fsize)), BOX_COLOR)
	# draw_multiline_string place la ligne de base de la première ligne en pos : on ajoute l'ascendante
	var baseline := pos + Vector2(padding, padding + font.get_ascent(fsize))
	draw_multiline_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)

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


## Texte affiché pour une abeille : une ligne par donnée utile au réglage des boucles.
func _bee_info(bee: Bee) -> String:
	var lines := PackedStringArray()
	lines.append(str(bee.name))
	lines.append("État : %s" % _state_name(bee).trim_suffix("State"))
	lines.append("Nectar : %.1f / %.1f" % [bee.nectar, bee.simulation.forage_capacity])

	var flower := bee.known_flower
	if is_instance_valid(flower):
		lines.append("Source : %s (%s)" % [flower.name, flower.get_species_label()])
		lines.append("Stock source : %.0f" % flower.resource)
		lines.append("Rentabilité : %.2f" % bee.known_profitability)
	else:
		lines.append("Source : aucune")

	# Le chrono n'avance que dehors (Bee._physics_process)
	if bee.current_state is FieldState:
		lines.append("Trajet : %.1f s" % bee.trip_time)
	return "\n".join(lines)


## Texte affiché pour une fleur : état de son automate, stock, et pression des abeilles.
func _flower_info(flower: Flower) -> String:
	var sim := flower.simulation
	var lines := PackedStringArray()
	lines.append("%s (%s)" % [flower.name, flower.get_species_label()])
	lines.append("État : %s" % flower.get_state_label())
	lines.append("Stock : %.0f / %.0f (seuil %.0f)" % [flower.resource, sim.max_resource, sim.threshold])
	lines.append("Rentabilité : %.2f" % flower.get_profitability())
	if flower.state == Flower.State.EMPTY:
		lines.append("Recharge : reste %s sur %s" % [
			_format_hours(flower.get_recharge_remaining()), _format_hours(flower.recharge_time)])
	# Réservée dès qu'une abeille décide d'y aller : une fleur « Disponible »
	# peut donc déjà être visée par une abeille en vol
	var claimant := flower.get_claimant()
	if claimant != null:
		lines.append("Réservée par : %s" % claimant.name)
	lines.append("Abeilles qui la connaissent : %d" % _bees_knowing(flower))
	return "\n".join(lines)


## Texte affiché pour la ruche : une ligne par grandeur des deux boucles qu'elle porte,
## le recrutement (danses, suiveuses) et la saturation (file, receveuses).
func _hive_info(h: Hive) -> String:
	if h == null:
		return "Ruche introuvable"
	var lines := PackedStringArray()
	lines.append("Ruche")
	lines.append("Nectar stocké : %.1f" % h.nectar_stock)
	# bees_inside compte les abeilles dans un état du super-état Ruche
	lines.append("Abeilles dans la ruche : %d / %d" % [h.bees_inside, bees_container.get_child_count()])

	# --- Saturation (boucle négative) ---
	lines.append("File de déchargement : %d" % h.get_queue_length())
	var bee := _first_bee()
	if bee != null:
		var count := bee.simulation.receiver_count
		lines.append("Receveuses occupées : %d / %d" % [h.get_busy_receiver_count(count), count])

	# --- Recrutement (boucle positive) ---
	lines.append("Danses en cours : %d (suiveuses : %d)" % [h.get_dance_count(), h.get_follower_total()])
	# Une ligne par espèce annoncée : montre quelle source l'emporte dans le recrutement
	var dances := h.get_dances_by_species()
	for species in dances:
		lines.append("    %s : %d" % [Flower.SPECIES_LABELS.get(species, "?"), dances[species]])
	return "\n".join(lines)


## Nombre d'abeilles dont la source connue est [param flower] (exploration ou danse).
## Calculé seulement pour la fleur affichée : 200 comparaisons par image, négligeable.
func _bees_knowing(flower: Flower) -> int:
	var count := 0
	for node in bees_container.get_children():
		var bee := node as Bee
		if bee != null and bee.known_flower == flower:
			count += 1
	return count


## Durée en heures simulées → « 1 h 20 min ».
func _format_hours(hours: float) -> String:
	var minutes := roundi(hours * 60.0)
	return "%d h %02d min" % [minutes / 60, minutes % 60]
