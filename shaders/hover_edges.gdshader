shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Resaltado de "esto se puede usar" dibujado SOBRE el objeto (next_pass):
// las aristas de su caja se marcan en naranja, con las esquinas mas intensas
// que laten (el mismo lenguaje que los marcos de la UI y el cristal), y un
// barrido de luz recorre el eje mas largo. Sirve para objetos apoyados en
// paredes o pisos, donde un contorno por detras quedaria escondido.
// mesh_interactable.gd pasa la caja de la malla en su espacio y su tamano en
// metros.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(1.0, 0.52, 0.14, 1.0);
uniform vec4 tint : source_color = vec4(0.78, 0.92, 1.0, 1.0);
uniform vec3 box_origin = vec3(0.0);
uniform vec3 box_size = vec3(1.0);
/// Tamano de la caja en metros (para medir las lineas en metros).
uniform vec3 size_m = vec3(1.0);
/// Eje mas largo (0=x 1=y 2=z): por ahi corre el barrido.
uniform int long_axis = 0;
uniform float line_width = 0.025;
uniform float corner_length = 0.12;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.7;
uniform float sweep_period = 2.2;
/// Acerca el dibujo a la camara para no pelear en profundidad con la malla.
uniform float depth_pull = 0.004;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz -= normalize(view.xyz) * depth_pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	if (intensity <= 0.0) {
		discard;
	}
	vec3 n = clamp((local_pos - box_origin) / max(box_size, vec3(1e-6)), 0.0, 1.0);
	// Distancia (m) a la cara mas cercana de la caja, por eje.
	vec3 d = min(n, vec3(1.0) - n) * size_m;
	vec3 on = step(d, vec3(line_width));
	bool on_edge = on.x + on.y + on.z >= 2.0;
	// Esquina: sobre una arista y cerca del extremo por el tercer eje. Los
	// brazos crecen con la intensidad.
	vec3 near = step(d, vec3(corner_length * intensity));
	bool on_corner = on_edge && near.x + near.y + near.z >= 3.0;

	float t = fract(TIME / sweep_period);
	float band = 1.0 - smoothstep(0.0, 0.05, abs(n[long_axis] - (t * 1.4 - 0.2)));
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0);

	if (on_corner) {
		ALBEDO = accent.rgb;
		ALPHA = pulse * intensity;
	} else if (on_edge) {
		ALBEDO = accent.rgb;
		ALPHA = edge_alpha * intensity;
	} else {
		ALBEDO = tint.rgb;
		ALPHA = (0.04 + 0.2 * band) * intensity;
	}
}
