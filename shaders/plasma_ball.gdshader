shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Bola de plasma de la recamara del laser: superficie que hierve (ruido que
// gira), centro mas caliente mirando a la camara y latido rapido.
// `energy` 0 = apagada (vidrio oscuro), 1 = encendida.

uniform float energy : hint_range(0.0, 2.0) = 0.0;
uniform vec4 off_color : source_color = vec4(0.02, 0.04, 0.1, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.3, 0.95, 1.0);
uniform vec4 hot_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// Ruido sobre la esfera que gira en dos ejes: plasma hirviendo.
	float t = TIME;
	vec3 d = local_dir;
	vec3 p1 = vec3(d.x * cos(t * 1.3) - d.z * sin(t * 1.3), d.y, d.x * sin(t * 1.3) + d.z * cos(t * 1.3));
	float n = noise(p1 * 3.0 + vec3(0.0, t * 1.5, 0.0)) * 0.65
		+ noise(p1 * 7.0 - vec3(t * 2.0)) * 0.35;
	// Centro (de frente a la camara) mas blanco, borde mas azul.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float heat = clamp(n * 0.7 + facing * 0.6, 0.0, 1.0);
	float pulse = 0.85 + 0.15 * sin(t * 19.0) * sin(t * 7.0);
	vec3 col = mix(deep_color.rgb, hot_color.rgb, smoothstep(0.35, 0.95, heat)) * pulse;
	ALBEDO = mix(off_color.rgb, col * (0.6 + 0.6 * energy), clamp(energy, 0.0, 1.0));
}
