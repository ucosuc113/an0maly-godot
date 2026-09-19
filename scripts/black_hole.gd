@tool
extends Node3D

# Todo lo exportado es ajustable EN CALIENTE: se puede animar con Tween o
# AnimationPlayer (p. ej. tween_property(bh, "sphere_radius", 0.2, 3.0)).
# Cambiar un valor no reconstruye nada: solo marca los uniforms como sucios y
# se reenvian una vez por frame, aunque cambien varios a la vez.

## Radio del horizonte de sucesos (la esfera negra real).
@export var sphere_radius: float = 0.25:
	set(value):
		sphere_radius = value
		_mark_dirty()
## Radio exterior del disco de acrecion.
@export var disc_radius: float = 1.2:
	set(value):
		disc_radius = value
		_mark_dirty()
## Inclinacion del disco respecto al nodo.
@export var disc_tilt_degrees: Vector3 = Vector3(15.0, 0.0, 7.0):
	set(value):
		disc_tilt_degrees = value
		_mark_dirty()
## Curvatura del rayo. 0 = sin lente gravitacional. Es invariante a escala:
## el mismo valor se ve igual con un agujero grande o chico.
@export var bend_strength: float = 1.5:
	set(value):
		bend_strength = value
		_mark_dirty()
@export_range(16, 256, 1) var march_steps: int = 140:
	set(value):
		march_steps = value
		_mark_dirty()
## Tope de octavas (modo FAST lo baja aunque una animacion pida mas).
var max_octaves: int = 5:
	set(value):
		max_octaves = value
		_mark_dirty()

## Para cuando el agujero crece mas que la recamara: el volumen del raymarch
## atraviesa las paredes y la prueba de profundidad normal lo taparia entero.
## En este modo el shader corta cada rayo contra la profundidad de la escena:
## lo de delante lo sigue tapando y el horizonte se traga lo que alcanza.
@export var draw_over_everything: bool = false:
	set(value):
		draw_over_everything = value
		_apply_shader_mode()

@export_group("Disco")
## Borde interior del disco, en radios del horizonte (~ISCO). Bajarlo acerca
## el disco a la esfera.
@export var disc_inner_ratio: float = 2.6:
	set(value):
		disc_inner_ratio = value
		_mark_dirty()
@export var disc_color_hot: Color = Color(1.0, 0.95, 0.8):
	set(value):
		disc_color_hot = value
		_mark_dirty()
@export var disc_color_cold: Color = Color(1.0, 0.3, 0.05):
	set(value):
		disc_color_cold = value
		_mark_dirty()
@export var disc_brightness: float = 1.8:
	set(value):
		disc_brightness = value
		_mark_dirty()
## Opacidad del disco. Ya no depende de disc_thickness_ratio: puedes afinar el
## disco sin que se vuelva transparente.
@export_range(0.0, 8.0) var disc_opacity: float = 0.35:
	set(value):
		disc_opacity = value
		_mark_dirty()
## Grosor del disco como fraccion de disc_radius (no en unidades absolutas,
## asi la silueta no cambia al escalar el agujero).
@export_range(0.01, 0.5) var disc_thickness_ratio: float = 0.07:
	set(value):
		disc_thickness_ratio = value
		_mark_dirty()
## Caida del brillo hacia el borde. Bajala con discos enormes.
@export_range(0.0, 2.0) var disc_falloff: float = 1.0:
	set(value):
		disc_falloff = value
		_mark_dirty()
@export var doppler_strength: float = 0.55:
	set(value):
		doppler_strength = value
		_mark_dirty()

@export_group("Textura del disco")
## Cuanto modula el ruido procedural a la densidad. 0 = disco liso.
@export_range(0.0, 1.0) var turbulence: float = 0.7:
	set(value):
		turbulence = value
		_mark_dirty()
## Detalle del ruido medido en ciclos A LO ANCHO del disco, no en unidades
## absolutas: asi la textura se ve igual escales como escales el agujero.
@export var noise_detail: float = 4.0:
	set(value):
		noise_detail = value
		_mark_dirty()
@export_range(1, 5) var noise_octaves: int = 3:
	set(value):
		noise_octaves = value
		_mark_dirty()
