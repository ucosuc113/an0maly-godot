shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Resaltado de "esto se puede usar", como next_pass del cristal. Habla el
// mismo idioma que los menus: esquinas naranjas que crecen desde las puntas y
// laten, un marco fino entre ellas y un destello diagonal que cruza el vidrio.
// Trabaja en espacio del modelo: window_crystal.gd pasa la caja de la malla,
// cuales de sus ejes son el ancho y el alto del panel, y las medidas (en
// fraccion del ancho/alto, ya convertidas desde metros).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(1.0, 0.52, 0.14, 1.0);
uniform vec4 tint : source_color = vec4(0.78, 0.92, 1.0, 1.0);
uniform vec3 box_origin = vec3(0.0);
uniform vec3 box_size = vec3(1.0);
/// Ejes del modelo que son el ancho (u) y el alto (v) del panel: 0=x 1=y 2=z.
uniform int axis_u = 0;
uniform int axis_v = 2;
/// Separacion del marco respecto al borde real del panel.
uniform vec2 inset = vec2(0.016, 0.045);
/// Separacion extra arriba (ahi la moldura de la pared tapa el panel).
uniform float inset_top = 0.07;
/// true si v = 1 es el borde de arriba.
uniform bool top_is_high = true;
/// Grosor de las lineas.
uniform vec2 thickness = vec2(0.012, 0.034);
/// Largo de los brazos de las esquinas.
uniform vec2 corner = vec2(0.06, 0.17);
uniform float frame_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float sweep_period = 2.2;
uniform float sweep_width = 0.05;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = (local_pos - box_origin) / max(box_size, vec3(1e-6));
	float u = n[axis_u];
	float v = n[axis_v];
	// Distancia al marco (0 = sobre su borde exterior).
	float du = min(u, 1.0 - u) - inset.x;
	float to_top = top_is_high ? 1.0 - v : v;
	float dv = min(to_top - inset_top, 1.0 - to_top) - inset.y;
	if (du < 0.0 || dv < 0.0 || intensity <= 0.0) {
		discard;
	}

	bool on_line = du < thickness.x || dv < thickness.y;
	// Las esquinas crecen con la intensidad, como la linea de los botones.
	bool on_corner = on_line && du < corner.x * intensity && dv < corner.y * intensity;
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0);

	// Destello diagonal: entra por la izquierda, sale por la derecha y espera.
	float t = fract(TIME / sweep_period);
	float diag = u * 0.8 + v * 0.2;
	float band = 1.0 - smoothstep(0.0, sweep_width, abs(diag - (t * 1.8 - 0.4)));

	if (on_corner) {
		ALBEDO = accent.rgb;
		ALPHA = pulse * intensity;
	} else if (on_line) {
		ALBEDO = mix(accent.rgb, tint.rgb, 0.35);
		ALPHA = frame_alpha * intensity;
	} else {
		ALBEDO = tint.rgb;
		ALPHA = (0.05 + 0.22 * band) * intensity;
	}
}
