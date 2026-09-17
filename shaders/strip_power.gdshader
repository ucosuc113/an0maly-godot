shader_type spatial;

// Tiras de luz del exterior que se encienden de arriba hacia abajo. Todo lo
// que esta por encima de `front_y` (alto del mundo) emite; el frente es una
// franja mas brillante que baja, con un temblor de tubo que pelea por prender.
// outside_power.gd copia el color y la emision del material importado.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_energy = 2.0;
/// Alto (mundo) del frente de encendido.
uniform float front_y = 100.0;
/// Alto de la franja brillante del frente.
uniform float front_width = 0.25;
/// Tono apagado del tubo (fraccion del albedo).
uniform float off_level : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float above = world_pos.y - front_y;
	float lit = smoothstep(-0.02, 0.02, above);
	// Franja del frente: mas brillante y temblando por tramos de tira.
	float band = exp(-pow(above / front_width, 2.0)) * step(0.0, above);
	float cell = floor(world_pos.x * 3.0 + world_pos.z * 3.0);
	float flick = step(0.35, hash(cell + floor(TIME * 24.0)));
	float e = lit * (1.0 + band * 1.5 * flick);

	ALBEDO = albedo.rgb * mix(off_level, 1.0, lit);
	ROUGHNESS = roughness;
	EMISSION = emission_color.rgb * emission_energy * e;
}
