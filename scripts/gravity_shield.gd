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
## Nodo con game_settings.gd: con REDUCE FLASHING los destellos se suavizan.
@export var settings: Node

var _mat: ShaderMaterial
var _seed_ball: MeshInstance3D
var _seed_halo: MeshInstance3D
var _ball_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _ripples: Array[Vector4] = []
var _next_ripple: int = 0

var build: float = 0.0:
	set(value):
		build = value
		_mat.set_shader_parameter("build", value)
var density: float = 0.0:
	set(value):
		density = value
		_mat.set_shader_parameter("density", value)
var flash_amount: float = 0.0:
	set(value):
		flash_amount = value
		_mat.set_shader_parameter("flash", value)
var seed_size: float = 0.0:
	set(value):
		seed_size = value
		_update_seed()
var seed_energy: float = 0.0:
	set(value):
		seed_energy = value
		_update_seed()

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHIELD_SHADER
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("rim_color", rim_color)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	var sphere := MeshInstance3D.new()
	sphere.name = "Shield"
	sphere.mesh = mesh
	sphere.material_override = _mat
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
		_mat.set_shader_parameter(names[i], r)
	# La semilla late un poco.
	if _seed_ball.visible:
		var beat := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.012)
		_seed_ball.scale = Vector3.ONE * seed_size * beat
