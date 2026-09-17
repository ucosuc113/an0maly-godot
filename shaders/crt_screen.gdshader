shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

// Pantalla del CRT. La malla del panel trae UVs de un cubo desplegado (rotadas y
// en una franja), asi que la UV de la imagen sale de la posicion LOCAL del
// fragmento.
//
// El vidrio es curvo (abomba hacia la camara). Una proyeccion plana en XY hace
// que el centro se vea mas grande que los bordes y el texto ondula. Por eso el
// punto se proyecta, a lo largo del rayo de la camara, sobre el plano z =
// plane_z: desde la camara la imagen se ve como un plano plano, con 1 texel =
// 1 pixel en toda la pantalla. crt_monitor.gd hace la misma cuenta para el clic.

uniform sampler2D screen_tex : source_color, filter_nearest;
/// Medio ancho/alto del panel en unidades locales de la malla.
uniform vec2 half_extents = vec2(0.9867, 0.9867);
/// Tamano de la textura en texels (para el halo y el grosor minimo del apagado).
uniform vec2 screen_size = vec2(180.0, 136.0);
/// Z local del borde del vidrio: el plano de referencia de la proyeccion.
uniform float plane_z = 0.875;
/// 1 = corregir la curvatura desde la camara, 0 = proyeccion plana simple.
uniform float view_correction : hint_range(0.0, 1.0) = 1.0;

/// 0 = imagen normal, 1 = apagado. Recorrido del efecto clasico: la imagen se
/// aplasta a una linea (0-0.45), la linea se encoge a un punto (0.45-0.8) y el
/// punto se desvanece (0.8-1). Al reves sirve de encendido.
uniform float collapse : hint_range(0.0, 1.0) = 0.0;
uniform vec3 collapse_color : source_color = vec3(1.0, 0.92, 0.75);

/// Brillo del halo alrededor del texto (fosforo que "sangra").
uniform float glow : hint_range(0.0, 1.0) = 0.35;
uniform float brightness : hint_range(0.0, 3.0) = 1.15;
/// Oscurecimiento hacia los bordes del tubo.
uniform float vignette : hint_range(0.0, 2.0) = 0.9;
/// Color del vidrio apagado: el CRT nunca es negro puro.
uniform vec3 glass_color : source_color = vec3(0.035, 0.04, 0.038);
/// Reflejo suave arriba a la izquierda.
uniform float glass_reflection : hint_range(0.0, 0.3) = 0.05;

varying vec3 v_local;
varying vec3 v_cam_local;

void vertex() {
	v_local = VERTEX;
	v_cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

vec3 sample_screen(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	vec2 t = 1.0 / screen_size;
	vec3 halo = texture(screen_tex, uv + vec2(t.x, 0.0)).rgb
			+ texture(screen_tex, uv - vec2(t.x, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(0.0, t.y)).rgb
			+ texture(screen_tex, uv - vec2(0.0, t.y)).rgb;
	return c + halo * 0.25 * glow;
}

void fragment() {
	vec3 p = v_local;
	// Interseccion del rayo camara->fragmento con el plano de referencia.
	float denom = v_cam_local.z - p.z;
	if (abs(denom) > 0.0001) {
		vec3 flat_p = v_cam_local + (p - v_cam_local) * ((v_cam_local.z - plane_z) / denom);
		p = mix(p, flat_p, view_correction);
	}
	vec2 c = vec2(p.x / half_extents.x, -p.y / half_extents.y) * 0.5;

	// Escala de la imagen durante el apagado. Nunca menor a ~1.5 texels: a esta
	// resolucion una linea mas fina desaparece entre pixeles.
	vec2 min_s = 1.5 / screen_size;
	float sy = mix(1.0, min_s.y, smoothstep(0.0, 0.45, collapse));
	float sx = mix(1.0, min_s.x, smoothstep(0.45, 0.8, collapse));
	vec2 q = c / vec2(sx, sy);

	vec3 img = vec3(0.0);
	if (abs(q.x) <= 0.5 && abs(q.y) <= 0.5) {
		img = sample_screen(q + 0.5) * brightness;
		// Al comprimirse, la energia se concentra: la imagen se vuelve una
		// linea casi blanca en vez de un borron oscuro.
		img = mix(img, collapse_color * 1.4, smoothstep(0.1, 0.4, collapse));
		img *= 1.0 - smoothstep(0.8, 1.0, collapse);
	}

	// Vineta del tubo: afecta a la imagen, no al vidrio.
	float edge = dot(c * vec2(1.1, 1.25), c * vec2(1.1, 1.25));
	img *= clamp(1.0 - edge * vignette, 0.0, 1.0);

	vec3 glass = glass_color;
	glass += glass_reflection * smoothstep(0.45, 0.0, length(c - vec2(-0.28, -0.3)));

	ALBEDO = glass + img;
}
