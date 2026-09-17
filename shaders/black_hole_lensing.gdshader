shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// El trazado se hace en ESPACIO LOCAL del nodo: el centro es siempre (0,0,0),
// asi que el efecto sigue al nodo aunque lo muevas o lo rotes. Los radios estan
// en unidades locales.
//
// La malla es solo el VOLUMEN del raymarch. Se renderizan las caras traseras
// (cull_front) para que el efecto siga dibujandose si la camara entra dentro.

uniform float bound_radius = 2.0;
uniform float event_horizon_radius = 0.25;
uniform float disc_inner_radius = 0.65;
uniform float disc_outer_radius = 1.2;
uniform vec3 disc_normal = vec3(0.0, 1.0, 0.0);

uniform float bend_strength : hint_range(0.0, 5.0) = 1.5;
uniform int march_steps : hint_range(16, 256) = 140;

uniform vec3 disc_color_hot : source_color = vec3(1.0, 0.95, 0.80);
uniform vec3 disc_color_cold : source_color = vec3(1.0, 0.30, 0.05);
uniform float disc_thickness : hint_range(0.01, 0.5) = 0.07;
/// Opacidad del disco. Normalizada contra el GROSOR, asi que afinar el disco
/// ya no lo vuelve transparente: grosor y opacidad son independientes.
uniform float disc_opacity : hint_range(0.0, 8.0) = 0.35;
uniform float disc_brightness : hint_range(0.0, 10.0) = 1.8;
uniform float doppler_strength : hint_range(0.0, 1.0) = 0.55;

// --- Textura del disco (todo procedural, cero imagenes) ---

/// Cuanto modula el ruido a la densidad. 0 = disco liso como antes.
uniform float turbulence : hint_range(0.0, 1.0) = 0.7;
/// Frecuencia espacial del ruido, en ciclos por unidad local.
uniform float noise_scale : hint_range(0.5, 40.0) = 7.0;
/// Octavas de FBM. Cada una duplica el detalle y el coste.
uniform int noise_octaves : hint_range(1, 5) = 3;
/// Cuanto se enrollan los brazos. 0 = turbulencia sin direccion.
uniform float spiral_tightness : hint_range(-8.0, 8.0) = 2.5;
/// Angulo de giro ACUMULADO en el borde interior (radianes). Lo integra el
/// script (fase += velocidad * delta) en vez de usar velocidad * TIME: asi se
/// puede cambiar la velocidad en caliente sin que el disco pegue un salto.
/// La rotacion es kepleriana: lo de dentro va mas rapido, y esa cizalla es lo
/// que estira el ruido en espirales por si sola.
uniform float swirl_phase = 0.0;
/// Bandas concentricas superpuestas.
uniform float ring_contrast : hint_range(0.0, 1.0) = 0.25;
uniform float ring_frequency : hint_range(0.0, 20.0) = 4.0;
/// Cuanto aplana los filamentos contra el plano del disco. 0 = esferas.
uniform float filament_flatten : hint_range(0.0, 0.95) = 0.75;
/// Ancho de los brazos: baja el umbral del ruido, asi que mas area cuenta como
/// filamento. 0.5 = neutro, 0.8 = brazos gordos.
uniform float filament_width : hint_range(0.0, 1.0) = 0.7;
/// Dureza del borde del filamento. Alto = brazos solidos con corte definido,
/// bajo = humo difuso.
uniform float filament_contrast : hint_range(0.5, 8.0) = 3.0;

varying vec3 v_local_vertex;

