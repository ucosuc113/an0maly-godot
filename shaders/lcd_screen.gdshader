shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Pantalla LED de los monitores de telemetria. Muestra la textura de un
// SubViewport (info_monitor.gd) sobre la superficie de la pantalla. El UV del
// modelo ocupa un recorte del atlas, girado o espejado segun como se hizo en
// Blender: uv_matrix / uv_offset (afin) lo llevan a 0..1 con x a la derecha e
// y hacia abajo.
//
// power: 0 apagada (vidrio oscuro), 1 encendida. Al encender, la
// retroiluminacion titila y una franja clara barre la pantalla.

uniform sampler2D screen_tex : source_color, filter_nearest;
/// Filas de la matriz afin: st.x = dot(row0, uv), st.y = dot(row1, uv).
uniform vec4 uv_matrix = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float power : hint_range(0.0, 1.0) = 0.0;
/// 0..1: franja del encendido (baja por la pantalla).
uniform float sweep : hint_range(0.0, 1.0) = 1.0;
uniform vec4 glass_color : source_color = vec4(0.015, 0.018, 0.03, 1.0);
uniform float brightness = 1.15;

void fragment() {
	vec2 uv = vec2(dot(uv_matrix.xy, UV), dot(uv_matrix.zw, UV)) + uv_offset;
	vec3 img = texture(screen_tex, clamp(uv, 0.0, 1.0)).rgb * brightness;
	// Franja del encendido: por encima de ella la imagen ya esta; en ella, luz.
	float shown = step(uv.y, sweep);
	float band = exp(-pow((uv.y - sweep) / 0.03, 2.0)) * step(sweep, 0.999);
	vec3 lit = img * shown + vec3(0.55, 0.6, 0.9) * band;
	// Retroiluminacion: el negro de la imagen queda un poco levantado.
	vec3 backlight = vec3(0.012, 0.012, 0.022);
	ALBEDO = mix(glass_color.rgb, lit + backlight, power);
}
