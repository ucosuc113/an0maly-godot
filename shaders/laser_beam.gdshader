shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Haz de un laser (cilindro a lo largo de Y, laser_emitter.gd lo estira del
// cabezal al centro). Nucleo blanco que mira a la camara, borde del color del
// laser, pulsos de energia que viajan hacia el objetivo y un parpadeo rapido.

uniform float intensity : hint_range(0.0, 4.0) = 0.0;
uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.9, 0.97, 1.0, 1.0);
/// Largo del haz (para que los pulsos tengan tamano fijo en metros).
uniform float length_m = 1.0;
uniform float pulse_speed = 6.0;
/// 0..1: el haz crece desde el cabezal al dispararse.
uniform float reach : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// UV.y: 0 en un extremo, 1 en el otro (CylinderMesh). El cabezal esta en y=0.
	float along = 1.0 - UV.y;
	if (along > reach) {
		discard;
	}
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, 4.0);
	float edge = pow(facing, 1.2);
	// Pulsos que viajan hacia el centro (cada ~0.25 m).
	float d = along * length_m;
	float pulses = 0.6 + 0.4 * pow(0.5 + 0.5 * sin((d * 25.0 - TIME * pulse_speed * 4.0)), 3.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 53.0) * sin(TIME * 31.0);
	// Punta que brilla mientras crece.
	float tip = exp(-pow((along - reach) / 0.04, 2.0)) * step(reach, 0.999);
	vec3 col = color.rgb * edge + core_color.rgb * core * 1.4;
	ALBEDO = (col * pulses * flicker + core_color.rgb * tip * 2.0) * intensity;
}
