shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// Contorno de "esto se puede usar" para objetos con volumen (casco invertido):
// la malla se infla un poco desde su centro y solo se dibujan sus caras de
// atras, que asoman como un borde naranja alrededor del objeto. Va como
// next_pass. Se infla escalando por eje desde el centro (no por la normal):
// asi las mallas con caras planas y normales partidas no dejan huecos en las
// esquinas. Para piezas sueltas (con el objeto pegado a una pared, el casco
// queda escondido: ahi va hover_edges). mesh_interactable.gd pasa el centro y el inflado por eje en
// espacio del modelo (ya convertido desde metros).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.52, 0.14, 1.0);
uniform vec3 center = vec3(0.0);
/// Cuanto crece cada eje, en fraccion de la media caja (escala - 1).
uniform vec3 grow = vec3(0.05);
/// Empuje hacia atras en metros: el casco queda detras del objeto y solo
/// asoma por la silueta (sin esto, los detalles internos inflados atraviesan
/// las caras de arriba y se ven rayas).
uniform float depth_push = 0.03;

void vertex() {
	vec3 grown = center + (VERTEX - center) * (vec3(1.0) + grow * intensity);
	vec4 view = MODELVIEW_MATRIX * vec4(grown, 1.0);
	view.xyz += normalize(view.xyz) * depth_push;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	if (intensity <= 0.0) {
		discard;
	}
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0);
	ALBEDO = color.rgb * pulse;
}
