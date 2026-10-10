shader_type sky;

// Couleurs du ciel
uniform vec3 sky_top : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 sky_horizon : source_color = vec3(0.68, 0.78, 0.88);
uniform vec3 ground_color : source_color = vec3(0.30, 0.28, 0.25);

// Nuages (cloud_noise : NoiseTexture2D avec Seamless activé)
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.2;
uniform float cloud_scale = 0.12;
uniform vec2 wind = vec2(0.004, 0.0015);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.58, 0.65);

// Soleil
uniform float sun_halo : hint_range(0.0, 2.0) = 0.6;

void sky() {
	float h = EYEDIR.y;
	vec3 col = mix(sky_horizon, sky_top, clamp(h * 2.0, 0.0, 1.0));

	// Soleil : position et taille viennent du DirectionalLight3D
	// (rotation de la lumière + Light > Angular Distance)
	if (LIGHT0_ENABLED) {
		float a = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		float disc = 1.0 - smoothstep(LIGHT0_SIZE * 0.5, LIGHT0_SIZE * 0.5 + 0.003, a);
		float halo = exp(-a * 8.0) * sun_halo;
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * 6.0 + halo);
	}

	// Nuages projetés sur un plan au-dessus de la caméra
	if (h > 0.0) {
		vec2 uv = EYEDIR.xz / (h + 0.08) * cloud_scale;
		float n1 = texture(cloud_noise, uv + wind * TIME).r;
		float n2 = texture(cloud_noise, uv * 2.3 - wind * TIME * 0.6).r;
		float n = n1 * 0.65 + n2 * 0.35;

		float threshold = 1.0 - cloud_cover;
		float cov = smoothstep(threshold, threshold + cloud_softness, n);
		cov *= smoothstep(0.0, 0.12, h); // fondu vers l'horizon

		// Nuages plus sombres là où ils sont épais
		vec3 c = mix(cloud_light, cloud_shadow, smoothstep(0.5, 1.0, n));
		if (LIGHT0_ENABLED) {
			c *= mix(vec3(1.0), LIGHT0_COLOR, 0.3);
		}
		col = mix(col, c, cov);
	} else {
		col = mix(sky_horizon, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	COLOR = col;
}
