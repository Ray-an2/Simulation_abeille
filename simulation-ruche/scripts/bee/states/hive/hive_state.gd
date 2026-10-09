class_name HiveState extends BeeState
## Super-état « Ruche » : comportements communs aux états où l'abeille marche sur le cadre.

# =============================================================================
# Constantes
# =============================================================================

## Distance (m) en dessous de laquelle une voisine est évitée.
## Environ une longueur d'abeille : à ajuster à la taille du modèle.
const AVOID_RADIUS := 0.02

# =============================================================================
# Utilitaires pour les états du cadre
# =============================================================================

## Direction pour s'éloigner des voisines trop proches, dans le plan du cadre.
## Sa longueur mesure l'urgence : 0 sans voisine, environ 1 au contact d'une voisine,
## davantage si plusieurs sont collées. Renvoie Vector3.ZERO si personne n'est à portée.
## Si [param forward] est fourni (cap de l'abeille), seules les voisines situées devant
## comptent, d'autant plus qu'elles sont dans l'axe : l'abeille ne réagit pas
## à celles qui l'approchent par l'arrière.
func get_avoidance(normal: Vector3, forward: Vector3 = Vector3.ZERO) -> Vector3:
	var away := Vector3.ZERO
	for other in bee.hive.get_comb_bees_near(bee.global_position, AVOID_RADIUS, bee):
		# Vecteur voisine → abeille, ramené dans le plan du cadre
		var diff := (bee.global_position - other.global_position).slide(normal)
		var d := diff.length()
		# Deux abeilles exactement superposées : direction de fuite arbitraire (sur le côté)
		if d < 0.000001:
			diff = bee.global_basis.x.slide(normal)
			d = 0.000001
		var dir_away := diff / d

		# Poids linéaire : 0 au bord du rayon, 1 au contact
		var weight := 1.0 - d / AVOID_RADIUS

		if forward != Vector3.ZERO:
			# Cosinus entre le cap et la direction de la voisine :
			# 1 droit devant, 0 sur le côté, négatif derrière
			var facing := forward.dot(-dir_away)
			if facing <= 0.0:
				continue   # voisine derrière ou sur le côté : ignorée
			weight *= facing

		away += dir_away * weight
	return away
