shader_type canvas_item;

// Transicion entre vistas de camara: la pantalla se divide en celdas y cada
// una se tapa con un cuadrado que crece GIRANDO 90 grados, en una ola que baja
// de arriba a abajo (con un poco de desorden por celda). Al destapar, la ola
// vuelve a bajar y los cuadrados siguen girando en el mismo sentido mientras
// se encogen. Las celdas en transito brillan con edge_color (las mismas
// "chispas" naranjas del disolvente de los menus).
//
// Vive en un ColorRect a pantalla completa dentro del PixelViewport: 1 unidad
// = 1 pixel del juego, y el post-proceso lo cuantiza como a todo lo demas.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
/// false: tapando (progress 0 -> 1). true: destapando (progress 1 -> 0).
uniform bool uncovering = false;
/// Tamano del ColorRect en pixeles (lo pone view_transition.gd).
uniform vec2 rect_size = vec2(320.0, 180.0);
uniform float cell = 10.0;
/// Cuanto dura cada celda, en fraccion del recorrido (mas = ola mas ancha).
uniform float spread : hint_range(0.05, 1.0) = 0.45;
/// Desorden del frente de la ola (0 = filas perfectas).
uniform float jitter : hint_range(0.0, 1.0) = 0.3;
uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.52, 0.14, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV * rect_size);
	vec2 c = floor(px / cell);
	float rows = max(ceil(rect_size.y / cell) - 1.0, 1.0);
	// 0 arriba .. 1 abajo, con un poco de ruido por celda.
	float d = (c.y / rows) * (1.0 - jitter) + hash(c) * jitter;
	// Al destapar, progress baja: las celdas con d alto se destapan primero,
	// asi que se invierte para que la ola siga yendo hacia abajo.
	if (uncovering) {
		d = 1.0 - d;
	}
	float k = clamp((progress * (1.0 + spread) - d) / spread, 0.0, 1.0);
	if (k <= 0.0) {
		discard;
	}

	float ang = (uncovering ? 2.0 - k : k) * PI * 0.5;
	vec2 p = px + 0.5 - (c + 0.5) * cell;
	float cs = cos(ang);
	float sn = sin(ang);
	vec2 q = vec2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
	// Celda completa: medio pixel extra para que no queden rendijas.
	float half_side = k * cell * 0.5 + (k >= 1.0 ? 1.0 : 0.0);
	if (max(abs(q.x), abs(q.y)) > half_side) {
		discard;
	}

	float glow = 1.0 - smoothstep(0.3, 0.9, k);
	COLOR = mix(fill_color, edge_color, glow);
}