// Rodrigues: gira p alrededor de axis (unitario) un angulo ang.
vec3 rotate_axis(vec3 p, vec3 axis, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise trilineal con suavizado smoothstep.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i + vec3(0.0, 0.0, 0.0)), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p, int octaves) {
	float amp = 0.5;
	float sum = 0.0;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += amp * vnoise(p);
		norm += amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

void vertex() {
	v_local_vertex = VERTEX;
}

void fragment() {
	vec3 ro = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 rd = normalize(v_local_vertex - ro);

	// Entrada analitica al volumen: no gastamos pasos del march llegando hasta
	// aqui. El max(..., 0.0) cubre el caso de la camara dentro de la esfera.
	float b = dot(ro, rd);
	float c = dot(ro, ro) - bound_radius * bound_radius;
	float h = b * b - c;
	if (h < 0.0) {
		discard;
	}
	h = sqrt(h);

	vec3 disc_n = normalize(disc_normal);

	// Desplazamiento aleatorio del punto de entrada. Sin esto, todos los rayos
	// muestrean en las mismas "conchas" concentricas y el disco sale a anillos.
	// Debe valer UN paso, no mas: si supera el grosor del disco deja de romper
	// las conchas y se convierte en ruido por pixel que tapa la textura.
	float jitter = hash31(vec3(FRAGCOORD.xy, 0.0))
			* min(bound_radius * 0.06, disc_thickness * 0.5);
	vec3 pos = ro + rd * (max(-b - h, 0.0) + jitter);
	vec3 dir = rd;

	vec3 accum = vec3(0.0);
	float alpha = 0.0;

	for (int i = 0; i < march_steps; i++) {
		float r = length(pos);
		if (r > bound_radius * 1.001) {
			break;
		}
		if (r < event_horizon_radius) {
			alpha = 1.0;
			break;
		}

		// Paso adaptativo, en fraccion del volumen: fino donde la curvatura
		// importa, grueso lejos. Relativo para que no dependa de la escala.
		float dt = clamp((r - event_horizon_radius) * 0.30,
				bound_radius * 0.004, bound_radius * 0.06);

		// Cerca del plano del disco el paso no puede superar su grosor, o el
		// rayo lo cruza de un salto y aparecen anillos de muestreo.
		float plane_gap = abs(dot(pos, disc_n));
		float near_disc = 1.0 - smoothstep(disc_thickness * 1.5, disc_thickness * 5.0, plane_gap);
		dt = mix(dt, max(min(dt, disc_thickness * 0.5), bound_radius * 0.002), near_disc);

		// Deflexion ~ Rs/r^2 por unidad de arco. El factor event_horizon_radius
		// es lo que la hace INVARIANTE A ESCALA: sin el, achicar el agujero
		// dispara 1/r^2 y el horizonte se traga la pantalla entera.
		dir = normalize(dir - (pos / r)
				* (bend_strength * event_horizon_radius / (r * r)) * dt);

		float y = dot(pos, disc_n);
		vec3 radial_vec = pos - y * disc_n;
		float radial = length(radial_vec);

		float vertical = exp(-(y * y) / (disc_thickness * disc_thickness));
		float inner = smoothstep(disc_inner_radius, disc_inner_radius * 1.3, radial);
		float outer = 1.0 - smoothstep(disc_outer_radius * 0.75, disc_outer_radius, radial);
		float density = vertical * inner * outer;

		if (density > 0.001) {
			// Rotacion diferencial kepleriana (omega ~ r^-1.5) mas un warp
			// logaritmico. Rotamos el PUNTO antes de muestrear el ruido 3D, asi
			// que no hay costura en phi = 0 y la espiral sale de la cizalla.
			float phase = swirl_phase
					* pow(clamp(disc_inner_radius / radial, 0.0001, 1.0), 1.5);
			float ang = -phase
					+ spiral_tightness * log(max(radial / max(disc_inner_radius, 0.0001), 1.0001));

			vec3 sample_pos = rotate_axis(pos, disc_n, ang) * noise_scale;
			// Aplasta el eje normal: filamentos tumbados en el plano, no bolas.
			sample_pos -= disc_n * dot(sample_pos, disc_n) * filament_flatten;

			float n = fbm(sample_pos, noise_octaves);
			// Remapeo: desplazar el umbral ensancha los brazos, y el contraste
			// los convierte en placas solidas en vez de humo.
			float shaped = clamp((n - (1.0 - filament_width)) * filament_contrast + 0.5, 0.0, 1.0);
			float rings = 1.0 + ring_contrast * sin(radial * ring_frequency * TAU - phase);
			density *= max(mix(1.0, shaped * 2.0 * rings, turbulence), 0.0);
			if (density <= 0.001) {
				pos += dir * dt;
				continue;
			}

			float t_norm = clamp((radial - disc_inner_radius)
					/ max(disc_outer_radius - disc_inner_radius, 0.0001), 0.0, 1.0);
			vec3 col = mix(disc_color_hot, disc_color_cold, t_norm);
			// Los grumos densos tambien queman mas.
			col *= mix(1.0, 0.55 + shaped, turbulence * 0.8);

			// Doppler beaming: el lado que viene hacia la camara brilla mas.
			vec3 tangential = cross(disc_n, radial_vec / max(radial, 0.0001));
			float boost = 1.0 + doppler_strength * dot(tangential, -dir);
			col *= disc_brightness * boost * boost;

			// Mas caliente y brillante hacia dentro.
			col *= disc_inner_radius / max(radial, 0.0001);

			// Acumulacion volumetrica: bordes suaves en vez de corte binario.
			float a = clamp(density * disc_opacity
					* (dt / max(disc_thickness, 0.0001)), 0.0, 1.0);
			accum += col * a * (1.0 - alpha);
			alpha += a * (1.0 - alpha);
			if (alpha > 0.995) {
				break;
			}
		}

		pos += dir * dt;
	}

	if (alpha < 0.002) {
		discard;
	}

	ALBEDO = accum / max(alpha, 0.0001);
	ALPHA = alpha;
}
