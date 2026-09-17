extends Node3D

# Laser (emisor lateral o diagonal). Nodo padre de las 4 piezas del modelo,
# colocado en su posicion final (fuera del agujero). El eje del laser es su +Y
# local. Los colores (plasma, bola, tiras, luz) son por laser: los laterales
# van en azul y los diagonales en morado.
#
#   hide_retracted()   escondido dentro de la pared (inicio del juego)
#   await rise()       sale por su agujero: anticipacion, recorrido pesado con
#                      el anillo girando, se pasa un poco y se asienta; despues
#                      el cabezal se extiende y el anillo frena.
#   await ignite()     el nucleo se llena de plasma (plasma_core.gdshader), las
#                      tiras prenden con parpadeo, se enciende la luz y las
#                      piezas empiezan a girar: Lanzador y AnilloRotacion en
#                      sentido horario, Guiadores en antihorario (vistos de
#                      frente), todos a spin_speed.
#
#   fire(target)       dispara el haz hacia un punto (crece desde el cabezal)
#   pulse()            golpe de energia (haz, plasma y luz)
#   set_beam(v, t)     intensidad del haz
#   charge_up(v, t)    intensidad del plasma (1 = normal)
#
# El agujero por donde sale se calcula cruzando el eje con las mallas de
# `walls`; si no hay, se usa hole_offset.
#
# Piezas (hijos): Inferior (cuerpo + nucleo + recamara de vidrio + luz),
# AnilloRotacion, Guiadores y Lanzador (cabezal). Dentro de la recamara
# (superficie glass_material) se crea una bola de plasma con su halo; la luz
# azul sale de ahi.

signal locked
signal risen
signal ignited

const PLASMA_SHADER = preload("res://shaders/plasma_core.gdshader")
const BALL_SHADER = preload("res://shaders/plasma_ball.gdshader")
const HALO_SHADER = preload("res://shaders/plasma_halo.gdshader")
const BEAM_SHADER = preload("res://shaders/laser_beam.gdshader")

## Mallas de las paredes (el exterior): el agujero se calcula solo.
@export var walls: Array[Node3D] = []
## Distancia (m) desde la base, en la posicion final, hasta el agujero (si no
## hay `walls` o el eje no las cruza).
@export var hole_offset: float = 0.3
## Cuanto mas adentro del agujero queda escondida la punta (m).
@export var retract_margin: float = 0.08
## Cuanto sale el cabezal despues de que el cuerpo se asienta (m).
@export var head_travel: float = 0.12
@export var rise_time: float = 2.1
## Giro de las piezas una vez encendido (rad/s).
@export var spin_speed: float = 9.0
@export_group("Materiales")
@export var core_material: String = "Material.001"
@export var glass_material: String = "Material.012"
@export var strip_material: String = "Material.008"
## Opacidad del vidrio alrededor del nucleo.
@export_range(0.0, 1.0, 0.01) var glass_opacity: float = 0.15
@export_range(0.0, 8.0, 0.1) var strip_energy: float = 2.5
## Tamano de la bola de plasma respecto al radio de la recamara.
@export_range(0.1, 1.0, 0.01) var ball_size: float = 0.55
## Tamano del halo respecto al radio de la recamara.
@export_range(0.1, 1.5, 0.01) var halo_size: float = 0.95
@export_group("Colores")
@export var plasma_deep: Color = Color(0.04, 0.16, 0.62)
@export var plasma_mid: Color = Color(0.12, 0.58, 1.0)
@export var plasma_hot: Color = Color(0.8, 0.96, 1.0)
@export var light_color: Color = Color(0.32, 0.62, 1.0)
@export_group("Haz")
@export var beam_radius: float = 0.035
@export_group("Luz")
@export var light_energy: float = 2.5
@export var light_range: float = 1.6
@export_group("")
@export var sfx: Node

@onready var _inferior: Node3D = $Inferior
@onready var _ring: Node3D = $AnilloRotacion
@onready var _guides: Node3D = $Guiadores
@onready var _launcher: Node3D = $Lanzador

## Estado para los monitores: hidden, rising, ready, online.
var stage: StringName = &"hidden"
var _unit: float = 1.0
var _retract: float = 0.0
var _body_offset: float = 0.0
var _head_offset: float = 0.0
## Velocidades con signo (rad/s, positivo = antihorario visto de frente).
var _ring_speed: float = 0.0
var _head_speed: float = 0.0
var _ring_angle: float = 0.0
var _head_angle: float = 0.0
var _charge: float = 0.0
## 0..1: tiras y luz (lo animan los tirones de la ignicion).
var _glow: float = 0.0
## Donde empieza el cuerpo sobre el eje, en metros desde el origen.
var _base_along: float = 0.0
var _core_mats: Array[ShaderMaterial] = []
var _strip_mats: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _core_center_local: Vector3
## Recamara (espacio de Inferior): centro y radio.
var _chamber_center: Vector3
var _chamber_radius: float = 0.0
var _ball_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _beam_target: Vector3
var _beam_intensity: float = 0.0
var _beam_reach: float = 0.0
var _plasma_boost: float = 1.0
var _pulse: float = 0.0
var _length_m: float = 0.0

