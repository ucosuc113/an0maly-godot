shader_type canvas_item;
render_mode unshaded;

// Igual que pixel_quantize.gdshader, pero dentro del PixelViewport (320x180)
// leyendo la pantalla: mismo resultado sin pagar el shader a resolucion nativa.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

group_uniforms Degradado;

uniform int color_steps : hint_range(2, 64) = 12;

uniform float dither_strength : hint_range(0.0, 1.5) = 0.3;

uniform int dither_pattern : hint_range(2, 8) = 8;

uniform int dither_scale : hint_range(1, 8) = 1;

group_uniforms Color;

uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform float contrast : hint_range(0.5, 2.0) = 1.45;
uniform float black_level : hint_range(0.0, 0.3) = 0.02;

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

float bayer8(vec2 a) {
	return bayer4(a * 0.5) * 0.25 + bayer2(a);
}

void fragment() {
	vec4 src = texture(screen_tex, SCREEN_UV);
	vec3 col = src.rgb;

	vec2 texel = floor(SCREEN_UV / SCREEN_PIXEL_SIZE);
	vec2 cell = floor(texel / float(max(dither_scale, 1)));

	float d;
	float levels;
	if (dither_pattern <= 2) {
		d = bayer2(cell);
		levels = 4.0;
	} else if (dither_pattern <= 4) {
		d = bayer4(cell);
		levels = 16.0;
	} else {
		d = bayer8(cell);
		levels = 64.0;
	}
	float threshold = d - (levels - 1.0) / (2.0 * levels);

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col = mix(vec3(black_level), vec3(1.0), col);
	col = clamp(col, 0.0, 1.0);

	float steps = float(color_steps - 1);
	col = floor(col * steps + 0.5 + threshold * dither_strength) / steps;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
