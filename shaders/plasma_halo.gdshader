shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Halo de la bola de plasma: esfera algo mas grande, suma luz que se apaga
// hacia el borde y titila, con "brazos" que giran (los filamentos de una
// lampara de plasma, a la escala de unos pocos pixeles).

uniform float energy : hint_range(0.0, 2.0) = 0.0;
uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, 2.5);
	// Brazos: bandas angulares que giran y cambian de largo.
	float ang = atan(local_dir.z, local_dir.x);
	float arms = pow(max(0.0, sin(ang * 4.0 + TIME * 3.0 + sin(TIME * 5.0 + local_dir.y * 6.0) * 1.5)), 6.0);
	float flicker = 0.75 + 0.25 * sin(TIME * 31.0) * sin(TIME * 11.0);
	float a = (core * 0.8 + arms * (1.0 - core) * 0.6) * flicker * energy;
	ALBEDO = color.rgb * a;
}
