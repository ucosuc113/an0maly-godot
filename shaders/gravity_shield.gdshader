shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Escudo gravitatorio (esfera). Muy transparente: suma luz.
//
//   build     0..1  la reticula (paralelos y meridianos) se teje desde el
//                   ecuador hacia los polos
//   density   0..1  relleno y borde (fresnel): el escudo "cargado"
//   ripple_*        ondas que recorren la superficie desde un punto
//                   (xyz = direccion, w = edad en segundos; w < 0 = inactiva)
//   flash           destello de todo el escudo

uniform float build : hint_range(0.0, 1.0) = 0.0;
uniform float density : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 2.0) = 0.0;
uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.7, 0.95, 1.0, 1.0);
uniform float grid_step_deg = 15.0;
uniform vec4 ripple_a = vec4(0.0, 0.0, 1.0, -1.0);
uniform vec4 ripple_b = vec4(0.0, 0.0, 1.0, -1.0);
uniform vec4 ripple_c = vec4(0.0, 0.0, 1.0, -1.0);
uniform vec4 ripple_d = vec4(0.0, 0.0, 1.0, -1.0);
uniform float ripple_speed = 2.4;
/// Brillo general.
uniform float brightness = 1.0;
/// 0..1: el escudo se comprime (la reticula se tensa y brilla mas).
uniform float compression = 0.0;

varying vec3 n;

void vertex() {
	n = normalize(VERTEX);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float ripple(vec4 r, vec3 dir) {
	if (r.w < 0.0) {
		return 0.0;
	}
	float ang = acos(clamp(dot(dir, normalize(r.xyz)), -1.0, 1.0));
	float front = r.w * ripple_speed;
	float band = exp(-pow((ang - front) / 0.14, 2.0));
	return band * clamp(1.0 - r.w / 1.3, 0.0, 1.0);
}

void fragment() {
	vec3 d = normalize(n);
	float lat = degrees(asin(clamp(d.y, -1.0, 1.0)));
	float lon = degrees(atan(d.z, d.x)) + TIME * 6.0;

	// Reticula: lineas finas cada grid_step_deg.
	float gl = abs(fract(lat / grid_step_deg + 0.5) - 0.5) * grid_step_deg;
	float go = abs(fract(lon / grid_step_deg + 0.5) - 0.5) * grid_step_deg * cos(radians(lat));
	float line = max(1.0 - smoothstep(0.35, 0.9, gl), 1.0 - smoothstep(0.35, 0.9, go));
	// Se teje desde el ecuador; el frente titila.
	float reach = build * 92.0;
	float woven = 1.0 - smoothstep(reach - 4.0, reach, abs(lat));
	float front = exp(-pow((abs(lat) - reach) / 3.0, 2.0)) * step(0.01, build) * step(build, 0.99);

	// Celdas que titilan en el relleno.
	vec2 cell = floor(vec2(lat, lon) / grid_step_deg);
	float twinkle = 0.6 + 0.4 * sin(TIME * 3.0 + hash(cell) * 40.0);

	float facing = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - facing, 2.2);

	float rip = ripple(ripple_a, d) + ripple(ripple_b, d) + ripple(ripple_c, d) + ripple(ripple_d, d);

	vec3 col = color.rgb * line * woven * (0.55 + 0.45 * density)
		+ rim_color.rgb * front * 1.5
		+ color.rgb * density * 0.10 * twinkle
		+ rim_color.rgb * rim * density * 0.9
		+ rim_color.rgb * rip * (0.4 + density)
		+ rim_color.rgb * flash * (0.35 + rim);
	ALBEDO = col * brightness * (1.0 + compression * 0.6);
}
