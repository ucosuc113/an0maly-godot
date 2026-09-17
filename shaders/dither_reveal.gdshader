shader_type canvas_item;

// Aparicion "materializandose": los pixeles se encienden en orden Bayer 4x4
// (el mismo lenguaje que el dithering del post-proceso). Los que estan a punto
// de aparecer brillan con el color de borde, como chispas.
// Usa FRAGCOORD: dentro del SubViewport pixelado, 1 celda = 1 pixel del juego.

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
/// Ancho de la franja de "chispas", en fraccion del recorrido.
uniform float edge_width : hint_range(0.0, 0.5) = 0.12;
/// Mezcla de ruido sobre el Bayer para que el patron no se vea tan regular.
uniform float noise_mix : hint_range(0.0, 1.0) = 0.35;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	if (progress < 1.0) {
		vec2 cell = floor(FRAGCOORD.xy);
		float th = mix(bayer4(cell), hash(cell), noise_mix);
		// Se reescala para que progress=0 no muestre nada y 1 lo muestre todo,
		// incluida la franja de chispas.
		float p = progress * (1.0 + edge_width);
		if (th > p) {
			discard;
		}
		if (th > p - edge_width) {
			COLOR.rgb = edge_color.rgb;
		}
	}
}