func _ready() -> void:
	_unit = global_basis.y.length()
	_setup_materials()
	_setup_ball()
	_setup_light()
	var length := _body_length()
	_length_m = length
	var hole := _find_hole(length)
	if hole > -INF:
		hole_offset = hole
	_retract = (length - hole_offset + retract_margin) / _unit
	hide_retracted()

# --- Preparacion -----------------------------------------------------------------

## Distancia desde la base hasta donde el eje cruza las paredes (la mayor
## entre la base y la punta). -INF si no las cruza.
func _find_hole(length: float) -> float:
	var axis := global_basis.y.normalized()
	var base := global_position + axis * _base_along
	var from := base - axis * 0.3
	var to := base + axis * length
	var best := -INF
	for w in walls:
		if w == null:
			continue
		for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.global_transform * mi.get_aabb()
			if not box.grow(0.05).intersects_segment(from, to):
				continue
			var faces := mi.mesh.get_faces()
			var xf := mi.global_transform
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(
					from, to, xf * faces[i], xf * faces[i + 1], xf * faces[i + 2])
				if hit != null:
					best = maxf(best, (hit as Vector3 - base).dot(axis))
	return best

func _setup_materials() -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null:
				continue
			if base.resource_name == core_material:
				var m := ShaderMaterial.new()
				m.shader = PLASMA_SHADER
				var box := _surface_aabb(mi, s)
				var axis := box.size.max_axis_index()
				m.set_shader_parameter("axis", axis)
				m.set_shader_parameter("axis_min", box.position[axis])
				m.set_shader_parameter("axis_max", box.end[axis])
				m.set_shader_parameter("deep_color", plasma_deep)
				m.set_shader_parameter("mid_color", plasma_mid)
				m.set_shader_parameter("hot_color", plasma_hot)
				mi.set_surface_override_material(s, m)
				_core_mats.append(m)
				_core_center_local = _inferior.global_transform.affine_inverse() \
					* (mi.global_transform * box.get_center())
			elif base.resource_name == glass_material:
				var to_inferior := _inferior.global_transform.affine_inverse()
				var cb: AABB = to_inferior * mi.global_transform * _surface_aabb(mi, s)
				_chamber_center = cb.get_center()
				_chamber_radius = minf(cb.size.x, cb.size.z) * 0.5
				var g := base.duplicate() as BaseMaterial3D
				g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				g.albedo_color.a = glass_opacity
				g.roughness = 0.05
				g.metallic_specular = 0.9
				g.emission_enabled = false
				mi.set_surface_override_material(s, g)
			elif base.resource_name == strip_material:
				var st := base.duplicate() as StandardMaterial3D
				st.emission_enabled = true
				st.emission = plasma_mid.lerp(plasma_hot, 0.35)
				st.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, st)
				_strip_mats.append(st)

func _setup_ball() -> void:
	if _chamber_radius <= 0.0:
		return
	_ball_mat = _sphere("PlasmaBall", BALL_SHADER, _chamber_radius * ball_size)
	_ball_mat.set_shader_parameter("deep_color", plasma_mid.darkened(0.2))
	_ball_mat.set_shader_parameter("hot_color", plasma_hot)
	_halo_mat = _sphere("PlasmaHalo", HALO_SHADER, _chamber_radius * halo_size)
	_halo_mat.set_shader_parameter("color", light_color)

