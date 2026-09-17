extends Node3D

# Escudo gravitatorio (fase 2): esfera muy transparente en el punto donde
# convergen los lasers, donde despues aparece la singularidad. En su centro,
# una semilla de energia que crece mientras los lasers la alimentan.
#
#   seed_to(size, energy, t)   semilla: tamano (m) y brillo
#   build_to(v, t)             la reticula se teje (0..1)
#   density_to(v, t)           el escudo se carga (0..1)
#   ripple(dir)                onda desde una direccion (golpes)
#   flash(amount)              destello
#
# Oculto hasta que la fase lo muestra.

const SHIELD_SHADER = preload("res://shaders/gravity_shield.gdshader")
const BALL_SHADER = preload("res://shaders/plasma_ball.gdshader")
const HALO_SHADER = preload("res://shaders/plasma_halo.gdshader")

@export var radius: float = 0.5
@export var color: Color = Color(0.35, 0.8, 1.0)
@export var rim_color: Color = Color(0.7, 0.95, 1.0)
## Brillo general del escudo.
@export var brightness: float = 1.5:
	set(value):
		brightness = value
		if _mat:
			_param("brightness", value)
## Nodo con game_settings.gd: con REDUCE FLASHING los destellos se suavizan.
@export var settings: Node

## Caras de adelante (se dibujan despues del agujero negro).
var _mat: ShaderMaterial
## Caras de atras (se dibujan antes).
var _mat_back: ShaderMaterial
var _seed_ball: MeshInstance3D
var _seed_halo: MeshInstance3D
var _ball_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _ripples: Array[Vector4] = []
var _next_ripple: int = 0

var build: float = 0.0:
	set(value):
		build = value
		_param("build", value)
var density: float = 0.0:
	set(value):
		density = value
		_param("density", value)
var flash_amount: float = 0.0:
	set(value):
		flash_amount = value
		_param("flash", value)
## 0..1: el escudo se comprime (se achica un cuarto y la reticula se tensa).
var compression: float = 0.0:
	set(value):
		compression = value
		_param("compression", value)
		for n in ["Shield", "ShieldBack"]:
			get_node(n).scale = Vector3.ONE * (1.0 - value * 0.25)
var seed_size: float = 0.0:
	set(value):
		seed_size = value
		_update_seed()
var seed_energy: float = 0.0:
	set(value):
		seed_energy = value
		_update_seed()

func _ready() -> void:
	_mat = _shield_material("cull_back", 2)
	_mat_back = _shield_material("cull_front", -2)
	_param("color", color)
	_param("rim_color", rim_color)
	_param("brightness", brightness)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	for pair in [["ShieldBack", _mat_back], ["Shield", _mat]]:
		var sphere := MeshInstance3D.new()
		sphere.name = pair[0]
		sphere.mesh = mesh
		sphere.material_override = pair[1]
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sphere)

	_ball_mat = ShaderMaterial.new()
	_ball_mat.shader = BALL_SHADER
	_ball_mat.set_shader_parameter("deep_color", color.darkened(0.3))
	_ball_mat.set_shader_parameter("hot_color", Color(0.92, 0.98, 1.0))
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_mat.set_shader_parameter("color", color)
	_seed_ball = _sphere_mesh("Seed", _ball_mat, 1.0)
	_seed_halo = _sphere_mesh("SeedHalo", _halo_mat, 2.2)

	_ripples.resize(4)
	for i in 4:
		_ripples[i] = Vector4(0, 0, 1, -1)
	visible = false
	_update_seed()

## Material del escudo con otro modo de caras y prioridad de dibujo.
func _shield_material(cull: String, priority: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHIELD_SHADER.code.replace("cull_disabled", cull)
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	return m

func _param(param: String, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	_mat_back.set_shader_parameter(param, value)

func _sphere_mesh(node_name: String, mat: ShaderMaterial, scale_factor: float) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 0.5 * scale_factor
	m.height = scale_factor
	m.radial_segments = 16
	m.rings = 8
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Capas de render (para que las luces del exterior lo vean igual que al resto).
func set_layers(layers: int) -> void:
	for c in get_children():
		if c is VisualInstance3D:
			c.layers = layers

func _update_seed() -> void:
	if _seed_ball == null:
		return
	var s := maxf(seed_size, 0.0001)
	_seed_ball.scale = Vector3.ONE * s
	_seed_halo.scale = Vector3.ONE * s
	_seed_ball.visible = seed_size > 0.001
	_seed_halo.visible = seed_size > 0.001
	_ball_mat.set_shader_parameter("energy", seed_energy)
	_halo_mat.set_shader_parameter("energy", seed_energy)

func seed_to(size: float, energy: float, time: float) -> Tween:
	var t := create_tween().set_parallel()
	t.tween_property(self, "seed_size", size, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "seed_energy", energy, time)
	return t

func build_to(value: float, time: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "build", value, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return t

func density_to(value: float, time: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "density", value, time).set_trans(Tween.TRANS_SINE)
	return t

func compress_to(value: float, time: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "compression", value, time).set_trans(Tween.TRANS_SINE)
	return t

## Cambia el color del escudo (p. ej. rojo en el derretimiento).
func tint_to(new_color: Color, new_rim: Color, time: float) -> void:
	var from_c := color
	var from_r := rim_color
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		color = from_c.lerp(new_color, k)
		rim_color = from_r.lerp(new_rim, k)
		_param("color", color)
		_param("rim_color", rim_color), 0.0, 1.0, time)

## Se rompe: destello, fragmentos que salen volando y el escudo desaparece.
func shatter() -> void:
	flash(2.5)
	var shards := CPUParticles3D.new()
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.amount = 90
	shards.lifetime = 2.2
	shards.local_coords = false
	shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	shards.emission_sphere_radius = radius * (1.0 - compression * 0.25)
	shards.direction = Vector3(0, 0, 1)
	shards.spread = 180.0
	shards.initial_velocity_min = 1.5
	shards.initial_velocity_max = 4.0
	shards.gravity = Vector3.ZERO
	shards.damping_min = 0.5
	shards.damping_max = 1.5
	shards.angular_velocity_min = -720.0
	shards.angular_velocity_max = 720.0
	shards.scale_amount_min = 0.4
	shards.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(rim_color, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	shards.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	shards.mesh = quad
	add_child(shards)
	shards.emitting = true
	var t := create_tween().set_parallel()
	t.tween_property(self, "density", 0.0, 0.25)
	t.tween_property(self, "build", 0.0, 0.4)
	t.tween_property(self, "brightness", 0.0, 0.5)

func ripple(dir: Vector3) -> void:
	_ripples[_next_ripple] = Vector4(dir.x, dir.y, dir.z, 0.0)
	_next_ripple = (_next_ripple + 1) % _ripples.size()

func flash(amount: float = 1.0) -> void:
	if settings and bool(settings.get_value("reduce_flashing")):
		amount *= 0.35
	flash_amount = maxf(flash_amount, amount)

func _process(delta: float) -> void:
	if not visible:
		return
	if flash_amount > 0.0:
		flash_amount = maxf(flash_amount - delta * 2.2, 0.0)
	var names := ["ripple_a", "ripple_b", "ripple_c", "ripple_d"]
	for i in _ripples.size():
		var r := _ripples[i]
		if r.w >= 0.0:
			r.w += delta
			if r.w > 1.4:
				r.w = -1.0
			_ripples[i] = r
		_param(names[i], r)
	# La semilla late un poco.
	if _seed_ball.visible:
		var beat := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.012)
		_seed_ball.scale = Vector3.ONE * seed_size * beat
