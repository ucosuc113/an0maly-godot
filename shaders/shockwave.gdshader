shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Onda expansiva del agujero negro (singularity_hunger.gd).
//   mode 0: anillo plano (PlaneMesh 2x2) en el plano del disco.
//   mode 1: cascaron esferico, solo el borde (fresnel).
// El script escala la malla con el radio y baja `intensity` al expandirse.

uniform int mode = 0;
uniform vec3 color : source_color = vec3(1.0, 0.45, 0.3);
uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float intensity = 1.0;
/// Ancho del frente, en fraccion del radio.
uniform float width : hint_range(0.005, 0.5) = 0.08;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

void fragment() {
	float a = 0.0;
	vec3 col = color;
	if (mode == 0) {
		vec2 p = UV * 2.0 - 1.0;
		float d = length(p);
		float ang = atan(p.y, p.x);
		// Frente irregular: se rompe en jirones, no es un aro perfecto.
		float wobble = 0.015 * sin(ang * 13.0 + seed) + 0.01 * sin(ang * 31.0 - seed * 2.0);
		float edge = 1.0 - wobble;
		float front = smoothstep(edge - width, edge, d) * (1.0 - smoothstep(edge, edge + 0.01, d));
		// Estela que queda detras del frente.
		float wake = smoothstep(edge - width * 4.0, edge, d) * (1.0 - step(edge, d)) * 0.25;
		float grain = 0.7 + 0.3 * hash(floor(vec2(ang * 40.0, d * 60.0)));
		a = (front + wake) * grain;
		col = mix(color, core_color, front * front);
	} else {
		float rim = 1.0 - abs(dot(NORMAL, VIEW));
		a = pow(rim, 4.0) * 0.6;
	}
	ALBEDO = col * a * intensity;
	ALPHA = 1.0;
}