func _sphere(node_name: String, shader: Shader, radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = _chamber_center
	mi.layers = _inferior_layers()
	_inferior.add_child(mi)
	return mat

func _setup_light() -> void:
	for c in _inferior.get_children():
		if c is OmniLight3D:
			_light = c
			break
	if _light == null:
		_light = OmniLight3D.new()
		_inferior.add_child(_light)
	# La luz sale de la recamara (o del nucleo si no hay), con el alcance en
	# metros reales.
	_light.position = _chamber_center if _chamber_radius > 0.0 else _core_center_local
	_light.scale = Vector3.ONE / _inferior.global_basis.get_scale()
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.omni_attenuation = 1.6
	_light.light_energy = 0.0
	_light.visible = false

func _surface_aabb(mi: MeshInstance3D, s: int) -> AABB:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box

## Largo del cuerpo en metros, medido sobre el eje.
func _body_length() -> float:
	var inv := global_transform.affine_inverse()
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		lo = minf(lo, b.position.y)
		hi = maxf(hi, b.end.y)
	_base_along = lo * _unit
	return (hi - lo) * _unit

# --- Estados ---------------------------------------------------------------------

func hide_retracted() -> void:
	_body_offset = -_retract
	_head_offset = -_retract - head_travel / _unit
	_ring_speed = 0.0
	_head_speed = 0.0
	_set_charge(0.0)
	_set_glow(0.0)
	_light.visible = false
	visible = false
	stage = &"hidden"
	_apply()

func rise() -> void:
	visible = true
	stage = &"rising"
	var head_rest := -head_travel / _unit
	# Anticipacion: se destraba y retrocede un poco.
	_play("laser_lock", -10.0, 0.7)
	var t := create_tween().set_parallel()
	t.tween_property(self, "_body_offset", _body_offset - 0.03 / _unit, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_head_offset", _head_offset - 0.03 / _unit, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	_play("laser_rise")
	# Vapor cuando la punta cruza el agujero (el recorrido es cubico).
	get_tree().create_timer(rise_time * 0.22, false).timeout.connect(_steam_puff)
	var overshoot := 0.025 / _unit
	t = create_tween().set_parallel()
	t.tween_property(self, "_body_offset", overshoot, rise_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_head_offset", head_rest + overshoot, rise_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_ring_speed", -spin_speed * 1.6, rise_time * 0.5) \
		.set_trans(Tween.TRANS_SINE)
	await t.finished

	# Se asienta: golpe, y el cuerpo vuelve de su pasada.
	_play("laser_lock")
	locked.emit()
	t = create_tween().set_parallel()
	t.tween_property(self, "_body_offset", 0.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_head_offset", head_rest, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished

	# El cabezal se extiende y el anillo frena hasta quedar alineado.
	_play("laser_lock", -8.0, 1.5)
	t = create_tween().set_parallel()
	t.tween_property(self, "_head_offset", 0.0, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_ring_speed", 0.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	stage = &"ready"
	risen.emit()

func ignite() -> void:
	_play("plasma_ignite")
	_light.visible = true
	var t := create_tween().set_parallel()
	# Las piezas arrancan a girar mientras se carga el plasma.
	t.tween_property(self, "_ring_speed", -spin_speed, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "_head_speed", spin_speed, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_method(_set_charge, 0.0, 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Tiras y luz: tirones de tubo antes de quedar fijas.
	var steps := [[0.0, 0.08], [0.6, 0.05], [0.1, 0.06], [0.9, 0.05], [0.3, 0.1], [1.0, 0.0]]
	var flick := create_tween()
	flick.tween_interval(0.9)
	for st in steps:
		flick.tween_callback(_set_glow.bind(st[0]))
		if st[1] > 0.0:
			flick.tween_interval(st[1])
	await t.finished
	_set_glow(1.0)
	_start_hum()
	stage = &"online"
	ignited.emit()

func _set_charge(v: float) -> void:
	_charge = v
	for m in _core_mats:
		m.set_shader_parameter("charge", v)
	# La recamara esta antes que el nucleo sobre el eje: prende primero.
	var ball := clampf(v * 3.0, 0.0, 1.0)
	if _ball_mat:
		_ball_mat.set_shader_parameter("energy", ball)
		_halo_mat.set_shader_parameter("energy", ball)

func _set_glow(v: float) -> void:
	_glow = v
	for m in _strip_mats:
		m.emission_energy_multiplier = strip_energy * v

# --- Haz -------------------------------------------------------------------------

## Punta del laser (entre las horquillas), en su posicion final.
func tip_position() -> Vector3:
	var axis := global_basis.y.normalized()
	return global_position + axis * (_base_along + _length_m)

## Dispara el haz hacia `target`: crece desde el cabezal en `grow` segundos.
func fire(target: Vector3, intensity: float = 1.0, grow: float = 0.18) -> void:
	_beam_target = target
	if _beam == null:
		_build_beam()
	_beam.visible = true
	_play("beam_fire", -6.0, randf_range(0.95, 1.05))
	var t := create_tween().set_parallel()
	t.tween_property(self, "_beam_reach", 1.0, grow).from(0.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_beam_intensity", intensity, grow * 0.5).from(intensity * 2.5)
	pulse()

## Intensidad del haz (0 = apagado).
func set_beam(intensity: float, time: float = 0.4) -> void:
	var t := create_tween()
	t.tween_property(self, "_beam_intensity", intensity, time).set_trans(Tween.TRANS_SINE)
	if intensity <= 0.0:
		t.tween_callback(func() -> void:
			if _beam:
				_beam.visible = false)

## Golpe de energia: el haz, el plasma y la luz destellan y vuelven.
func pulse(amount: float = 1.0) -> void:
	_pulse = maxf(_pulse, amount)

## Intensidad del plasma y de la luz (1 = normal).
func charge_up(value: float, time: float = 1.0) -> void:
	create_tween().tween_property(self, "_plasma_boost", value, time).set_trans(Tween.TRANS_SINE)

func _build_beam() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = beam_radius
	mesh.bottom_radius = beam_radius
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("color", light_color)
	_beam_mat.set_shader_parameter("core_color", plasma_hot)
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = mesh
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.layers = _inferior_layers()
	add_child(_beam)

func _update_beam() -> void:
	var a := tip_position()
	var ab := _beam_target - a
	var length := ab.length()
	if length < 0.001:
		return
	var dir := ab / length
	# Cilindro: +Y hacia el objetivo, alto = largo del haz.
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var basis := Basis(side, dir * length, side.cross(dir).normalized())
	_beam.global_transform = Transform3D(basis, a + ab * 0.5)
	var boost := 1.0 + _pulse * 1.5
	_beam_mat.set_shader_parameter("intensity", _beam_intensity * boost)
	_beam_mat.set_shader_parameter("reach", _beam_reach)
	_beam_mat.set_shader_parameter("length_m", length)

# --- Movimiento ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_ring_angle = wrapf(_ring_angle + _ring_speed * delta, 0.0, TAU)
	_head_angle = wrapf(_head_angle + _head_speed * delta, 0.0, TAU)
	_apply()
	_pulse = maxf(_pulse - delta * 2.5, 0.0)
	if _beam and _beam.visible:
		_update_beam()
	var boost := _plasma_boost + _pulse
	for m in _core_mats:
		m.set_shader_parameter("intensity", boost)
	if _ball_mat:
		_ball_mat.set_shader_parameter("energy", clampf(_charge * 3.0, 0.0, 1.0) * boost)
		_halo_mat.set_shader_parameter("energy", clampf(_charge * 3.0, 0.0, 1.0) * boost)
	if _light.visible:
		# La luz sigue a las tiras y a la carga; encendida, respira con el plasma.
		var ms := Time.get_ticks_msec()
		var breathe := 1.0 + 0.06 * sin(ms * 0.011) + 0.04 * sin(ms * 0.027)
		var k := breathe if _glow >= 1.0 else 1.0
		_light.light_energy = light_energy * maxf(_glow, _charge * 0.35) * k * boost

func _apply() -> void:
	_inferior.position = Vector3(0.0, _body_offset, 0.0)
	_ring.position = Vector3(0.0, _body_offset, 0.0)
	_ring.rotation = Vector3(0.0, _ring_angle, 0.0)
	_guides.position = Vector3(0.0, _head_offset, 0.0)
	_launcher.position = Vector3(0.0, _head_offset, 0.0)
	# Lanzador horario, Guiadores antihorario (misma velocidad).
	_launcher.rotation = Vector3(0.0, -_head_angle, 0.0)
	_guides.rotation = Vector3(0.0, _head_angle, 0.0)

# --- Efectos ---------------------------------------------------------------------

## Vapor que sale del agujero cuando pasa la punta.
func _steam_puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 28
	p.lifetime = 1.4
	p.explosiveness = 0.85
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.16
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, 0.12, 0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.9, 1.0, 0.55))
	ramp.set_color(1, Color(0.6, 0.65, 0.75, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	p.mesh = quad
	p.layers = _inferior_layers()
	add_child(p)
	# En el agujero, con la direccion del eje del laser (sin la escala del nodo).
	var axis := global_basis.y.normalized()
	p.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)),
		global_position + axis * (_base_along + hole_offset))
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2, false).timeout.connect(p.queue_free)

func _inferior_layers() -> int:
	for mi: MeshInstance3D in _inferior.find_children("*", "MeshInstance3D", true, false):
		return mi.layers
	return 1

func _start_hum() -> void:
	if sfx == null or _hum:
		return
	_hum = AudioStreamPlayer3D.new()
	_hum.bus = &"SFX"
	_hum.stream = await sfx.get_stream("plasma_hum")
	_hum.unit_size = 3.0
	_hum.volume_db = -40.0
	_inferior.add_child(_hum)
	_hum.position = _core_center_local
	_hum.play()
	create_tween().tween_property(_hum, "volume_db", -8.0, 1.2)

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