## Cuanto se enrollan los brazos. Negativo invierte el sentido del remolino.
@export_range(-8.0, 8.0) var spiral_tightness: float = 2.5:
	set(value):
		spiral_tightness = value
		_mark_dirty()
## Velocidad de giro (rad/s en el borde interior). La rotacion es kepleriana:
## lo de dentro va mas rapido. Se integra por frame, asi que cambiarla en
## caliente acelera o frena el disco sin saltos.
@export_range(0.0, 4.0, 0.01, "or_greater") var swirl_speed: float = 0.6
## Bandas concentricas: contraste y cuantas caben en el disco.
@export_range(0.0, 1.0) var ring_contrast: float = 0.25:
	set(value):
		ring_contrast = value
		_mark_dirty()
@export var ring_count: float = 2.0:
	set(value):
		ring_count = value
		_mark_dirty()
## Cuanto se aplastan los filamentos contra el plano. 0 = grumos esfericos.
@export_range(0.0, 0.95) var filament_flatten: float = 0.75:
	set(value):
		filament_flatten = value
		_mark_dirty()
## Ancho de los brazos. 0.5 = neutro, 0.8 = gordos.
@export_range(0.0, 1.0) var filament_width: float = 0.7:
	set(value):
		filament_width = value
		_mark_dirty()
## Dureza del borde: alto = brazos solidos, bajo = humo difuso.
@export_range(0.5, 8.0) var filament_contrast: float = 3.0:
	set(value):
		filament_contrast = value
		_mark_dirty()

@export_group("Debug")
## El shader ya dibuja el disco. Esto solo saca una malla plana translucida
## para comprobar donde cae el plano del disco.
@export var draw_geometry_disc: bool = false:
	set(value):
		draw_geometry_disc = value
		if is_node_ready():
			_rebuild()
@export var disc_segments: int = 48:
	set(value):
		disc_segments = value
		if is_node_ready():
			_rebuild()

@export_tool_button("Reconstruir") var _rebuild_button: Callable = _rebuild

const HORIZON_NAME := "EventHorizon"
const DISC_NAME := "AccretionDisc"

var _material: ShaderMaterial
var _sphere: SphereMesh
var _debug_disc: MeshInstance3D
var _debug_disc_base_radius: float = 1.0
var _dirty: bool = true
## Angulo acumulado del giro. No se envuelve: el giro es diferencial (cada radio
## avanza a otra velocidad) y un wrap a TAU produciria un salto visible.
var _swirl_phase: float = 0.0

func _ready() -> void:
	_rebuild()

func _process(delta: float) -> void:
	_swirl_phase += swirl_speed * delta
	if _material == null:
		return
	_material.set_shader_parameter("swirl_phase", _swirl_phase)
	if _dirty:
		_apply_params()

func _apply_shader_mode() -> void:
	if _material == null:
		return
	var base: Shader = load("res://shaders/black_hole_lensing.gdshader")
	if draw_over_everything:
		var over := Shader.new()
		over.code = base.code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,") \
				.replace("shader_type spatial;", "shader_type spatial;\n#define MANUAL_DEPTH")
		_material.shader = over
	else:
		_material.shader = base
	_mark_dirty()

func _mark_dirty() -> void:
	_dirty = true

func _rebuild() -> void:
	for child in get_children():
		if child.name == HORIZON_NAME or child.name == DISC_NAME:
			remove_child(child)
			child.queue_free()
	_material = null
	_sphere = null
	_debug_disc = null

	if draw_geometry_disc:
		_debug_disc = _build_accretion_disc()
	_build_event_horizon()
	_apply_params()

func _build_event_horizon() -> void:
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 32
	_sphere.rings = 16

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = HORIZON_NAME
	mesh_instance.mesh = _sphere
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/black_hole_lensing.gdshader")
	mesh_instance.material_override = _material
	_apply_shader_mode()

	add_child(mesh_instance)

## Esta malla no es el agujero negro: es el volumen donde corre el raymarch.
## Tiene que envolver al disco con margen suficiente para que los rayos
## desviados quepan dentro y alcancen a cruzarlo por detras.
func _bound_radius() -> float:
	return maxf(maxf(disc_radius * 1.8, sphere_radius * 8.0), 0.001)

