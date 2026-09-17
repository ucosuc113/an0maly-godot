shader_type canvas_item;
render_mode unshaded;

// Cuantizacion de color + dither ordenado para el look de pixel art.
//
// Tres perillas controlan cosas DISTINTAS y conviene no confundirlas:
//
//   color_steps    -> CUANTAS bandas tiene un degradado.
//   dither_*       -> COMO se mezclan dos bandas vecinas.
//   saturation     -> cuanto color tiene la imagen (nada que ver con lo anterior).

group_uniforms Degradado;

/// Niveles por canal. Menos = bandas mas grandes y look mas duro.
/// 3-4 = muy marcado, 5-6 = equilibrado, 10+ = casi continuo.
uniform int color_steps : hint_range(2, 64) = 12;

/// Ancho de la zona mezclada entre dos bandas, en fraccion de banda.
/// 0.0 = corte seco sin dither. 1.0 = la banda entera dithered.
uniform float dither_strength : hint_range(0.0, 1.5) = 0.3;

/// Tamano de la matriz de Bayer: 2 = basto (4 tonos de mezcla),
/// 4 = clasico (16), 8 = fino y suave (64).
uniform int dither_pattern : hint_range(2, 8) = 8;

/// Texeles por celda de dither. 1 = un punto por pixel del pixel art.
/// 2 o 3 dan un dither mas gordo y tranquilo, menos "ruidoso".
uniform int dither_scale : hint_range(1, 8) = 1;

group_uniforms Color;

uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform float contrast : hint_range(0.5, 2.0) = 1.45;
uniform float black_level : hint_range(0.0, 0.3) = 0.02;

// Bayer en forma cerrada por recursion: sin arrays ni indexado dinamico.
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
	vec4 src = texture(TEXTURE, UV);
	vec3 col = src.rgb;

	// Indice del texel de BAJA resolucion. Sin esto el dither se calcularia por
	// pixel de pantalla y a 4x veriamos el patron DENTRO de cada pixel gordo.
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
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
	// Centrado en cero: si no, el dither desplaza el brillo medio.
	float threshold = d - (levels - 1.0) / (2.0 * levels);

	// Grado antes de cuantizar, para repartir bien los pocos niveles que quedan.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col = mix(vec3(black_level), vec3(1.0), col);
	col = clamp(col, 0.0, 1.0);

	float steps = float(color_steps - 1);
	col = floor(col * steps + 0.5 + threshold * dither_strength) / steps;

	COLOR = vec4(clamp(col, 0.0, 1.0), src.a);
}
