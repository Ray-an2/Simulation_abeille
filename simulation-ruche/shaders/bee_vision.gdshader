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

// Pas de la grille hexagonale : 1 en largeur, √3 en hauteur
const vec2 HEX = vec2(1.0, 1.7320508);

// Centre de l'hexagone contenant p (p exprimé en unités de cellule).
// La grille hexagonale = deux grilles rectangulaires décalées ;
// on garde le centre le plus proche des deux.
vec2 hex_center(vec2 p) {
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / HEX.xyxy) + 0.5;
	vec2 a = hc.xy * HEX;
	vec2 b = (hc.zw + 0.5) * HEX;
	return dot(p - a, p - a) < dot(p - b, p - b) ? a : b;
}

void fragment() {
	// Rapport largeur/hauteur, pour que les hexagones ne soient pas étirés
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 scale = vec2(cells_across, cells_across / aspect);

	// Toute la cellule prend la couleur lue en son centre
	vec2 p = SCREEN_UV * scale;
	vec2 center = hex_center(p);
	vec3 c = textureLod(screen_texture, center / scale, blur_lod).rgb;

	// Fausses couleurs : vert → rouge, bleu → vert, UV (approché) → bleu.
	// Le rouge humain disparaît : une surface purement rouge devient sombre.
	vec3 bee = vec3(c.g, c.b, c.b * uv_from_blue);
	vec3 col = mix(c, bee, color_shift);

	// Bord de cellule : distance au centre (≈ 0,5 au bord d'un hexagone)
	float edge = smoothstep(0.38, 0.55, length(p - center));
	COLOR = vec4(col * (1.0 - border_strength * edge), 1.0);
}