func _apply_params() -> void:
	_dirty = false
	if _material == null:
		return

	# El volumen sigue al tamano actual. Solo se regenera la esfera cuando el
	# radio cambia de verdad (32x16 vertices: barato aunque se anime).
	var bound_radius := _bound_radius()
	if not is_equal_approx(_sphere.radius, bound_radius):
		_sphere.radius = bound_radius
		_sphere.height = bound_radius * 2.0
		var mesh_instance := _sphere_instance()
		if mesh_instance:
			mesh_instance.extra_cull_margin = bound_radius

	# Normal del disco en espacio LOCAL, no global: asi sobrevive a mover el nodo.
	var tilt := Basis.from_euler(Vector3(
		deg_to_rad(disc_tilt_degrees.x),
		deg_to_rad(disc_tilt_degrees.y),
		deg_to_rad(disc_tilt_degrees.z)))
	if _debug_disc:
		_debug_disc.rotation_degrees = disc_tilt_degrees
		_debug_disc.scale = Vector3.ONE * (disc_radius / maxf(_debug_disc_base_radius, 0.001))

	var m := _material
	m.set_shader_parameter("bound_radius", bound_radius)
	m.set_shader_parameter("event_horizon_radius", sphere_radius)
	# ~ISCO: deja un hueco negro visible entre el horizonte y el disco.
	m.set_shader_parameter("disc_inner_radius",
			minf(sphere_radius * disc_inner_ratio, disc_radius * 0.8))
	m.set_shader_parameter("disc_outer_radius", disc_radius)
	m.set_shader_parameter("disc_normal", tilt.y.normalized())
	m.set_shader_parameter("bend_strength", bend_strength)
	m.set_shader_parameter("march_steps", march_steps)
	m.set_shader_parameter("disc_color_hot", disc_color_hot)
	m.set_shader_parameter("disc_color_cold", disc_color_cold)
	m.set_shader_parameter("disc_brightness", disc_brightness)
	m.set_shader_parameter("disc_opacity", disc_opacity)
	m.set_shader_parameter("disc_thickness",
			maxf(disc_radius * disc_thickness_ratio, 0.0001))
	m.set_shader_parameter("doppler_strength", doppler_strength)
	m.set_shader_parameter("disc_falloff", disc_falloff)
	m.set_shader_parameter("turbulence", turbulence)
	# Relativos al tamano del disco, igual que el resto: invariantes a escala.
	m.set_shader_parameter("noise_scale", noise_detail / maxf(disc_radius, 0.001))
	m.set_shader_parameter("noise_octaves", mini(noise_octaves, max_octaves))
	m.set_shader_parameter("spiral_tightness", spiral_tightness)
	m.set_shader_parameter("swirl_phase", _swirl_phase)
	m.set_shader_parameter("ring_contrast", ring_contrast)
	m.set_shader_parameter("ring_frequency", ring_count / maxf(disc_radius, 0.001))
	m.set_shader_parameter("filament_flatten", filament_flatten)
	m.set_shader_parameter("filament_width", filament_width)
	m.set_shader_parameter("filament_contrast", filament_contrast)

func _sphere_instance() -> MeshInstance3D:
	return get_node_or_null(HORIZON_NAME) as MeshInstance3D

func _build_accretion_disc() -> MeshInstance3D:
	# Se genera con el radio actual y luego se escala si disc_radius cambia.
	_debug_disc_base_radius = maxf(disc_radius, 0.001)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = DISC_NAME
	mesh_instance.mesh = _generate_disc_mesh(_debug_disc_base_radius, disc_segments)
	mesh_instance.rotation_degrees = disc_tilt_degrees
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.6, 0.2, 0.2)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material

	add_child(mesh_instance)
	return mesh_instance

func _generate_disc_mesh(radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var center := Vector3.ZERO

	for i in range(segments):
		var angle_a := i * TAU / segments
		var angle_b := (i + 1) * TAU / segments

		var point_a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var point_b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)

		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(center)

		st.set_uv(Vector2(cos(angle_a), sin(angle_a)) * 0.5 + Vector2(0.5, 0.5))
		st.add_vertex(point_a)

		st.set_uv(Vector2(cos(angle_b), sin(angle_b)) * 0.5 + Vector2(0.5, 0.5))
		st.add_vertex(point_b)

	st.generate_normals()
	return st.commit()
