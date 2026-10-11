shader_type canvas_item;
// Vision d'abeille approchée, appliquée à l'image déjà rendue :
// mosaïque hexagonale (yeux composés) + couleurs décalées (pas de récepteur rouge).

// Image de l'écran ; les mipmaps servent à moyenner la couleur de chaque cellule
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

/// Nombre de cellules (ommatidies) sur la largeur de l'écran
uniform float cells_across : hint_range(20.0, 300.0) = 80.0;

/// Niveau de mipmap lu : plus il est haut, plus chaque cellule est floue
uniform float blur_lod : hint_range(0.0, 6.0) = 2.5;

/// Assombrissement du bord des cellules (effet visuel, pas biologique)
uniform float border_strength : hint_range(0.0, 1.0) = 0.0;

/// 0 = couleurs humaines, 1 = fausses couleurs complètes
uniform float color_shift : hint_range(0.0, 1.0) = 1.0;

/// Part du bleu utilisée pour simuler l'UV, absent du rendu (approximation :
/// le ciel et beaucoup de surfaces bleutées réfléchissent aussi des UV)
uniform float uv_from_blue : hint_range(0.0, 1.0) = 0.5;

/// Niveaux de mipmap supplémentaires pour lire la couleur (réglé par BeeVisionFilter)
uniform float color_lod_offset : hint_range(0.0, 6.0) = 2.5;

/// 0 = couleur à pleine résolution, 1 = couleur perçue seulement sur les grandes zones
uniform float color_pooling : hint_range(0.0, 1.0) = 1.0;

// Pas de la grille hexagonale : 1 en largeur, √3 en hauteur
const vec2 HEX = vec2(1.0, 1.7320508);

/// Demi-axes de chaque œil (largeur, hauteur), en hauteurs d'écran
uniform vec2 eye_radius = vec2(0.55, 0.55);

/// Décalage horizontal du centre de chaque œil (0 = un seul ovale)
uniform float eye_offset : hint_range(0.0, 0.5) = 0.3;

/// Largeur du dégradé au bord du champ visuel (0 = bord net)
uniform float vignette_softness : hint_range(0.0, 0.5) = 0.5;

/// Lissage de la jonction entre les deux yeux (0 = encoche nette, effet jumelles)
uniform float eye_blend : hint_range(0.0, 1.0) = 0.3;

/// Largeur du dégradé à l'intérieur des ovales (avant le bord)
uniform float vignette_inner : hint_range(0.0, 0.5) = 0.15;

/// Largeur du dégradé à l'extérieur des ovales (après le bord)
uniform float vignette_outer : hint_range(0.0, 1.0) = 0.2;

// Distance normalisée à une ellipse : 0 au centre, 1 sur le bord, > 1 à l'extérieur
float ellipse_dist(vec2 q, vec2 center, vec2 radius) {
	return length((q - center) / radius);
}

// Centre de l'hexagone contenant p (p exprimé en unités de cellule).
// La grille hexagonale = deux grilles rectangulaires décalées ;
// on garde le centre le plus proche des deux.
vec2 hex_center(vec2 p) {
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / HEX.xyxy) + 0.5;
	vec2 a = hc.xy * HEX;
	vec2 b = (hc.zw + 0.5) * HEX;
	return dot(p - a, p - a) < dot(p - b, p - b) ? a : b;
}

// Minimum lissé : se comporte comme min(a, b) quand a et b sont éloignés,
// mais arrondit la transition quand ils sont proches (jonction des deux ovales)
float smooth_min(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void fragment() {
	// Rapport largeur/hauteur, pour que les hexagones ne soient pas étirés
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 scale = vec2(cells_across, cells_across / aspect);

	// Toute la cellule prend la couleur lue en son centre
	vec2 p = SCREEN_UV * scale;
	vec2 center = hex_center(p);
	vec2 uv_center = center / scale;
	// Lecture à la taille d'une ommatidie : sert au contraste et aux contours
	vec3 fine = textureLod(screen_texture, uv_center, blur_lod).rgb;
	// Lecture sur une zone d'environ 15° : seule échelle où la couleur est perçue
	vec3 coarse = textureLod(screen_texture, uv_center, blur_lod + color_lod_offset).rgb;

	// Fausses couleurs : vert → rouge, bleu → vert, UV (approché) → bleu.
	// Le rouge humain disparaît : une surface purement rouge devient sombre.
	vec3 bee_fine = vec3(fine.g, fine.b, fine.b * uv_from_blue);
	vec3 bee_coarse = vec3(coarse.g, coarse.b, coarse.b * uv_from_blue);

	// Teinte de la zone large, modulée par le contraste vert local de la cellule.
	// Le +0,05 évite l'explosion du rapport dans les zones très sombres.
	float green_contrast = (fine.g + 0.05) / (coarse.g + 0.05);
	vec3 bee_pooled = bee_coarse * clamp(green_contrast, 0.0, 4.0);

	vec3 bee = mix(bee_fine, bee_pooled, color_pooling);
	vec3 col = mix(fine, bee, color_shift);

	// Bord de cellule : distance au centre (≈ 0,5 au bord d'un hexagone)
	float edge = smoothstep(0.38, 0.55, length(p - center));
	
	// Coordonnées centrées sur l'écran, corrigées du rapport largeur/hauteur
	// pour que les ovales ne soient pas étirés (x dans ±aspect/2, y dans ±0,5)
	vec2 q = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);

	// Union adoucie des deux yeux : pas d'encoche nette entre les ovales
	float d = smooth_min(
		ellipse_dist(q, vec2(-eye_offset, 0.0), eye_radius),
		ellipse_dist(q, vec2(eye_offset, 0.0), eye_radius),
		eye_blend
	);

	// Plein éclairage jusqu'à 1 - inner, noir complet à partir de 1 + outer :
	// le bord des ovales (d = 1) est désormais au milieu du dégradé
	float vignette = 1.0 - smoothstep(1.0 - vignette_inner, 1.0 + vignette_outer, d);
	col *= vignette;
	
	COLOR = vec4(col * (1.0 - border_strength * edge), 1.0);
}