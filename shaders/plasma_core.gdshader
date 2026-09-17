shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Nucleo de plasma del laser (reemplaza el material azul del cilindro del
// nucleo). Plasma que fluye a lo largo del eje, con filamentos que giran y
// laten. `charge` lo llena desde la base hacia la punta con un frente blanco;
// sin carga el nucleo queda como vidrio azul oscuro.
// laser_emitter.gd pasa el eje y el rango del cilindro en espacio del modelo.

uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform vec4 off_color : source_color = vec4(0.03, 0.06, 0.16, 1.0);
uniform vec4 deep_color : source_color = vec4(0.04, 0.16, 0.62, 1.0);
uniform vec4 mid_color : source_color = vec4(0.12, 0.58, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.8, 0.96, 1.0, 1.0);
/// Eje del cilindro (0=x 1=y 2=z) y su rango en espacio del modelo.
uniform int axis = 2;
uniform float axis_min = 0.0;
uniform float axis_max = 1.0;
/// Velocidad del flujo (hacia la punta).
uniform float flow_speed = 2.2;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
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
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float a = clamp((local_pos[axis] - axis_min) / max(axis_max - axis_min, 1e-6), 0.0, 1.0);
	// Angulo alrededor del eje (los otros dos ejes estan centrados en 0).
	vec2 radial = axis == 0 ? local_pos.yz : (axis == 1 ? local_pos.xz : local_pos.xy);
	float ang = atan(radial.y, radial.x);
	vec2 ring = vec2(cos(ang), sin(ang));

	float t = TIME * flow_speed;
	// Turbulencia que sube por el tubo.
	float n = noise(vec3(ring * 1.6, a * 5.0 - t))
		+ 0.5 * noise(vec3(ring * 3.2, a * 11.0 - t * 1.7 + 7.0));
	n /= 1.5;
	// Filamentos: bandas helicoidales que giran y se deforman con el ruido.
	float helix = sin(ang * 3.0 + a * 14.0 - TIME * 6.0 + n * 5.0);
	float filaments = pow(1.0 - abs(helix), 10.0);
	float heat = clamp(n * 0.85 + filaments * 0.9, 0.0, 1.0);

	vec3 col = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.2, 0.7, heat));
	col = mix(col, hot_color.rgb, smoothstep(0.75, 1.0, heat));
	float flicker = 0.9 + 0.06 * sin(TIME * 37.0) + 0.04 * sin(TIME * 23.0 + a * 9.0);
	col *= intensity * flicker;

	// Llenado: por debajo del frente hay plasma; el frente es blanco.
	float front = charge * 1.08;
	float lit = 1.0 - smoothstep(front - 0.06, front, a);
	float edge = (charge > 0.001 && charge < 0.999)
		? exp(-pow((a - front) / 0.035, 2.0)) : 0.0;

	ALBEDO = mix(off_color.rgb, col, lit) + hot_color.rgb * edge * 1.5;
}
