class_name Units extends RefCounted
## Mise en forme des quantités affichées par l'interface (BeeOverlay, SimulationHud).
## Passe à l'unité suivante dès 1000 de l'unité courante :
## µL → mL → L pour les volumes, mg → g → kg pour les masses.
## Utilisée pour les stocks de la ruche, qui grossissent vite ; les quantités
## d'une abeille ou d'une fleur restent en µL et mg.

## Unités de volume, de la plus petite à la plus grande, d'un facteur 1000 chacune.
const VOLUME_UNITS: PackedStringArray = ["µL", "mL", "L"]

## Unités de masse, de la plus petite à la plus grande, d'un facteur 1000 chacune.
const MASS_UNITS: PackedStringArray = ["mg", "g", "kg"]

## Formats selon le nombre de décimales (0, 1 ou 2). Tableau typé : l'indexer
## donne une String, ce qui permet l'inférence de type dans _format().
const DECIMAL_FORMATS: PackedStringArray = ["%.0f", "%.1f", "%.2f"]

## Volume donné en µL, mis en forme dans l'unité adaptée (ex. « 12,5 mL »).
static func volume(microliters: float) -> String:
	return _format(microliters, VOLUME_UNITS)


## Masse donnée en mg, mise en forme dans l'unité adaptée (ex. « 1,25 g »).
static func mass(milligrams: float) -> String:
	return _format(milligrams, MASS_UNITS)


## Divise [param value] par 1000 tant qu'elle atteint 1000 et qu'il reste
## une unité plus grande, puis l'écrit avec trois chiffres significatifs
## environ : 0 décimale à partir de 100, 1 à partir de 10, 2 en dessous.
static func _format(value: float, units: PackedStringArray) -> String:
	var i := 0
	while absf(value) >= 1000.0 and i < units.size() - 1:
		value /= 1000.0
		i += 1
	var decimals := 0 if absf(value) >= 100.0 else (1 if absf(value) >= 10.0 else 2)
	# Format fixe plutôt que String.num(), qui retire les zéros finaux :
	# le texte ne change pas de largeur d'un rafraîchissement à l'autre.
	# Virgule décimale française.
	var text := (DECIMAL_FORMATS[decimals] % value).replace(".", ",")
	return "%s %s" % [text, units[i]]
